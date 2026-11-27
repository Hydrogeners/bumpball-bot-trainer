--!nonstrict
-- Resumable headless self-play evolutionary trainer for Bumpball BotBrain.
-- Usage:
--   lune run scripts/train-bot.luau -- [--generations N] [--minutes M] [--matches K]
--       [--checkpoint path] [--out path] [--dry-run]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

-- ===========================================================================
-- CLI argument parsing
-- ===========================================================================
local cfg = {
	generations = nil,
	minutes = nil,
	matches = 4,
	checkpoint = "build/bot-checkpoint.json",
	out = "src/server/BotWeights.luau",
	dryRun = false,
}

do
	local args = process.args or {}
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--generations" and args[i + 1] then
			cfg.generations = tonumber(args[i + 1])
			i += 2
		elseif a == "--minutes" and args[i + 1] then
			cfg.minutes = tonumber(args[i + 1])
			i += 2
		elseif a == "--matches" and args[i + 1] then
			cfg.matches = math.max(1, math.floor(tonumber(args[i + 1]) or 4))
			i += 2
		elseif a == "--checkpoint" and args[i + 1] then
			cfg.checkpoint = args[i + 1]
			i += 2
		elseif a == "--out" and args[i + 1] then
			cfg.out = args[i + 1]
			i += 2
		elseif a == "--dry-run" then
			cfg.dryRun = true
			i += 1
		else
			i += 1
		end
	end
	if not cfg.generations and not cfg.minutes then
		cfg.generations = 5
	end
end

-- ===========================================================================
-- Load Bumpball simulation + BotBrain in Lune
-- ===========================================================================
local modules = {}
local moduleNames = setmetatable({}, {
	__index = function(_, name)
		return name
	end,
})

local function makeLcg(seed)
	local s = math.floor(math.abs(seed or 424242)) % 2147483647
	if s == 0 then
		s = 424242
	end
	local obj = {}
	function obj:nextFloat()
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
	function obj:NextNumber()
		return self:nextFloat()
	end
	function obj:NextInteger(minVal, maxVal)
		if maxVal <= minVal then
			return minVal
		end
		return minVal + math.floor(self:nextFloat() * (maxVal - minVal + 1)) % (maxVal - minVal + 1)
	end
	function obj:state()
		return s
	end
	return obj
end

local env = {
	Random = {
		new = function(seed)
			return makeLcg(seed or 1337)
		end,
	},
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	script = { Parent = moduleNames },
	require = function(name)
		return assert(modules[name], "Missing module: " .. tostring(name))
	end,
}

local function loadModule(path)
	return luau.load(fs.readFile(path), {
		debugName = path,
		environment = env,
	})()
end

for _, name in ipairs({ "BobblePhysics", "BobbleRoster", "KickoffFormations", "PowerPlays", "PrototypeRound" }) do
	modules[name] = loadModule("src/shared/" .. name .. ".luau")
end
modules.BotWeights = loadModule("src/server/BotWeights.luau")
modules.BotBrain = loadModule("src/server/BotBrain.luau")

local Round = modules.PrototypeRound
local Powers = modules.PowerPlays
local BotWeights = modules.BotWeights
local BotBrain = modules.BotBrain

-- ===========================================================================
-- Weight vector helpers
-- ===========================================================================
local TUNABLE_KEYS = {
	{ key = "goalScore", min = 600, max = 2400, step = 120 },
	{ key = "concedePenalty", min = 250, max = 1400, step = 80 },
	{ key = "ownGoalPenalty", min = 350, max = 1600, step = 90 },
	{ key = "ballProgress", min = 5, max = 60, step = 4.0 },
	{ key = "ballGoalAlign", min = 5, max = 60, step = 4.0 },
	{ key = "crateGrab", min = 20, max = 160, step = 12.0 },
	{ key = "crateCamp", min = 4, max = 60, step = 4.0 },
	{ key = "keeperGuard", min = 10, max = 90, step = 6.0 },
	{ key = "strikerBump", min = 5, max = 80, step = 5.0 },
	{ key = "passSetup", min = 5, max = 80, step = 5.0 },
	{ key = "bankBonus", min = 5, max = 90, step = 6.0 },
	{ key = "powerAggression", min = 0.35, max = 1.0, step = 0.08 },
}

local function copyWeights(src)
	local out = {}
	for k, v in pairs(src) do
		out[k] = v
	end
	return out
end

local function roundNum(val)
	return math.floor(val * 1000 + 0.5) / 1000
end

local function mutateWeights(base, rng)
	local child = copyWeights(base)
	-- Mutate 3-5 randomly chosen tactical weights per generation.
	local count = rng:NextInteger(3, 5)
	for _ = 1, count do
		local spec = TUNABLE_KEYS[rng:NextInteger(1, #TUNABLE_KEYS)]
		-- Approximate Gaussian via sum of 3 uniforms minus 1.5
		local delta = (rng:nextFloat() + rng:nextFloat() + rng:nextFloat() - 1.5) * spec.step
		child[spec.key] = roundNum(math.clamp((child[spec.key] or spec.min) + delta, spec.min, spec.max))
	end
	child.aimJitter = 0.0
	child.simCandidates = base.simCandidates or 16
	child.simTicks = base.simTicks or 105
	return child
end

local function scaleTier(pro, factor, jitter, candidates, ticks)
	local out = copyWeights(pro)
	for _, spec in ipairs(TUNABLE_KEYS) do
		if spec.key == "powerAggression" then
			out[spec.key] = roundNum(math.clamp(pro[spec.key] * factor, 0.35, 1.0))
		else
			out[spec.key] = roundNum(pro[spec.key] * factor)
		end
	end
	out.aimJitter = jitter
	out.simCandidates = candidates
	out.simTicks = ticks
	return out
end

-- ===========================================================================
-- Headless match simulator
-- ===========================================================================
local function applyBotPower(round, team, power)
	if not power or round.held[team] ~= power.kind then
		return
	end
	local kind = power.kind
	if kind == "steal" then
		round:stealPower(team)
		return
	end
	local interaction = Powers.Interaction[kind]
	if interaction == "placed" then
		if Powers.isLegal(power, round) then
			round:placePower(power)
		end
	elseif interaction == "target" then
		local ath = power.id and round.athletes[power.id]
		if ath and Powers.canTarget(kind, ath, round.activePowers) then
			power.x, power.z = ath.position.X, ath.position.Z
			round:placePower(power)
		end
	elseif interaction == "instant" then
		round:placePower(power)
	end
end

local function playMatch(weights0, weights1, seed, maxTurns)
	local rng = makeLcg(seed)
	local round = Round.new(rng)
	local attackingTeam = rng:NextInteger(0, 1)
	local choices = {
		BotBrain.chooseFormation(0, attackingTeam, "Pro", rng),
		BotBrain.chooseFormation(1, attackingTeam, "Pro", rng),
	}
	assert(round:applyKickoff(choices, attackingTeam), "Kickoff failed in self-play")

	-- Use fast training sim caps so self-play runs quickly while keeping identical tactical weights.
	local eval0 = copyWeights(weights0)
	local eval1 = copyWeights(weights1)
	eval0.simCandidates = math.min(eval0.simCandidates or 12, 10)
	eval0.simTicks = math.min(eval0.simTicks or 85, 70)
	eval1.simCandidates = math.min(eval1.simCandidates or 12, 10)
	eval1.simTicks = math.min(eval1.simTicks or 85, 70)

	for turn = 1, (maxTurns or 8) do
		round:prepareCrates(turn)
		local ctx = { goldenGoal = (turn >= (maxTurns or 8)) }
		-- Alternate which side reacts to an earlier opponent power (mirroring human-like mid-turn reactivity!)
		local firstTeam = if (turn % 2 == 1) then 0 else 1
		local secondTeam = 1 - firstTeam
		local firstWeights = if firstTeam == 0 then eval0 else eval1
		local secondWeights = if secondTeam == 0 then eval0 else eval1

		local pFirst = BotBrain.planTurn(round, firstTeam, turn, "Pro", firstWeights, ctx)
		-- Half the time the first player drops power early enough for the second player to react; half the time it's a late buzzer drop!
		local earlyDrop = (rng:NextInteger(0, 1) == 1)
		if earlyDrop and pFirst.power then
			applyBotPower(round, firstTeam, pFirst.power)
		end

		local pSecond = BotBrain.planTurn(round, secondTeam, turn, "Pro", secondWeights, ctx)
		if not earlyDrop and pFirst.power then
			applyBotPower(round, firstTeam, pFirst.power)
		end
		if pSecond.power then
			applyBotPower(round, secondTeam, pSecond.power)
		end

		local combined = {}
		for _, mv in ipairs(pFirst.moves) do
			combined[mv.id] = mv
		end
		for _, mv in ipairs(pSecond.moves) do
			combined[mv.id] = mv
		end
		if round:launchMoves(combined, false) then
			for _ = 1, 300 do
				round:step()
				if not round.resolving then
					break
				end
			end
		end
		if round.scorer ~= nil then
			return round.scorer, turn
		end
	end
	-- Draw: slight territorial tiebreak based on final ball X
	return nil, maxTurns or 8, round.ball.position.X
end

local function evaluateChallenger(challenger, opponents, matchPairs, rng)
	local points = 0.0
	local totalGames = 0
	local wins, losses, draws = 0, 0, 0

	for pairIdx = 1, matchPairs do
		local opp = opponents[((pairIdx - 1) % #opponents) + 1]
		local pairSeed = rng:NextInteger(1, 10000000)

		-- Game A: Challenger as Team 0, Opponent as Team 1
		local wA, _, ballXA = playMatch(challenger, opp, pairSeed, 6)
		totalGames += 1
		if wA == 0 then
			points += 1.0
			wins += 1
		elseif wA == 1 then
			losses += 1
		else
			draws += 1
			points += 0.5 + math.clamp((ballXA or 0) / 13.0, -1, 1) * 0.05
		end

		-- Game B (side-swapped): Opponent as Team 0, Challenger as Team 1
		local wB, _, ballXB = playMatch(opp, challenger, pairSeed + 7919, 6)
		totalGames += 1
		if wB == 1 then
			points += 1.0
			wins += 1
		elseif wB == 0 then
			losses += 1
		else
			draws += 1
			points += 0.5 + math.clamp(-(ballXB or 0) / 13.0, -1, 1) * 0.05
		end
	end

	return points / math.max(1, totalGames), wins, losses, draws, totalGames
end

-- ===========================================================================
-- Persistence (JSON checkpoint + BotWeights.luau emitter)
-- ===========================================================================
local function formatTier(name, tbl)
	local lines = {
		string.format("\t%s = {", name),
		string.format("\t\tgoalScore = %s,", tostring(tbl.goalScore)),
		string.format("\t\tconcedePenalty = %s,", tostring(tbl.concedePenalty)),
		string.format("\t\townGoalPenalty = %s,", tostring(tbl.ownGoalPenalty)),
		string.format("\t\tballProgress = %s,", tostring(tbl.ballProgress)),
		string.format("\t\tballGoalAlign = %s,", tostring(tbl.ballGoalAlign)),
		string.format("\t\tcrateGrab = %s,", tostring(tbl.crateGrab)),
		string.format("\t\tcrateCamp = %s,", tostring(tbl.crateCamp)),
		string.format("\t\tkeeperGuard = %s,", tostring(tbl.keeperGuard)),
		string.format("\t\tstrikerBump = %s,", tostring(tbl.strikerBump)),
		string.format("\t\tpassSetup = %s,", tostring(tbl.passSetup)),
		string.format("\t\tbankBonus = %s,", tostring(tbl.bankBonus)),
		string.format("\t\tpowerAggression = %s,", tostring(tbl.powerAggression)),
		string.format("\t\taimJitter = %s,", tostring(tbl.aimJitter)),
		string.format("\t\tsimCandidates = %d,", math.floor(tbl.simCandidates)),
		string.format("\t\tsimTicks = %d,", math.floor(tbl.simTicks)),
		"\t},",
	}
	return table.concat(lines, "\n")
end

local function writeBotWeightsFile(path, proWeights)
	local normalWeights = scaleTier(proWeights, 0.85, 0.045, 12, 85)
	local easyWeights = scaleTier(proWeights, 0.65, 0.14, 8, 65)
	local content = table.concat({
		"--!nonstrict",
		"-- Tunable tactical weights for Bumpball's BotBrain.",
		"-- Updated automatically by scripts/train-bot.luau (or edited by hand).",
		"",
		"local BotWeights = {",
		'\tDefault = "Normal",',
		"",
		formatTier("Easy", easyWeights),
		"",
		formatTier("Normal", normalWeights),
		"",
		formatTier("Pro", proWeights),
		"}",
		"",
		"function BotWeights.get(difficulty)",
		'\tif type(difficulty) == "string" and type(BotWeights[difficulty]) == "table" then',
		"\t\treturn BotWeights[difficulty]",
		"\tend",
		"\treturn BotWeights[BotWeights.Default]",
		"end",
		"",
		"return BotWeights",
		"",
	}, "\n")
	fs.writeFile(path, content)
end

local function loadCheckpoint(path)
	if fs.isFile(path) then
		local ok, decoded = pcall(function()
			return serde.decode("json", fs.readFile(path))
		end)
		if ok and type(decoded) == "table" and type(decoded.champion) == "table" then
			return decoded
		end
	end
	return {
		generation = 0,
		elo = 1200,
		totalMatches = 0,
		rngState = 20261121,
		champion = copyWeights(BotWeights.Pro),
		league = { copyWeights(BotWeights.Normal) },
	}
end

local function saveCheckpoint(path, state)
	local parent = path:match("^(.*)[/\\][^/\\]+$")
	if parent and parent ~= "" and not fs.isDir(parent) then
		fs.writeDir(parent)
	end
	fs.writeFile(path, serde.encode("json", state, true))
end

-- ===========================================================================
-- Main evolutionary training loop
-- ===========================================================================
local state = loadCheckpoint(cfg.checkpoint)
local rng = makeLcg(state.rngState)
local startClock = os.clock()
local maxSeconds = if cfg.minutes then cfg.minutes * 60 else nil
local gensRun = 0
local promotions = 0

print(string.format(
	"Bumpball Trainer starting | gen=%d elo=%d league=%d matches/gen=%d pairs dryRun=%s",
	state.generation,
	math.floor(state.elo),
	#state.league,
	cfg.matches,
	tostring(cfg.dryRun)
))

while true do
	if cfg.generations and gensRun >= cfg.generations then
		break
	end
	if maxSeconds and (os.clock() - startClock) >= maxSeconds then
		break
	end

	gensRun += 1
	state.generation += 1

	local challenger = mutateWeights(state.champion, rng)
	local opponents = { state.champion }
	for _, archived in ipairs(state.league) do
		table.insert(opponents, archived)
	end

	local score, wins, losses, draws, totalGames = evaluateChallenger(challenger, opponents, cfg.matches, rng)
	state.totalMatches += totalGames
	state.rngState = rng:state()

	local promoted = score > 0.52
	if promoted then
		promotions += 1
		table.insert(state.league, 1, copyWeights(state.champion))
		while #state.league > 6 do
			table.remove(state.league)
		end
		state.champion = challenger
		state.elo = math.floor(state.elo + 24 * (score - 0.5) + 0.5)
	end

	print(string.format(
		"Gen %d | W-L-D %d-%d-%d (score=%.3f) | %s | elo=%d | elapsed=%.1fs",
		state.generation,
		wins,
		losses,
		draws,
		score,
		if promoted then "PROMOTED" else "kept champion",
		math.floor(state.elo),
		os.clock() - startClock
	))

	if not cfg.dryRun then
		saveCheckpoint(cfg.checkpoint, state)
		if promoted then
			writeBotWeightsFile(cfg.out, state.champion)
		end
	end
end

print(string.format(
	"Bumpball Trainer finished | gensRun=%d promotions=%d totalMatches=%d elo=%d elapsed=%.1fs",
	gensRun,
	promotions,
	state.totalMatches,
	math.floor(state.elo),
	os.clock() - startClock
))

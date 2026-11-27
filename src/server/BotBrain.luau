--!nonstrict
-- 4-layer tactical Bot AI for Bumpball (Roblox Server & Lune compatible).
-- Layer 1: Kickoff formation selection.
-- Layer 2: 4-bobble role assignment & rotation (Striker, Keeper, Crate Runner/Camper, Support).
-- Layer 3: Ghost-ball aiming + fast scratch physics micro-sim evaluator with opponent threat prediction.
-- Layer 4: High-IQ Power Play decision engine.

local Shared = if game
	then game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	else script.Parent
local Physics = require(Shared.BobblePhysics)
local Round = require(Shared.PrototypeRound)
local Formations = require(Shared.KickoffFormations)
local Powers = require(Shared.PowerPlays)
local BotWeights = require(script.Parent.BotWeights)

local BotBrain = {}

local GOAL_LINE_X = 13.2
local FIELD_HALF_Z = Physics.FIELD_HALF_Z or 8.5
local CRATE_Z = 5.5
local GOAL_MOUTH_HALF_Z = 3.2

-- Reusable scratch simulation round so micro-sim candidates never mutate liveRound
-- and never pay static arena construction cost repeatedly.
local scratchRound = nil

local function getScratchRound()
	if not scratchRound then
		scratchRound = Round.new()
	end
	return scratchRound
end

-- Deterministic lightweight PRNG (avoids depending on Random:NextNumber in Lune test mocks).
local function makeRng(seed)
	local state = math.floor(math.abs(seed or 1337)) % 2147483647
	if state == 0 then
		state = 1337
	end
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

local function sampleRng(rng, fallbackSeed)
	if type(rng) == "function" then
		return rng()
	elseif type(rng) == "table" or type(rng) == "userdata" then
		if rng.NextNumber then
			return rng:NextNumber()
		elseif rng.NextInteger then
			return (rng:NextInteger(1, 10000) - 0.5) / 10000
		end
	end
	return makeRng(fallbackSeed)()
end

local function attackSign(round, team)
	local sign = if team == 0 then 1 else -1
	if round.goalsFlipped then
		sign = -sign
	end
	return sign
end

local function flatUnit(vec)
	local flat = Vector3.new(vec.X, 0, vec.Z)
	local mag = flat.Magnitude
	if mag ~= mag or mag < 1e-4 then
		return nil, 0
	end
	return flat / mag, mag
end

local function rotateFlat(dir, radians)
	local c = math.cos(radians)
	local s = math.sin(radians)
	local x = dir.X * c - dir.Z * s
	local z = dir.X * s + dir.Z * c
	local unit = flatUnit(Vector3.new(x, 0, z))
	return unit or dir
end

local function powerForDistance(dist)
	if dist <= 0.15 then
		return 0
	end
	return math.clamp(math.sqrt(dist / 24.0), 0.22, 1.0)
end

local function dirToYawDegrees(dir)
	-- Boost / ramp local +Z maps to (sin(yaw), 0, cos(yaw)) under CFrame.Angles(0, rad(yaw), 0).
	local deg = math.deg(math.atan2(dir.X, dir.Z))
	local snapped = math.floor(deg / Powers.RotationStep + 0.5) * Powers.RotationStep
	return snapped % 360
end

local function ghostBallDirection(shooterPos, ballPos, targetPos, shooterRadius, ballRadius)
	local toTarget, targetDist = flatUnit(targetPos - ballPos)
	if not toTarget or targetDist < 0.05 then
		return nil, 0
	end
	local contactOffset = (shooterRadius or 0.5) + (ballRadius or 0.5)
	local ghostPos = ballPos - toTarget * contactOffset
	local aimDir, aimDist = flatUnit(ghostPos - shooterPos)
	if not aimDir then
		aimDir, aimDist = flatUnit(ballPos - shooterPos)
	end
	if not aimDir then
		return nil, 0
	end
	local align = aimDir:Dot(toTarget)
	return aimDir, align, aimDist
end

local function teamRange(team)
	local first = team * 4 + 1
	return first, first + 3
end

local function findActiveCrate(round)
	if not round or not round.world or not round.world.triggers then
		return nil
	end
	for _, trigger in ipairs(round.world.triggers) do
		if trigger.kind == "crate" and not trigger.disabled and trigger.data and trigger.data.power ~= nil then
			return trigger
		end
	end
	return nil
end

local function isLaneBlocked(round, fromPos, toPos, ignoreA, ignoreB)
	local seg = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
	local len = seg.Magnitude
	if len < 0.1 then
		return false
	end
	local dir = seg / len
	for _, athlete in ipairs(round.athletes) do
		if athlete.id ~= ignoreA and athlete.id ~= ignoreB and not athlete.ghosted then
			local rel = Vector3.new(athlete.position.X - fromPos.X, 0, athlete.position.Z - fromPos.Z)
			local proj = rel:Dot(dir)
			if proj > 0.35 and proj < len - 0.35 then
				local perpSq = rel.Magnitude * rel.Magnitude - proj * proj
				local blockRadius = athlete.cfg.radius + 0.55
				if perpSq < blockRadius * blockRadius then
					return true, athlete
				end
			end
		end
	end
	return false, nil
end

-- ===========================================================================
-- Layer 1: Kickoff Formation Selection
-- ===========================================================================

local ATTACKING_WEIGHTS = {
	Easy = { forward = 0.34, option = 0.33, slant = 0.33 },
	Normal = { forward = 0.34, option = 0.34, slant = 0.32 },
	Pro = { forward = 0.34, option = 0.34, slant = 0.32 },
}

local DEFENDING_WEIGHTS = {
	Easy = { zone = 0.34, box = 0.33, rush = 0.33 },
	Normal = { zone = 0.34, box = 0.34, rush = 0.32 },
	Pro = { zone = 0.34, box = 0.34, rush = 0.32 },
}

function BotBrain.chooseFormation(team, attackingTeam, difficulty, rng, avoidFormation)
	local options = Formations.options(team, attackingTeam)
	if not options or #options == 0 then
		return "forward"
	end
	local tier = if type(difficulty) == "string" and ATTACKING_WEIGHTS[difficulty] then difficulty else "Normal"
	local tableWeights = if team == attackingTeam then ATTACKING_WEIGHTS[tier] else DEFENDING_WEIGHTS[tier]

	-- Filter out the previous kickoff formation when multiple options exist so the AI never spams one kickoff
	local pool = {}
	for _, id in ipairs(options) do
		if id ~= avoidFormation then
			table.insert(pool, id)
		end
	end
	if #pool == 0 then
		pool = options
	end

	local total = 0
	for _, id in ipairs(pool) do
		total += tableWeights[id] or 0.33
	end
	local u = if rng ~= nil then sampleRng(rng, (team + 1) * 97 + (attackingTeam + 1) * 31) else math.random()
	local roll = u * total
	local accum = 0
	for _, id in ipairs(pool) do
		accum += tableWeights[id] or 0.33
		if roll <= accum then
			return id
		end
	end
	return pool[1]
end

-- ===========================================================================
-- Layer 2: 4-Bobble Role Assignment & Rotation
-- ===========================================================================

local function assignRoles(round, team, turnId, weights)
	local atkSign = attackSign(round, team)
	local tgtGoal = Vector3.new(GOAL_LINE_X * atkSign, 0, 0)
	local ownGoal = Vector3.new(-GOAL_LINE_X * atkSign, 0, 0)
	local ballPos = round.ball.position

	local firstId, lastId = teamRange(team)
	local available = {}
	for id = firstId, lastId do
		table.insert(available, round.athletes[id])
	end

	-- 1. Striker: best bobble with a clean attacking approach behind the ball toward opponent goal.
	local strikerIndex = 1
	local bestStrikerScore = -math.huge
	for idx, athlete in ipairs(available) do
		local pos = athlete.position
		local _, align, aimDist = ghostBallDirection(pos, ballPos, tgtGoal, athlete.cfg.radius, round.ball.cfg.radius)
		local behindBall = (ballPos.X - pos.X) * atkSign
		local score = align * 14.0 - aimDist * 1.15
		if behindBall > 0.25 then
			score += 5.5
		elseif behindBall < -0.5 then
			score -= 8.0
		end
		if isLaneBlocked(round, pos, ballPos, athlete.id, nil) then
			score -= 3.5
		end
		if score > bestStrikerScore then
			bestStrikerScore = score
			strikerIndex = idx
		end
	end
	local striker = table.remove(available, strikerIndex)

	-- 2. Keeper: closest remaining bobble to own goal.
	local keeperIndex = 1
	local bestKeeperDist = math.huge
	for idx, athlete in ipairs(available) do
		local dx = athlete.position.X - ownGoal.X
		local dz = athlete.position.Z - ownGoal.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < bestKeeperDist then
			bestKeeperDist = d
			keeperIndex = idx
		end
	end
	local keeper = table.remove(available, keeperIndex)

	-- 3. Crate Runner / Camper (if inventory is empty).
	local activeCrate = findActiveCrate(round)
	local crateRunner = nil
	local crateTarget = nil
	local isCamping = false
	if round.held[team] == nil then
		if activeCrate then
			crateTarget = activeCrate.center
		elseif turnId % 2 == 0 then
			-- Pre-position near the opposite crate spawn for the upcoming odd turn.
			local campZ = CRATE_Z
			if round.lastPickup and round.lastPickup.center then
				campZ = if round.lastPickup.center.Z >= 0 then -CRATE_Z else CRATE_Z
			elseif ballPos.Z >= 0 then
				campZ = -CRATE_Z
			end
			crateTarget = Vector3.new(0, 0, campZ)
			isCamping = true
		end
		if crateTarget and #available > 0 then
			local bestIdx = 1
			local bestDist = math.huge
			for idx, athlete in ipairs(available) do
				local dx = athlete.position.X - crateTarget.X
				local dz = athlete.position.Z - crateTarget.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < bestDist then
					bestDist = d
					bestIdx = idx
				end
			end
			crateRunner = table.remove(available, bestIdx)
		end
	end

	-- 4. Support (remaining 1 or 2 bobbles).
	local supports = available

	return {
		atkSign = atkSign,
		tgtGoal = tgtGoal,
		ownGoal = ownGoal,
		striker = striker,
		keeper = keeper,
		crateRunner = crateRunner,
		crateTarget = crateTarget,
		isCamping = isCamping,
		supports = supports,
		weights = weights,
	}
end

local function makeMoveToPoint(athlete, targetPos, minDist, powerBoost, maxPower)
	local dir, dist = flatUnit(targetPos - athlete.position)
	if not dir or dist < (minDist or 0.45) then
		return nil
	end
	local power = math.clamp(powerForDistance(dist) + (powerBoost or 0), 0.22, maxPower or 1.0)
	return { id = athlete.id, direction = dir, power = power }
end

local function findOpponentThreatStriker(round, opponentTeam)
	local oppAtkSign = attackSign(round, opponentTeam)
	local oppGoal = Vector3.new(GOAL_LINE_X * oppAtkSign, 0, 0)
	local ballPos = round.ball.position
	local firstId, lastId = teamRange(opponentTeam)
	local bestAthlete, bestScore, bestDir = nil, -math.huge, nil
	for id = firstId, lastId do
		local athlete = round.athletes[id]
		local aimDir, align, aimDist = ghostBallDirection(athlete.position, ballPos, oppGoal, athlete.cfg.radius, round.ball.cfg.radius)
		if aimDir then
			local score = align * 10.0 - aimDist
			if (ballPos.X - athlete.position.X) * oppAtkSign > 0 then
				score += 4.0
			end
			if score > bestScore then
				bestScore = score
				bestAthlete = athlete
				bestDir = aimDir
			end
		end
	end
	return bestAthlete, bestDir
end

local function buildBaseRoleMoves(round, team, roles)
	local moves = {}
	local atkSign = roles.atkSign
	local ballPos = round.ball.position
	local ownX = roles.ownGoal.X

	-- Keeper movement: guard goal-defense bisector line or clear immediate danger.
	local keeper = roles.keeper
	if keeper then
		local ballDistToOwn = (ballPos.X - ownX) * atkSign
		local dangerousBall = ballDistToOwn < 5.5 and math.abs(ballPos.Z) < 5.0
		local keeperBehindBall = (ballPos.X - keeper.position.X) * atkSign > 0.2
		if dangerousBall and keeperBehindBall then
			local clearZ = if ballPos.Z >= 0 then 6.8 else -6.8
			local clearTarget = Vector3.new(ballPos.X + atkSign * 7.5, 0, clearZ)
			local clearDir, align = ghostBallDirection(keeper.position, ballPos, clearTarget, keeper.cfg.radius, round.ball.cfg.radius)
			if clearDir and align > 0.25 then
				moves[keeper.id] = { id = keeper.id, direction = clearDir, power = 0.95 }
			end
		end
		if not moves[keeper.id] then
			local guardX = ownX + atkSign * 2.1
			local guardZ = math.clamp(ballPos.Z * 0.42, -2.5, 2.5)
			local guardTarget = Vector3.new(guardX, 0, guardZ)
			-- Avoid driving straight through the ball into our own net when retreating to guard.
			local toGuard, guardDist = flatUnit(guardTarget - keeper.position)
			if toGuard and toGuard.X * (-atkSign) > 0.2 then
				local toBall = Vector3.new(ballPos.X - keeper.position.X, 0, ballPos.Z - keeper.position.Z)
				local proj = toBall:Dot(toGuard)
				local perpSq = toBall.Magnitude * toBall.Magnitude - proj * proj
				if proj > 0 and proj < guardDist + 1.8 and perpSq < 2.2 * 2.2 then
					local sidestepZ = if ballPos.Z >= 0 then -2.6 else 2.6
					guardTarget = Vector3.new(math.clamp(ballPos.X - atkSign * 0.5, -11.5, 11.5), 0, sidestepZ)
				end
			end
			moves[keeper.id] = makeMoveToPoint(keeper, guardTarget, 0.55, 0.05, 0.85)
		end
	end

	-- Crate Runner / Camper movement.
	local runner = roles.crateRunner
	if runner and roles.crateTarget then
		if roles.isCamping then
			moves[runner.id] = makeMoveToPoint(runner, roles.crateTarget, 0.7, 0.0, 0.78)
		else
			-- Drive cleanly through active crate.
			local dir, dist = flatUnit(roles.crateTarget - runner.position)
			if dir and dist > 0.25 then
				local pwr = math.clamp(powerForDistance(dist + 1.8), 0.45, 0.95)
				moves[runner.id] = { id = runner.id, direction = dir, power = pwr }
			end
		end
	end

	-- Support movement: bump dangerous opponent striker OR stage a 1-2 pass lane.
	local oppThreat = findOpponentThreatStriker(round, 1 - team)
	for idx, sup in ipairs(roles.supports) do
		local move = nil
		if idx == 1 and oppThreat then
			local toOpp, oppDist = flatUnit(oppThreat.position - sup.position)
			local oppBallDist = (Vector3.new(oppThreat.position.X - ballPos.X, 0, oppThreat.position.Z - ballPos.Z)).Magnitude
			if toOpp and oppBallDist < 5.5 and oppDist < 8.5 then
				-- Check that bumping won't accidentally drive through the ball toward our own net.
				local dotOwn = toOpp:Dot(Vector3.new(-atkSign, 0, 0))
				local ballOnLine = (Vector3.new(ballPos.X - sup.position.X, 0, ballPos.Z - sup.position.Z)):Dot(toOpp)
				local safeBump = not (dotOwn > 0.45 and ballOnLine > 0 and ballOnLine < oppDist)
				if safeBump then
					move = { id = sup.id, direction = toOpp, power = math.clamp(powerForDistance(oppDist + 2.5), 0.55, 0.95) }
				end
			end
		end
		if not move then
			local laneZ = if ballPos.Z >= 0 then -2.8 else 2.8
			if idx == 2 then
				laneZ = -laneZ
			end
			local laneX = math.clamp(ballPos.X + atkSign * 3.8, -10.5, 10.5)
			-- Avoid crossing straight through the striker's approach lane to the ball
			local striker = roles.striker
			if striker then
				local midX = (striker.position.X + ballPos.X) * 0.5
				local midZ = (striker.position.Z + ballPos.Z) * 0.5
				if math.abs(laneX - midX) < 1.6 and math.abs(laneZ - midZ) < 1.6 then
					laneZ = if laneZ >= 0 then math.min(6.4, laneZ + 2.2) else math.max(-6.4, laneZ - 2.2)
				end
			end
			move = makeMoveToPoint(sup, Vector3.new(laneX, 0, laneZ), 0.65, 0.0, 0.82)
		end
		if move then
			moves[sup.id] = move
		end
	end

	return moves
end

-- ===========================================================================
-- Layer 3: Scratch Clone + Micro-Sim Evaluator
-- ===========================================================================

local function cloneIntoScratch(liveRound, scratch, pendingPower)
	scratch:expirePowers()
	scratch.world:clearContacts()
	scratch.world:clearTriggerOccupancy()

	-- Sync ball
	if scratch.ball.cfg ~= liveRound.ball.cfg then
		Physics.setSphereConfig(scratch.ball, liveRound.ball.cfg)
	end
	scratch.ball.position = liveRound.ball.position
	scratch.ball.velocity = liveRound.ball.velocity
	scratch.ball.angularVelocity = liveRound.ball.angularVelocity
	scratch.ball.rotation = liveRound.ball.rotation
	scratch.ball.grounded = liveRound.ball.grounded
	scratch.giantBallActive = liveRound.giantBallActive

	-- Sync all 8 athletes
	for i, liveAth in ipairs(liveRound.athletes) do
		local scAth = scratch.athletes[i]
		if scAth.cfg ~= liveAth.cfg then
			Physics.setSphereConfig(scAth, liveAth.cfg)
		end
		scAth.position = liveAth.position
		scAth.velocity = liveAth.velocity
		scAth.angularVelocity = liveAth.angularVelocity
		scAth.rotation = liveAth.rotation
		scAth.grounded = liveAth.grounded
		scAth.ghosted = liveAth.ghosted
	end

	scratch.goalsFlipped = liveRound.goalsFlipped
	scratch.attackingTeam = liveRound.attackingTeam
	scratch.attackingFormation = liveRound.attackingFormation
	scratch.resolving = false
	scratch.ticks = 0
	scratch.scorer = nil
	scratch.goalTick = nil
	scratch.goalPosition = nil
	scratch.ballTouch = nil
	scratch.ballBank = nil
	scratch.magnetPull = nil
	scratch.held = { [0] = liveRound.held[0], [1] = liveRound.held[1] }

	-- Sync crate triggers
	for i, liveTrig in ipairs(liveRound.world.triggers) do
		local scTrig = scratch.world.triggers[i]
		if scTrig and liveTrig.kind == "crate" and scTrig.kind == "crate" then
			scTrig.data.power = liveTrig.data and liveTrig.data.power or nil
			scratch.world:setTriggerEnabled(scTrig, not liveTrig.disabled)
		end
	end

	-- Re-apply active placed powers / armor / magnets / bigbumpers without re-running instant teleports/flips.
	for _, active in ipairs(liveRound.activePowers) do
		local k = active.kind
		if Powers.Interaction[k] == "placed" then
			scratch:placePower({ kind = k, x = active.x, z = active.z, yaw = active.yaw })
		elseif k == "armor" and not active.spent and active.id then
			scratch.armor[active.id] = { kind = "armor", id = active.id }
		elseif k == "magnet" and not active.spent and active.id then
			scratch.magnets[active.id] = { kind = "magnet", id = active.id }
		elseif k == "bigbumpers" then
			scratch:placePower({ kind = "bigbumpers" })
		end
	end

	-- Apply the bot's pending power decision to scratch so planned moves match it!
	if pendingPower then
		if pendingPower.kind == "steal" then
			scratch:stealPower(pendingPower.team)
		else
			local copy = {
				kind = pendingPower.kind,
				team = pendingPower.team,
				id = pendingPower.id,
				x = pendingPower.x or 0,
				z = pendingPower.z or 0,
				yaw = pendingPower.yaw or 0,
			}
			scratch:placePower(copy)
		end
	end
end

local function cloneMoveMap(base)
	local copy = {}
	for id, move in pairs(base) do
		copy[id] = move
	end
	return copy
end

local function buildCandidates(round, team, roles, baseMoves, weights)
	local candidates = {}
	local striker = roles.striker
	local ballPos = round.ball.position
	local atkSign = roles.atkSign
	local tgtX = roles.tgtGoal.X
	local ownX = roles.ownGoal.X
	local sr = striker.cfg.radius
	local br = round.ball.cfg.radius

	local function addCandidate(overrideMap, tag)
		local merged = cloneMoveMap(baseMoves)
		for id, mv in pairs(overrideMap) do
			merged[id] = mv
		end
		table.insert(candidates, { moves = merged, tag = tag })
	end

	local ballNearOwnGoal = (ballPos.X - ownX) * atkSign < 5.2
	local ballNearTgtGoal = (tgtX - ballPos.X) * atkSign < 3.5
	-- Aim slightly past the goal line so ghostBallDirection never degenerates when the ball sits on the line.
	local aimGoalX = tgtX + atkSign * 1.8

	-- 1. Direct ghost-ball shots at center, left post, right post across power levels.
	local goalTargets = {
		Vector3.new(aimGoalX, 0, 0),
		Vector3.new(aimGoalX, 0, 2.2),
		Vector3.new(aimGoalX, 0, -2.2),
	}
	local shotPowers = { 1.0, 0.85, 0.65 }
	for _, target in ipairs(goalTargets) do
		local aimDir, align = ghostBallDirection(striker.position, ballPos, target, sr, br)
		if aimDir and align > (if ballNearTgtGoal then -0.1 else 0.15) then
			-- Guard against hitting backward when ball is near our own goal.
			local towardOwn = aimDir.X * (-atkSign)
			if not (ballNearOwnGoal and towardOwn > 0.25) then
				for _, pwr in ipairs(shotPowers) do
					addCandidate({ [striker.id] = { id = striker.id, direction = aimDir, power = pwr } }, "direct")
				end
			end
		end
	end

	-- 1b. Goal-line tap-in fallback when ball is right on the opponent's goal line.
	if ballNearTgtGoal then
		local tapDir = flatUnit(ballPos - striker.position)
		if tapDir and tapDir.X * atkSign > 0.1 then
			addCandidate({ [striker.id] = { id = striker.id, direction = tapDir, power = 0.85 } }, "tapIn")
		end
	end

	-- 2. Rail-mirrored bank shots (top & bottom walls at Z = ±8.5).
	local bankTargets = {
		Vector3.new(tgtX, 0, 2 * FIELD_HALF_Z),
		Vector3.new(tgtX, 0, -2 * FIELD_HALF_Z),
	}
	for _, bankTarget in ipairs(bankTargets) do
		local aimDir, align = ghostBallDirection(striker.position, ballPos, bankTarget, sr, br)
		if aimDir and align > 0.18 then
			local towardOwn = aimDir.X * (-atkSign)
			if not (ballNearOwnGoal and towardOwn > 0.2) then
				addCandidate({ [striker.id] = { id = striker.id, direction = aimDir, power = 1.0 } }, "bank")
			end
		end
	end

	-- 3. 2-bobble pass combo: striker feeds toward support, support drives toward goal.
	local firstSup = roles.supports[1]
	if firstSup then
		local passSpot = Vector3.new(
			math.clamp(ballPos.X + atkSign * 3.5, -10.5, 10.5),
			0,
			math.clamp(firstSup.position.Z * 0.7, -5.0, 5.0)
		)
		local passDir, passAlign = ghostBallDirection(striker.position, ballPos, passSpot, sr, br)
		local supDir = flatUnit(Vector3.new(tgtX, 0, 0) - firstSup.position)
		if passDir and passAlign > 0.1 and supDir then
			addCandidate({
				[striker.id] = { id = striker.id, direction = passDir, power = 0.72 },
				[firstSup.id] = { id = firstSup.id, direction = supDir, power = 0.9 },
			}, "pass")
		end
	end

	-- 4. Defensive clearances (diagonal away from own goal toward sidelines / midfield).
	for _, clearZ in ipairs({ 6.5, -6.5 }) do
		local clearTarget = Vector3.new(ballPos.X + atkSign * 7.5, 0, clearZ)
		local clearDir, align = ghostBallDirection(striker.position, ballPos, clearTarget, sr, br)
		if clearDir and align > 0.05 and clearDir.X * atkSign > -0.15 then
			addCandidate({ [striker.id] = { id = striker.id, direction = clearDir, power = 0.95 } }, "clear")
		end
	end

	-- 5. Reposition striker behind ball (safe fallback when striker is on the wrong side of the ball!).
	local behindSpot = Vector3.new(
		math.clamp(ballPos.X - atkSign * 2.8, -11.2, 11.2),
		0,
		math.clamp(ballPos.Z + (if ballPos.Z >= 0 then -1.6 else 1.6), -6.8, 6.8)
	)
	local repoMove = makeMoveToPoint(striker, behindSpot, 0.4, 0.05, 0.85)
	if repoMove then
		addCandidate({ [striker.id] = repoMove }, "reposition")
	end

	-- 6. Alternate striker candidate (if a support bobble is actually behind the ball).
	if firstSup and (ballPos.X - firstSup.position.X) * atkSign > 0.25 then
		local altDir, altAlign = ghostBallDirection(firstSup.position, ballPos, roles.tgtGoal, firstSup.cfg.radius, br)
		if altDir and altAlign > 0.2 then
			addCandidate({ [firstSup.id] = { id = firstSup.id, direction = altDir, power = 1.0 } }, "altStriker")
		end
	end

	-- 7. Pure base-role defensive fallback (only when baseMoves is non-empty; never submit an empty "give up" plan).
	if next(baseMoves) ~= nil then
		addCandidate({}, "hold")
	end

	-- Cap to weights.simCandidates while always keeping at least one safe clearance/reposition candidate.
	local limit = math.max(4, math.floor(weights.simCandidates or 12))
	if #candidates > limit then
		local trimmed = {}
		for i = 1, limit - 1 do
			trimmed[i] = candidates[i]
		end
		trimmed[limit] = candidates[#candidates]
		candidates = trimmed
	end

	return candidates
end

local function evaluateState(liveRound, scratch, team, roles, turnId, weights, oppThreatBefore)
	local score = 0
	local atkSign = roles.atkSign
	local ownX = roles.ownGoal.X
	local tgtX = roles.tgtGoal.X
	local startBallX = liveRound.ball.position.X
	local endBall = scratch.ball.position

	-- Goal / Concede / Own-Goal scoring
	if scratch.scorer == team then
		score += weights.goalScore + (120 - math.min(120, scratch.ticks)) * 1.5
		if scratch.ballBank ~= nil then
			score += weights.bankBonus
		end
	elseif scratch.scorer == 1 - team then
		score -= weights.concedePenalty
		if scratch.ballTouch and scratch.ballTouch.team == team then
			score -= weights.ownGoalPenalty
		end
	end

	-- Ball progress & field position
	local deltaX = (endBall.X - startBallX) * atkSign
	score += deltaX * weights.ballProgress
	score += (endBall.X * atkSign / GOAL_LINE_X) * weights.ballProgress * 2.2

	-- Alignment toward opponent goal & danger penalty near own goal
	local distToTarget = math.sqrt((tgtX - endBall.X) ^ 2 + endBall.Z ^ 2)
	local distToOwn = math.sqrt((ownX - endBall.X) ^ 2 + endBall.Z ^ 2)
	score += (18.0 - math.min(18.0, distToTarget)) * (weights.ballGoalAlign * 0.45)
	if distToOwn < 5.5 then
		score -= (5.5 - distToOwn) * (weights.ballGoalAlign * 1.6)
	end
	if math.abs(endBall.Z) < GOAL_MOUTH_HALF_Z and (endBall.X * atkSign) > 4.0 then
		score += weights.ballGoalAlign * 0.8
	end

	-- Crate pickup reward
	if liveRound.held[team] == nil and scratch.held[team] ~= nil then
		score += weights.crateGrab
	end

	-- Crate camping reward on even turns with empty inventory
	if turnId % 2 == 0 and liveRound.held[team] == nil and roles.crateTarget then
		local firstId, lastId = teamRange(team)
		local bestDist = math.huge
		for id = firstId, lastId do
			local p = scratch.athletes[id].position
			local d = math.sqrt((p.X - roles.crateTarget.X) ^ 2 + (p.Z - roles.crateTarget.Z) ^ 2)
			if d < bestDist then
				bestDist = d
			end
		end
		if bestDist < 2.8 then
			score += weights.crateCamp * (1.0 - bestDist / 2.8)
		end
	end

	-- Keeper guard reward
	local guardX = ownX + atkSign * 2.1
	local guardZ = math.clamp(endBall.Z * 0.42, -2.5, 2.5)
	local firstId, lastId = teamRange(team)
	local bestGuardDist = math.huge
	for id = firstId, lastId do
		local p = scratch.athletes[id].position
		local d = math.sqrt((p.X - guardX) ^ 2 + (p.Z - guardZ) ^ 2)
		if d < bestGuardDist then
			bestGuardDist = d
		end
	end
	if bestGuardDist < 3.5 then
		score += weights.keeperGuard * (1.0 - bestGuardDist / 3.5)
	end

	-- Striker bump / disruption reward
	if oppThreatBefore then
		local oppAfter = scratch.athletes[oppThreatBefore.id]
		if oppAfter then
			local oppBallDist = math.sqrt((oppAfter.position.X - endBall.X) ^ 2 + (oppAfter.position.Z - endBall.Z) ^ 2)
			if oppBallDist > 3.0 then
				score += weights.strikerBump * math.min(1.0, (oppBallDist - 3.0) / 5.0)
			end
		end
	end

	-- Pass setup reward: friendly bobble behind the new ball with clean line to goal
	local bestFollow = 0
	for id = firstId, lastId do
		local p = scratch.athletes[id].position
		if (endBall.X - p.X) * atkSign > 0.3 then
			local d = math.sqrt((endBall.X - p.X) ^ 2 + (endBall.Z - p.Z) ^ 2)
			if d < 6.0 then
				local val = 1.0 - d / 6.0
				if val > bestFollow then
					bestFollow = val
				end
			end
		end
	end
	score += bestFollow * weights.passSetup

	return score
end

-- ===========================================================================
-- Layer 4: High-IQ Power Play Decisions
-- ===========================================================================

local function findLegalPlacement(round, team, kind, candidates)
	for _, c in ipairs(candidates) do
		local power = {
			kind = kind,
			team = team,
			x = math.clamp(c.x, -11.6, 11.6),
			z = math.clamp(c.z, -7.3, 7.3),
			yaw = (c.yaw or 0) % 360,
		}
		if Powers.isLegal(power, round) then
			return power
		end
	end
	return nil
end

function BotBrain.choosePower(round, team, weights)
	local kind = round.held[team]
	if not kind then
		return nil
	end
	weights = weights or BotWeights.get(nil)
	local aggr = weights.powerAggression or 0.85
	local atkSign = attackSign(round, team)
	local ballPos = round.ball.position
	local ownX = -GOAL_LINE_X * atkSign
	local tgtX = GOAL_LINE_X * atkSign
	local firstId, lastId = teamRange(team)

	if kind == "steal" then
		if round.held[1 - team] ~= nil then
			return { kind = "steal", team = team }
		end
		return nil
	end

	if kind == "goalswap" then
		local ballDistToOwn = (ballPos.X - ownX) * atkSign
		if ballDistToOwn < 6.5 * aggr + 1.0 then
			return { kind = "goalswap", team = team, x = 0, z = 0, yaw = 0 }
		end
		return nil
	end

	if kind == "yellowcard" then
		if ballPos.X * atkSign < -3.5 then
			return { kind = "yellowcard", team = team, x = 0, z = 0, yaw = 0 }
		end
		return nil
	end

	if kind == "giantball" then
		if ballPos.X * atkSign > -1.0 or aggr >= 0.85 then
			return { kind = "giantball", team = team, x = 0, z = 0, yaw = 0 }
		end
		return nil
	end

	if kind == "bigbumpers" then
		if math.abs(ballPos.Z) > 3.0 or aggr >= 0.9 then
			return { kind = "bigbumpers", team = team, x = 0, z = 0, yaw = 0 }
		end
		return nil
	end

	if kind == "armor" or kind == "bighead" then
		-- Equip on our best striker (closest owned bobble behind/near the ball).
		local bestId, bestScore = nil, -math.huge
		for id = firstId, lastId do
			local ath = round.athletes[id]
			if Powers.canTarget(kind, ath, round.activePowers) then
				local d = (Vector3.new(ballPos.X - ath.position.X, 0, ballPos.Z - ath.position.Z)).Magnitude
				local s = -d + (if (ballPos.X - ath.position.X) * atkSign > 0 then 3.5 else 0)
				if s > bestScore then
					bestScore = s
					bestId = id
				end
			end
		end
		if bestId then
			local ath = round.athletes[bestId]
			return { kind = kind, team = team, id = bestId, x = ath.position.X, z = ath.position.Z, yaw = 0 }
		end
		return nil
	end

	if kind == "magnet" then
		local bestId, bestDist = nil, math.huge
		for id = firstId, lastId do
			local ath = round.athletes[id]
			if Powers.canTarget("magnet", ath, round.activePowers) then
				local d = (Vector3.new(ballPos.X - ath.position.X, 0, ballPos.Z - ath.position.Z)).Magnitude
				if d < bestDist then
					bestDist = d
					bestId = id
				end
			end
		end
		if bestId and bestDist < 7.5 then
			local ath = round.athletes[bestId]
			return { kind = "magnet", team = team, id = bestId, x = ath.position.X, z = ath.position.Z, yaw = 0 }
		end
		return nil
	end

	if kind == "ghost" then
		for id = firstId, lastId do
			local ath = round.athletes[id]
			if Powers.canTarget("ghost", ath, round.activePowers) then
				local blocked = isLaneBlocked(round, ath.position, ballPos, id, nil)
				if blocked then
					return { kind = "ghost", team = team, id = id, x = ath.position.X, z = ath.position.Z, yaw = 0 }
				end
			end
		end
		return nil
	end

	if kind == "redcard" then
		local oppThreat = findOpponentThreatStriker(round, 1 - team)
		if oppThreat and Powers.canTarget("redcard", oppThreat, round.activePowers) then
			return {
				kind = "redcard",
				team = team,
				id = oppThreat.id,
				x = oppThreat.position.X,
				z = oppThreat.position.Z,
				yaw = 0,
			}
		end
		return nil
	end

	if kind == "block" then
		local bx = ownX + atkSign * 2.8
		local bz = math.clamp(ballPos.Z * 0.45, -2.4, 2.4)
		return findLegalPlacement(round, team, "block", {
			{ x = bx, z = bz, yaw = 90 },
			{ x = bx + atkSign * 1.4, z = bz, yaw = 90 },
			{ x = bx, z = bz + 1.6, yaw = 90 },
			{ x = bx, z = bz - 1.6, yaw = 90 },
		})
	end

	if kind == "boost" or kind == "ramp" then
		local toGoal = flatUnit(Vector3.new(tgtX, 0, 0) - ballPos) or Vector3.new(atkSign, 0, 0)
		local yaw = dirToYawDegrees(toGoal)
		local candidates = {
			{ x = ballPos.X + toGoal.X * 2.4, z = ballPos.Z + toGoal.Z * 2.4, yaw = yaw },
			{ x = ballPos.X + toGoal.X * 3.6, z = ballPos.Z + toGoal.Z * 3.6, yaw = yaw },
			{ x = ballPos.X - toGoal.X * 2.4, z = ballPos.Z - toGoal.Z * 2.4, yaw = yaw },
			{ x = atkSign * 4.0, z = 0, yaw = yaw },
		}
		return findLegalPlacement(round, team, kind, candidates)
	end

	return nil
end

-- ===========================================================================
-- Main Entry Point: BotBrain.planTurn
-- ===========================================================================

local function evaluateCandidatePlan(round, scratch, team, turnId, weights, candidatePower)
	cloneIntoScratch(round, scratch, candidatePower)
	local roles = assignRoles(scratch, team, turnId, weights)
	local baseMoves = buildBaseRoleMoves(scratch, team, roles)
	local oppThreat, oppThreatDir = findOpponentThreatStriker(scratch, 1 - team)
	local oppMove = if oppThreat and oppThreatDir
		then { id = oppThreat.id, direction = oppThreatDir, power = 0.9 }
		else nil

	local candidates = buildCandidates(scratch, team, roles, baseMoves, weights)
	local simTicks = math.clamp(math.floor(weights.simTicks or 85), 30, 180)
	local bestMoves = baseMoves
	local bestScore = -math.huge
	local scoredGoal = false

	for _, cand in ipairs(candidates) do
		cloneIntoScratch(round, scratch, candidatePower)
		local launchMap = {}
		for id, mv in pairs(cand.moves) do
			launchMap[id] = mv
		end
		if oppMove then
			launchMap[oppMove.id] = oppMove
		end
		if scratch:launchMoves(launchMap, false) then
			for _ = 1, simTicks do
				scratch:step()
				if not scratch.resolving then
					break
				end
			end
		end
		local sc = evaluateState(round, scratch, team, roles, turnId, weights, oppThreat)
		if sc > bestScore then
			bestScore = sc
			bestMoves = cand.moves
			scoredGoal = (scratch.scorer == team)
		end
	end

	return bestMoves, bestScore, roles, scoredGoal
end

function BotBrain.planTurn(round, team, turnId, difficulty, customWeights, matchCtx)
	local baseWeights = customWeights or BotWeights.get(difficulty)
	local weights = baseWeights
	local isGoldenGoal = matchCtx ~= nil and matchCtx.goldenGoal == true
	if isGoldenGoal then
		-- Clutch Golden Goal weighting: tighten defense & seize decisive Power Plays
		weights = table.clone(baseWeights)
		weights.concedePenalty = (baseWeights.concedePenalty or 600) * 1.45
		weights.ownGoalPenalty = (baseWeights.ownGoalPenalty or 1200) * 1.4
		weights.powerAggression = math.min(1.0, (baseWeights.powerAggression or 0.5) * 1.35)
	end
	turnId = turnId or 1

	-- Layer 4: Decide candidate Power Play
	local chosenPower = BotBrain.choosePower(round, team, weights)
	local scratch = getScratchRound()

	-- Evaluate best move plan with chosenPower
	local bestMoves, bestScore, roles, scoredGoal = evaluateCandidatePlan(round, scratch, team, turnId, weights, chosenPower)

	-- Smart Power-vs-Hold evaluation (Normal/Pro): don't burn a valuable crate power if holding it is almost as good!
	if chosenPower ~= nil and chosenPower.kind ~= "steal" and (weights.simCandidates or 8) >= 12 then
		local holdMoves, holdScore, holdRoles = evaluateCandidatePlan(round, scratch, team, turnId, weights, nil)
		local minGain = if isGoldenGoal then 4 else 22
		if not scoredGoal and bestScore < holdScore + minGain then
			chosenPower = nil
			bestMoves = holdMoves
			bestScore = holdScore
			roles = holdRoles
		end
	end

	-- Sync scratch once to winning state for fallback safety checks
	cloneIntoScratch(round, scratch, chosenPower)

	-- Build dense, sorted, ValidatePlan-safe array of up to 4 moves (applying aimJitter if > 0).
	local jitter = weights.aimJitter or 0
	local rng = makeRng(turnId * 1009 + team * 313 + math.floor((round.ball.position.X + 20) * 37))
	local denseMoves = {}
	local firstId, lastId = teamRange(team)
	for id = firstId, lastId do
		local mv = bestMoves[id]
		if mv and mv.direction and mv.power and mv.power > 0 then
			local dir = flatUnit(mv.direction)
			if dir then
				if jitter > 0 then
					local angle = (rng() * 2 - 1) * jitter
					dir = rotateFlat(dir, angle)
				end
				table.insert(denseMoves, {
					id = id,
					direction = dir,
					power = math.clamp(mv.power, 0.05, 1.0),
				})
			end
		end
	end

	-- Safety net: never return an empty move list (e.g. when ball is on either goal line).
	if #denseMoves == 0 then
		local fallbackAth = roles.striker or roles.keeper or scratch.athletes[firstId]
		if fallbackAth then
			local ballPos = scratch.ball.position
			local atkSign = roles.atkSign
			local ballNearOwn = (ballPos.X - roles.ownGoal.X) * atkSign < 5.2
			local fallbackDir = nil
			local fallbackPower = 0.85
			if ballNearOwn then
				-- If behind ball, clear diagonally away from own goal; otherwise sidestep/reposition safely.
				if (ballPos.X - fallbackAth.position.X) * atkSign > 0.15 then
					local clearZ = if ballPos.Z >= 0 then 6.5 else -6.5
					fallbackDir = flatUnit(Vector3.new(ballPos.X + atkSign * 7.5, 0, clearZ) - fallbackAth.position)
				else
					local safeSpot = Vector3.new(
						math.clamp(ballPos.X - atkSign * 2.4, -11.2, 11.2),
						0,
						if ballPos.Z >= 0 then -2.6 else 2.6
					)
					fallbackDir = flatUnit(safeSpot - fallbackAth.position)
					fallbackPower = 0.72
				end
			else
				fallbackDir = flatUnit(ballPos - fallbackAth.position)
			end
			if not fallbackDir then
				fallbackDir = Vector3.new(atkSign, 0, 0)
			end
			table.insert(denseMoves, {
				id = fallbackAth.id,
				direction = fallbackDir,
				power = fallbackPower,
			})
		end
	end

	return {
		moves = denseMoves,
		power = chosenPower,
	}
end

return BotBrain

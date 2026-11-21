--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 1000.0,
		concedePenalty = 320.0,
		ownGoalPenalty = 380.0,
		ballProgress = 14.0,
		ballGoalAlign = 10.0,
		crateGrab = 42.0,
		crateCamp = 10.0,
		keeperGuard = 18.0,
		strikerBump = 12.0,
		passSetup = 12.0,
		bankBonus = 18.0,
		powerAggression = 0.55,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 1200.0,
		concedePenalty = 480.0,
		ownGoalPenalty = 550.0,
		ballProgress = 20.0,
		ballGoalAlign = 18.0,
		crateGrab = 65.0,
		crateCamp = 18.0,
		keeperGuard = 30.0,
		strikerBump = 22.0,
		passSetup = 22.0,
		bankBonus = 28.0,
		powerAggression = 0.85,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1400.0,
		concedePenalty = 620.0,
		ownGoalPenalty = 720.0,
		ballProgress = 26.0,
		ballGoalAlign = 24.0,
		crateGrab = 82.0,
		crateCamp = 24.0,
		keeperGuard = 40.0,
		strikerBump = 30.0,
		passSetup = 30.0,
		bankBonus = 36.0,
		powerAggression = 1.0,
		aimJitter = 0.0,
		simCandidates = 16,
		simTicks = 105,
	},
}

function BotWeights.get(difficulty)
	if type(difficulty) == "string" and type(BotWeights[difficulty]) == "table" then
		return BotWeights[difficulty]
	end
	return BotWeights[BotWeights.Default]
end

return BotWeights

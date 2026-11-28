--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 646.775,
		concedePenalty = 277.551,
		ownGoalPenalty = 1008.466,
		ballProgress = 29.507,
		ballGoalAlign = 25.552,
		crateGrab = 99.715,
		crateCamp = 17.6,
		keeperGuard = 22.331,
		strikerBump = 47.75,
		passSetup = 42.836,
		bankBonus = 33.532,
		powerAggression = 0.35,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 845.783,
		concedePenalty = 362.951,
		ownGoalPenalty = 1318.763,
		ballProgress = 38.587,
		ballGoalAlign = 33.414,
		crateGrab = 130.397,
		crateCamp = 23.015,
		keeperGuard = 29.203,
		strikerBump = 62.443,
		passSetup = 56.017,
		bankBonus = 43.85,
		powerAggression = 0.391,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 995.039,
		concedePenalty = 427.001,
		ownGoalPenalty = 1551.486,
		ballProgress = 45.396,
		ballGoalAlign = 39.31,
		crateGrab = 153.408,
		crateCamp = 27.077,
		keeperGuard = 34.356,
		strikerBump = 73.462,
		passSetup = 65.902,
		bankBonus = 51.588,
		powerAggression = 0.46,
		aimJitter = 0,
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

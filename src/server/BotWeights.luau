--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 608.44,
		concedePenalty = 400.895,
		ownGoalPenalty = 941.81,
		ballProgress = 22.659,
		ballGoalAlign = 18.515,
		crateGrab = 104,
		crateCamp = 14.992,
		keeperGuard = 21.357,
		strikerBump = 33.509,
		passSetup = 26.116,
		bankBonus = 32.196,
		powerAggression = 0.35,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 795.653,
		concedePenalty = 524.247,
		ownGoalPenalty = 1231.597,
		ballProgress = 29.631,
		ballGoalAlign = 24.212,
		crateGrab = 136,
		crateCamp = 19.605,
		keeperGuard = 27.928,
		strikerBump = 43.82,
		passSetup = 34.152,
		bankBonus = 42.103,
		powerAggression = 0.425,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 936.062,
		concedePenalty = 616.761,
		ownGoalPenalty = 1448.938,
		ballProgress = 34.86,
		ballGoalAlign = 28.485,
		crateGrab = 160,
		crateCamp = 23.065,
		keeperGuard = 32.857,
		strikerBump = 51.553,
		passSetup = 40.179,
		bankBonus = 49.533,
		powerAggression = 0.5,
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

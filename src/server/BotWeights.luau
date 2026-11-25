--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 1190.872,
		concedePenalty = 162.5,
		ownGoalPenalty = 964.101,
		ballProgress = 16.754,
		ballGoalAlign = 21.573,
		crateGrab = 58.527,
		crateCamp = 16.751,
		keeperGuard = 13.917,
		strikerBump = 31.256,
		passSetup = 21.433,
		bankBonus = 46.43,
		powerAggression = 0.35,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 1557.294,
		concedePenalty = 212.5,
		ownGoalPenalty = 1260.747,
		ballProgress = 21.91,
		ballGoalAlign = 28.211,
		crateGrab = 76.535,
		crateCamp = 21.905,
		keeperGuard = 18.199,
		strikerBump = 40.873,
		passSetup = 28.028,
		bankBonus = 60.716,
		powerAggression = 0.35,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1832.111,
		concedePenalty = 250,
		ownGoalPenalty = 1483.232,
		ballProgress = 25.776,
		ballGoalAlign = 33.189,
		crateGrab = 90.041,
		crateCamp = 25.771,
		keeperGuard = 21.411,
		strikerBump = 48.086,
		passSetup = 32.974,
		bankBonus = 71.43,
		powerAggression = 0.374,
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

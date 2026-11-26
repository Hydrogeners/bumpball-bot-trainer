--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 747.989,
		concedePenalty = 338.454,
		ownGoalPenalty = 851.45,
		ballProgress = 24.739,
		ballGoalAlign = 32.064,
		crateGrab = 75.037,
		crateCamp = 12.46,
		keeperGuard = 14.202,
		strikerBump = 40.897,
		passSetup = 31.171,
		bankBonus = 35.569,
		powerAggression = 0.535,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 978.139,
		concedePenalty = 442.594,
		ownGoalPenalty = 1113.435,
		ballProgress = 32.351,
		ballGoalAlign = 41.93,
		crateGrab = 98.126,
		crateCamp = 16.294,
		keeperGuard = 18.572,
		strikerBump = 53.48,
		passSetup = 40.762,
		bankBonus = 46.513,
		powerAggression = 0.7,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1150.752,
		concedePenalty = 520.699,
		ownGoalPenalty = 1309.923,
		ballProgress = 38.06,
		ballGoalAlign = 49.329,
		crateGrab = 115.442,
		crateCamp = 19.169,
		keeperGuard = 21.849,
		strikerBump = 62.918,
		passSetup = 47.955,
		bankBonus = 54.721,
		powerAggression = 0.823,
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

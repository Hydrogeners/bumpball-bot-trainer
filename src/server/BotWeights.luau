--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 838.098,
		concedePenalty = 401.315,
		ownGoalPenalty = 904.016,
		ballProgress = 5.716,
		ballGoalAlign = 11.071,
		crateGrab = 62.592,
		crateCamp = 5.58,
		keeperGuard = 47.072,
		strikerBump = 5.242,
		passSetup = 21.592,
		bankBonus = 42.852,
		powerAggression = 0.374,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 1095.974,
		concedePenalty = 524.797,
		ownGoalPenalty = 1182.175,
		ballProgress = 7.475,
		ballGoalAlign = 14.477,
		crateGrab = 81.852,
		crateCamp = 7.297,
		keeperGuard = 61.555,
		strikerBump = 6.854,
		passSetup = 28.236,
		bankBonus = 56.037,
		powerAggression = 0.489,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1289.381,
		concedePenalty = 617.408,
		ownGoalPenalty = 1390.794,
		ballProgress = 8.794,
		ballGoalAlign = 17.032,
		crateGrab = 96.296,
		crateCamp = 8.585,
		keeperGuard = 72.418,
		strikerBump = 8.064,
		passSetup = 33.219,
		bankBonus = 65.926,
		powerAggression = 0.575,
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

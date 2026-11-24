--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 761.183,
		concedePenalty = 184.53,
		ownGoalPenalty = 1000.504,
		ballProgress = 8.785,
		ballGoalAlign = 14.925,
		crateGrab = 46.071,
		crateCamp = 4.202,
		keeperGuard = 22.752,
		strikerBump = 17.45,
		passSetup = 23.44,
		bankBonus = 56.477,
		powerAggression = 0.402,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 995.393,
		concedePenalty = 241.309,
		ownGoalPenalty = 1308.351,
		ballProgress = 11.489,
		ballGoalAlign = 19.517,
		crateGrab = 60.246,
		crateCamp = 5.495,
		keeperGuard = 29.753,
		strikerBump = 22.819,
		passSetup = 30.653,
		bankBonus = 73.854,
		powerAggression = 0.525,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1171.051,
		concedePenalty = 283.893,
		ownGoalPenalty = 1539.237,
		ballProgress = 13.516,
		ballGoalAlign = 22.961,
		crateGrab = 70.878,
		crateCamp = 6.465,
		keeperGuard = 35.003,
		strikerBump = 26.846,
		passSetup = 36.062,
		bankBonus = 86.887,
		powerAggression = 0.618,
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

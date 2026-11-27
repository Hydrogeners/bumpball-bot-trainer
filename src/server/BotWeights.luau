--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 873.671,
		concedePenalty = 269.027,
		ownGoalPenalty = 822.942,
		ballProgress = 27.711,
		ballGoalAlign = 15.114,
		crateGrab = 102.329,
		crateCamp = 15.496,
		keeperGuard = 16.348,
		strikerBump = 44.702,
		passSetup = 27.251,
		bankBonus = 33.485,
		powerAggression = 0.352,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 1142.493,
		concedePenalty = 351.805,
		ownGoalPenalty = 1076.155,
		ballProgress = 36.238,
		ballGoalAlign = 19.765,
		crateGrab = 133.815,
		crateCamp = 20.264,
		keeperGuard = 21.378,
		strikerBump = 58.457,
		passSetup = 35.636,
		bankBonus = 43.789,
		powerAggression = 0.461,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1344.11,
		concedePenalty = 413.888,
		ownGoalPenalty = 1266.065,
		ballProgress = 42.633,
		ballGoalAlign = 23.253,
		crateGrab = 157.429,
		crateCamp = 23.84,
		keeperGuard = 25.151,
		strikerBump = 68.773,
		passSetup = 41.925,
		bankBonus = 51.516,
		powerAggression = 0.542,
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

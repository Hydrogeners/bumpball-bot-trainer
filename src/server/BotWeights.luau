--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 783.208,
		concedePenalty = 406.887,
		ownGoalPenalty = 856.204,
		ballProgress = 8.456,
		ballGoalAlign = 3.25,
		crateGrab = 55.056,
		crateCamp = 7.275,
		keeperGuard = 39.87,
		strikerBump = 9.366,
		passSetup = 15.05,
		bankBonus = 32.12,
		powerAggression = 0.35,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 1024.196,
		concedePenalty = 532.083,
		ownGoalPenalty = 1119.651,
		ballProgress = 11.058,
		ballGoalAlign = 4.25,
		crateGrab = 71.997,
		crateCamp = 9.513,
		keeperGuard = 52.137,
		strikerBump = 12.248,
		passSetup = 19.681,
		bankBonus = 42.004,
		powerAggression = 0.414,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1204.936,
		concedePenalty = 625.98,
		ownGoalPenalty = 1317.237,
		ballProgress = 13.009,
		ballGoalAlign = 5,
		crateGrab = 84.702,
		crateCamp = 11.192,
		keeperGuard = 61.338,
		strikerBump = 14.409,
		passSetup = 23.154,
		bankBonus = 49.416,
		powerAggression = 0.487,
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

--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 650.568,
		concedePenalty = 329.332,
		ownGoalPenalty = 956.643,
		ballProgress = 27.979,
		ballGoalAlign = 17.959,
		crateGrab = 83.307,
		crateCamp = 17.951,
		keeperGuard = 14.536,
		strikerBump = 49.355,
		passSetup = 39.963,
		bankBonus = 43.501,
		powerAggression = 0.35,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 850.743,
		concedePenalty = 430.664,
		ownGoalPenalty = 1250.995,
		ballProgress = 36.587,
		ballGoalAlign = 23.485,
		crateGrab = 108.939,
		crateCamp = 23.474,
		keeperGuard = 19.009,
		strikerBump = 64.541,
		passSetup = 52.259,
		bankBonus = 56.885,
		powerAggression = 0.374,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1000.874,
		concedePenalty = 506.664,
		ownGoalPenalty = 1471.759,
		ballProgress = 43.044,
		ballGoalAlign = 27.629,
		crateGrab = 128.164,
		crateCamp = 27.617,
		keeperGuard = 22.363,
		strikerBump = 75.93,
		passSetup = 61.481,
		bankBonus = 66.924,
		powerAggression = 0.44,
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

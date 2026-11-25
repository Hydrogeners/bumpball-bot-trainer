--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 1065.999,
		concedePenalty = 440.785,
		ownGoalPenalty = 894.695,
		ballProgress = 18.867,
		ballGoalAlign = 21.849,
		crateGrab = 72.855,
		crateCamp = 12.139,
		keeperGuard = 6.5,
		strikerBump = 24.583,
		passSetup = 25.383,
		bankBonus = 46.973,
		powerAggression = 0.35,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 1393.999,
		concedePenalty = 576.411,
		ownGoalPenalty = 1169.986,
		ballProgress = 24.672,
		ballGoalAlign = 28.572,
		crateGrab = 95.271,
		crateCamp = 15.874,
		keeperGuard = 8.5,
		strikerBump = 32.147,
		passSetup = 33.193,
		bankBonus = 61.426,
		powerAggression = 0.412,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1639.999,
		concedePenalty = 678.131,
		ownGoalPenalty = 1376.454,
		ballProgress = 29.026,
		ballGoalAlign = 33.614,
		crateGrab = 112.084,
		crateCamp = 18.675,
		keeperGuard = 10,
		strikerBump = 37.82,
		passSetup = 39.051,
		bankBonus = 72.266,
		powerAggression = 0.485,
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

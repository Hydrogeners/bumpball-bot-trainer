--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 929.673,
		concedePenalty = 285.854,
		ownGoalPenalty = 704.658,
		ballProgress = 16.946,
		ballGoalAlign = 8.934,
		crateGrab = 47.257,
		crateCamp = 10.54,
		keeperGuard = 33.4,
		strikerBump = 16.341,
		passSetup = 16.351,
		bankBonus = 28.725,
		powerAggression = 0.45,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 1215.726,
		concedePenalty = 373.81,
		ownGoalPenalty = 921.476,
		ballProgress = 22.16,
		ballGoalAlign = 11.683,
		crateGrab = 61.798,
		crateCamp = 13.784,
		keeperGuard = 43.676,
		strikerBump = 21.369,
		passSetup = 21.383,
		bankBonus = 37.563,
		powerAggression = 0.589,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1430.266,
		concedePenalty = 439.776,
		ownGoalPenalty = 1084.089,
		ballProgress = 26.07,
		ballGoalAlign = 13.745,
		crateGrab = 72.703,
		crateCamp = 16.216,
		keeperGuard = 51.384,
		strikerBump = 25.14,
		passSetup = 25.156,
		bankBonus = 44.192,
		powerAggression = 0.693,
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

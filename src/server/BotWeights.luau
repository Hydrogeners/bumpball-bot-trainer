--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 604.78,
		concedePenalty = 373.321,
		ownGoalPenalty = 749.627,
		ballProgress = 15.746,
		ballGoalAlign = 22.055,
		crateGrab = 80.685,
		crateCamp = 10.498,
		keeperGuard = 10.426,
		strikerBump = 41.255,
		passSetup = 25.841,
		bankBonus = 43.389,
		powerAggression = 0.374,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 790.866,
		concedePenalty = 488.189,
		ownGoalPenalty = 980.282,
		ballProgress = 20.59,
		ballGoalAlign = 28.841,
		crateGrab = 105.511,
		crateCamp = 13.728,
		keeperGuard = 13.634,
		strikerBump = 53.949,
		passSetup = 33.792,
		bankBonus = 56.74,
		powerAggression = 0.489,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 930.431,
		concedePenalty = 574.34,
		ownGoalPenalty = 1153.273,
		ballProgress = 24.224,
		ballGoalAlign = 33.93,
		crateGrab = 124.13,
		crateCamp = 16.151,
		keeperGuard = 16.04,
		strikerBump = 63.469,
		passSetup = 39.755,
		bankBonus = 66.753,
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

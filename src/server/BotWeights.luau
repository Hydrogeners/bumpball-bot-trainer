--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 966.218,
		concedePenalty = 197.174,
		ownGoalPenalty = 865.463,
		ballProgress = 11.723,
		ballGoalAlign = 13.684,
		crateGrab = 38.626,
		crateCamp = 12.392,
		keeperGuard = 40.247,
		strikerBump = 9.895,
		passSetup = 25.358,
		bankBonus = 42.834,
		powerAggression = 0.365,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 1263.516,
		concedePenalty = 257.842,
		ownGoalPenalty = 1131.759,
		ballProgress = 15.33,
		ballGoalAlign = 17.894,
		crateGrab = 50.511,
		crateCamp = 16.205,
		keeperGuard = 52.63,
		strikerBump = 12.94,
		passSetup = 33.161,
		bankBonus = 56.013,
		powerAggression = 0.477,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1486.489,
		concedePenalty = 303.344,
		ownGoalPenalty = 1331.481,
		ballProgress = 18.035,
		ballGoalAlign = 21.052,
		crateGrab = 59.425,
		crateCamp = 19.065,
		keeperGuard = 61.918,
		strikerBump = 15.223,
		passSetup = 39.013,
		bankBonus = 65.898,
		powerAggression = 0.561,
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

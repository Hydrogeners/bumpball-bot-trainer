--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 771.683,
		concedePenalty = 203.718,
		ownGoalPenalty = 975.469,
		ballProgress = 7.22,
		ballGoalAlign = 17.685,
		crateGrab = 54.226,
		crateCamp = 7.212,
		keeperGuard = 50.662,
		strikerBump = 7.205,
		passSetup = 30.298,
		bankBonus = 42.806,
		powerAggression = 0.35,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 1009.124,
		concedePenalty = 266.4,
		ownGoalPenalty = 1275.614,
		ballProgress = 9.442,
		ballGoalAlign = 23.127,
		crateGrab = 70.91,
		crateCamp = 9.432,
		keeperGuard = 66.25,
		strikerBump = 9.421,
		passSetup = 39.62,
		bankBonus = 55.977,
		powerAggression = 0.428,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1187.205,
		concedePenalty = 313.412,
		ownGoalPenalty = 1500.722,
		ballProgress = 11.108,
		ballGoalAlign = 27.208,
		crateGrab = 83.424,
		crateCamp = 11.096,
		keeperGuard = 77.941,
		strikerBump = 11.084,
		passSetup = 46.612,
		bankBonus = 65.855,
		powerAggression = 0.504,
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

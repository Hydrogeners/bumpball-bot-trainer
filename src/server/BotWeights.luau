--!nonstrict
-- Tunable tactical weights for Bumpball's BotBrain.
-- Updated automatically by scripts/train-bot.luau (or edited by hand).

local BotWeights = {
	Default = "Normal",

	Easy = {
		goalScore = 935.691,
		concedePenalty = 243.164,
		ownGoalPenalty = 918.035,
		ballProgress = 9.321,
		ballGoalAlign = 21.035,
		crateGrab = 49.154,
		crateCamp = 12.982,
		keeperGuard = 11.43,
		strikerBump = 17.847,
		passSetup = 21.03,
		bankBonus = 42.927,
		powerAggression = 0.393,
		aimJitter = 0.14,
		simCandidates = 8,
		simTicks = 65,
	},

	Normal = {
		goalScore = 1223.596,
		concedePenalty = 317.983,
		ownGoalPenalty = 1200.508,
		ballProgress = 12.189,
		ballGoalAlign = 27.508,
		crateGrab = 64.279,
		crateCamp = 16.976,
		keeperGuard = 14.946,
		strikerBump = 23.338,
		passSetup = 27.501,
		bankBonus = 56.136,
		powerAggression = 0.513,
		aimJitter = 0.045,
		simCandidates = 12,
		simTicks = 85,
	},

	Pro = {
		goalScore = 1439.525,
		concedePenalty = 374.098,
		ownGoalPenalty = 1412.362,
		ballProgress = 14.34,
		ballGoalAlign = 32.362,
		crateGrab = 75.622,
		crateCamp = 19.972,
		keeperGuard = 17.584,
		strikerBump = 27.457,
		passSetup = 32.354,
		bankBonus = 66.042,
		powerAggression = 0.604,
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

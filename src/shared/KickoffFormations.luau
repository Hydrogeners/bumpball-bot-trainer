local Formations = {}

Formations.CHOICE_SECONDS = 5
Formations.ATTACKING_TEAM = 0
Formations.ATTACKING = table.freeze({ "forward", "option", "slant" })
Formations.DEFENDING = table.freeze({ "zone", "box", "rush" })

-- Recovered Team A slot order in Unity X/Z coordinates.
local layouts = {
	forward = { { -2.54, 1.59 }, { -5, 3.5 }, { -5, 0 }, { -5, -3.5 } },
	option = { { -7.25, 0 }, { -2.625, 2.8145833 }, { -4.25, 0 }, { -2.625, -2.8145821 } },
	slant = { { -2.25, 4.5 }, { -3.25, 1.5 }, { -4.25, -1.75 }, { -5.25, -4.5 } },
	zone = { { -5, 0 }, { -5, 4.5 }, { -10, 0 }, { -5, -4.5 } },
	box = { { -6.25, 2.5 }, { -8.75, 0 }, { -6.25, -2.5 }, { -3.75, 0 } },
	rush = { { -3.5, 4.5 }, { -6.25, 0.75 }, { -6.25, -0.75 }, { -3.5, -4.25 } },
}
local attackingBallSpot = { -1, 0 }

function Formations.options(team, attackingTeam)
	return team == attackingTeam and Formations.ATTACKING or Formations.DEFENDING
end

function Formations.allows(team, attackingTeam, id)
	return type(id) == "string" and table.find(Formations.options(team, attackingTeam), id) ~= nil
end

local function worldPosition(pair, team, height)
	-- The authored Team B layout reflects X only. Reflect Unity Z for both
	-- teams so the slot placement agrees with the Bumpball match camera.
	local xSign = team == 0 and 1 or -1
	return Vector3.new(pair[1] * xSign, height, -pair[2])
end

function Formations.positions(choices, attackingTeam, athleteHeight, ballHeight)
	local positions = {}
	for team = 0, 1 do
		local id = choices[team + 1]
		if not Formations.allows(team, attackingTeam, id) then return nil end
		for slot, pair in ipairs(layouts[id]) do
			positions[team * 4 + slot] = worldPosition(pair, team, athleteHeight)
		end
	end
	return positions, worldPosition(attackingBallSpot, attackingTeam, ballHeight)
end

function Formations.ballLocation(formation, team, height)
	if type(formation) ~= "string" or not table.find(Formations.ATTACKING, formation) then return nil end
	return worldPosition(attackingBallSpot, team, height)
end

return table.freeze(Formations)

--!nonstrict
--[[
	BobbleRoster — who is on the pitch, and where they line up at kickoff.

	Shared roster and team colors for the simulation and presentation.
]]

local Roster = {}

Roster.SPECIES = {
	[0] = { "Bear", "Bull", "Hawk", "Tiger" },
	[1] = { "Bug", "Dino", "Pig", "Tiger" },
}

Roster.COLOR = {
	[0] = Color3.fromRGB(90, 150, 255),
	[1] = Color3.fromRGB(255, 120, 90),
}

Roster.NAME = { [0] = "BLUE", [1] = "ORANGE" }

--[[ Kickoff formation: each team in a 2x2 block on its own side. Returns an
     array of { team, species, home } indexed 1..8 (team 0 first). ]]
function Roster.build()
	local list = {}
	for team = 0, 1 do
		local sx = (team == 0) and -5.0 or 5.0
		for i = 1, 4 do
			local col = (i - 1) % 2
			local row = math.floor((i - 1) / 2)
			table.insert(list, {
				team = team,
				species = Roster.SPECIES[team][i],
				home = Vector3.new(sx + (team == 0 and col or -col) * 1.6, 0.5, (row - 0.5) * 2.4),
			})
		end
	end
	return list
end

return Roster

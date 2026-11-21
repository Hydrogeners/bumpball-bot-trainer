--!nonstrict
local Physics = require(script.Parent.BobblePhysics)

local Powers = {}
Powers.Pool = { "boost", "block", "steal", "ramp", "bigbumpers", "giantball", "bighead", "goalswap", "armor", "redcard", "ghost", "magnet" }
Powers.Names = { boost = "Boost", block = "Block", sticky = "Sticky", ramp = "Ramp", bigbumpers = "Big Bumpers", giantball = "Giant Ball", bighead = "Big Head", goalswap = "Goal Swap", armor = "Armor", redcard = "Move Player", ghost = "Ghost", magnet = "Ball Magnet" }
Powers.Exclusive = { redcard = true }
Powers.Interaction = {
	boost = "placed", block = "placed", sticky = "placed", ramp = "placed",
	bigbumpers = "instant", giantball = "instant", goalswap = "instant", yellowcard = "instant", steal = "instant",
	bighead = "target", redcard = "target", ghost = "target", armor = "target", magnet = "target",
}
Powers.Names.steal = "Power Steal"
Powers.Directional = { boost = true, ramp = true, block = true }
Powers.MagnetReach = 1.65 -- Extra range beyond the two colliders' radii.
Powers.MagnetReleaseMargin = 1.0
Powers.MagnetDuration = 1.25

function Powers.canTarget(kind, body, powers)
	if not body then return false, "Choose a bobble" end
	if kind ~= "armor" and kind ~= "magnet" then return true end
	for _, power in ipairs(powers) do
		if power.kind == kind and power.id == body.id and not power.spent then
			return false, "Bobble already equipped"
		end
	end
	return true
end
Powers.Radius = 0.8
Powers.Buffer = 0.25
Powers.BlockScale = 1.10
Powers.RotationStep = 15
-- PlayArena.ValidPowerPlacementBounds describes the permitted placement centers.
local placementHalfX, placementHalfZ = 11.8, 7.5

local rampRoot = CFrame.new(-5.960464477539063e-08, -0.1979999989271164, 0.0430000014603138)
	* Physics.cfFromQuat(6.183981895446777e-07, -0.976296067237854, 0.21643954515457153, 2.8014183044433594e-06)

function Powers.geometry(placement)
	if Powers.Interaction[placement.kind] ~= "placed" then
		return {}
	end
	local kind = placement.kind
	local root = CFrame.new(placement.x, Physics.FLOOR_TOP_Y, placement.z) * Physics.yawCFrame(placement.yaw)
	local function shape(frame, extent, surface)
		return {
			name = Powers.Names[kind],
			kind = kind,
			tag = kind,
			center = frame.Position,
			rotation = frame.Rotation,
			halfExtent = extent,
			surface = surface,
			ignoresGhosts = true,
			data = kind == "boost" and { velocity = frame:VectorToWorldSpace(Vector3.new(0, 0, 15)) } or nil,
		}
	end
	local surfaces = Physics.Surfaces
	if kind == "boost" then
		return { shape(root * CFrame.new(0, 0.2, 0), Vector3.new(0.75, 0.20, 0.77)) }
	elseif kind == "sticky" then
		return { shape(root, Vector3.new(0.8, 0.1, 0.8)) }
	elseif kind == "block" then
		return { shape(root * CFrame.new(0, 0.5 * Powers.BlockScale, 0), Vector3.new(0.5, 0.5, 0.25) * Powers.BlockScale, surfaces.Block) }
	elseif kind == "ramp" then
		return {
			shape(root * CFrame.new(0, 0, 0.5249999761581421),
				Vector3.new(0.824999988079071, 0.5, 0.15000000596046448), surfaces.RampLead),
			shape(root * rampRoot,
				Vector3.new(0.824999988079071, 0.5, 0.6000000238418579), surfaces.RampBody),
		}
	end
	error("Unknown power")
end

local function within(x, z, otherX, otherZ, distance)
	return (x - otherX) ^ 2 + (z - otherZ) ^ 2 < distance ^ 2
end

function Powers.conflicts(a, b)
	return within(a.x, a.z, b.x, b.z, 2 * Powers.Radius + Powers.Buffer)
end

function Powers.isLegal(placement, arena)
	local x, z = placement.x, placement.z
	local margin = Powers.Radius + Powers.Buffer
	if math.abs(x) > placementHalfX or math.abs(z) > placementHalfZ then
		return false, "Outside the placement area"
	end
	local function overlapsBody(body)
		return within(x, z, body.position.X, body.position.Z, margin + body.cfg.radius)
	end
	if overlapsBody(arena.ball) then return false, "Too close to the ball" end
	for _, body in ipairs(arena.athletes) do
		if overlapsBody(body) then return false, "Too close to a bobble" end
	end
	for _, trigger in ipairs(arena.triggers) do
		if trigger.kind == "crate" and within(x, z, trigger.center.X, trigger.center.Z, 2 * Powers.Radius + Powers.Buffer) then
			return false, "Too close to a crate spot"
		end
	end
	for _, other in ipairs(arena.activePowers) do
		if Powers.Interaction[other.kind] == "placed" and Powers.conflicts(placement, other) then
			return false, "Too close to another power"
		end
	end
	return true
end

return Powers

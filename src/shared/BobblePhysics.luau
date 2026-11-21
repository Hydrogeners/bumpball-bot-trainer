--!nonstrict
--[[
	BobblePhysics — a Luau reconstruction of the shipped Bobble League
	physics (CG6, Prod-590-CL28650, Unity 2021.3.4f1).

	Ground truth lives in Z:\bobble-league-sim:
		bobble/solver.py   — the sequential-impulse solver
		bobble/vmath.py    — Vec3 / Quat
		bobble/config.py   — constants read from the shipped bundles
		bobble/arena.py    — the pitch geometry
	...all of which were verified against CG6.wasm (see dump/wasm_decomp/FINDINGS.md).

	WHY THIS EXISTS: Roblox's built-in engine cannot reproduce this physics. The
	client runs a fixed 60 Hz sequential-impulse solver modelled on Box2D-Lite,
	with several load-bearing quirks (linear-only normal impulses, a circular
	friction cone, a constant tangential rolling drag, angle-axis rotation in
	degrees). So this module *is* the physics: bodies are simulated here and
	rendered by CFrame'ing anchored parts. Roblox is the renderer + input + net.

	Units: 1 game unit = 1 stud.
]]

local BobblePhysics = {}

-- ===========================================================================
-- Constants (bobble/config.py — every value READ from the shipped data)
-- ===========================================================================
local UPDATE_HZ = 60
local FIXED_DT = 1 / UPDATE_HZ
local GRAVITY = Vector3.new(0, -9.8, 0)
local SEPARATION_BIAS_FACTOR = 0.2   -- Box2D-Lite k_biasFactor
local ALLOWED_PENETRATION = 0.01     -- Box2D-Lite k_allowedPenetration
local MAX_IMPULSE_ITERATIONS = 6
local IMPULSE_CONVERGENCE_THRESHOLD = 0.01

BobblePhysics.UPDATE_HZ = UPDATE_HZ
BobblePhysics.FIXED_DT = FIXED_DT
BobblePhysics.GRAVITY = GRAVITY

-- gameplay tuning (NetGameCG6)
BobblePhysics.MAX_MOVE_POWER = 16.0
BobblePhysics.MIN_TOTAL_SIM_TIME = 1.0
BobblePhysics.MAX_TOTAL_SIM_TIME = 10.0
BobblePhysics.SIM_TIME_AFTER_GOAL = 1.5
BobblePhysics.MAX_TIME_PER_TURN = 15.0

-- m_moveInputToVelocityCurve — keyframes (time, value, slope).
BobblePhysics.MOVE_INPUT_CURVE = {
	{ 0.0, 0.0, 0.5678408145904541 },
	{ 0.1460123062133789, 0.21394142508506775, 2.2464871406555176 },
	{ 1.0, 1.0, 0.10085800290107727 },
}

-- ===========================================================================
-- Body + surface configs (GameplayConfig* prefabs, verbatim)
-- ===========================================================================
local Surfaces = {
	Floor    = { friction = 1.0, restitution = 0.0, restitutionThreshold = 4.0, surfaceType = 0 },
	Wall     = { friction = 1.0, restitution = 0.0, restitutionThreshold = 0.2, surfaceType = 4 },
	Goalpost = { friction = 1.0, restitution = 0.0, restitutionThreshold = 0.2, surfaceType = 5 },
	Block    = { friction = 1.0, restitution = 0.0, restitutionThreshold = 0.2, surfaceType = 6 },
	RampLead = { friction = 0.5, restitution = 0.0, restitutionThreshold = 0.2, surfaceType = 9 },
	RampBody = { friction = 0.5, restitution = 0.0, restitutionThreshold = 0.2, surfaceType = 6 },
}

local Presets = {
	Ball = {
		name = "GameplayConfigBall", radius = 0.5, mass = 1.0,
		friction = 0.5, restitution = 0.8, restitutionThreshold = 3.0,
		angularDamping = 0.0, rollingDrag = 1.15, rollingSpinDrag = 0.675, surfaceType = 2,
	},
	GiantBall = {
		name = "GameplayConfigGiantBall", radius = 1.0, mass = 2.0,
		friction = 0.5, restitution = 0.8, restitutionThreshold = 3.0,
		angularDamping = 0.0, rollingDrag = 1.15, rollingSpinDrag = 0.675, surfaceType = 2,
	},
	Athlete = {
		name = "GameplayConfigAthlete", radius = 0.5, mass = 1.0,
		friction = 1.0, restitution = 0.8, restitutionThreshold = 4.0,
		angularDamping = 0.0, rollingDrag = 4.5, rollingSpinDrag = 3.0, surfaceType = 1,
	},
	AthleteBigHead = {
		name = "GameplayConfigAthleteBigHead", radius = 0.5, mass = 3.0,
		friction = 1.0, restitution = 0.8, restitutionThreshold = 4.0,
		angularDamping = 0.0, rollingDrag = 9.0, rollingSpinDrag = 5.0, surfaceType = 1,
	},
}

BobblePhysics.Surfaces = Surfaces
BobblePhysics.Presets = Presets

-- ===========================================================================
-- Math helpers
-- ===========================================================================

--[[ Rotation-only CFrame from a Unity-order quaternion (x, y, z, w). Built via
     axis-angle so it never depends on CFrame.fromMatrix's column convention. ]]
function BobblePhysics.cfFromQuat(x, y, z, w)
	local n = math.sqrt(x * x + y * y + z * z + w * w)
	if n == 0 then
		return CFrame.identity
	end
	x, y, z, w = x / n, y / n, z / n, w / n
	if w < 0 then
		x, y, z, w = -x, -y, -z, -w
	end
	local s = math.sqrt(x * x + y * y + z * z)
	local axis
	if s < 1e-9 then
		axis = Vector3.new(1, 0, 0)
	else
		axis = Vector3.new(x / s, y / s, z / s)
	end
	local angle = 2 * math.acos(math.clamp(w, -1, 1))
	return CFrame.fromAxisAngle(axis, angle)
end

--[[ Rotation about +Y by `deg` degrees (Quat.from_yaw_degrees). ]]
function BobblePhysics.yawCFrame(deg)
	return CFrame.Angles(0, math.rad(deg), 0)
end

-- Evaluate the move-input curve with cubic Hermite interpolation.
function BobblePhysics.evalMoveCurve(t)
	local keys = BobblePhysics.MOVE_INPUT_CURVE
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			local span = b[1] - a[1]
			local u = (t - a[1]) / span
			local u2 = u * u
			local u3 = u2 * u
			return (2 * u3 - 3 * u2 + 1) * a[2]
				+ (u3 - 2 * u2 + u) * span * a[3]
				+ (-2 * u3 + 3 * u2) * b[2]
				+ (u3 - u2) * span * b[3]
		end
	end
	return keys[#keys][2]
end

-- ===========================================================================
-- Bodies
-- ===========================================================================
local Sphere = {}
Sphere.__index = Sphere

function Sphere.new(cfg, position)
	local self = setmetatable({}, Sphere)
	self.isSphere = true
	self.name = cfg.name
	self.cfg = cfg
	self.position = position or Vector3.new()
	self.velocity = Vector3.new()
	self.angularVelocity = Vector3.new()
	self.rotation = CFrame.identity
	-- InvI = 1 / (0.4 * Mass * Radius^2) — solid-sphere inertia, verified against
	-- the live client's SetBodyStateInfoFromBallConfig.
	self.invMass = 1.0 / cfg.mass
	self.invInertia = 1.0 / (0.4 * cfg.mass * cfg.radius * cfg.radius)
	-- gameplay flags
	self.team = -1
	self.isBall = false
	self.ghosted = false
	self.stuck = false
	self.stuckImmune = false
	self.heldPowerId = nil
	self.grounded = false
	self.visual = nil
	return self
end

-- Install a body config without changing motion. Radius changes keep the body
-- resting on the floor by changing height only; all other position components,
-- rotation, linear velocity, and spin are preserved.
function BobblePhysics.setSphereConfig(body, cfg)
	local radiusDelta = cfg.radius - body.cfg.radius
	body.cfg = cfg
	body.name = cfg.name
	body.invMass = 1.0 / cfg.mass
	body.invInertia = 1.0 / (0.4 * cfg.mass * cfg.radius * cfg.radius)
	body.position += Vector3.yAxis * radiusDelta
end

local Box = {}
Box.__index = Box

function Box.new(props)
	local self = setmetatable({}, Box)
	self.isSphere = false
	self.name = props.name or "Box"
	self.center = props.center or Vector3.new()
	self.halfExtent = props.halfExtent or Vector3.new(1, 1, 1)
	self.rotation = props.rotation or CFrame.identity
	self.surface = props.surface
	self.ignoresGhosts = props.ignoresGhosts or false
	self.tag = props.tag or ""
	self.invMass = 0.0
	self.invInertia = 0.0
	self.velocity = Vector3.new()
	self.angularVelocity = Vector3.new()
	return self
end

function Box:closestPoint(p)
	local local_ = self.rotation:VectorToObjectSpace(p - self.center)
	local e = self.halfExtent
	local c = Vector3.new(
		math.clamp(local_.X, -e.X, e.X),
		math.clamp(local_.Y, -e.Y, e.Y),
		math.clamp(local_.Z, -e.Z, e.Z)
	)
	return self.center + self.rotation:VectorToWorldSpace(c)
end

function Box:contains(p)
	local local_ = self.rotation:VectorToObjectSpace(p - self.center)
	local e = self.halfExtent
	return math.abs(local_.X) <= e.X
		and math.abs(local_.Y) <= e.Y
		and math.abs(local_.Z) <= e.Z
end

function Box:overlapsSphere(p, radius)
	local d = p - self:closestPoint(p)
	return d:Dot(d) <= radius * radius or self:contains(p)
end

local Trigger = {}
Trigger.__index = Trigger

function Trigger.new(props)
	local self = setmetatable({}, Trigger)
	self.name = props.name or "Trigger"
	self.center = props.center or Vector3.new()
	self.halfExtent = props.halfExtent or Vector3.new(1, 1, 1)
	self.rotation = props.rotation or CFrame.identity
	self.kind = props.kind or ""
	self.ignoresGhosts = props.ignoresGhosts or false
	self.data = props.data or {}
	return self
end

function Trigger:containsSphere(p, radius)
	local local_ = self.rotation:VectorToObjectSpace(p - self.center)
	local e = self.halfExtent
	local dx = math.max(math.abs(local_.X) - e.X, 0)
	local dy = math.max(math.abs(local_.Y) - e.Y, 0)
	local dz = math.max(math.abs(local_.Z) - e.Z, 0)
	return dx * dx + dy * dy + dz * dz <= radius * radius
end

BobblePhysics.Sphere = Sphere
BobblePhysics.Box = Box
BobblePhysics.Trigger = Trigger

-- ===========================================================================
-- Contact solve helpers
-- ===========================================================================
local function bodyPos(b)
	return b.isSphere and b.position or b.center
end

local function combineFriction(a, b)
	-- READ from AddOrUpdateContact (funcidx 10297): FrictionCoeff = sqrt(fA*fB).
	return math.sqrt(a * b)
end

local function combineRestitution(a, b)
	-- READ from AddOrUpdateContact: Restitution = MAX(rA, rB).
	return math.max(a, b)
end

local function velAt(body, r)
	return body.velocity + body.angularVelocity:Cross(r)
end

local function applyImpulse(body, r, p)
	local im = body.invMass
	if im == 0 then
		return
	end
	body.velocity = body.velocity + p * im
	local ii = body.invInertia
	if ii ~= 0 then
		body.angularVelocity = body.angularVelocity + r:Cross(p) * ii
	end
end

local function newContact(a, b, point, normal, separation, friction, restitution, threshold)
	return {
		bodyA = a, bodyB = b,
		point = point, normal = normal, separation = separation,
		friction = friction, restitution = restitution, restitutionThreshold = threshold,
		pn = 0.0, ptF = 0.0, ptS = 0.0,
		massNormal = 0.0, massTangent = 0.0,
		tangentF = Vector3.new(), tangentS = Vector3.new(), bias = 0.0,
	}
end

-- ===========================================================================
-- World — the solver
-- ===========================================================================
local World = {}
World.__index = World

function BobblePhysics.newWorld()
	local self = setmetatable({}, World)
	self.spheres = {}
	self.boxes = {}
	self.triggers = {}
	self.gravity = GRAVITY
	self.time = 0.0
	self.triggerHandler = nil      -- function(sphere, trigger, world, transition)
	self._triggerOccupancy = {}    -- sphere -> { trigger -> true }
	self._contacts = {}
	self._bodyCount = 0
	self._impulseCache = {}        -- sphere -> { otherBody -> {pn, ptF, ptS} }
	return self
end

function World:addSphere(s)
	self._bodyCount += 1
	s._bodyIndex = self._bodyCount
	table.insert(self.spheres, s)
	return s
end

function World:addBox(b)
	self._bodyCount += 1
	b._bodyIndex = self._bodyCount
	table.insert(self.boxes, b)
	return b
end

function World:addTrigger(t)
	table.insert(self.triggers, t)
	return t
end

function World:clearContacts()
	table.clear(self._contacts)
	table.clear(self._impulseCache)
end

function World:clearTriggerOccupancy()
	table.clear(self._triggerOccupancy)
end

-- -- narrow phase -----------------------------------------------------------
function World:collideSphereBox(s, b)
	if b.ignoresGhosts and s.ghosted then
		return nil
	end
	local closest = b:closestPoint(s.position)
	local delta = s.position - closest
	local distSq = delta:Dot(delta)
	local r = s.cfg.radius
	if distSq > r * r then
		return nil
	end

	local normal, separation
	if distSq > 1e-12 then
		local dist = math.sqrt(distSq)
		normal = delta / dist
		separation = dist - r
	else
		-- centre inside the box: push out along the shallowest local axis
		local local_ = b.rotation:VectorToObjectSpace(s.position - b.center)
		local e = b.halfExtent
		local ox = e.X - math.abs(local_.X)
		local oy = e.Y - math.abs(local_.Y)
		local oz = e.Z - math.abs(local_.Z)
		local axis, best = 1, ox
		if oy < best then axis, best = 2, oy end
		if oz < best then axis, best = 3, oz end
		local ln
		if axis == 1 then
			ln = Vector3.new(local_.X >= 0 and 1 or -1, 0, 0)
		elseif axis == 2 then
			ln = Vector3.new(0, local_.Y >= 0 and 1 or -1, 0)
		else
			ln = Vector3.new(0, 0, local_.Z >= 0 and 1 or -1)
		end
		normal = b.rotation:VectorToWorldSpace(ln)
		separation = -r
	end

	local surf = b.surface
	local friction = combineFriction(s.cfg.friction, surf and surf.friction or 1.0)
	local restitution = combineRestitution(s.cfg.restitution, surf and surf.restitution or 0.0)
	local threshold = math.min(s.cfg.restitutionThreshold, surf and surf.restitutionThreshold or 0.0)
	return newContact(s, b, closest, normal, separation, friction, restitution, threshold)
end

function World:collideSphereSphere(a, b)
	local delta = a.position - b.position
	local r = a.cfg.radius + b.cfg.radius
	local distSq = delta:Dot(delta)
	if distSq > r * r or distSq < 1e-12 then
		return nil
	end
	local dist = math.sqrt(distSq)
	local normal = delta / dist
	local separation = dist - r
	-- The reference measures from the first sphere and adds penetration to
	-- its radius. This changes the friction lever arm during deep contact.
	local point = a.position - normal * (a.cfg.radius - separation)
	return newContact(
		a, b, point, normal, separation,
		combineFriction(a.cfg.friction, b.cfg.friction),
		combineRestitution(a.cfg.restitution, b.cfg.restitution),
		math.min(a.cfg.restitutionThreshold, b.cfg.restitutionThreshold)
	)
end

local function contactFirstIndex(contact)
	-- The reference contact table indexes box/sphere pairs by box, then
	-- sphere. The contact itself keeps the sphere first for floor drag.
	return if contact.bodyB.isSphere then contact.bodyA._bodyIndex else contact.bodyB._bodyIndex
end

local function contactSecondIndex(contact)
	return if contact.bodyB.isSphere then contact.bodyB._bodyIndex else contact.bodyA._bodyIndex
end

function World:buildContacts()
	local contacts = {}
	for _, s in ipairs(self.spheres) do
		if not s.stuck then
			for _, b in ipairs(self.boxes) do
				local c = self:collideSphereBox(s, b)
				if c then
					table.insert(contacts, c)
				end
			end
		end
	end
	local n = #self.spheres
	for i = 1, n do
		for j = i + 1, n do
			local a, b = self.spheres[i], self.spheres[j]
			-- Ghost's installed delegate rejects athlete IDs [1000, 3000) for
			-- either target, but explicitly allows the ball. The solver's sphere
			-- order is irrelevant: either ghosted athlete suppresses the pair.
			local ghostRejects = (a.ghosted and not b.isBall) or (b.ghosted and not a.isBall)
			if not (a.stuck or b.stuck) and not ghostRejects then
				local c = self:collideSphereSphere(a, b)
				if c then
					if self.sphereContactHandler then self.sphereContactHandler(c) end
					table.insert(contacts, c)
				end
			end
		end
	end
	-- Warm-start and impulse iteration scan the reference's contact table
	-- in ascending (first registered body index, second body index) order.
	table.sort(contacts, function(a, b)
		local firstA, firstB = contactFirstIndex(a), contactFirstIndex(b)
		if firstA ~= firstB then
			return firstA < firstB
		end
		return contactSecondIndex(a) < contactSecondIndex(b)
	end)
	self._contacts = contacts
end

-- -- pre-step (mass terms, bias, warm start) --------------------------------
function World:preStep(invDt)
	for _, c in ipairs(self._contacts) do
		local a, b = c.bodyA, c.bodyB
		local r1 = c.point - a.position
		local r2 = c.point - bodyPos(b)
		local n = c.normal

		local kNormal = (c.normalInvMassA or a.invMass) + (c.normalInvMassB or b.invMass)
		c.massNormal = kNormal > 0 and 1 / kNormal or 0.0
		-- NOTE: the tangent term uses plain |r|^2 (not (r x t)^2), and the normal
		-- term carries no rotational part at all — read from the real pre-step.
		local kTangent = a.invMass + b.invMass
			+ a.invInertia * r1:Dot(r1)
			+ b.invInertia * r2:Dot(r2)
		c.massTangent = kTangent > 0 and 1 / kTangent or 0.0

		-- Match the original tangent coordinates before reusing cached impulses.
		-- Sphere pairs store the opposite normal and impulse direction here.
		local sourceNormal = if b.isSphere then -n else n
		local relative = if b.isSphere then b.velocity - a.velocity else a.velocity - b.velocity
		local tf = relative - sourceNormal * relative:Dot(sourceNormal)
		if tf:Dot(tf) >= 1.1210387714598537e-44 then
			tf = tf.Unit
		elseif sourceNormal == Vector3.xAxis then
			tf = Vector3.zAxis
		else
			tf = Vector3.xAxis:Cross(sourceNormal)
			tf = if tf.Magnitude > 1e-5 then tf.Unit else Vector3.zero
		end
		c.tangentF = tf
		c.tangentS = n:Cross(tf)

		local positional = -SEPARATION_BIAS_FACTOR * invDt
			* math.min(0.0, c.separation + ALLOWED_PENETRATION)
		local dv = velAt(a, r1) - velAt(b, r2)
		local vn = dv:Dot(n)
		if self.impactHandler and vn < -2.5 then
			self.impactHandler(c, -vn)
		end
		local target = vn < -c.restitutionThreshold and (-c.restitution * vn) or 0.0
		c.bias = math.max(target, positional)

		local row = self._impulseCache[a]
		local cached = not c.normalInvMassA and row and row[b]
		if cached then
			c.pn, c.ptF, c.ptS = cached[1], cached[2], cached[3]
			local p = n * c.pn + c.tangentF * c.ptF + c.tangentS * c.ptS
			applyImpulse(a, r1, p)
			applyImpulse(b, r2, -p)
		end
	end
end

-- -- impulse iterations ------------------------------------------------------
function World:applyImpulses()
	local thresh = IMPULSE_CONVERGENCE_THRESHOLD
	for _ = 1, MAX_IMPULSE_ITERATIONS do
		local maxDpn, maxDptSq = 0.0, 0.0
		for _, c in ipairs(self._contacts) do
			local a, b = c.bodyA, c.bodyB
			local r1 = c.point - a.position
			local r2 = c.point - bodyPos(b)
			local n, tf, ts = c.normal, c.tangentF, c.tangentS

			-- normal: linear relative velocity only, linear impulse only
			local vn = (a.velocity - b.velocity):Dot(n)
			local pn0 = c.pn
			c.pn = math.max(pn0 + c.massNormal * (-vn + c.bias), 0.0)
			local dPn = c.pn - pn0
			local p = n * dPn
			local invA, invB = c.normalInvMassA or a.invMass, c.normalInvMassB or b.invMass
			if invA ~= 0 then
				a.velocity = a.velocity + p * invA
			end
			if invB ~= 0 then
				b.velocity = b.velocity - p * invB
			end

			-- friction: full point velocity, 2D CIRCULAR clamp (isotropic cone)
			local dv = velAt(a, r1) - velAt(b, r2)
			local newF = c.ptF - dv:Dot(tf) * c.massTangent
			local newS = c.ptS - dv:Dot(ts) * c.massTangent
			local maxPt = c.friction * c.pn
			local magSq = newF * newF + newS * newS
			if maxPt * maxPt < magSq then
				local scale = maxPt / math.sqrt(magSq)
				newF = newF * scale
				newS = newS * scale
			end
			local dF, dS = newF - c.ptF, newS - c.ptS
			c.ptF, c.ptS = newF, newS
			p = tf * dF + ts * dS
			applyImpulse(a, r1, p)
			applyImpulse(b, r2, -p)

			-- The original convergence test compares signed normal deltas.
			maxDpn = math.max(maxDpn, dPn)
			maxDptSq = math.max(maxDptSq, dF * dF + dS * dS)
		end
		if maxDptSq < thresh * thresh and maxDpn < thresh then
			break
		end
	end

	-- rebuild the warm-start cache
	local cache = {}
	for _, c in ipairs(self._contacts) do
		if c.normalInvMassA then continue end
		local a, b = c.bodyA, c.bodyB
		local row = cache[a]
		if not row then
			row = {}
			cache[a] = row
		end
		row[b] = { c.pn, c.ptF, c.ptS }
	end
	self._impulseCache = cache
end

-- -- rolling drag (real per-contact function, funcidx 18155) ------------------
function World:applyDrag(dt)
	local grounded = {}
	for _, c in ipairs(self._contacts) do
		local s, box = c.bodyA, c.bodyB
		if box.isSphere or s.stuck then
			continue
		end
		local n = c.normal
		local v = s.velocity
		local tangential = v - n * v:Dot(n)
		local tSpeed = tangential.Magnitude
		local maxSlow = s.invMass * s.cfg.rollingDrag * dt
		if tSpeed > 0 then
			if tSpeed <= maxSlow then
				s.velocity = v - tangential
			else
				s.velocity = v - tangential * (maxSlow / tSpeed)
			end
		end

		local wN = s.angularVelocity:Dot(n)
		local maxSpinSlow = s.invInertia * s.cfg.rollingSpinDrag * dt
		if math.abs(wN) <= maxSpinSlow then
			s.angularVelocity = s.angularVelocity - n * wN
		else
			local sign = wN > 0 and 1 or -1
			s.angularVelocity = s.angularVelocity - n * (sign * maxSpinSlow)
		end
		grounded[s] = true
	end
	for _, s in ipairs(self.spheres) do
		s.grounded = grounded[s] == true
	end
end

-- -- integration -------------------------------------------------------------
function World:integrateForces(dt)
	for _, s in ipairs(self.spheres) do
		if not s.stuck then
			s.velocity = s.velocity + self.gravity * dt
			if s.cfg.angularDamping ~= 0 then
				s.angularVelocity = s.angularVelocity
					* (1.0 / (1.0 + s.cfg.angularDamping * dt))
			end
		end
	end
end

function World:integrateVelocity(dt)
	for _, s in ipairs(self.spheres) do
		if not s.stuck then
			s.position = s.position + s.velocity * dt
			local w = s.angularVelocity
			if w:Dot(w) >= 1e-10 then
				-- NOTE: the angle is |w| itself, interpreted as DEGREES (no dt).
				s.rotation = CFrame.fromAxisAngle(w.Unit, math.rad(w.Magnitude)) * s.rotation
			end
		end
	end
end

function World:fireTriggers()
	for _, s in ipairs(self.spheres) do
		local occupied = self._triggerOccupancy[s]
		if not occupied then
			occupied = {}
			self._triggerOccupancy[s] = occupied
		end
		for _, t in ipairs(self.triggers) do
			local isInside = not t.disabled and not (t.ignoresGhosts and s.ghosted)
				and t:containsSphere(s.position, s.cfg.radius)
			if isInside ~= (occupied[t] == true) then
				occupied[t] = if isInside then true else nil
				if self.triggerHandler then
					self.triggerHandler(s, t, self, if isInside then "enter" else "exit")
				end
			end
		end
	end
end

function World:setTriggerEnabled(trigger, enabled)
	trigger.disabled = not enabled
	for _, occupied in pairs(self._triggerOccupancy) do
		occupied[trigger] = nil
	end
end

function World:step(dt)
	dt = dt or FIXED_DT
	self:integrateForces(dt)
	self:buildContacts()
	self:applyDrag(dt)
	self:preStep(1.0 / dt)
	self:applyImpulses()
	self:integrateVelocity(dt)
	self:fireTriggers()
	self.time = self.time + dt
end

function World:isAtRest(epsSq)
	epsSq = epsSq or 0.1
	for _, s in ipairs(self.spheres) do
		if not s.stuck then
			if s.velocity:Dot(s.velocity) >= epsSq then
				return false
			end
			if s.angularVelocity:Dot(s.angularVelocity) >= epsSq then
				return false
			end
		end
	end
	return true
end

BobblePhysics.World = World

-- ===========================================================================
-- The pitch (bobble/arena.py — every transform READ from the asset bundles)
-- ===========================================================================
local WALLS = {
	{ "WallNegZ",      Vector3.new(0.0, 9.0, -13.5),     0.0, Vector3.new(12.75, 10.0, 5.0) },
	{ "WallPosZ",      Vector3.new(0.0, 9.0, 13.5),      0.0, Vector3.new(12.75, 10.0, 5.0) },
	{ "WallPosXLeft",  Vector3.new(17.55, 9.0, 8.5),  -90.0, Vector3.new(4.5, 10.0, 4.8) },
	{ "WallPosXRight", Vector3.new(17.55, 9.0, -8.5), -90.0, Vector3.new(4.5, 10.0, 4.8) },
	{ "WallPosXTop",   Vector3.new(17.55, 14.0, 0.0), -90.0, Vector3.new(4.0, 10.0, 5.0) },
	{ "WallPosXBack",  Vector3.new(19.42, 2.0, 0.0),  -90.0, Vector3.new(4.0, 2.0, 4.0) },
	{ "WallNegXRight", Vector3.new(-17.55, 9.0, 8.5),  -90.0, Vector3.new(4.5, 10.0, 4.8) },
	{ "WallNegXLeft",  Vector3.new(-17.55, 9.0, -8.5), -90.0, Vector3.new(4.5, 10.0, 4.8) },
	{ "WallNegXTop",   Vector3.new(-17.55, 14.0, 0.0), -90.0, Vector3.new(4.0, 10.0, 5.0) },
	{ "WallNegXBack",  Vector3.new(-19.42, 2.0, 0.0),  -90.0, Vector3.new(4.0, 2.0, 4.0) },
}

-- Goal areas are ordered +X, then -X. The roster defends its own half.
local GOAL_AREAS = {
	{ Vector3.new(14.775872230529785, 0, 0),
		BobblePhysics.cfFromQuat(-0.7071068286895752, 0, 0, 0.7071068286895752) },
	{ Vector3.new(-14.775870323181152, 0, 0),
		BobblePhysics.cfFromQuat(0, 0.7071068286895752, 0.7071068286895752, 0) },
}
local GOAL_FRAME_BOXES = {
	{ "GoalPostCollision1", Vector3.new(-1.9, 4.0, 2.0),  Vector3.new(0.2, 0.2, 2.0) },
	{ "GoalPostCollision2", Vector3.new(-1.9, -4.0, 2.0), Vector3.new(0.2, 0.2, 2.0) },
	{ "GoalPostCollision3", Vector3.new(-1.9, 0.0, 4.0),  Vector3.new(0.2, 4.2, 0.2) },
}
local GOAL_TRIGGER_LOCAL = { Vector3.new(-0.35, 0.0, 2.0), Vector3.new(1.05, 4.0, 2.0) }

-- Serialized registration order, with existing names preserved for diagnostics.
local BUMP_PADS = {
	{ "BumpPad0", Vector3.new(12.25, 0.25, 8),
		BobblePhysics.cfFromQuat(0.27059832215309143, 0.6532813906669617, 0.6532813906669617, -0.2705982029438019) },
	{ "BumpPad2", Vector3.new(-12.25, 0.25, 8),
		BobblePhysics.cfFromQuat(-0.27059686183929443, 0.6532819271087646, 0.6532819867134094, 0.2705969214439392) },
	{ "BumpPad3", Vector3.new(-12.25, 0.25, -8),
		BobblePhysics.cfFromQuat(-0.6532806158065796, 0.2706001102924347, 0.27060022950172424, 0.6532806158065796) },
	{ "BumpPad1", Vector3.new(12.25, 0.25, -8),
		BobblePhysics.cfFromQuat(0.6532818078994751, 0.27059754729270935, 0.27059757709503174, -0.6532816290855408) },
}
local BUMP_VEL_LOCAL = Vector3.new(0.0, -12.0, 0.0)
local BALL_BUMP_VEL_LOCAL = Vector3.new(0.0, -8.0, 0.0)
local BUMPER_TRIGGER_EXTENT = Vector3.new(2.0, 2.0, 1.5)
local BUMPER_TRIGGER_LOCAL_OFFSET = Vector3.new(0.0, 1.103, 0.030)
local BUMPER_PHYSICS_ROOT_OFFSET = Vector3.new(0.0, -0.006, 0.640)

local CRATE_SPAWNS = {
	{ "PowerCrateA", Vector3.new(0.0, 0.0, 5.5),  BobblePhysics.cfFromQuat(0.0, 0.9914, 0.0, 0.1305) },
	{ "PowerCrateB", Vector3.new(0.0, 0.0, -5.5), BobblePhysics.cfFromQuat(0.0, 0.9914, 0.0, -0.1305) },
}

-- PlayArena support-floor footprint. The legacy FIELD_HALF_X name is not the
-- painted central-pitch or goal boundary; keep both meanings explicit.
BobblePhysics.FLOOR_HALF_X = 20.0
BobblePhysics.FIELD_HALF_X = BobblePhysics.FLOOR_HALF_X -- legacy alias
BobblePhysics.FIELD_HALF_Z = 8.5
-- Replica's painted/placement rectangle; not a recovered collision boundary.
BobblePhysics.CENTRAL_PITCH_HALF_X = 12.75
BobblePhysics.FLOOR_TOP_Y = 0.0
BobblePhysics.KICKOFF_SPOT = Vector3.new(0.0, 0.5, 0.0)

--[[ Populate `world` with the arena's fixed geometry (colliders + triggers). ]]
function BobblePhysics.buildArena(world)
	world:addBox(Box.new({
		name = "PlayArena",
		center = Vector3.new(0.0, -1.0, 0.0),
		halfExtent = Vector3.new(20.0, 1.0, 8.5),
		surface = Surfaces.Floor,
		tag = "floor",
	}))

	for _, w in ipairs(WALLS) do
		world:addBox(Box.new({
			name = w[1],
			center = w[2],
			halfExtent = w[4],
			rotation = BobblePhysics.yawCFrame(w[3]),
			surface = Surfaces.Wall,
			tag = "wall",
		}))
	end

	for team = 0, 1 do
		local area = GOAL_AREAS[team + 1]
		local gpos, grot = area[1], area[2]
		for _, fb in ipairs(GOAL_FRAME_BOXES) do
			world:addBox(Box.new({
				name = fb[1] .. "_" .. team,
				center = gpos + grot:VectorToWorldSpace(fb[2]),
				halfExtent = fb[3],
				rotation = grot,
				surface = Surfaces.Goalpost,
				tag = "goalpost",
			}))
		end
		world:addTrigger(Trigger.new({
			name = "GoalTrigger_" .. team,
			center = gpos + grot:VectorToWorldSpace(GOAL_TRIGGER_LOCAL[1]),
			halfExtent = GOAL_TRIGGER_LOCAL[2],
			rotation = grot,
			kind = "goal",
			data = { defendingTeam = 1 - team },
		}))
	end

	local localOffset = BUMPER_PHYSICS_ROOT_OFFSET + BUMPER_TRIGGER_LOCAL_OFFSET
	for _, pad in ipairs(BUMP_PADS) do
		local name, pos, rot = pad[1], pad[2], pad[3]
		world:addTrigger(Trigger.new({
			name = name,
			center = pos + rot:VectorToWorldSpace(localOffset),
			halfExtent = BUMPER_TRIGGER_EXTENT,
			rotation = rot,
			kind = "bumper",
			ignoresGhosts = false,
			data = {
				baseHalfExtent = BUMPER_TRIGGER_EXTENT,
				bumpDir = rot:VectorToWorldSpace(BUMP_VEL_LOCAL.Unit),
				bumpSpeed = BUMP_VEL_LOCAL.Magnitude,
				ballBumpSpeed = BALL_BUMP_VEL_LOCAL.Magnitude,
			},
		}))
	end

	for _, cr in ipairs(CRATE_SPAWNS) do
		local pos, rot = cr[2], cr[3]
		world:addTrigger(Trigger.new({
			name = cr[1],
			center = pos + rot:VectorToWorldSpace(Vector3.new(0.0, 0.55, 0.0)),
			halfExtent = Vector3.new(0.6, 0.6, 0.6),
			rotation = rot,
			kind = "crate",
			ignoresGhosts = true,
		}))
	end
end

return BobblePhysics

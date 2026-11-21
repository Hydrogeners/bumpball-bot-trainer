--!nonstrict
local Physics = require(script.Parent.BobblePhysics)
local Roster = require(script.Parent.BobbleRoster)
local Formations = require(script.Parent.KickoffFormations)
local Powers = require(script.Parent.PowerPlays)

local Round = {}
Round.__index = Round

local MIN_TICKS = Physics.MIN_TOTAL_SIM_TIME * Physics.UPDATE_HZ
local MAX_TICKS = Physics.MAX_TOTAL_SIM_TIME * Physics.UPDATE_HZ
local POST_GOAL_TICKS = Physics.SIM_TIME_AFTER_GOAL * Physics.UPDATE_HZ

function Round.new(random)
	local self = setmetatable({}, Round)
	self.world = Physics.newWorld()
	Physics.buildArena(self.world)
	self.random = random or Random.new()
	self.triggers = self.world.triggers
	self.powerShapes = {}
	self.goalsFlipped = false
	self.giantBallActive = false
	self.bigHeadActive = {}
	self.ghostActive = {}
	self.attackingTeam = Formations.ATTACKING_TEAM
	self.attackingFormation = "forward"
	self.roster = Roster.build()
	self.ball = self.world:addSphere(Physics.Sphere.new(Physics.Presets.Ball, Physics.KICKOFF_SPOT))
	self.ball.isBall = true
	self.athletes = {}
	for i, entry in ipairs(self.roster) do
		local athlete = self.world:addSphere(Physics.Sphere.new(Physics.Presets.Athlete, entry.home))
		athlete.id = i
		athlete.team = entry.team
		self.athletes[i] = athlete
	end
	self.world.sphereContactHandler = function(contact)
		local a, b, normal = contact.bodyA, contact.bodyB, contact.normal
		if not a.id or not b.id or a.team == b.team then return end
		local speedA, speedB = -a.velocity:Dot(normal), b.velocity:Dot(normal)
		local protected = if speedB > speedA then a else b
		local armor = self.armor[protected.id]
		if not armor or speedA + speedB < 1.5 or math.max(speedA, speedB) < 1.5 then return end
		contact.normalInvMassA = if protected == a then a.invMass * 0.10 else a.invMass
		contact.normalInvMassB = if protected == b then b.invMass * 0.10 else b.invMass
		contact.restitution = 0.85
		contact.restitutionThreshold = 0
		contact.friction = 0
		armor.spent, armor.impact = true, contact.point
		armor.impactNormal = if protected == a then -normal else normal
		self.armor[protected.id] = nil
	end
	self.world.impactHandler = function(contact, speed)
		local a, b = contact.bodyA, contact.bodyB
		if b.tag == "floor" then return end
		local ball = a.isBall or b.isBall
		local athlete = if a.isBall then b elseif b.isBall then a else nil
		if athlete and athlete.id then
			local last = self.ballTouch
			if not last or last.tick ~= self.ticks or speed > last.speed then
				self.ballTouch = { id = athlete.id, team = athlete.team, tick = self.ticks, speed = speed }
				self.ballBank = nil
			end
		elseif a.isBall and b.tag == "wall" and self.ballBank == nil then
			self.ballBank = "bank"
		end
		local device = b.tag == "ramp" or b.tag == "block"
		if not ball and not device and speed < 4 then return end
		local kind = if device then b.tag elseif b.isSphere then (if ball then "kick" else "bump") else "rail"
		local cueNormal = if kind == "ramp" and a.velocity.Magnitude > 0.01 then a.velocity.Unit else contact.normal
		if self.replayContact then
			self.replayContact(kind, contact.point, cueNormal, speed, ball, self.ticks + 1, athlete and athlete.id)
		end
		self:recordImpact(kind, contact.point, cueNormal, speed)
	end
	self.world.triggerHandler = function(body, trigger, _, transition)
		if transition ~= "enter" then return end
		if trigger.kind == "bumper" then
			local speed = body.isBall and trigger.data.ballBumpSpeed or trigger.data.bumpSpeed
			local direction = trigger.data.bumpDir.Unit
			local deficit = speed - body.velocity:Dot(direction)
			if deficit > 0 then
				body.velocity += direction * deficit * (trigger.data.bigBumpers and 1.5 or 1)
				if body.isBall then self.ballBank = "bumper" end
				if self.replayContact and body.isBall then
					self.replayContact("bumper", body.position, direction, deficit, true, self.ticks + 1)
				end
				if deficit >= 2.5 then self:recordImpact("bumper", body.position, direction, deficit) end
			end
		elseif trigger.kind == "goal" and body == self.ball and self.scorer == nil then
			self.scorer = if self.goalsFlipped then trigger.data.defendingTeam else 1 - trigger.data.defendingTeam
			self.goalTick = self.ticks + 1
			self.goalPosition = body.position
			self.goalSpeed = body.velocity.Magnitude
		elseif trigger.kind == "crate" and body.id and not self.held[body.team] and not trigger.disabled then
			self.held[body.team] = trigger.data.power
			self.pickupNumber += 1
			self.lastPickup = {
				number = self.pickupNumber,
				team = body.team,
				center = trigger.center,
				kind = trigger.data.power,
			}
			trigger.data.power = nil
			self.world:setTriggerEnabled(trigger, false)
		elseif trigger.kind == "boost" then
			body.velocity = trigger.data.velocity
			if self.replayContact then
				self.replayContact("boost", body.position, body.velocity.Unit, body.velocity.Magnitude,
					body.isBall, self.ticks + 1, body.id)
			end
			self:recordImpact("boost", body.position, body.velocity.Unit, body.velocity.Magnitude)
		elseif trigger.kind == "sticky" then
			body.velocity = Vector3.zero
		end
	end
	self:restart()
	return self
end

function Round:recordImpact(kind, position, normal, speed)
	-- A kick at the same instant must not swallow a power firing. Keep the last few
	-- device contacts across the three ticks between two public snapshots.
	if kind == "boost" or kind == "block" or kind == "ramp" or kind == "bumper" then
		local prior = self.deviceHits[#self.deviceHits]
		if not prior or prior.kind ~= kind or (position - prior.position).Magnitude > 0.8 or self.ticks - prior.tick >= 4 then
			self.deviceSerial += 1
			table.insert(self.deviceHits, { serial = self.deviceSerial, tick = self.ticks, kind = kind,
				position = position, normal = normal, speed = speed })
			if #self.deviceHits > 12 then table.remove(self.deviceHits, 1) end
		end
	end
	local previous = self.lastImpact
	if previous and self.ticks - previous.tick < 5 then
		if self.ticks ~= previous.tick or speed <= previous.speed then return end
	end
	self.lastImpact = { tick = self.ticks, kind = kind, position = position, normal = normal, speed = speed }
end

local function resetBody(body, position)
	body.position = position
	body.velocity = Vector3.zero
	body.angularVelocity = Vector3.zero
	body.rotation = CFrame.identity
	body.grounded = false
end

function Round:resetPositions(positions, ballPosition)
	self.world:clearContacts()
	self.world:clearTriggerOccupancy()
	resetBody(self.ball, ballPosition or Physics.KICKOFF_SPOT)
	for i, athlete in ipairs(self.athletes) do
		resetBody(athlete, positions and positions[i] or self.roster[i].home)
	end
end

function Round:applyKickoff(choices, attackingTeam)
	if self.kickoffApplied or self.resolving or self.ticks ~= 0 then return false end
	local positions, ballPosition = Formations.positions(choices, attackingTeam,
		Physics.FLOOR_TOP_Y + Physics.Presets.Athlete.radius, Physics.FLOOR_TOP_Y + self.ball.cfg.radius)
	if not positions then return false end
	self:resetPositions(positions, ballPosition)
	self.attackingTeam = attackingTeam
	self.attackingFormation = choices[attackingTeam + 1]
	self.kickoffApplied = true
	return true
end

function Round:expirePowers()
	if #self.activePowers == 0 then return end

	if self.giantBallActive then
		Physics.setSphereConfig(self.ball, Physics.Presets.Ball)
	end
	for id in pairs(self.bigHeadActive) do
		Physics.setSphereConfig(self.athletes[id], Physics.Presets.Athlete)
	end
	for id in pairs(self.ghostActive) do
		self.athletes[id].ghosted = false
	end
	self.goalsFlipped = false
	self.giantBallActive = false
	table.clear(self.bigHeadActive)
	table.clear(self.ghostActive)
	table.clear(self.activePowers)
	table.clear(self.armor)
	table.clear(self.magnets)
	self.magnetPull = nil
	for _, trigger in ipairs(self.world.triggers) do
		if trigger.kind == "bumper" and trigger.data.bigBumpers then
			trigger.halfExtent = trigger.data.baseHalfExtent
			trigger.data.bigBumpers = false
		end
	end
	for _, shape in ipairs(self.powerShapes) do
		local shapes = shape.surface and self.world.boxes or self.triggers
		if not shape.surface then self.world:setTriggerEnabled(shape, false) end
		table.remove(shapes, table.find(shapes, shape))
	end
	table.clear(self.powerShapes)
	self.world:clearContacts()
end

function Round:restart()
	self.activePowers = self.activePowers or {}
	self.armor, self.magnets = self.armor or {}, self.magnets or {}
	self:expirePowers()
	self:resetPositions()
	self.score = { [0] = 0, [1] = 0 }
	self.resolving = false
	self.ticks = 0
	self.kickoffApplied = false
	self.scorer = nil
	self.goalTick, self.goalPosition, self.lastImpact = nil, nil, nil
	self.deviceHits, self.deviceSerial = {}, 0
	self.goalSpeed, self.ballTouch, self.ballBank = nil, nil, nil
	self.attackingTeam = Formations.ATTACKING_TEAM
	self.attackingFormation = "forward"
	self.held = {}
	self.pickupNumber, self.lastPickup = 0, nil
	self.stealNumber, self.lastStealTeam = 0, nil
	self:prepareCrates(0)
end

function Round:prepareCrates(turn)
	if turn % 2 == 0 and turn ~= 0 then return end

	local slots = {}
	local oppositeSlot
	for _, trigger in ipairs(self.world.triggers) do
		if trigger.kind == "crate" then
			table.insert(slots, trigger)
			if not trigger.disabled then oppositeSlot = 3 - #slots end
			trigger.data.power = nil
			self.world:setTriggerEnabled(trigger, false)
		end
	end
	if turn == 0 then return end

	local crate = slots[oppositeSlot or self.random:NextInteger(1, #slots)]
	crate.data.power = Powers.Pool[self.random:NextInteger(1, #Powers.Pool)]
	self.world:setTriggerEnabled(crate, true)
end

function Round:stealPower(team)
	local opponent = 1 - team
	local stolen = self.held[opponent]
	if self.held[team] ~= "steal" or not stolen then return false end
	self.held[team], self.held[opponent] = stolen, nil
	self.stealNumber += 1
	self.lastStealTeam = team
	return true
end

function Round:placePower(placement)
	if placement.kind == "armor" then
		self.armor[placement.id] = placement
	elseif placement.kind == "magnet" then
		self.magnets[placement.id] = placement
	elseif placement.kind == "yellowcard" then
		local location = Formations.ballLocation(self.attackingFormation, self.attackingTeam,
			Physics.FLOOR_TOP_Y + self.ball.cfg.radius)
		if location then
			self.ball.position = location
			self.ball.rotation = CFrame.identity
		end
	elseif placement.kind == "redcard" then
		local athlete = self.athletes[placement.id]
		if athlete then
			athlete.position = Vector3.new(0, Physics.FLOOR_TOP_Y + athlete.cfg.radius, 0)
			athlete.rotation = CFrame.identity
		end
	elseif placement.kind == "giantball" then
		if not self.giantBallActive then
			Physics.setSphereConfig(self.ball, Physics.Presets.GiantBall)
			self.giantBallActive = true
		end
	elseif placement.kind == "bighead" then
		if not self.bigHeadActive[placement.id] then
			Physics.setSphereConfig(self.athletes[placement.id], Physics.Presets.AthleteBigHead)
			self.bigHeadActive[placement.id] = true
		end
	elseif placement.kind == "goalswap" then
		self.goalsFlipped = not self.goalsFlipped
	elseif placement.kind == "ghost" then
		local athlete = self.athletes[placement.id]
		if athlete then
			athlete.ghosted = true
			self.ghostActive[placement.id] = true
		end
	end
	if placement.kind == "bigbumpers" then
		for _, trigger in ipairs(self.world.triggers) do
			if trigger.kind == "bumper" then
				if not trigger.data.baseHalfExtent then trigger.data.baseHalfExtent = trigger.halfExtent end
				trigger.data.bigBumpers = true
				trigger.halfExtent = trigger.data.baseHalfExtent * 1.5
			end
		end
	end
	for _, geometry in ipairs(Powers.geometry(placement)) do
		if geometry.surface then
			table.insert(self.powerShapes, self.world:addBox(Physics.Box.new(geometry)))
		else
			table.insert(self.powerShapes, self.world:addTrigger(Physics.Trigger.new(geometry)))
		end
	end
	if placement.team ~= nil then self.held[placement.team] = nil end
	table.insert(self.activePowers, placement)
end

function Round:launchMoves(moves, hasPlacements)
	if self.resolving or self.scorer ~= nil then
		return false
	end
	local launched = false
	for index, athlete in ipairs(self.athletes) do
		local move = moves[index]
		if move then
			local horizontal = Vector3.new(move.direction.X, 0, move.direction.Z)
			local power = math.clamp(move.power, 0, 1)
			if horizontal.Magnitude >= 1e-4 and power > 0 then
				athlete.velocity = horizontal.Unit * (Physics.MAX_MOVE_POWER * Physics.evalMoveCurve(power))
				launched = true
			end
		end
	end
	if not launched and not hasPlacements then return false end
	self.ticks = 0
	self.lastImpact = nil
	table.clear(self.deviceHits)
	self.scorer = nil
	self.ballTouch, self.ballBank = nil, nil
	self.resolving = true
	return true
end

function Round:stepMagnet()
	if self.scorer ~= nil then
		self.magnetPull = nil
		return
	end
	if not self.magnetPull then
		-- Only one pull can act on the ball at a time. Roster order breaks ties.
		for id, athlete in ipairs(self.athletes) do
			local magnet = self.magnets[id]
			if not magnet then continue end
			local offset = athlete.position - self.ball.position
			local speed = Vector3.new(athlete.velocity.X, 0, athlete.velocity.Z).Magnitude
			local radii = athlete.cfg.radius + self.ball.cfg.radius
			if speed >= 0.8 and offset.Magnitude <= radii + Powers.MagnetReach and math.abs(offset.Y) < radii then
				magnet.spent, magnet.impact = true, self.ball.position
				self.magnets[id] = nil
				self.magnetPull = { athlete = athlete, ticks = math.round(Powers.MagnetDuration * Physics.UPDATE_HZ) }
				break
			end
		end
	end
	local pull = self.magnetPull
	if not pull then return end
	local offset = pull.athlete.position - self.ball.position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local radii = pull.athlete.cfg.radius + self.ball.cfg.radius
	if offset.Magnitude > radii + Powers.MagnetReach + Powers.MagnetReleaseMargin then
		self.magnetPull = nil
		return
	end
	-- Pull only toward the moving bobble. Carry the ball through a turn
	-- without welding it to the bobble or overpowering a strong clearance.
	if flat.Magnitude > 1e-4 then
		local direction = flat.Unit
		local gap = math.max(0, flat.Magnitude - radii)
		local desiredClosing = math.min(10, 1.8 + gap * 6)
		local closing = (self.ball.velocity - pull.athlete.velocity):Dot(direction)
		local acceleration = math.clamp((desiredClosing - closing) * 7, 0, 56)
		self.ball.velocity += direction * (acceleration * Physics.FIXED_DT)
	end
	pull.ticks -= 1
	if pull.ticks == 0 then self.magnetPull = nil end
end

function Round:step()
	if not self.resolving then return end
	self:stepMagnet()
	self.world:step(Physics.FIXED_DT)
	self.ticks += 1
	local goalGraceEnded = self.goalTick and self.ticks >= self.goalTick + POST_GOAL_TICKS
	if goalGraceEnded or self.ticks >= MAX_TICKS or (self.ticks >= MIN_TICKS and self.world:isAtRest(0.1)) then
		if self.scorer ~= nil then
			self.score[self.scorer] = 1
		end
		-- Freeze any residual motion before the next turn.
		for _, body in ipairs(self.world.spheres) do
			body.velocity = Vector3.zero
			body.angularVelocity = Vector3.zero
		end
		self.resolving = false
		self:expirePowers()
	end
end

return Round

--!strict
-- One live creature: senses, brain, movement. Perception follows the design
-- rules: creatures act on what they actually see, hear and sense, remember a
-- last known position, never read a player's true location for free, and
-- never pass through the walls of a secure shelter.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CreatureBrain = require(ReplicatedStorage.Shared.Logic.CreatureBrain)
local CreatureConfig = require(ReplicatedStorage.Shared.Config.CreatureConfig)
local LightVisibility = require(ReplicatedStorage.Shared.Logic.LightVisibility)
local Perception = require(ReplicatedStorage.Shared.Logic.Perception)
local Shelter = require(ReplicatedStorage.Shared.Logic.Shelter)
local Services = script.Parent.Parent.Services
local CollectiveService = require(Services.CollectiveService)
local LightService = require(Services.LightService)
local NoiseService = require(Services.NoiseService)
local PlayerService = require(Services.PlayerService)
local ShelterService = require(Services.ShelterService)
local TimeService = require(Services.TimeService)
local WeatherService = require(Services.WeatherService)
local Rigs = require(script.Parent.Rigs)

local Creature = {}

export type Creature = {
	id: string,
	kind: string,
	arch: CreatureConfig.Archetype,
	rig: Rigs.Rig,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	brain: CreatureBrain.Brain,
	home: Vector3,
	retreatTo: Vector3,
	patrol: { Vector3 }?,
	leash: number?,
	-- movement
	goal: Vector3?,
	waypoints: { PathWaypoint },
	wpIndex: number,
	pathGoal: Vector3?,
	pathAt: number,
	computing: boolean,
	lastPos: Vector3,
	stuckFor: number,
	climbing: boolean,
	-- senses
	heard: { NoiseService.NoiseEvent },
	targetPlayer: Player?,
	visibleTarget: Player?,
	lastReport: number,
	lastBeacon: number,
	-- behaviour
	window: Instance?,
	windowStare: number,
	windowLimit: number,
	windowCooldown: number,
	lastSeenThroughWindow: number,
	observedFor: number,
	observedBy: Player?,
	attackEntry: Instance?,
	searchPing: number,
	fleeUntil: number,
	despawnAt: number?,
	state: string,
	alive: boolean,
	nextTick: number,
}

local rng = Random.new(31)
local counter = 0
local folder: Folder? = nil

local function creaturesFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = workspace:FindFirstChild("Creatures")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Creatures"
		f.Parent = workspace
	end
	folder = f :: Folder
	return f :: Folder
end

function Creature.folder(): Folder
	return creaturesFolder()
end

local function now(): number
	return os.clock()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function groundAt(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { creaturesFolder() }
	params.RespectCanCollide = true -- land on the ground, not on tree canopies
	local hit = workspace:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), params)
	return if hit then hit.Position else pos
end
Creature.groundAt = groundAt

function Creature.new(
	kind: string,
	spawnPos: Vector3,
	opts: { patrol: { Vector3 }?, leash: number?, retreatTo: Vector3? }?
): Creature
	local arch = CreatureConfig.Archetypes[kind]
	assert(arch, "unknown creature " .. kind)
	local rig = if kind == "Watcher"
		then Rigs.watcher()
		elseif kind == "Dweller" then Rigs.dweller()
		else Rigs.crawler()
	counter += 1
	local id = kind .. "_" .. counter
	local ground = groundAt(spawnPos)
	rig.model.Name = id
	rig.model:SetAttribute("Kind", kind)
	rig.model:SetAttribute("State", "DORMANT")
	CollectionService:AddTag(rig.model, "Creature")
	rig.model:PivotTo(CFrame.new(ground + Vector3.new(0, rig.humanoid.HipHeight + 2, 0)))
	rig.model.Parent = creaturesFolder()
	pcall(function()
		rig.root:SetNetworkOwner(nil)
	end)
	local c: Creature = {
		id = id,
		kind = kind,
		arch = arch,
		rig = rig,
		model = rig.model,
		root = rig.root,
		humanoid = rig.humanoid,
		brain = CreatureBrain.new(arch.brain :: any, "DORMANT"),
		home = ground,
		retreatTo = (opts and opts.retreatTo) or ground,
		patrol = opts and opts.patrol,
		leash = opts and opts.leash,
		goal = nil,
		waypoints = {},
		wpIndex = 1,
		pathGoal = nil,
		pathAt = 0,
		computing = false,
		lastPos = ground,
		stuckFor = 0,
		climbing = false,
		heard = {},
		targetPlayer = nil,
		visibleTarget = nil,
		lastReport = 0,
		lastBeacon = 0,
		window = nil,
		windowStare = 0,
		windowLimit = rng:NextNumber(25, 50),
		windowCooldown = 0,
		lastSeenThroughWindow = 0,
		observedFor = 0,
		observedBy = nil,
		attackEntry = nil,
		searchPing = 0,
		fleeUntil = 0,
		despawnAt = nil,
		state = "DORMANT",
		alive = true,
		nextTick = 0,
	}
	return c
end

function Creature.position(c: Creature): Vector3
	return c.root.Position
end

function Creature.eye(c: Creature): Vector3
	return c.root.Position + Vector3.new(0, c.rig.eyeHeight - c.root.Size.Y / 2, 0)
end

-- Movement ---------------------------------------------------------------------

local function stop(c: Creature)
	c.goal = nil
	c.waypoints = {}
	c.humanoid:MoveTo(c.root.Position)
end

local function face(c: Creature, pos: Vector3)
	local p = c.root.Position
	local dir = flat(pos - p)
	if dir.Magnitude > 0.1 then
		c.root.CFrame = CFrame.lookAt(p, p + dir)
	end
end

-- Destinations inside a shelter the creature may not enter get moved outside,
-- to the nearest entry's outside point.
local function legalGoal(c: Creature, goal: Vector3): Vector3
	local shelter = ShelterService.shelterAt(goal, 2)
	if
		shelter
		and ShelterService.isSecure(shelter)
		and ShelterService.shelterAt(c.root.Position, 1) ~= shelter
	then
		local best, bestD = goal, math.huge
		for _, e in ShelterService.entries(shelter) do
			local out = CollectiveService.outsidePoint(e)
			if out then
				local d = (out - goal).Magnitude
				if d < bestD then
					best, bestD = out, d
				end
			end
		end
		return best
	end
	return goal
end

local function computePath(c: Creature, goal: Vector3)
	if c.computing then
		return
	end
	c.computing = true
	c.pathAt = now()
	c.pathGoal = goal
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = if c.kind == "Watcher" then 1.2 else 1.6,
			AgentHeight = if c.kind == "Watcher" then 10 else 5,
			AgentCanJump = true,
			WaypointSpacing = 6,
			Costs = { Water = math.huge },
		})
		local ok = pcall(function()
			path:ComputeAsync(c.root.Position, goal)
		end)
		c.computing = false
		if not c.alive then
			return
		end
		if ok and path.Status == Enum.PathStatus.Success then
			c.waypoints = path:GetWaypoints()
			c.wpIndex = math.min(2, #c.waypoints)
		else
			c.waypoints = {}
		end
	end)
end

local function moveTo(c: Creature, goal: Vector3, speed: string)
	goal = legalGoal(c, goal)
	c.goal = goal
	c.humanoid.WalkSpeed = (c.arch.speeds :: any)[speed] or c.arch.speeds.walk
	local needPath = c.pathGoal == nil
		or ((c.pathGoal :: Vector3) - goal).Magnitude > 6
		or now() - c.pathAt > 4
	if needPath and (goal - c.root.Position).Magnitude > 10 then
		computePath(c, goal)
	end
	local wp = c.waypoints[c.wpIndex]
	if wp and ((c.pathGoal :: Vector3) - goal).Magnitude <= 8 then
		if (flat(wp.Position - c.root.Position)).Magnitude < 3 then
			c.wpIndex += 1
			wp = c.waypoints[c.wpIndex]
		end
		if wp then
			if wp.Action == Enum.PathWaypointAction.Jump then
				c.humanoid.Jump = true
			end
			c.humanoid:MoveTo(wp.Position)
			return
		end
	end
	c.humanoid:MoveTo(goal)
end

function Creature.arrived(c: Creature, radius: number?): boolean
	local g = c.goal
	return g ~= nil and flat(g - c.root.Position).Magnitude < (radius or 4)
end

-- Climb through a window opening: the creature moves through the gap in the
-- glass, never through a wall.
local function climbThrough(c: Creature, window: Instance, inward: boolean)
	if c.climbing then
		return
	end
	local watch = window:FindFirstChild("WatchPoint")
	local inside = window:FindFirstChild("InsidePoint")
	local glass = window:FindFirstChild("Glass")
	if
		not (
			watch
			and inside
			and glass
			and watch:IsA("BasePart")
			and inside:IsA("BasePart")
			and glass:IsA("BasePart")
		)
	then
		return
	end
	c.climbing = true
	c.root.Anchored = true
	local from = if inward then watch.Position else inside.Position
	local to = if inward then inside.Position else watch.Position
	local up = Vector3.new(0, c.humanoid.HipHeight + c.root.Size.Y / 2, 0)
	c.root.CFrame = CFrame.lookAt(from + up, to + up)
	local mid =
		TweenService:Create(c.root, TweenInfo.new(0.8), { CFrame = CFrame.lookAt(glass.Position, to + up) })
	mid:Play()
	mid.Completed:Wait()
	local fin = TweenService:Create(
		c.root,
		TweenInfo.new(0.6),
		{ CFrame = CFrame.lookAt(to + up, to + up + (to - from) * Vector3.new(1, 0, 1)) }
	)
	fin:Play()
	fin.Completed:Wait()
	c.root.Anchored = false
	c.climbing = false
	c.waypoints = {}
	c.pathGoal = nil
end

-- Senses ---------------------------------------------------------------------

type Seen = {
	player: Player,
	gain: number,
	visible: boolean,
	position: Vector3,
	distance: number,
	throughWindow: boolean,
	protected: boolean,
}

local function perceivePlayers(c: Creature): Seen?
	local best: Seen? = nil
	local eye = Creature.eye(c)
	local look = c.root.CFrame.LookVector
	local senses = c.arch.senses
	local maxRange = math.max(senses.visionRange, senses.presenceRange) + 5
	local myShelter = ShelterService.shelterAt(c.root.Position, 1)
	for _, s in PlayerService.all() do
		if not PlayerService.isActive(s.player) then
			continue
		end
		local head = PlayerService.head(s.player)
		local root = PlayerService.root(s.player)
		if not head or not root then
			continue
		end
		local to = head.Position - eye
		local dist = to.Magnitude
		if dist > maxRange then
			continue
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { creaturesFolder() }
		if s.player.Character then
			params:AddToFilter(s.player.Character)
		end
		local dogs = workspace:FindFirstChild("Dogs")
		if dogs then
			params:AddToFilter(dogs)
		end
		local hit = workspace:Raycast(eye, to, params)
		local los = hit == nil
		local angle = if dist > 0.01 then math.deg(math.acos(math.clamp(look:Dot(to.Unit), -1, 1))) else 0
		local throughWindow = s.shelter ~= nil and myShelter ~= s.shelter
		local vis = Perception.visionScore(senses :: any, {
			distance = dist,
			angleDegrees = angle,
			hasLineOfSight = los,
			illumination = s.illumination,
			movement = s.movement,
			coatEquipped = s.coat,
			weatherVisibility = WeatherService.visibility(),
			throughWindow = throughWindow,
		})
		-- Walls and closed shelters block the unnatural sense less than sight,
		-- but a secure shelter still dulls it.
		local pres = Perception.presenceScore(senses :: any, dist, s.coat, s.movement == "still")
		if throughWindow and s.secure then
			pres *= 0.5
		end
		if s.breath.holding and dist < 10 then
			vis *= 0.6
			pres *= 0.6
		end
		local gain = vis + pres
		if gain > 0 and (best == nil or gain > (best :: Seen).gain) then
			local approx = root.Position
			if vis <= 0 then
				-- Presence alone gives only a vague direction.
				approx += Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))
			end
			best = {
				player = s.player,
				gain = gain,
				visible = vis > 0,
				position = approx,
				distance = dist,
				throughWindow = throughWindow,
				protected = c.arch.respectsShelter
					and s.shelter ~= nil
					and s.secure
					and myShelter ~= s.shelter,
			}
		end
	end
	return best
end

local function strongestNoise(c: Creature): (number, Vector3?)
	local bestS, bestP = 0, nil
	for _, ev in c.heard do
		if ev.source == nil and ev.kind == "scratch" then
			continue
		end
		local s = NoiseService.strengthAt(ev, c.root.Position, c.arch.senses.hearingMultiplier)
		if s > bestS then
			local err = NoiseService.positionError((ev.position - c.root.Position).Magnitude, s)
			bestS = s
			bestP = ev.position + Vector3.new(rng:NextNumber(-err, err), 0, rng:NextNumber(-err, err))
		end
	end
	table.clear(c.heard)
	return bestS, bestP
end

function Creature.hear(c: Creature, ev: NoiseService.NoiseEvent)
	if #c.heard < 6 then
		table.insert(c.heard, ev)
	end
end

-- Cabin lights draw nocturnal creatures. Returns (strength, point near a window).
local function beacon(c: Creature): (number, Vector3?)
	if c.arch.lightAttraction <= 0 or now() - c.lastBeacon < 6 then
		return 0, nil
	end
	c.lastBeacon = now()
	local vol = ShelterService.volume("Cabin")
	if not vol or (vol.Position - c.root.Position).Magnitude > 230 then
		return 0, nil
	end
	local electric, fire = LightService.shelterLights("Cabin")
	local open, total = 0, 0
	local points: { Vector3 } = {}
	for _, w in CollectionService:GetTagged("Window") do
		if w:GetAttribute("Shelter") == "Cabin" then
			total += 1
			if w:GetAttribute("CurtainsClosed") ~= true and w:GetAttribute("Shuttered") ~= true then
				open += 1
				local wp = w:FindFirstChild("WatchPoint")
				if wp and wp:IsA("BasePart") then
					table.insert(points, wp.Position)
				end
			end
		end
	end
	local b = LightVisibility.houseBeacon({
		electricLightsOn = electric,
		fireLit = fire,
		curtainsOpenFraction = if total > 0 then open / total else 0,
		nightFactor = TimeService.nightFactor(),
		weatherVisibility = WeatherService.visibility(),
	})
	local strength = b * c.arch.lightAttraction
	if strength < 0.15 then
		return 0, nil
	end
	local target = if #points > 0 then points[rng:NextInteger(1, #points)] else vol.Position
	-- Strong enough that a brightly lit, open house is worth walking to.
	return math.min(strength * 1.2, 1), target
end

-- The window between a creature and a player inside, if any.
local function windowBetween(from: Vector3, to: Vector3): Instance?
	local best, bestD = nil, math.huge
	for _, w in CollectionService:GetTagged("Window") do
		local glass = w:FindFirstChild("Glass")
		if glass and glass:IsA("BasePart") then
			local ab = to - from
			local t = math.clamp((glass.Position - from):Dot(ab) / math.max(ab:Dot(ab), 1e-3), 0, 1)
			local d = (from + ab * t - glass.Position).Magnitude
			if d < bestD then
				best, bestD = w, d
			end
		end
	end
	return if bestD < 8 then best else nil
end

-- Is a player looking right at this creature (with clear sight)?
local function observedBy(c: Creature): Player?
	local eye = Creature.eye(c)
	for _, s in PlayerService.all() do
		if not PlayerService.isActive(s.player) then
			continue
		end
		local head = PlayerService.head(s.player)
		if not head then
			continue
		end
		local to = eye - head.Position
		local d = to.Magnitude
		if d < 170 and d > 1 and s.look:Dot(to.Unit) > math.cos(math.rad(14)) then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { creaturesFolder() }
			if s.player.Character then
				params:AddToFilter(s.player.Character)
			end
			if workspace:Raycast(head.Position, to, params) == nil then
				return s.player
			end
		end
	end
	return nil
end

-- Brain + behaviour tick -------------------------------------------------------------

local function isActiveNow(c: Creature): boolean
	if not c.arch.nocturnal then
		return true
	end
	local p = TimeService.snapshot().phase
	return p == "Night" or p == "Dusk"
end

local function shouldRetreat(c: Creature): boolean
	if now() < c.fleeUntil then
		return true
	end
	if not c.arch.nocturnal then
		return false
	end
	local snap = TimeService.snapshot()
	return snap.phase == "Day" or (snap.phase == "Dawn" and snap.phaseProgress > 0.15)
end

function Creature.flee(c: Creature, seconds: number)
	c.fleeUntil = now() + seconds
end

local function randomPatrolPoint(c: Creature): Vector3
	if c.patrol and #c.patrol > 0 then
		return c.patrol[rng:NextInteger(1, #c.patrol)]
	end
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(20, 70)
	return c.home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local function interiorPoint(shelterId: string): Vector3?
	local vol = ShelterService.volume(shelterId)
	if not vol then
		return nil
	end
	local h = vol.Size / 2
	return (vol.CFrame * CFrame.new(
		rng:NextNumber(-h.X + 3, h.X - 3),
		-h.Y + 2.5,
		rng:NextNumber(-h.Z + 3, h.Z - 3)
	)).Position
end

-- Returns the player this creature caught, if any.
function Creature.tick(c: Creature, dt: number): Player?
	if not c.alive or c.climbing then
		return nil
	end
	local pos = c.root.Position
	local seen = perceivePlayers(c)
	local heardS, heardP = strongestNoise(c)
	local bS, bP = 0, nil
	if c.brain.state == "PATROL" then
		bS, bP = beacon(c)
	end

	-- Shared leads from the collective mind.
	local leadPos, leadLevel, leadSector = nil, 0, nil
	if c.arch.collective then
		leadPos, leadLevel, leadSector = CollectiveService.lead()
		if seen and seen.gain > 0.15 then
			if now() - c.lastReport > 1 then
				c.lastReport = now()
				CollectiveService.report(c.id, seen.position, math.min(seen.gain, 1))
			end
		elseif heardS > 0.2 and heardP then
			CollectiveService.report(c.id, heardP, heardS * 0.8)
		end
	end
	if heardS <= 0 and bS > heardS and bP then
		heardS, heardP = bS, bP
	end
	if heardS <= 0 and leadPos and c.brain.state == "PATROL" and (leadPos - pos).Magnitude < 260 then
		heardS, heardP = 0.6, leadPos
	end

	local stim: CreatureBrain.Stimulus? = nil
	if seen then
		stim = {
			gainPerSecond = seen.gain,
			position = seen.position,
			targetId = seen.player.UserId,
			visible = seen.visible,
		}
	end
	local heard: CreatureBrain.Heard? = if heardS > 0 and heardP
		then { strength = heardS, position = heardP }
		else nil
	local intent = CreatureBrain.step(c.brain, {
		dt = dt,
		active = isActiveNow(c),
		shouldRetreat = shouldRetreat(c),
		stimulus = stim,
		heard = heard,
		arrived = Creature.arrived(c),
		targetProtected = seen ~= nil and seen.protected and (c.brain.state == "HUNT" or seen.visible),
	})
	c.state = c.brain.state
	c.model:SetAttribute("State", c.state)
	c.targetPlayer = if seen then seen.player else nil
	c.visibleTarget = if seen and seen.visible then seen.player else nil

	-- Breaching: on bad nights the collective sends breachers at the weakest entry.
	if c.arch.canBreach and leadLevel == 4 and leadSector and not shouldRetreat(c) then
		c.attackEntry = CollectiveService.breachTarget(leadSector)
	elseif leadLevel ~= 4 then
		c.attackEntry = nil
	end

	-- Inside a breached shelter: search rooms while the network still says so.
	local myShelter = ShelterService.shelterAt(pos, 1)
	if leadLevel == 5 and leadSector and c.arch.collective and not shouldRetreat(c) then
		if now() - c.searchPing > 6 then
			c.searchPing = now()
			local p = interiorPoint(leadSector)
			if p then
				c.brain.lastKnown = p
				c.brain.lastKnownAge = 0
				c.brain.awareness = math.max(c.brain.awareness, c.arch.brain.investigateThreshold)
				if c.brain.state == "PATROL" or c.brain.state == "LOST_TARGET" then
					c.brain.state = "INVESTIGATE"
					c.brain.stateTime = 0
				end
			end
		end
	end

	-- Window paradox (Watchers): seen through glass -> go to that window and stare.
	if c.arch.reactsToObservation == "watcher" and not shouldRetreat(c) then
		if seen and seen.visible and seen.throughWindow and now() > c.windowCooldown then
			c.lastSeenThroughWindow = now()
			if not c.window then
				local head = PlayerService.head(seen.player)
				c.window = if head then windowBetween(Creature.eye(c), head.Position) else nil
				c.windowStare = 0
				c.windowLimit = rng:NextNumber(25, 50)
			end
		end
		local w = c.window
		if w then
			local watch = w:FindFirstChild("WatchPoint")
			local glass = w:FindFirstChild("Glass")
			if watch and watch:IsA("BasePart") and glass and glass:IsA("BasePart") then
				local lost = now() - c.lastSeenThroughWindow > 9
				if lost or c.windowStare > c.windowLimit then
					c.window = nil
					c.windowCooldown = now() + rng:NextNumber(40, 90)
					CreatureBrain.forget(c.brain)
					c.brain.state = "PATROL"
				elseif flat(watch.Position - pos).Magnitude > 3 then
					moveTo(c, watch.Position, "slow")
					return nil
				else
					stop(c)
					face(c, glass.Position)
					c.windowStare += dt
					c.model:SetAttribute("Staring", true)
					return nil
				end
			else
				c.window = nil
			end
		end
		c.model:SetAttribute("Staring", false)
		-- Moves only when unobserved; stared at too long, it withdraws.
		local watcher = observedBy(c)
		c.observedBy = watcher
		if watcher and c.brain.state ~= "HUNT" then
			c.observedFor += dt
			stop(c)
			face(c, (PlayerService.head(watcher) :: BasePart).Position)
			if c.observedFor > 12 then
				Creature.flee(c, 60)
			end
			return nil
		else
			c.observedFor = math.max(0, c.observedFor - dt * 0.5)
		end
	end

	-- Attack an entry point.
	local entry = c.attackEntry
	if entry and not myShelter then
		local out = CollectiveService.outsidePoint(entry)
		if out then
			if flat(out - pos).Magnitude > 5 then
				moveTo(c, out, "run")
			else
				stop(c)
				face(c, if entry:IsA("Model") then entry:GetPivot().Position else out)
				CollectiveService.attack(c.id, entry)
			end
			return nil
		end
	end

	-- Leash for territorial creatures.
	if c.leash and flat(pos - c.home).Magnitude > c.leash and c.brain.state ~= "RETREAT" then
		CreatureBrain.forget(c.brain)
		c.brain.state = "PATROL"
		moveTo(c, c.home, "walk")
		return nil
	end

	-- Getting into a shelter that has an opening: doors are walked through,
	-- windows are climbed through.
	local function goToward(target: Vector3, speed: string)
		local targetShelter = ShelterService.shelterAt(target, 1)
		if targetShelter and targetShelter ~= myShelter and not ShelterService.isSecure(targetShelter) then
			local openings = ShelterService.openings(targetShelter)
			local bestW: Instance? = nil
			local doorOpen = false
			for _, o in openings do
				if o:GetAttribute("EntryKind") == "door" then
					doorOpen = true
				elseif o:GetAttribute("EntryKind") == "window" then
					bestW = o
				end
			end
			if not doorOpen and bestW and c.kind ~= "Watcher" then
				local watch = bestW:FindFirstChild("WatchPoint")
				if watch and watch:IsA("BasePart") then
					if flat(watch.Position - pos).Magnitude > 3 then
						moveTo(c, watch.Position, speed)
					else
						local win = bestW
						task.spawn(climbThrough, c, win, true)
					end
					return
				end
			end
		end
		if myShelter and (targetShelter ~= myShelter) then
			-- Leaving: through an open door, or back out of the window.
			local openings = ShelterService.openings(myShelter)
			local hasDoor = false
			for _, o in openings do
				if o:GetAttribute("EntryKind") == "door" then
					hasDoor = true
				end
			end
			if not hasDoor then
				for _, o in openings do
					if o:GetAttribute("EntryKind") == "window" then
						local inside = o:FindFirstChild("InsidePoint")
						if inside and inside:IsA("BasePart") then
							if flat(inside.Position - pos).Magnitude > 3 then
								moveTo(c, inside.Position, speed)
							else
								task.spawn(climbThrough, c, o, false)
							end
							return
						end
					end
				end
				-- No opening at all: it opens the door on its way out.
				for _, e in ShelterService.entries(myShelter) do
					if e:GetAttribute("EntryKind") == "door" and e:GetAttribute("Installed") == true then
						e:SetAttribute("Open", true)
						NoiseService.emit(pos, "doorSlam")
					end
				end
			end
		end
		moveTo(c, target, speed)
	end

	local caught: Player? = nil
	local kind = intent.kind
	if kind == "Idle" then
		stop(c)
	elseif kind == "Look" then
		stop(c)
		if intent.position then
			face(c, intent.position :: Vector3)
		end
	elseif kind == "Patrol" then
		if c.goal == nil or Creature.arrived(c, 5) or rng:NextNumber() < 0.01 then
			goToward(randomPatrolPoint(c), "slow")
		else
			goToward(c.goal :: Vector3, "slow")
		end
	elseif kind == "MoveTo" then
		goToward(intent.position :: Vector3, intent.speed)
	elseif kind == "Wander" then
		local center = (intent.position :: Vector3?) or pos
		if c.goal == nil or Creature.arrived(c, 4) then
			goToward(center + Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-14, 14)), "walk")
		else
			goToward(c.goal :: Vector3, "walk")
		end
	elseif kind == "Chase" then
		local target = seen and seen.player
		goToward(intent.position :: Vector3, "run")
		if target then
			local root = PlayerService.root(target)
			local s = PlayerService.get(target)
			if root and s and flat(root.Position - pos).Magnitude < c.arch.catchRange then
				local ev = if s.shelter then ShelterService.evaluation(s.shelter) else nil
				local canHarm = ev == nil or Shelter.canHarmInside(ev, c.arch.respectsShelter)
				if canHarm and math.abs(root.Position.Y - pos.Y) < 8 then
					caught = target
					CreatureBrain.forget(c.brain)
					c.brain.state = "LOST_TARGET"
				end
			end
		end
	elseif kind == "Retreat" then
		goToward(c.retreatTo, "walk")
		if Creature.arrived(c, 8) and c.arch.nocturnal then
			c.despawnAt = c.despawnAt or now()
		end
	end

	-- Stuck handling: jump, then pick something else to do.
	if c.goal then
		if (pos - c.lastPos).Magnitude < 0.3 then
			c.stuckFor += dt
			if c.stuckFor > 2 then
				c.humanoid.Jump = true
			end
			if c.stuckFor > 6 then
				c.stuckFor = 0
				c.goal = nil
				c.pathGoal = nil
				c.waypoints = {}
			end
		else
			c.stuckFor = 0
		end
	end
	c.lastPos = pos
	return caught
end

function Creature.destroy(c: Creature)
	c.alive = false
	c.model:Destroy()
end

return Creature

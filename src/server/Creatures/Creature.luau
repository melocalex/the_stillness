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
local FearEcology = require(ReplicatedStorage.Shared.Logic.FearEcology)
local LightVisibility = require(ReplicatedStorage.Shared.Logic.LightVisibility)
local Net = require(ReplicatedStorage.Shared.Net)
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
	-- fear ecology and unnatural movement (Chapter 35)
	energy: number,
	hunger: number,
	temperament: string,
	profile: { dash: number, displace: number, stare: number, noise: number, pause: number },
	dashUntil: number,
	freezeUntil: number,
	displaceAt: number,
	pauseUntil: number,
	gaitUntil: number,
	gaitPaused: boolean,
	noiseAt: number,
	echoAt: number?,
	echoCue: string?,
	hops: number, -- window-to-window moves this visit
	tapPending: boolean,
	windowSince: number, -- when it set off for the current window
	windowArrived: boolean,
	returnWindow: Instance?, -- a false departure: it will come back here
	returnAt: number,
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

-- A temperament from the species' weighted odds (CreatureConfig).
local function pickTemperament(kind: string): string
	local odds = CreatureConfig.TemperamentOdds[kind]
	if not odds then
		return "Curious"
	end
	local total = 0
	for _, w in odds do
		total += w
	end
	local roll = rng:NextNumber(0, total)
	for name, w in odds do
		roll -= w
		if roll <= 0 then
			return name
		end
	end
	return "Curious"
end

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
	local temperament = pickTemperament(kind)
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
		energy = 0,
		hunger = 0,
		temperament = temperament,
		profile = CreatureConfig.Temperaments[temperament],
		dashUntil = 0,
		freezeUntil = 0,
		displaceAt = 0,
		pauseUntil = 0,
		gaitUntil = 0,
		gaitPaused = false,
		noiseAt = rng:NextNumber(10, 40),
		echoAt = nil,
		echoCue = nil,
		hops = 0,
		tapPending = false,
		windowSince = 0,
		windowArrived = false,
		returnWindow = nil,
		returnAt = 0,
	}
	rig.model:SetAttribute("Temperament", temperament)
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
	if c.kind == "Crawler" then
		-- Its rushes are faster; its dead stops (gait) more than pay for it.
		c.humanoid.WalkSpeed *= 1.3 + 0.2 * c.energy
	end
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

-- Unnatural movement (Chapter 35) ------------------------------------------------
-- Calm by default, sudden when it moves. Fear energy and temperament decide
-- how often; these rules decide where: never into a shelter, never onto a
-- player, never in view when it relocates, and never a catch mid-dash.

local function mods(c: Creature): FearEcology.Mods
	return FearEcology.mods(c.energy, c.hunger, c.profile)
end

local function unnatural(c: Creature): boolean
	return c.model:GetAttribute("NoUnnatural") ~= true and isActiveNow(c) and not shouldRetreat(c)
end

local function playerWithin(p: Vector3, radius: number): boolean
	for _, s in PlayerService.all() do
		local r = PlayerService.root(s.player)
		if r and flat(r.Position - p).Magnitude < radius then
			return true
		end
	end
	return false
end

-- Could anyone see this point? A wide cone (60 degrees either side of where
-- they look) and a clear line: much wider than the "staring at it" test.
local function visibleToAnyone(point: Vector3): boolean
	for _, s in PlayerService.all() do
		if not PlayerService.isActive(s.player) then
			continue
		end
		local head = PlayerService.head(s.player)
		if head then
			local to = point - head.Position
			local d = to.Magnitude
			if d < 220 and d > 1 and s.look:Dot(to.Unit) > 0.5 then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { creaturesFolder() }
				if s.player.Character then
					params:AddToFilter(s.player.Character)
				end
				if workspace:Raycast(head.Position, to, params) == nil then
					return true
				end
			end
		end
	end
	return false
end

-- Open ground it may stand on: terrain, not water, outside every shelter,
-- 20+ studs from every player, inside its leash.
local function standable(c: Creature, p: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { creaturesFolder() }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(p + Vector3.new(0, 120, 0), Vector3.new(0, -300, 0), params)
	if not hit or not hit.Instance:IsA("Terrain") or hit.Material == Enum.Material.Water then
		return nil
	end
	local g = hit.Position
	if ShelterService.shelterAt(g, 4) or playerWithin(g, 20) then
		return nil
	end
	if c.leash and flat(g - c.home).Magnitude > c.leash then
		return nil
	end
	return g
end

local function nearTree(g: Vector3): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { creaturesFolder() }
	for _, p in workspace:GetPartBoundsInRadius(g + Vector3.new(0, 4, 0), 6, params) do
		if p.Name == "Collider" then
			return true
		end
	end
	return false
end

local function stand(c: Creature, g: Vector3, look: Vector3)
	local up = Vector3.new(0, c.humanoid.HipHeight + c.root.Size.Y / 2, 0)
	local dir = flat(look - g)
	c.model:PivotTo(if dir.Magnitude > 0.1 then CFrame.lookAt(g + up, g + up + dir) else CFrame.new(g + up))
	c.goal = nil
	c.waypoints = {}
	c.pathGoal = nil
	c.stuckFor = 0
	c.lastPos = g + up
end

-- Dogs near a sudden sound or movement jump at it (DogService reads this).
local function startleDogs(pos: Vector3, radius: number, strength: number)
	for _, dog in CollectionService:GetTagged("Dog") do
		if dog:IsA("Model") and (dog:GetPivot().Position - pos).Magnitude < radius then
			dog:SetAttribute("StartleStrength", strength)
			dog:SetAttribute("StartledAt", now())
		end
	end
end

-- Which unnatural move it made last, for logs and tests in Studio.
local function moved(c: Creature, how: string)
	c.model:SetAttribute("LastMove", how)
	c.model:SetAttribute("LastMoveAt", now())
end

-- Where it wants to be: what it remembers, or (when hungry) the lit house.
local function interest(c: Creature): Vector3?
	local hungry = mods(c).seeksPeople
	local lk = c.brain.lastKnown
	if lk and (hungry or c.brain.state ~= "PATROL") then
		return lk
	end
	if hungry then
		local _, bp = beacon(c)
		if bp then
			return bp
		end
	end
	return c.goal
end

-- Spatial displacement: unseen, it is suddenly 10-22 studs closer to what
-- it wants, also somewhere nobody is looking, then it holds still.
local function displace(c: Creature): boolean
	local pos = c.root.Position
	if visibleToAnyone(Creature.eye(c)) then
		return false
	end
	local target = interest(c)
	local toward = if target then flat(target - pos) else Vector3.zero
	local a = rng:NextNumber(0, math.pi * 2)
	local dir = if toward.Magnitude > 1 then toward.Unit else Vector3.new(math.cos(a), 0, math.sin(a))
	for _ = 1, 6 do
		local side = Vector3.new(-dir.Z, 0, dir.X) * rng:NextNumber(-6, 6)
		local g = standable(c, pos + dir * rng:NextNumber(10, 22) + side)
		local eye = g and g + Vector3.new(0, c.humanoid.HipHeight + c.rig.eyeHeight, 0)
		if g and eye and not visibleToAnyone(eye) then
			stand(c, g, target or (g + dir))
			c.displaceAt = now() + rng:NextNumber(8, 16)
			c.freezeUntil = now() + rng:NextNumber(1.5, 4)
			moved(c, "displace")
			return true
		end
	end
	c.displaceAt = now() + 3
	return false
end

-- The dash: after a long stare, a burst sideways across open ground to a
-- spot by a tree, then complete stillness. Seen, but over in a moment.
local DASH_SPEED = 55
local function dash(c: Creature, from: Vector3): boolean
	local pos = c.root.Position
	local away = flat(pos - from)
	local base = if away.Magnitude > 1 then away.Unit else Vector3.new(1, 0, 0)
	local pick: Vector3? = nil
	for _ = 1, 8 do
		local turn = math.rad(rng:NextNumber(50, 130)) * (if rng:NextNumber() < 0.5 then -1 else 1)
		local dir = CFrame.Angles(0, turn, 0):VectorToWorldSpace(base)
		local g = standable(c, pos + dir * rng:NextNumber(12, 18))
		if g then
			if nearTree(g) then
				pick = g
				break
			end
			pick = pick or g
		end
	end
	local g = pick
	if not g then
		return false
	end
	c.humanoid.WalkSpeed = DASH_SPEED
	c.humanoid:MoveTo(g)
	c.goal = g
	c.waypoints = {}
	c.pathGoal = nil
	c.dashUntil = now() + (g - pos).Magnitude / DASH_SPEED + 0.2
	c.freezeUntil = c.dashUntil + rng:NextNumber(3, 8)
	startleDogs(g, 60, 0.3)
	moved(c, "dash")
	return true
end

-- Burst gait (Crawler, Dweller): a quick rush, a dead stop, a rush. Pauses
-- slow its average speed, so it is jumpier but never harder to escape.
local function gait(c: Creature, target: Vector3?): boolean
	if (c.kind ~= "Crawler" and c.kind ~= "Dweller") or c.model:GetAttribute("NoUnnatural") == true then
		return false
	end
	local t = now()
	if c.gaitPaused then
		if t < c.gaitUntil then
			stop(c)
			if target then
				face(c, target)
			end
			return true
		end
		c.gaitPaused = false
		c.gaitUntil = t + rng:NextNumber(0.6, 1.4) * (1 + 0.5 * c.energy)
		return false
	end
	if t > c.gaitUntil then
		c.gaitPaused = true
		c.gaitUntil = t + rng:NextNumber(0.4, 1.4) * (1 - 0.4 * c.energy)
		stop(c)
		return true
	end
	return false
end

-- Noises are behaviour: far calls, close breathing, and at a wall a tap or
-- a scratch that comes again a few seconds later, as if testing for an
-- answer. Silence is the default; fear makes them more frequent.
local NOISES: { [string]: { far: { string }, near: { string }, wall: { string } } } = {
	Watcher = {
		far = { "creatureCall" },
		near = { "creatureResponse" },
		wall = { "windowRattle", "scratch" },
	},
	Dweller = { far = { "floorCreak" }, near = { "creatureResponse", "floorCreak" }, wall = { "scratch" } },
	Crawler = {
		far = { "creatureCall" },
		near = { "scratch", "creatureResponse" },
		wall = { "scratch", "doorHit" },
	},
}
local lastNoise = 0

local SUDDEN: { [string]: boolean } = { windowRattle = true, scratch = true, doorHit = true }

local function noise(name: string, pos: Vector3, volume: number)
	Net.event("SoundCue"):FireAllClients(name, pos, volume)
	startleDogs(pos, if SUDDEN[name] then 40 else 25, if SUDDEN[name] then 0.35 else 0.15)
	for _, s in PlayerService.all() do
		local r = PlayerService.root(s.player)
		if r and (r.Position - pos).Magnitude < 60 then
			s.player:SetAttribute("HeardCreatureAt", now())
		end
	end
end

local function mutter(c: Creature, pos: Vector3)
	local t = now()
	local echo = c.echoCue
	if echo and c.echoAt and t >= c.echoAt then
		c.echoAt = nil
		c.echoCue = nil
		noise(echo, pos, 0.4)
		return
	end
	if t < c.noiseAt or t - lastNoise < 6 then
		return
	end
	c.noiseAt = t + mods(c).noiseInterval * rng:NextNumber(0.7, 1.3)
	local nearest = math.huge
	for _, s in PlayerService.all() do
		local r = PlayerService.root(s.player)
		if r then
			nearest = math.min(nearest, (r.Position - pos).Magnitude)
		end
	end
	local set = NOISES[c.kind]
	if not set or nearest > 160 then
		return
	end
	local atWall = ShelterService.shelterAt(pos, 6) ~= nil and c.energy > 0.3
	local list = if atWall then set.wall elseif nearest < 40 then set.near else set.far
	local name = list[rng:NextInteger(1, #list)]
	lastNoise = t
	noise(name, pos, 0.3 + 0.4 * c.energy)
	if atWall then
		c.echoAt = t + rng:NextNumber(3, 6)
		c.echoCue = name
	end
end

-- The window encounter: shut out at one window, it is soon at another of
-- the same house, tapping. It walks there, or (unseen, never inside, never
-- on top of anyone) is simply there.
local function otherWindow(w: Instance): Instance?
	local shelter = w:GetAttribute("Shelter")
	if type(shelter) ~= "string" then
		return nil
	end
	local options = {}
	for _, e in ShelterService.entries(shelter) do
		if e ~= w and e:GetAttribute("EntryKind") == "window" and e:FindFirstChild("WatchPoint") then
			table.insert(options, e)
		end
	end
	return if #options > 0 then options[rng:NextInteger(1, #options)] else nil
end

local function goToWindow(c: Creature, w: Instance)
	c.window = w
	c.windowStare = 0
	c.windowLimit = rng:NextNumber(15, 30)
	c.lastSeenThroughWindow = now()
	c.windowSince = now()
	c.windowArrived = false
	c.tapPending = true
	moved(c, "hop")
	local watch = w:FindFirstChild("WatchPoint")
	if watch and watch:IsA("BasePart") and not visibleToAnyone(Creature.eye(c)) then
		local g = watch.Position
		if not ShelterService.shelterAt(g, 1) and not playerWithin(g, 6) and not visibleToAnyone(g) then
			local glass = w:FindFirstChild("Glass")
			stand(c, groundAt(g), if glass and glass:IsA("BasePart") then glass.Position else g)
		end
	end
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

	-- Unnatural movement in progress: a dash runs its course, then stillness.
	if isActiveNow(c) and not shouldRetreat(c) then
		mutter(c, pos)
	end
	local tNow = now()
	if tNow < c.dashUntil then
		return nil
	end
	if tNow < c.freezeUntil and c.brain.state ~= "HUNT" and not shouldRetreat(c) then
		stop(c)
		local w = observedBy(c)
		local head = if w then PlayerService.head(w) else nil
		if head then
			face(c, head.Position)
		end
		return nil
	end

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
				c.hops = 0
				c.windowSince = now()
				c.windowArrived = false
			end
		end
		local w = c.window
		if w then
			local watch = w:FindFirstChild("WatchPoint")
			local glass = w:FindFirstChild("Glass")
			if watch and watch:IsA("BasePart") and glass and glass:IsA("BasePart") then
				-- It walks to the window first (up to 25 s); the clock for losing
				-- sight starts when it arrives. Curtains or shutters then shut it
				-- out quickly; otherwise it waits.
				local atWatch = flat(watch.Position - pos).Magnitude <= 3
				if not atWatch and now() - c.windowSince < 25 then
					moveTo(c, watch.Position, "slow")
					return nil
				end
				if atWatch and not c.windowArrived then
					c.windowArrived = true
					c.lastSeenThroughWindow = now()
				end
				local shut = w:GetAttribute("CurtainsClosed") == true or w:GetAttribute("Shuttered") == true
				local lost = not atWatch or now() - c.lastSeenThroughWindow > (if shut then 3 else 9)
				if lost or c.windowStare > c.windowLimit then
					c.window = nil
					c.windowCooldown = now() + rng:NextNumber(40, 90)
					CreatureBrain.forget(c.brain)
					c.brain.state = "PATROL"
					-- Not finished with this house: another window, or it leaves
					-- and comes back later without a sound.
					if lost and unnatural(c) then
						local other = if c.hops < 2 then otherWindow(w) else nil
						if other and rng:NextNumber() < 0.35 + 0.4 * c.energy then
							c.hops += 1
							goToWindow(c, other)
						elseif c.temperament == "Deceiver" or c.energy > 0.5 then
							c.returnWindow = w
							c.returnAt = now() + rng:NextNumber(20, 40)
						end
					end
				else
					stop(c)
					face(c, glass.Position)
					if c.tapPending then
						c.tapPending = false
						noise("windowRattle", glass.Position, 0.45)
						c.echoAt = now() + rng:NextNumber(3, 6)
						c.echoCue = "windowRattle"
					end
					c.windowStare += dt
					c.model:SetAttribute("Staring", true)
					return nil
				end
			else
				c.window = nil
			end
		end
		-- The false departure ends: it comes back to the window it left.
		local back = c.returnWindow
		if back and not c.window and now() >= c.returnAt then
			c.returnWindow = nil
			if unnatural(c) and back.Parent then
				c.hops = 0
				c.window = back
				c.windowStare = 0
				c.windowLimit = rng:NextNumber(15, 30)
				c.lastSeenThroughWindow = now()
				c.windowSince = now()
				c.windowArrived = false
				moved(c, "return")
			end
		end
		c.model:SetAttribute("Staring", false)
		-- Moves only when unobserved. Under a gaze it holds dead still; after
		-- a long stare it either withdraws or, fed on fear, dashes. Unwatched,
		-- it may simply be somewhere else.
		local watcher = observedBy(c)
		c.observedBy = watcher
		if watcher and c.brain.state ~= "HUNT" then
			c.observedFor += dt
			stop(c)
			local from = (PlayerService.head(watcher) :: BasePart).Position
			face(c, from)
			local m = mods(c)
			if c.observedFor > m.stareSeconds then
				c.observedFor = 0
				if not (unnatural(c) and rng:NextNumber() < m.dashChance and dash(c, from)) then
					Creature.flee(c, 60)
				end
			end
			return nil
		else
			c.observedFor = math.max(0, c.observedFor - dt * 0.5)
			if
				unnatural(c)
				and c.brain.state ~= "HUNT"
				and tNow >= c.displaceAt
				and rng:NextNumber() < mods(c).displaceChance * dt
				and displace(c)
			then
				return nil
			end
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
		if c.kind == "Watcher" and speed == "walk" then
			speed = "slow" -- it never hurries toward a house; it arrives
		end
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
	if (kind == "MoveTo" or kind == "Chase" or kind == "Wander") and gait(c, intent.position) then
		return nil
	end
	if kind == "Idle" then
		stop(c)
	elseif kind == "Look" then
		stop(c)
		if intent.position then
			face(c, intent.position :: Vector3)
		end
	elseif kind == "Patrol" then
		if c.kind == "Watcher" and tNow < c.pauseUntil then
			-- Long observation: still, facing the lit house if there is one.
			stop(c)
			local _, bp = beacon(c)
			if bp then
				face(c, bp)
			end
		elseif c.kind == "Watcher" and c.goal ~= nil and Creature.arrived(c, 5) then
			c.pauseUntil = tNow + rng:NextNumber(6, 18) * c.profile.pause
			stop(c)
		elseif c.goal == nil or Creature.arrived(c, 5) or rng:NextNumber() < 0.01 then
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

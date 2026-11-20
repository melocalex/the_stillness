--!strict
-- Per-player authoritative state: inventory, stance, stamina, breath, coat,
-- comfort and exposure. Everything a creature uses to detect a player is
-- computed here, on the server, from what the server can see.
--
-- Player attributes (read-only for clients): Stamina, Breath, HoldingBreath,
-- Straining, Coat, CoatFound, Comfort, Exposure, Sheltered, ShelterSecure,
-- Movement, Threat, Captured, Spawned.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Breath = require(ReplicatedStorage.Shared.Logic.Breath)
local Comfort = require(ReplicatedStorage.Shared.Logic.Comfort)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Inventory = require(ReplicatedStorage.Shared.Logic.Inventory)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Perception = require(ReplicatedStorage.Shared.Logic.Perception)
local LightService = require(script.Parent.LightService)
local NoiseService = require(script.Parent.NoiseService)
local ShelterService = require(script.Parent.ShelterService)
local TimeService = require(script.Parent.TimeService)
local WeatherService = require(script.Parent.WeatherService)

local PlayerService = {}

export type PState = {
	player: Player,
	inventory: Inventory.Inventory,
	coatFound: boolean,
	coat: boolean,
	sprint: boolean,
	crouch: boolean,
	wantBreath: boolean,
	stamina: number,
	breath: Breath.State,
	comfort: number,
	exposure: number,
	illumination: number,
	movement: Perception.Movement,
	speed: number,
	shelter: string?,
	secure: boolean,
	observing: Instance?,
	look: Vector3,
	lastOutside: number,
	outsideSince: number,
	insideSince: number,
	pettedAt: number,
	chasedAt: number,
	routine: { [string]: boolean },
	routineDay: number,
	captured: boolean,
	spawned: boolean,
	sleeping: number,
	threat: number,
	heavyBreathAt: number,
	loadStatus: string, -- "pending" | "ok" | "failed"
	saved: { [string]: any },
}

local states: { [Player]: PState } = {}
-- Extra sections other services keep in the same save (e.g. "progression").
local sections: { [string]: (Player) -> any } = {}
local spawnListeners: { (Player, Model) -> () } = {}
local chest = Inventory.new({}, 200)
local store: DataStore? = nil

local knownItems: { [string]: boolean } = {}
local caps: { [string]: number } = {}
for id, item in ItemConfig.Items do
	knownItems[id] = true
	caps[id] = item.cap
end

local function now(): number
	return os.clock()
end

function PlayerService.get(player: Player): PState?
	return states[player]
end

function PlayerService.all(): { PState }
	local out = {}
	for _, s in states do
		table.insert(out, s)
	end
	return out
end

function PlayerService.root(player: Player): BasePart?
	local c = player.Character
	if not c then
		return nil
	end
	local r = c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

function PlayerService.head(player: Player): BasePart?
	local c = player.Character
	if not c then
		return nil
	end
	local h = c:FindFirstChild("Head")
	return if h and h:IsA("BasePart") then h else PlayerService.root(player)
end

function PlayerService.humanoid(player: Player): Humanoid?
	local c = player.Character
	return if c then c:FindFirstChildOfClass("Humanoid") else nil
end

-- Is this player in the world and catchable?
function PlayerService.isActive(player: Player): boolean
	local s = states[player]
	if not s or not s.spawned or s.captured then
		return false
	end
	local h = PlayerService.humanoid(player)
	return h ~= nil and h.Health > 0
end

function PlayerService.onSpawned(fn: (Player, Model) -> ())
	table.insert(spawnListeners, fn)
end

-- Inventory ---------------------------------------------------------------

function PlayerService.pushInventory(player: Player)
	local s = states[player]
	if s then
		Net.event("Inventory"):FireClient(player, Inventory.snapshot(s.inventory), Inventory.snapshot(chest))
	end
end

function PlayerService.count(player: Player, item: string): number
	local s = states[player]
	return if s then Inventory.count(s.inventory, item) else 0
end

function PlayerService.give(player: Player, item: string, n: number): number
	local s = states[player]
	if not s or not knownItems[item] then
		return 0
	end
	local added = Inventory.add(s.inventory, item, n)
	if added > 0 then
		PlayerService.pushInventory(player)
	elseif n > 0 then
		Net.event("Notify")
			:FireClient(player, "You can't carry more " .. ItemConfig.Items[item].name .. ".", "info")
	end
	return added
end

function PlayerService.canAfford(player: Player, cost: { [string]: number }): boolean
	local s = states[player]
	return s ~= nil and Inventory.canAfford(s.inventory, cost)
end

function PlayerService.spend(player: Player, cost: { [string]: number }): boolean
	local s = states[player]
	if not s then
		return false
	end
	if not Inventory.spend(s.inventory, cost) then
		local parts = {}
		for item, n in cost do
			table.insert(
				parts,
				string.format("%d %s", n, ItemConfig.Items[item] and ItemConfig.Items[item].name or item)
			)
		end
		Net.event("Notify"):FireClient(player, "Needs " .. table.concat(parts, ", ") .. ".", "info")
		return false
	end
	PlayerService.pushInventory(player)
	return true
end

function PlayerService.chest(): Inventory.Inventory
	return chest
end

-- Moves items between a player's pack and the shared cabin chest.
local function storageMove(player: Player, item: any, amount: any, toChest: any)
	if type(item) ~= "string" or type(amount) ~= "number" or type(toChest) ~= "boolean" then
		return
	end
	if not knownItems[item] or amount < 1 or amount > 200 or math.floor(amount) ~= amount then
		return
	end
	local s = states[player]
	local root = PlayerService.root(player)
	if not s or not root then
		return
	end
	local near = false
	for _, c in CollectionService:GetTagged("Chest") do
		if c:IsA("BasePart") and (c.Position - root.Position).Magnitude < 12 then
			near = true
		end
	end
	if not near then
		return
	end
	if toChest then
		local taken = Inventory.remove(s.inventory, item, amount)
		local stored = Inventory.add(chest, item, taken)
		if stored < taken then
			Inventory.add(s.inventory, item, taken - stored)
		end
	else
		local taken = Inventory.remove(chest, item, amount)
		local added = Inventory.add(s.inventory, item, taken)
		if added < taken then
			Inventory.add(chest, item, taken - added)
		end
	end
	for _, p in Players:GetPlayers() do
		PlayerService.pushInventory(p)
	end
end

-- Coat, routine, comfort hooks -----------------------------------------------

function PlayerService.setCoatFound(player: Player)
	local s = states[player]
	if s then
		s.coatFound = true
		player:SetAttribute("CoatFound", true)
	end
end

function PlayerService.setCoat(player: Player, on: boolean)
	local s = states[player]
	if not s or not s.coatFound then
		return
	end
	s.coat = on
	player:SetAttribute("Coat", on)
	local c = player.Character
	if c then
		local coat = c:FindFirstChild("StillnessCoat")
		if on and not coat then
			local torso = c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso")
			if torso and torso:IsA("BasePart") then
				local p = Instance.new("Part")
				p.Name = "StillnessCoat"
				p.Size = torso.Size + Vector3.new(0.35, 1.6, 0.35)
				p.Color = Color3.fromRGB(46, 42, 40)
				p.Material = Enum.Material.Fabric
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.Massless = true
				p.CFrame = torso.CFrame * CFrame.new(0, -0.6, 0)
				local w = Instance.new("WeldConstraint")
				w.Part0 = torso
				w.Part1 = p
				w.Parent = p
				p.Parent = c
			end
		elseif not on and coat then
			coat:Destroy()
		end
	end
	local root = PlayerService.root(player)
	if root then
		NoiseService.emit(root.Position, "curtain", player)
	end
end

function PlayerService.markRoutine(player: Player, key: string)
	local s = states[player]
	if s then
		local day = TimeService.snapshot().day
		if s.routineDay ~= day then
			s.routine = {}
			s.routineDay = day
		end
		s.routine[key] = true
	end
end

function PlayerService.markPetted(player: Player)
	local s = states[player]
	if s then
		s.pettedAt = now()
		PlayerService.markRoutine(player, "dog")
	end
end

function PlayerService.markChased(player: Player)
	local s = states[player]
	if s then
		s.chasedAt = now()
	end
end

function PlayerService.setThreat(player: Player, threat: number)
	local s = states[player]
	if s and s.threat ~= threat then
		s.threat = threat
		player:SetAttribute("Threat", threat)
	end
end

function PlayerService.setObserving(player: Player, window: Instance?)
	local s = states[player]
	if s then
		s.observing = window
		player:SetAttribute("Observing", window ~= nil)
	end
end

function PlayerService.setSleeping(player: Player, on: boolean)
	local s = states[player]
	if s then
		s.sleeping = if on then now() else 0
	end
end

function PlayerService.isSleeping(player: Player): boolean
	local s = states[player]
	return s ~= nil and s.sleeping > 0 and now() - s.sleeping < 30
end

function PlayerService.eatStew(player: Player)
	local s = states[player]
	if not s or not Net.allow(player, "eat", 1) then
		return
	end
	if Inventory.spend(s.inventory, { Stew = 1 }) then
		s.stamina = GameConfig.Player.StaminaMax
		s.comfort = math.min(100, s.comfort + 15)
		PlayerService.markRoutine(player, "meal")
		PlayerService.pushInventory(player)
		Net.event("Notify"):FireClient(player, "Warm stew. You feel steadier.", "good")
	end
end

-- Spawning and capture -------------------------------------------------------

local bedCFrame: CFrame? = nil
local function bedSpawn(): CFrame
	if bedCFrame then
		return bedCFrame
	end
	local world = workspace:FindFirstChild("World")
	if world then
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Respawn") == true then
				bedCFrame = d.CFrame
				return d.CFrame
			end
		end
	end
	local sp = ReplicatedStorage:GetAttribute("SpawnPoint")
	return CFrame.new(if typeof(sp) == "Vector3" then sp else Vector3.new(0, 20, 40))
end

local function applySpeed(s: PState)
	local h = PlayerService.humanoid(s.player)
	if not h then
		return
	end
	local cfg = GameConfig.Player
	if s.captured then
		h.WalkSpeed = 0
	elseif s.crouch then
		h.WalkSpeed = cfg.SneakSpeed
	elseif s.sprint and s.stamina > 2 then
		h.WalkSpeed = cfg.RunSpeed
	else
		h.WalkSpeed = cfg.WalkSpeed
	end
end

function PlayerService.spawnAt(player: Player, cf: CFrame)
	local s = states[player]
	if not s then
		return
	end
	player:LoadCharacterAsync()
	local character = player.Character
	if not character then
		return
	end
	character:PivotTo(cf + Vector3.new(0, 3, 0))
	s.spawned = true
	s.captured = false
	player:SetAttribute("Spawned", true)
	player:SetAttribute("Captured", false)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			task.wait(3)
			if player.Parent and states[player] then
				PlayerService.spawnAt(player, bedSpawn())
			end
		end)
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping then
				local r = PlayerService.root(player)
				if r then
					NoiseService.emit(r.Position, "jump", player)
				end
			end
		end)
	end
	if s.coat then
		s.coat = false
		PlayerService.setCoat(player, true)
	end
	applySpeed(s)
	for _, fn in spawnListeners do
		task.spawn(fn, player, character)
	end
end

local function requestSpawn(player: Player)
	local s = states[player]
	if not s or s.spawned or not Net.allow(player, "spawn", 1) then
		return
	end
	if workspace:GetAttribute("WorldReady") ~= true then
		return
	end
	local sp = ReplicatedStorage:GetAttribute("SpawnPoint")
	local pos = if typeof(sp) == "Vector3" then sp else Vector3.new(0, 20, 60)
	PlayerService.spawnAt(player, CFrame.new(pos) * CFrame.Angles(0, math.rad(20), 0))
end

-- A creature reached the player. Never a permanent loss: fade out, drop some
-- of what you carry, wake up in the cabin.
function PlayerService.capture(player: Player, by: string)
	local s = states[player]
	if not s or s.captured or not s.spawned then
		return
	end
	s.captured = true
	player:SetAttribute("Captured", true)
	applySpeed(s)
	local lost = Inventory.loseFraction(
		s.inventory,
		GameConfig.Player.CaptureLossFraction,
		GameConfig.Player.CaptureLostItems
	)
	local parts = {}
	for item, n in lost do
		table.insert(parts, string.format("%d %s", n, ItemConfig.Items[item].name))
	end
	local text = string.format(
		"Something took you into the dark. (%s)%s",
		by,
		if #parts > 0 then "\nYou lost " .. table.concat(parts, ", ") .. "." else ""
	)
	Net.event("Captured"):FireClient(player, text)
	PlayerService.pushInventory(player)
	s.chasedAt = now()
	task.delay(GameConfig.Player.CaptureRespawnDelay, function()
		if not states[player] then
			return
		end
		local character = player.Character
		if character then
			character:PivotTo(bedSpawn() + Vector3.new(0, 2, 0))
		end
		s.captured = false
		player:SetAttribute("Captured", false)
		applySpeed(s)
	end)
end

-- Per-tick simulation ----------------------------------------------------------

local function skyLight(inside: boolean): number
	local nf = TimeService.nightFactor()
	local sky = (1 - nf) + nf * GameConfig.Player.NightSkyLight
	sky *= WeatherService.visibility() * 0.4 + 0.6
	return if inside then sky * 0.15 else sky
end

local function nearLitFire(pos: Vector3): boolean
	for _, f in CollectionService:GetTagged("Fireplace") do
		if f:IsA("BasePart") and f:GetAttribute("Lit") == true and (f.Position - pos).Magnitude < 20 then
			return true
		end
	end
	return false
end

local function dogNear(player: Player, pos: Vector3): boolean
	for _, d in CollectionService:GetTagged("Dog") do
		if d:IsA("Model") and d:GetAttribute("Owner") == player.UserId then
			local p = d:GetPivot().Position
			if (p - pos).Magnitude < 16 then
				return true
			end
		end
	end
	return false
end

local function slowTick(s: PState, dt: number)
	local player = s.player
	local root = PlayerService.root(player)
	if not root or not s.spawned then
		return
	end
	local pos = root.Position
	local t = now()
	local shelter = ShelterService.shelterAt(pos)
	if shelter and not s.shelter then
		s.insideSince = t
	elseif not shelter and s.shelter then
		s.outsideSince = t
	end
	if not shelter then
		s.lastOutside = t
	end
	s.shelter = shelter
	s.secure = shelter ~= nil and ShelterService.isSecure(shelter)
	s.illumination = LightService.illuminationAt(pos, skyLight(shelter ~= nil))

	local phase = TimeService.snapshot().phase
	local h = PlayerService.humanoid(player)
	local routineCount = 0
	for _ in s.routine do
		routineCount += 1
	end
	local target = Comfort.target({
		inside = shelter ~= nil,
		shelterSecure = s.secure,
		nearFire = nearLitFire(pos),
		warmLight = shelter ~= nil and s.illumination > 0.45,
		seated = h ~= nil and h.SeatPart ~= nil,
		dogNear = dogNear(player, pos),
		pettedRecently = t - s.pettedAt < GameConfig.Comfort.PetDogSeconds,
		homeComing = shelter ~= nil
			and t - s.insideSince < GameConfig.Comfort.HomeComingSeconds
			and s.insideSince - s.outsideSince > 60,
		weatherOutside = WeatherService.label(),
		observingSafely = s.observing ~= nil,
		routineDone = routineCount,
		upgradesBuilt = (ReplicatedStorage:GetAttribute("CabinUpgrades") :: number?) or 0,
		chasedRecently = t - s.chasedAt < GameConfig.Comfort.ChasedSeconds,
		night = phase == "Night" or phase == "Dusk",
	})
	s.comfort = Comfort.step(s.comfort, target.total, dt, GameConfig.Comfort.RatePerSecond)
	s.exposure = Comfort.exposure({
		outdoors = shelter == nil,
		illumination = s.illumination,
		movement = s.movement,
		coatEquipped = s.coat,
		weatherVisibility = WeatherService.visibility(),
	})
	player:SetAttribute("Comfort", math.floor(s.comfort + 0.5))
	player:SetAttribute("ComfortPhysical", target.physical)
	player:SetAttribute("ComfortEmotional", target.emotional)
	player:SetAttribute("ComfortWeather", target.weather)
	player:SetAttribute("Exposure", s.exposure)
	player:SetAttribute("Sheltered", shelter ~= nil)
	player:SetAttribute("ShelterSecure", s.secure)
	player:SetAttribute("Illumination", math.floor(s.illumination * 100) / 100)
end

local function fastTick(s: PState, dt: number)
	local player = s.player
	local root = PlayerService.root(player)
	if not root or not s.spawned then
		return
	end
	local vel = root.AssemblyLinearVelocity
	s.speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	s.movement = Perception.movementFromSpeed(s.speed, s.crouch)
	if s.captured then
		s.movement = "still"
	end
	player:SetAttribute("Movement", s.movement)

	local cfg = GameConfig.Player
	local running = s.movement == "run" and s.sprint
	if running then
		s.stamina = math.max(0, s.stamina - cfg.StaminaDrainPerSecond * dt)
		if s.stamina <= 2 then
			s.sprint = false
			applySpeed(s)
		end
	else
		s.stamina = math.min(
			cfg.StaminaMax,
			s.stamina + cfg.StaminaRegenPerSecond * Comfort.staminaMultiplier(s.comfort) * dt
		)
	end
	player:SetAttribute("Stamina", math.floor(s.stamina))

	local ev = Breath.step(s.breath, s.wantBreath and not s.captured, dt, Breath.Default)
	if ev == "gasp" then
		s.wantBreath = false
		NoiseService.emit(root.Position, "drop", player)
		Net.event("SoundCue"):FireClient(player, "gasp")
		Net.event("Notify"):FireClient(player, "You gasp for air.", "warning")
	elseif ev == "exhale" then
		NoiseService.emit(root.Position, "exhale", player, 4)
		Net.event("SoundCue"):FireClient(player, "exhale")
	end
	player:SetAttribute("Breath", math.floor(s.breath.breath * 100) / 100)
	player:SetAttribute("HoldingBreath", s.breath.holding)
	player:SetAttribute("Straining", Breath.straining(s.breath, Breath.Default))

	-- Heavy breathing after running is faintly audible unless held.
	if s.stamina < 35 and not s.breath.holding and now() - s.heavyBreathAt > 2 then
		s.heavyBreathAt = now()
		NoiseService.emit(root.Position, "breathing", player, 7)
	end
end

local function movementNoise(s: PState)
	local root = PlayerService.root(s.player)
	if not root or not s.spawned or s.captured then
		return
	end
	if s.movement == "sneak" then
		NoiseService.emit(root.Position, "crouch", s.player)
	elseif s.movement == "walk" then
		NoiseService.emit(root.Position, "walk", s.player)
	elseif s.movement == "run" then
		NoiseService.emit(root.Position, "run", s.player)
	end
end

-- Persistence (silently disabled without DataStore access, e.g. local Studio).

-- Another service stores its own section in this player's save. `saveFn`
-- returns the section, or nil to keep what was loaded.
function PlayerService.persist(key: string, saveFn: (Player) -> any)
	sections[key] = saveFn
end

-- "pending" until the save has been read, then "ok" (data or a new player;
-- also when there is no DataStore) or "failed" (never saved over).
function PlayerService.loadStatus(player: Player): string
	local s = states[player]
	return if s then s.loadStatus else "pending"
end

function PlayerService.savedSection(player: Player, key: string): any
	local s = states[player]
	return if s then s.saved[key] else nil
end

local function load(player: Player, s: PState)
	if not store then
		s.loadStatus = "ok"
		return
	end
	local ok, data = pcall(function()
		return (store :: DataStore):GetAsync("p_" .. player.UserId)
	end)
	if not ok then
		s.loadStatus = "failed"
		warn(
			"[Player] could not load save for " .. player.Name .. "; progress this session will not be saved"
		)
		return
	end
	if type(data) == "table" then
		s.saved = data
		Inventory.restore(s.inventory, data.items, knownItems)
		if data.coatFound == true then
			PlayerService.setCoatFound(player)
		end
		PlayerService.pushInventory(player)
	end
	s.loadStatus = "ok"
end

local function save(player: Player)
	local s = states[player]
	-- Never write over a save that could not be read.
	if not store or not s or s.loadStatus ~= "ok" then
		return
	end
	local data: { [string]: any } = { items = Inventory.snapshot(s.inventory), coatFound = s.coatFound }
	for key, fn in sections do
		local ok, v = pcall(fn, player)
		if ok and v ~= nil then
			data[key] = v
		elseif s.saved[key] ~= nil then
			data[key] = s.saved[key]
		end
	end
	pcall(function()
		(store :: DataStore):SetAsync("p_" .. player.UserId, data)
	end)
end

local function addPlayer(player: Player)
	local t = now()
	local s: PState = {
		player = player,
		inventory = Inventory.new(caps),
		coatFound = false,
		coat = false,
		sprint = false,
		crouch = false,
		wantBreath = false,
		stamina = GameConfig.Player.StaminaMax,
		breath = Breath.new(),
		comfort = 40,
		exposure = 0,
		illumination = 1,
		movement = "still",
		speed = 0,
		shelter = nil,
		secure = false,
		observing = nil,
		look = Vector3.new(0, 0, -1),
		lastOutside = t,
		outsideSince = t,
		insideSince = t,
		pettedAt = -1e9,
		chasedAt = -1e9,
		routine = {},
		routineDay = 1,
		captured = false,
		spawned = false,
		sleeping = 0,
		threat = 0,
		heavyBreathAt = 0,
		loadStatus = "pending",
		saved = {},
	}
	states[player] = s
	-- Shift is the run key; Roblox's shift-lock would steal it.
	player.DevEnableMouseLock = false
	player:SetAttribute("Stamina", s.stamina)
	player:SetAttribute("Breath", 1)
	player:SetAttribute("Comfort", s.comfort)
	player:SetAttribute("CoatFound", false)
	player:SetAttribute("Coat", false)
	player:SetAttribute("Threat", 0)
	player:SetAttribute("Spawned", false)
	task.spawn(load, player, s)
	PlayerService.pushInventory(player)
end

function PlayerService.start()
	pcall(function()
		store = DataStoreService:GetDataStore("StillnessSave_v1")
	end)
	Players.PlayerAdded:Connect(addPlayer)
	for _, p in Players:GetPlayers() do
		addPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		save(p)
		states[p] = nil
		Net.forget(p)
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do
			save(p)
		end
	end)

	Net.event("RequestSpawn").OnServerEvent:Connect(requestSpawn)
	Net.event("SetStance").OnServerEvent:Connect(function(player, sprint, crouch)
		local s = states[player]
		if
			not s
			or type(sprint) ~= "boolean"
			or type(crouch) ~= "boolean"
			or not Net.allow(player, "stance", 12)
		then
			return
		end
		s.sprint = sprint and not crouch
		s.crouch = crouch
		applySpeed(s)
	end)
	Net.event("SetBreath").OnServerEvent:Connect(function(player, holding)
		local s = states[player]
		if s and type(holding) == "boolean" and Net.allow(player, "breath", 10) then
			s.wantBreath = holding
		end
	end)
	Net.event("ToggleCoat").OnServerEvent:Connect(function(player)
		local s = states[player]
		if s and s.spawned and Net.allow(player, "coat", 2) then
			if not s.coatFound then
				Net.event("Notify"):FireClient(player, "You don't have a coat yet.", "info")
				return
			end
			PlayerService.setCoat(player, not s.coat)
		end
	end)
	Net.event("EatStew").OnServerEvent:Connect(PlayerService.eatStew)
	Net.event("StorageMove").OnServerEvent:Connect(storageMove)
	Net.unreliable("LookVector").OnServerEvent:Connect(function(player, v)
		local s = states[player]
		if
			s
			and typeof(v) == "Vector3"
			and v.Magnitude > 0.5
			and v.Magnitude < 1.5
			and Net.allow(player, "look", GameConfig.Net.LookRate + 2)
		then
			s.look = v.Unit
		end
	end)

	local slowAcc, noiseAcc, saveAcc = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		slowAcc += dt
		noiseAcc += dt
		saveAcc += dt
		for _, s in states do
			fastTick(s, dt)
		end
		if slowAcc >= 0.5 then
			for _, s in states do
				slowTick(s, slowAcc)
			end
			slowAcc = 0
		end
		if noiseAcc >= 0.4 then
			noiseAcc = 0
			for _, s in states do
				movementNoise(s)
			end
		end
		if saveAcc >= 120 then
			saveAcc = 0
			for _, p in Players:GetPlayers() do
				task.spawn(save, p)
			end
		end
	end)
end

return PlayerService

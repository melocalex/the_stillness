--!strict
-- The creatures' shared mental network (Logic/CollectiveMind) and the
-- coordinated attack on a shelter's entry points.
--
-- Creatures report evidence by sector. The network shares stale, imprecise
-- positions, never a player's true location. On Bad and Black nights, enough
-- distinct creatures with enough evidence about the cabin start breaking in
-- at its weakest door or window; one ordinary creature can only scratch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CollectiveMind = require(ReplicatedStorage.Shared.Logic.CollectiveMind)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Shelter = require(ReplicatedStorage.Shared.Logic.Shelter)
local NoiseService = require(script.Parent.NoiseService)
local ShelterService = require(script.Parent.ShelterService)

local CollectiveService = {}

local mind = CollectiveMind.new(GameConfig.Collective)
local L = CollectiveMind.Levels
local rng = Random.new(77)
local attackers: { [Instance]: { [string]: number } } = {} -- entry -> creature id -> last time
local lastCue: { [Instance]: number } = {}

local function now(): number
	return os.clock()
end

local function allowBreach(): boolean
	local t = ReplicatedStorage:GetAttribute("NightType")
	return t == "Bad" or t == "Black"
end

function CollectiveService.sectorFor(pos: Vector3): (string, boolean)
	for _, id in ShelterService.all() do
		local vol = ShelterService.volume(id)
		if vol and (vol.Position - pos).Magnitude < 45 then
			return id, true
		end
	end
	return string.format("%d_%d", pos.X // 60, pos.Z // 60), false
end

function CollectiveService.report(sourceId: string, pos: Vector3, strength: number)
	if strength <= 0 then
		return
	end
	local sector, breachable = CollectiveService.sectorFor(pos)
	CollectiveMind.report(mind, {
		sector = sector,
		strength = math.clamp(strength, 0, 1),
		position = pos,
		sourceId = sourceId,
		time = now(),
		breachable = breachable,
	})
end

-- Strongest shared lead, with position jittered by how stale it is.
function CollectiveService.lead(): (Vector3?, number, string?)
	local s = CollectiveMind.strongest(mind)
	if not s or s.level < L.INVESTIGATING or s.level == L.DISPERSING then
		return nil, if s then s.level else 0, nil
	end
	local u = CollectiveMind.uncertainty(mind, s)
	local base = s.position :: Vector3
	local jitter = Vector3.new(rng:NextNumber(-u, u), 0, rng:NextNumber(-u, u))
	return base + jitter, s.level, s.key
end

function CollectiveService.level(sector: string): number
	local s = mind.sectors[sector]
	return if s then s.level else 0
end

function CollectiveService.highestLevel(): number
	return CollectiveMind.highestLevel(mind)
end

local function resistance(entry: Instance): number
	local tier = (entry:GetAttribute("Tier") :: string?) or "standard"
	if entry:GetAttribute("Shuttered") == true then
		tier = "shutter"
	end
	return GameConfig.Breach.Resistance[tier] or 1
end

-- The entry point a breaching group should attack: lowest effective health.
function CollectiveService.breachTarget(shelterId: string): Instance?
	local best: Instance? = nil
	local bestScore = math.huge
	for _, e in ShelterService.entries(shelterId) do
		if e:GetAttribute("EntryKind") ~= "roof" and e:GetAttribute("Installed") == true then
			local h = (e:GetAttribute("Health") :: number?) or 100
			local score = h * resistance(e)
			if h > 0 and score < bestScore then
				bestScore = score
				best = e
			end
		end
	end
	return best
end

-- Outside standing point for an entry.
function CollectiveService.outsidePoint(entry: Instance): Vector3?
	local watch = entry:FindFirstChild("WatchPoint")
	if watch and watch:IsA("BasePart") then
		return watch.Position
	end
	local panel = entry:FindFirstChild("Panel")
	if panel and panel:IsA("BasePart") then
		local closed = panel:GetAttribute("ClosedCFrame") :: CFrame?
		local cf = closed or panel.CFrame
		-- The door's outside is +Z of the cabin; push away from the shelter centre.
		local vol = ShelterService.volume((entry:GetAttribute("Shelter") :: string?) or "Cabin")
		local away = if vol then (cf.Position - vol.Position) * Vector3.new(1, 0, 1) else Vector3.new(0, 0, 1)
		return cf.Position
			+ (if away.Magnitude > 0 then away.Unit else Vector3.new(0, 0, 1)) * 5
			- Vector3.new(0, 2.5, 0)
	end
	return nil
end

-- A creature says it is attacking this entry right now.
function CollectiveService.attack(creatureId: string, entry: Instance)
	local list = attackers[entry]
	if not list then
		list = {}
		attackers[entry] = list
	end
	list[creatureId] = now()
end

local function breach(entry: Instance)
	local shelter = (entry:GetAttribute("Shelter") :: string?) or "Cabin"
	local pos = (entry:IsA("Model") and entry:GetPivot().Position) or Vector3.zero
	local kind = entry:GetAttribute("EntryKind")
	CollectiveMind.setBreached(mind, shelter, true)
	NoiseService.emit(pos, if kind == "window" then "windowBreak" else "doorBreak")
	Net.event("SoundCue"):FireAllClients(if kind == "window" then "glassBreak" else "doorBreak", pos, 1)
	Net.event("Notify"):FireAllClients(
		if kind == "window" then "Glass breaks somewhere in the house." else "The door gives way.",
		"danger"
	)
end

local function tickAttacks(dt: number)
	local t = now()
	for entry, list in attackers do
		local n = 0
		for id, last in list do
			if t - last < 1.2 then
				n += 1
			else
				list[id] = nil
			end
		end
		if n == 0 then
			attackers[entry] = nil
			continue
		end
		local h = (entry:GetAttribute("Health") :: number?) or 100
		local maxH = (entry:GetAttribute("MaxHealth") :: number?) or 100
		if h <= 0 then
			continue
		end
		local nh =
			Shelter.applyAttack(h, maxH, n, GameConfig.Breach.damagePerAttacker, resistance(entry), dt, {
				groupThreshold = GameConfig.Breach.groupThreshold,
				soloDamageFloor = GameConfig.Breach.soloDamageFloor,
			})
		if not allowBreach() then
			nh = math.max(nh, maxH * GameConfig.Breach.soloDamageFloor)
		end
		if nh ~= h then
			entry:SetAttribute("Health", nh)
		end
		local pos = if entry:IsA("Model") then entry:GetPivot().Position else Vector3.zero
		if t - (lastCue[entry] or 0) > rng:NextNumber(1.2, 2.4) then
			lastCue[entry] = t
			local kind = entry:GetAttribute("EntryKind")
			local cue = if n >= GameConfig.Breach.groupThreshold
				then (if kind == "window" then "glassCrack" else "doorHit")
				else "scratch"
			Net.event("SoundCue"):FireAllClients(cue, pos, if n >= 3 then 1 else 0.6)
			NoiseService.emit(pos, "scratch", nil, if n >= 3 then 30 else 12)
		end
		if nh <= 0 and h > 0 then
			breach(entry)
		end
	end
end

function CollectiveService.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < 0.5 then
			return
		end
		CollectiveMind.update(mind, now(), allowBreach())
		tickAttacks(acc)
		acc = 0
		-- A repaired shelter is no longer breached.
		for _, id in ShelterService.all() do
			if ShelterService.isSecure(id) then
				CollectiveMind.setBreached(mind, id, false)
			end
		end
		ReplicatedStorage:SetAttribute("CollectiveLevel", CollectiveMind.highestLevel(mind))
	end)
end

return CollectiveService

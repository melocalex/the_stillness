--!strict
-- Owns all live creatures: spawning, despawning, AI tick scheduling (near
-- creatures tick at their archetype rate, far ones at 1 Hz), noise delivery,
-- and the per-player Threat level used by music, the dog and the HUD.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local NoiseService = require(script.Parent.NoiseService)
local PlayerService = require(script.Parent.PlayerService)

local CreatureService = {}

local Creature = require(script.Parent.Parent.Creatures.Creature)

type Creature = Creature.Creature

local creatures: { [string]: Creature } = {}
local rng = Random.new(91)

local function now(): number
	return os.clock()
end

function CreatureService.list(): { Creature }
	local out = {}
	for _, c in creatures do
		table.insert(out, c)
	end
	return out
end

function CreatureService.count(kind: string?): number
	local n = 0
	for _, c in creatures do
		if kind == nil or c.kind == kind then
			n += 1
		end
	end
	return n
end

function CreatureService.spawn(kind: string, pos: Vector3, opts: any?): Creature
	local c = Creature.new(kind, pos, opts)
	creatures[c.id] = c
	return c
end

function CreatureService.remove(c: Creature)
	creatures[c.id] = nil
	Creature.destroy(c)
end

-- Dawn: every nocturnal creature withdraws, then disappears.
function CreatureService.retreatAll()
	for _, c in creatures do
		if c.arch.nocturnal then
			Creature.flee(c, 400)
		end
	end
end

-- The Old One passes: Watchers nearby withdraw from it.
function CreatureService.fleeFrom(pos: Vector3, radius: number, kind: string?)
	for _, c in creatures do
		if (kind == nil or c.kind == kind) and (c.root.Position - pos).Magnitude < radius then
			Creature.flee(c, 90)
		end
	end
end

-- A point at the forest edge around the cabin, by compass bearing (degrees,
-- 0 = north, clockwise), at a given distance.
function CreatureService.edgePoint(bearing: number, distance: number): Vector3
	local a = math.rad(bearing)
	local cx, cz = WorldConfig.Cabin.x, WorldConfig.Cabin.z
	return Creature.groundAt(Vector3.new(cx + math.sin(a) * distance, 0, cz - math.cos(a) * distance))
end

local function nearestPlayerDistance(pos: Vector3): number
	local best = math.huge
	for _, s in PlayerService.all() do
		local r = PlayerService.root(s.player)
		if r then
			best = math.min(best, (r.Position - pos).Magnitude)
		end
	end
	return best
end

local THREAT_BY_STATE: { [string]: number } = {
	PATROL = 1,
	SUSPICIOUS = 2,
	INVESTIGATE = 2,
	SEARCH = 2,
	LOST_TARGET = 2,
	HUNT = 3,
}

local function updateThreats()
	local threat: { [Player]: number } = {}
	for _, s in PlayerService.all() do
		threat[s.player] = 0
	end
	for _, c in creatures do
		local level = THREAT_BY_STATE[c.state] or 0
		if level == 0 then
			continue
		end
		for _, s in PlayerService.all() do
			local r = PlayerService.root(s.player)
			if r then
				local d = (r.Position - c.root.Position).Magnitude
				local l = 0
				if c.state == "HUNT" and c.targetPlayer == s.player then
					l = 3
					PlayerService.markChased(s.player)
				elseif d < 45 then
					l = level
				elseif d < 90 then
					l = 1
				end
				if l > (threat[s.player] or 0) then
					threat[s.player] = l
				end
			end
		end
	end
	for player, l in threat do
		PlayerService.setThreat(player, l)
	end
end

-- Studio-only test hook: set the ReplicatedStorage attribute DebugSpawn to a
-- creature kind to place one 70 studs north of the cabin, fed with
-- DebugEnergy (0..1) of fear. Does nothing in a published game.
local function debugHook()
	if not RunService:IsStudio() then
		return
	end
	ReplicatedStorage:GetAttributeChangedSignal("DebugSpawn"):Connect(function()
		local kind = ReplicatedStorage:GetAttribute("DebugSpawn")
		if type(kind) ~= "string" or kind == "" then
			return
		end
		ReplicatedStorage:SetAttribute("DebugSpawn", "")
		local patrol = {}
		for i = 1, 5 do
			table.insert(patrol, CreatureService.edgePoint((i - 3) * 20, 50 + (i % 2) * 20))
		end
		local ok, c = pcall(CreatureService.spawn, kind, CreatureService.edgePoint(0, 70), {
			patrol = patrol,
			leash = 120,
			retreatTo = CreatureService.edgePoint(75, 240),
		})
		if ok and c then
			c.energy = math.clamp((ReplicatedStorage:GetAttribute("DebugEnergy") :: number?) or 0, 0, 1)
			print("[Creature] debug spawn", c.id, c.temperament, c.energy)
		else
			warn("[Creature] debug spawn failed: " .. tostring(c))
		end
	end)
end

function CreatureService.start()
	debugHook()
	NoiseService.onNoise(function(ev)
		for _, c in creatures do
			local reach = ev.loudness * c.arch.senses.hearingMultiplier + 5
			if (c.root.Position - ev.position).Magnitude < reach then
				Creature.hear(c, ev)
			end
		end
	end)
	local threatAcc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local t = now()
		for id, c in creatures do
			if c.despawnAt and t - c.despawnAt > 2 then
				CreatureService.remove(c)
				continue
			end
			if t >= c.nextTick then
				local near = nearestPlayerDistance(c.root.Position) < 220
				local rate = if near then c.arch.tickRate else 1
				local step = 1 / rate
				c.nextTick = t + step * rng:NextNumber(0.9, 1.1)
				local ok, caught = pcall(Creature.tick, c, step)
				if not ok then
					warn("[Creature] " .. id .. ": " .. tostring(caught))
				elseif caught then
					PlayerService.capture(caught, c.arch.displayName)
					Net.event("SoundCue"):FireClient(caught, "creatureCall")
				end
			end
		end
		threatAcc += dt
		if threatAcc > 0.5 then
			threatAcc = 0
			updateThreats()
		end
	end)
end

return CreatureService

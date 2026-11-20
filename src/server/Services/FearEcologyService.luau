--!strict
-- Fear ecology (Chapter 35). Twice a second: each character's fear drifts
-- toward a target built from fictional gameplay signals (creature threat,
-- pursuit, a creature in view, exposure in the dark, creature noises nearby;
-- calmed by a secure home, Caramelo, the fire and Maya). Creatures within
-- range feed on that fear: energy and hunger, stored on the creature, which
-- Creature.luau turns into bolder behaviour. Nothing here touches shelter,
-- breach or capture rules.
--
-- Published: player attributes Fear (0..1) and FearState; creature model
-- attributes FearEnergy and Hunger.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureConfig = require(ReplicatedStorage.Shared.Config.CreatureConfig)
local FearEcology = require(ReplicatedStorage.Shared.Logic.FearEcology)
local CreatureService = require(script.Parent.CreatureService)
local LightService = require(script.Parent.LightService)
local PlayerService = require(script.Parent.PlayerService)
local TimeService = require(script.Parent.TimeService)

local FearEcologyService = {}

local TICK = 0.5
local cfg = CreatureConfig.Fear :: FearEcology.Config
local fear: { [Player]: number } = {}

function FearEcologyService.fearOf(player: Player): number
	return fear[player] or 0
end

local function nearTagged(tag: string, pos: Vector3, radius: number, owner: number?): boolean
	for _, m in CollectionService:GetTagged(tag) do
		if m:IsA("Model") and (owner == nil or m:GetAttribute("Owner") == owner) then
			if (m:GetPivot().Position - pos).Magnitude < radius then
				return true
			end
		end
	end
	return false
end

local function update()
	local t = os.clock()
	local creatures = CreatureService.list()
	local night = TimeService.isNight()
	local roots: { [Player]: Vector3 } = {}
	for _, s in PlayerService.all() do
		local root = PlayerService.root(s.player)
		if not root or not s.spawned then
			continue
		end
		local pos = root.Position
		roots[s.player] = pos
		local saw = false
		for _, c in creatures do
			if
				c.observedBy == s.player
				or (c.visibleTarget == s.player and (c.root.Position - pos).Magnitude < 40)
			then
				saw = true
			end
		end
		local heardAt = s.player:GetAttribute("HeardCreatureAt") :: number?
		local fire = false
		if s.shelter then
			local _, lit = LightService.shelterLights(s.shelter)
			fire = lit
		end
		local target = FearEcology.target({
			threat = s.threat,
			chased = t - s.chasedAt < 8,
			sawCreature = saw,
			exposedDark = s.shelter == nil and night and s.illumination < 0.3,
			unexplainedSound = heardAt ~= nil and t - heardAt < 10,
			secureShelter = s.shelter ~= nil and s.secure,
			nearDog = nearTagged("Dog", pos, 12, s.player.UserId),
			nearFire = fire,
			nearMaya = nearTagged("Maya", pos, 16, nil),
		})
		local before = fear[s.player] or 0
		local now = FearEcology.step(before, target, TICK, cfg)
		fear[s.player] = now
		s.player:SetAttribute("Fear", math.floor(now * 100 + 0.5) / 100)
		s.player:SetAttribute("FearState", FearEcology.state(now, now < before))
	end
	for _, c in creatures do
		local intake = 0
		for player, pos in roots do
			intake += FearEcology.intake(fear[player] or 0, (c.root.Position - pos).Magnitude, cfg)
		end
		c.energy, c.hunger = FearEcology.feed(c.energy, c.hunger, intake, TICK, cfg)
		c.model:SetAttribute("FearEnergy", math.floor(c.energy * 100 + 0.5) / 100)
		c.model:SetAttribute("Hunger", math.floor(c.hunger * 100 + 0.5) / 100)
	end
end

function FearEcologyService.start()
	Players.PlayerRemoving:Connect(function(player)
		fear[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(update :: any)
			if not ok then
				warn("[Fear] " .. tostring(err))
			end
		end
	end)
end

return FearEcologyService

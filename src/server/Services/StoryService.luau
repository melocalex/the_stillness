--!strict
-- The "survive three nights" story. Facts are shared by everyone on the
-- server (a cooperative world). Other services set facts; this service also
-- derives location facts once per second and broadcasts the current step.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local StoryConfig = require(ReplicatedStorage.Shared.Config.StoryConfig)
local StoryProgress = require(ReplicatedStorage.Shared.Logic.StoryProgress)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local LightService = require(script.Parent.LightService)
local PlayerService = require(script.Parent.PlayerService)
local ShelterService = require(script.Parent.ShelterService)
local TimeService = require(script.Parent.TimeService)

local StoryService = {}

local facts: { [string]: any } = {}
local progress = StoryProgress.new()
local ended = false
local lastLabel = ""

local function currentLabel(): (string?, string?)
	local step = StoryProgress.current(progress, StoryConfig.Steps)
	if not step then
		return nil, nil
	end
	return StoryProgress.label(step, facts), step.hint
end

local function broadcast(completed: { string })
	local label, hint = currentLabel()
	local completedText: string? = nil
	if #completed > 0 then
		for _, s in StoryConfig.Steps do
			if s.id == completed[#completed] then
				completedText = s.text
			end
		end
	end
	if label ~= lastLabel or completedText then
		lastLabel = label or ""
		Net.event("Story"):FireAllClients(label, hint, completedText)
	end
	if not label and not ended then
		ended = true
		Net.event("EndCard"):FireAllClients(StoryConfig.Notes.ending)
	end
end

local function evaluate()
	local done = StoryProgress.advance(progress, StoryConfig.Steps, facts)
	broadcast(done)
end

function StoryService.setFact(key: string, value: any)
	if StoryConfig.KnownFacts[key] == nil then
		warn("[Story] unknown fact " .. key)
	end
	if facts[key] == value then
		return
	end
	facts[key] = value
	evaluate()
end

function StoryService.addFact(key: string, n: number)
	StoryService.setFact(key, (facts[key] or 0) + n)
end

function StoryService.getFact(key: string): any
	return facts[key]
end

local function insideZone(zoneName: string, pos: Vector3): boolean
	for _, z in CollectionService:GetTagged("Zone") do
		if z:IsA("BasePart") and z:GetAttribute("Zone") == zoneName then
			local p = z.CFrame:PointToObjectSpace(pos)
			local h = z.Size / 2
			if math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z then
				return true
			end
		end
	end
	return false
end

local function cabinCurtainsClosed(): boolean
	for _, w in CollectionService:GetTagged("Window") do
		if w:GetAttribute("Shelter") == "Cabin" then
			if not (w:GetAttribute("CurtainsClosed") == true or w:GetAttribute("Shuttered") == true) then
				return false
			end
		end
	end
	return true
end

local function derive()
	local snap = TimeService.snapshot()
	local night = snap.phase == "Dusk" or snap.phase == "Night"
	local nightType = ReplicatedStorage:GetAttribute("NightType")
	local cabin = Vector3.new(WorldConfig.Cabin.x, WorldConfig.Cabin.floorY, WorldConfig.Cabin.z)
	for _, s in PlayerService.all() do
		local root = PlayerService.root(s.player)
		if root and s.spawned then
			local pos = root.Position
			if not facts.foundCabin and (pos - cabin).Magnitude < WorldConfig.Cabin.clearing then
				StoryService.setFact("foundCabin", true)
			end
			if s.shelter == "Cabin" then
				if snap.day >= 2 and night then
					StoryService.setFact("homeAtDusk", true)
				end
				for _, d in CollectionService:GetTagged("Dog") do
					if d:IsA("Model") and d:GetAttribute("Owner") == s.player.UserId then
						if ShelterService.shelterAt(d:GetPivot().Position, 1) == "Cabin" then
							StoryService.setFact("dogInside", true)
						end
					end
				end
				if
					night
					and (nightType == "Bad" or nightType == "Black")
					and not LightService.hasPower("Cabin")
					and cabinCurtainsClosed()
					and s.coat
				then
					StoryService.setFact("preparedForNight", true)
				end
			end
			if insideZone("North", pos) then
				StoryService.setFact("reachedNorth", true)
			end
		end
	end
end

function StoryService.start()
	TimeService.onPhaseChanged(function(s, before)
		if s.phase == "Day" and before and s.day > before.day then
			StoryService.setFact("survivedNight" .. tostring(s.day - 1), true)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		task.wait(2)
		local label, hint = currentLabel()
		Net.event("Story"):FireClient(player, label, hint, nil)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			derive()
		end
	end)
	evaluate()
end

return StoryService

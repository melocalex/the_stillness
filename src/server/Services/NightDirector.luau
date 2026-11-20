--!strict
-- Classifies each night (Peaceful, Uneasy, Bad, Black), warns before bad
-- nights, schedules creature arrivals and sends them away at dawn.
--
-- Published on ReplicatedStorage: NightType, BadNightWarning, HowlingNight,
-- BirdsQuiet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local NightClass = require(ReplicatedStorage.Shared.Logic.NightClass)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local CreatureService = require(script.Parent.CreatureService)
local TimeService = require(script.Parent.TimeService)
local WeatherService = require(script.Parent.WeatherService)

local NightDirector = {}

local rng = Random.new(2026)
local classified: { [number]: string } = {}
local scheduled: { { at: number, fn: () -> () } } = {}

local function nightTypeFor(day: number): string
	local t = classified[day]
	if not t then
		t = NightClass.classify(day, rng:NextNumber(), GameConfig.Nights :: any)
		classified[day] = t
	end
	return t
end

function NightDirector.nightType(): string
	return (ReplicatedStorage:GetAttribute("NightType") :: string?) or "Peaceful"
end

local function after(seconds: number, fn: () -> ())
	table.insert(scheduled, { at = TimeService.elapsed() + seconds, fn = fn })
end

local function spawnWatcher(near: boolean)
	-- North of the cabin, between the trees and the lake: in view of the big window.
	local bearing = rng:NextNumber(-35, 35)
	local dist = if near then rng:NextNumber(60, 80) else rng:NextNumber(90, 120)
	local pos = CreatureService.edgePoint(bearing, dist)
	local retreat = CreatureService.edgePoint(bearing + rng:NextNumber(-60, 60), 260)
	local patrol = {}
	for i = 1, 6 do
		table.insert(patrol, CreatureService.edgePoint(bearing + (i - 3.5) * 25, rng:NextNumber(55, 110)))
	end
	CreatureService.spawn("Watcher", pos, { patrol = patrol, retreatTo = retreat })
end

local function spawnCrawler()
	local bearing = rng:NextNumber(0, 360)
	local pos = CreatureService.edgePoint(bearing, rng:NextNumber(150, 230))
	local patrol = {}
	for i = 1, 5 do
		table.insert(patrol, CreatureService.edgePoint(bearing + (i - 3) * 30, rng:NextNumber(50, 140)))
	end
	CreatureService.spawn(
		"Crawler",
		pos,
		{ patrol = patrol, retreatTo = CreatureService.edgePoint(bearing, 280) }
	)
end

local function startNight(day: number)
	local t = nightTypeFor(day)
	local profile = GameConfig.NightProfiles[t]
	local nightLen = GameConfig.Time.Durations.Night
	if rng:NextNumber() < profile.watcherChance then
		for i = 1, profile.watchers do
			-- The first night's watcher keeps its distance.
			after(nightLen * rng:NextNumber(0.1, 0.25) + i * 25, function()
				spawnWatcher(day > 1)
			end)
		end
	end
	for i = 1, profile.crawlers do
		after(nightLen * rng:NextNumber(0.08, 0.4) + i * 8, spawnCrawler)
	end
end

local function onPhase(snap: any, _before: any)
	if snap.phase == "Dusk" then
		local t = nightTypeFor(snap.day)
		ReplicatedStorage:SetAttribute("NightType", t)
		local bad = NightClass.isDangerous(t :: any)
		ReplicatedStorage:SetAttribute("BadNightWarning", bad)
		ReplicatedStorage:SetAttribute("BirdsQuiet", bad or t == "Uneasy")
		local howling = bad and (WeatherService.label() == "Storm" or WeatherService.rainIntensity() > 2.8)
		ReplicatedStorage:SetAttribute("HowlingNight", howling)
		if bad then
			Net.event("Notify")
				:FireAllClients("The birds have gone quiet. Something is wrong tonight.", "warning")
			Net.event("Radio"):FireAllClients(
				"Static... '...stay indoors tonight. Lights off. Curtains closed. Don't move when they're close.'"
			)
			Net.event("SoundCue"):FireAllClients("radioStatic", nil, 0.7)
		elseif t == "Uneasy" then
			Net.event("Notify"):FireAllClients("The forest feels watchful tonight.", "info")
		end
		if howling then
			task.delay(8, function()
				Net.event("Notify"):FireAllClients("The wind is rising. Latch the windows.", "warning")
			end)
		end
	elseif snap.phase == "Night" then
		startNight(snap.day)
	elseif snap.phase == "Dawn" then
		CreatureService.retreatAll()
		ReplicatedStorage:SetAttribute("BadNightWarning", false)
		ReplicatedStorage:SetAttribute("HowlingNight", false)
		ReplicatedStorage:SetAttribute("BirdsQuiet", false)
		table.clear(scheduled)
	elseif snap.phase == "Day" then
		ReplicatedStorage:SetAttribute("NightType", "Day")
	end
end

-- The Dweller lives in the abandoned house, day and night.
local function spawnDweller()
	local house = workspace:FindFirstChild("World")
		and (workspace :: any).World:FindFirstChild("AbandonedHouse")
	local points: { Vector3 } = {}
	if house then
		for _, d in house:GetDescendants() do
			if d:IsA("BasePart") and d.Parent and d.Parent.Name == "DwellerPoints" then
				table.insert(points, d.Position)
			end
		end
	end
	local center = Vector3.new(
		WorldConfig.AbandonedHouse.x,
		WorldConfig.AbandonedHouse.height + 2,
		WorldConfig.AbandonedHouse.z
	)
	local start = if #points > 0 then points[1] else center
	local c = CreatureService.spawn(
		"Dweller",
		start,
		{ patrol = if #points > 0 then points else nil, leash = 55, retreatTo = center }
	)
	c.home = center
end

function NightDirector.start()
	local snap = TimeService.snapshot()
	ReplicatedStorage:SetAttribute("NightType", if snap.phase == "Day" then "Day" else nightTypeFor(snap.day))
	TimeService.onPhaseChanged(onPhase)
	TimeService.onTick(function(_, _dt)
		local e = TimeService.elapsed()
		for i = #scheduled, 1, -1 do
			local job = scheduled[i]
			if e >= job.at then
				table.remove(scheduled, i)
				task.spawn(job.fn)
			end
		end
	end)
	task.delay(3, spawnDweller)
	-- If the Dweller is ever lost (stuck, destroyed), bring it back.
	task.spawn(function()
		while true do
			task.wait(30)
			if CreatureService.count("Dweller") == 0 then
				spawnDweller()
			end
		end
	end)
end

return NightDirector

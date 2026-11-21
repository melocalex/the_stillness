--!strict
-- Classifies each night (Peaceful, Uneasy, Bad, Black), warns before bad
-- nights, schedules creature arrivals and sends them away at dawn.
--
-- Published on ReplicatedStorage: NightType, BadNightWarning, HowlingNight,
-- BirdsQuiet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local NightClass = require(ReplicatedStorage.Shared.Logic.NightClass)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local CreatureService = require(script.Parent.CreatureService)
local MayaService = require(script.Parent.MayaService)
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

-- Tonight's night type, for the weather station's morning forecast. It only
-- ever asks for today, so nights are still classified in day order and the
-- seeded rolls do not change.
function NightDirector.forecast(): string
	return nightTypeFor(TimeService.snapshot().day)
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

-- Nights with stories: an ordinary night is one coherent situation, and
-- often nothing at all. Never the same story twice in two nights.
local recent: { string } = {}
local mayaSilent = false

local function pickStory(t: string): string?
	local weights = GameConfig.NightStories[t]
	if not weights then
		return nil
	end
	-- Studio-only: DebugStory forces the next ordinary night's story.
	local forced = ReplicatedStorage:GetAttribute("DebugStory")
	if RunService:IsStudio() and type(forced) == "string" and forced ~= "" then
		ReplicatedStorage:SetAttribute("DebugStory", "")
		return forced
	end
	local pool, total = {}, 0
	for name, w in weights do
		if name == "quiet" or not table.find(recent, name) then
			table.insert(pool, { name = name, w = w })
			total += w
		end
	end
	local roll = rng:NextNumber(0, total)
	for _, p in pool do
		roll -= p.w
		if roll <= 0 then
			return p.name
		end
	end
	return "quiet"
end

-- Compass bearing and distance from the cabin to a world point.
local function bearingTo(x: number, z: number): (number, number)
	local dx, dz = x - WorldConfig.Cabin.x, z - WorldConfig.Cabin.z
	return math.deg(math.atan2(dx, -dz)), math.sqrt(dx * dx + dz * dz)
end

local function watcherAround(bearing: number, dist: number, spread: number, leash: number?, arc: number)
	local patrol = {}
	for i = 1, 4 do
		table.insert(
			patrol,
			CreatureService.edgePoint(bearing + (i - 2.5) * arc, dist + rng:NextNumber(-spread, spread))
		)
	end
	CreatureService.spawn("Watcher", CreatureService.edgePoint(bearing, dist), {
		patrol = patrol,
		leash = leash,
		retreatTo = CreatureService.edgePoint(bearing, dist + 140),
	})
end

local function tellStory(story: string, nightLen: number)
	local at = nightLen * rng:NextNumber(0.1, 0.3)
	if story == "stays" then
		local b = rng:NextNumber(-30, 30)
		after(at, function()
			watcherAround(b, 75, 3, 25, 3)
		end)
	elseif story == "visit" then
		after(at, function()
			spawnWatcher(true)
		end)
	elseif story == "distant" then
		local hill = WorldConfig.Houses[1]
		for _, h in WorldConfig.Houses do
			if h.id == "HillHouse" then
				hill = h
			end
		end
		local b, d = bearingTo(hill.x, hill.z)
		after(at, function()
			watcherAround(b, d + 15, 15, 45, 6)
		end)
	elseif story == "passerby" then
		-- Any direction but north, where the lake is.
		local b = rng:NextNumber(35, 325)
		after(at, function()
			watcherAround(b, 140, 10, nil, 25)
		end)
	elseif story == "mayaSilent" then
		after(nightLen * 0.3, function()
			mayaSilent = true
			MayaService.setRoom("Upstairs", false)
			MayaService.setRoom("Downstairs", false)
		end)
	end
end

local function startNight(day: number)
	if day == 1 then
		return -- Night 1 is the guided first Watcher (OpeningService).
	end
	local t = nightTypeFor(day)
	local profile = GameConfig.NightProfiles[t]
	local nightLen = GameConfig.Time.Durations.Night
	local story = pickStory(t)
	if story then
		table.insert(recent, story)
		while #recent > 2 do
			table.remove(recent, 1)
		end
		ReplicatedStorage:SetAttribute("NightStory", story)
		tellStory(story, nightLen)
		return
	end
	ReplicatedStorage:SetAttribute("NightStory", t)
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
		if mayaSilent then
			mayaSilent = false
			task.delay(20, function()
				MayaService.radio(
					"Sorry. My radio battery died last night, and the lamp went with it. Did you sleep?"
				)
			end)
		end
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

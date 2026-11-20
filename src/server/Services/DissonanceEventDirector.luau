--!strict
-- Chapter 36: nonvisual tension inside a safe house. Answers anomaly beats
-- from ChaoticEnergyService (stage changes, coherence steps, level
-- crossings), never a clock. Logic/Dissonance picks the event, or nothing;
-- this module plays it with the systems that already exist: radio static,
-- a window rattle, one flicker of the house circuit, an ambience hush, a
-- moment of darkness in Maya's window, a startle for Caramelo (head up, or a
-- low growl), the Echo, and the needle moving while the scope is off.
--
-- Safety (Revision 2.0): no damage, no breaches, no noise events that call
-- creatures, nothing that blocks the story. Every effect undoes itself.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChaosField = require(ReplicatedStorage.Shared.Logic.ChaosField)
local Dissonance = require(ReplicatedStorage.Shared.Logic.Dissonance)
local DissonanceConfig = require(ReplicatedStorage.Shared.Config.DissonanceConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local LightService = require(script.Parent.LightService)
local MayaService = require(script.Parent.MayaService)
local ObservationService = require(script.Parent.ObservationService)
local PlayerService = require(script.Parent.PlayerService)
local ShelterService = require(script.Parent.ShelterService)
local TimeService = require(script.Parent.TimeService)

local DissonanceEventDirector = {}

local A = DissonanceConfig.Anomaly
local D = DissonanceConfig.Director
local LEVELS = DissonanceConfig.Levels

local rng = Random.new()
local scope: Model? = nil
local scopePos = Vector3.zero
local lastAt: { [string]: number } = {}
local flickered: { [number]: boolean } = {}
local ghostDone: { [number]: boolean } = {}
local lastRareDay = -math.huge
local hushSerial = 0

local function now(): number
	return os.clock()
end

local function between(range: { number }): number
	return rng:NextNumber(range[1], range[2])
end

local function scopeOn(): boolean
	local m = scope
	return m ~= nil and m:GetAttribute("Powered") == true
end

-- Players close enough to the scope to hear it.
local function listeners(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		local r = PlayerService.root(p)
		if r and (r.Position - scopePos).Magnitude <= D.hearRadius then
			table.insert(list, p)
		end
	end
	return list
end

-- One entry per key per day for everyone near the scope.
local function journal(key: string, subject: string, text: string)
	local day = TimeService.snapshot().day
	for _, p in listeners() do
		ObservationService.note(p, string.format("chaos-%s-d%d", key, day), subject, text)
	end
end

local function dogNear(): boolean
	for _, m in CollectionService:GetTagged("Dog") do
		if m:IsA("Model") and (m:GetPivot().Position - scopePos).Magnitude <= D.hearRadius then
			return true
		end
	end
	return false
end

local function entryPosition(kind: string): Vector3?
	local best: Vector3? = nil
	for _, e in ShelterService.entries("Cabin") do
		if e:GetAttribute("EntryKind") == kind and e:IsA("Model") then
			local p = if e.PrimaryPart then e.PrimaryPart.Position else e:GetPivot().Position
			if not best or rng:NextNumber() < 0.5 then
				best = p
			end
		end
	end
	return best
end

local function cue(name: string, position: Vector3?, volume: number)
	for _, p in listeners() do
		Net.event("SoundCue"):FireClient(p, name, position, volume)
	end
end

local function context(a: Dissonance.Anomaly, atHome: boolean, audible: boolean): Dissonance.Context
	local snap = TimeService.snapshot()
	local electric = LightService.shelterLights("Cabin")
	local house = MayaService.house()
	return {
		family = a.family,
		atHome = atHome,
		scopeOn = scopeOn() and audible,
		night = snap.phase == "Night" or snap.phase == "Dusk",
		dogNear = dogNear(),
		mayaLit = house ~= nil
			and (house:GetAttribute("Upstairs") == true or house:GetAttribute("Downstairs") == true),
		electric = electric > 0,
		flickered = flickered[a.id] == true,
		peaked = a.peaked,
		ghostDone = ghostDone[a.id] == true,
	}
end

-- Effects -------------------------------------------------------------------

local function transmission(a: Dissonance.Anomaly)
	local day = TimeService.snapshot().day
	local rareAllowed = day - lastRareDay >= A.noOutsideMinDays
	local line, rare =
		Dissonance.arrivalLine(a.coherence, rng:NextNumber(), rng:NextNumber(1, 9999), rareAllowed, A)
	if rare then
		lastRareDay = day
	end
	for _, p in listeners() do
		Net.event("Radio"):FireClient(p, "Unknown: " .. line)
		Net.event("SoundCue"):FireClient(p, "radioStatic", scopePos, 0.3)
	end
	if line == Dissonance.ARRIVAL then
		journal(
			"arrival-whole",
			"The Arrival",
			'A voice under the static on the Chaoscope: "The quiet is ending."'
		)
	elseif rare then
		journal(
			"arrival-rare",
			"The Arrival",
			"The transmission said something else tonight. I wrote it down and then I closed the book."
		)
	else
		journal(
			"arrival",
			"The Arrival",
			"Broken words under the Chaoscope's static. The same shape every time."
		)
	end
end

local function hush()
	hushSerial += 1
	local serial = hushSerial
	ReplicatedStorage:SetAttribute("Hush", 1)
	task.delay(between(D.hushSeconds), function()
		if hushSerial == serial then
			ReplicatedStorage:SetAttribute("Hush", 0)
		end
	end)
end

local function mayaBlink()
	local house = MayaService.house()
	if not house then
		return
	end
	local room = if house:GetAttribute("Upstairs") == true then "Upstairs" else "Downstairs"
	if house:GetAttribute(room) ~= true then
		return
	end
	local phase = TimeService.snapshot().phase
	MayaService.setRoom(room, false)
	task.delay(between(D.mayaDarkSeconds), function()
		if TimeService.snapshot().phase == phase then
			MayaService.setRoom(room, true)
		end
	end)
end

local function ghostNeedle(a: Dissonance.Anomaly)
	ghostDone[a.id] = true
	task.delay(between(D.ghostPause), function()
		local m = scope
		if not m or m:GetAttribute("Powered") == true then
			return
		end
		cue("switch", scopePos, 0.5)
		m:SetAttribute("Needle", rng:NextNumber(28, 55))
		task.delay(rng:NextNumber(1.2, 2), function()
			if m:GetAttribute("Powered") ~= true then
				m:SetAttribute("Needle", 0)
			end
		end)
		journal(
			"ghost",
			"Chaoscope",
			"I switched the Chaoscope off. A click, and the needle moved anyway. Then it settled."
		)
	end)
end

-- Caramelo's own mood system (DogService, Logic/DogMind) does the rest: a
-- startle lifts his agitation, so he raises his head (ALERT) or growls low
-- (SUSPICIOUS), then calms down by himself as it fades. Kept below what
-- makes him bark on its own.
local function startleDogs(strength: number)
	for _, m in CollectionService:GetTagged("Dog") do
		if m:IsA("Model") and (m:GetPivot().Position - scopePos).Magnitude <= D.hearRadius then
			m:SetAttribute("StartleStrength", math.clamp(strength, 0, 0.5))
			m:SetAttribute("StartledAt", os.clock())
		end
	end
end

local function play(event: string, a: Dissonance.Anomaly)
	if event == "transmission" then
		transmission(a)
	elseif event == "radio" then
		local radio = CollectionService:GetTagged("CabinRadio")[1]
		cue("radioStatic", if radio and radio:IsA("BasePart") then radio.Position else scopePos, 0.22)
	elseif event == "window" then
		local glass = entryPosition("window")
		if glass then
			cue("windowRattle", glass, 0.25)
		end
	elseif event == "flicker" then
		flickered[a.id] = true
		LightService.flicker("Cabin", 0.35)
	elseif event == "hush" then
		hush()
	elseif event == "maya" then
		mayaBlink()
	elseif event == "dogRouse" or event == "dogWatch" or event == "dogGrowl" then
		-- "relax" needs no code: the startle fades and he settles by himself.
		startleDogs(D.startle[event] or 0.2)
	elseif event == "echo" then
		local seed = rng:NextNumber(1, 9999)
		for _, p in listeners() do
			Net.event("Dissonance"):FireClient(p, "echo", scopePos, seed)
		end
		journal(
			"echo",
			"The Echo",
			"The Chaoscope's speaker played back sounds from the house, out of order and too slow."
		)
	elseif event == "ghostNeedle" then
		ghostNeedle(a)
	end
end

-- API -----------------------------------------------------------------------

function DissonanceEventDirector.setScope(m: Model)
	scope = m
	scopePos = m:GetPivot().Position
end

-- An anomaly beat. atHome: the anomaly is centred near the house.
-- audible: the scope, if it is on, can pick this anomaly up (it is at the
-- house, or the scope listens REGIONAL and it is in range).
function DissonanceEventDirector.beat(a: Dissonance.Anomaly, beat: string, atHome: boolean, audible: boolean)
	local ctx = context(a, atHome, audible)
	if beat == "drop" and ctx.scopeOn and atHome then
		journal(
			"absence",
			"The Absence",
			"The Chaoscope climbed, then fell to zero. Not low: zero. The house went very quiet."
		)
	end
	local event =
		Dissonance.choose(beat, ctx, lastAt, now(), rng:NextNumber(), D.cooldowns, A.ghostNeedleChance)
	if event then
		play(event, a)
	end
end

function DissonanceEventDirector.finish(a: Dissonance.Anomaly)
	flickered[a.id] = nil
	ghostDone[a.id] = nil
end

-- A fresh scope reading (only while it is on), for the journal.
function DissonanceEventDirector.reading(ceu: number, level: string, mode: string, wave: number)
	if ChaosField.levelIndex(LEVELS, level) < ChaosField.levelIndex(LEVELS, "DISTURBANCE") then
		return
	end
	local trace = if wave > 0.5 then "irregular" else "steady"
	journal(
		"reading",
		"Chaoscope",
		string.format(
			"The needle stood at %d CEU on %s, %s, with a %s trace.",
			math.floor(ceu + 0.5),
			mode,
			level,
			trace
		)
	)
end

return DissonanceEventDirector

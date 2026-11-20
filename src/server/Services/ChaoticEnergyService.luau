--!strict
-- Chapter 36: the chaotic energy field and the H-17 Chaoscope.
--
-- Server-authoritative. The field (Logic/ChaosField) ticks once a second on
-- real time, so a TimeScale skip never sprays events. Inputs: rain, night,
-- the collective's alert level, and each Creature-tagged model's FearEnergy
-- and Hunger attributes (missing reads as 0). Anomalies (Logic/Dissonance)
-- start by chance, a little more often on worse nights and in rain, never
-- on day 1, one at a time; their beats go to DissonanceEventDirector.
--
-- Wire rules: clients only see what the scope displays, as attributes on
-- the Chaoscope model: Powered, Mode, Sensitivity, Needle (noisy CEU),
-- Jitter (noise sigma), Wave (trace irregularity 0..1), Level, Emit (EMIT
-- lamp state). True energy, anomaly families and stages, and every hidden
-- position stay on the server. Nothing is measured while the scope is off.
--
-- Creature hook (read-only for creature code): workspace attributes
-- ChaosSignal (0..1, strength of the last scan pulse; 0 again after
-- Scan.pulseHold seconds), ChaosSignalPosition (Vector3, the scope) and
-- ChaosSignalAt (server time of the pulse). Nothing reads them yet.
--
-- Studio: in Server view, set the ReplicatedStorage attribute
-- DissonanceForce to "Arrival", "Echo" or "Absence" to seed one anomaly at
-- the house; it then runs through the normal machinery.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChaosField = require(ReplicatedStorage.Shared.Logic.ChaosField)
local Dissonance = require(ReplicatedStorage.Shared.Logic.Dissonance)
local DissonanceConfig = require(ReplicatedStorage.Shared.Config.DissonanceConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Chaoscope = require(script.Parent.Parent.World.Chaoscope)
local CollectiveService = require(script.Parent.CollectiveService)
local DissonanceEventDirector = require(script.Parent.DissonanceEventDirector)
local PlayerService = require(script.Parent.PlayerService)
local TimeService = require(script.Parent.TimeService)
local WeatherService = require(script.Parent.WeatherService)

local ChaoticEnergyService = {}

local F = DissonanceConfig.Field
local A = DissonanceConfig.Anomaly
local S = DissonanceConfig.Scan
local D = DissonanceConfig.Director
local SENS = DissonanceConfig.Sensitivity
local MODES = DissonanceConfig.Modes
local LEVELS = DissonanceConfig.Levels
local RULES = DissonanceConfig.LevelRules

local rng = Random.new()
local field = ChaosField.new(F)
local anomalies: { Dissonance.Anomaly } = {}
local forced: { [number]: boolean } = {}
local homePeak: { [number]: number } = {} -- anomaly id -> highest home level index announced
local emitter = Dissonance.newEmitter()
local scope: Model? = nil
local scopePos = Vector3.zero
local powerPrompt: ProximityPrompt? = nil
local nextId = 0
local quietUntil = 0
local sinceRead = math.huge
local shownLevel: string? = nil
local smoothed: number? = nil -- the damped needle; nil starts fresh

local function gauss(): number
	local u1 = math.max(rng:NextNumber(), 1e-9)
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * rng:NextNumber())
end

local function round(v: number, step: number): number
	return math.floor(v / step + 0.5) * step
end

local function scopeState(): (boolean, string, number)
	local m = scope
	if not m then
		return false, "PASSIVE", SENS.default
	end
	local mode = m:GetAttribute("Mode")
	local sens = m:GetAttribute("Sensitivity")
	return m:GetAttribute("Powered") == true,
		if type(mode) == "string" and MODES[mode] then mode else "PASSIVE",
		if type(sens) == "number" then sens else SENS.default
end

local function creatures(): { ChaosField.Creature }
	local list: { ChaosField.Creature } = {}
	for _, m in CollectionService:GetTagged("Creature") do
		if m:IsA("Model") then
			local p = m:GetPivot().Position
			local e = m:GetAttribute("FearEnergy")
			local h = m:GetAttribute("Hunger")
			table.insert(list, {
				x = p.X,
				z = p.Z,
				energy = if type(e) == "number" then e else 0,
				hunger = if type(h) == "number" then h else 0,
			})
		end
	end
	return list
end

local function collectiveLevel(): number
	local level = CollectiveService.highestLevel()
	-- DISPERSING (6) is the network letting go: barely there.
	return if level >= 6 then 1 else level
end

-- Is this anomaly centred close enough to the house to touch it?
local function atHome(a: Dissonance.Anomaly): boolean
	local home = ChaosField.sectorAt(field, scopePos.X, scopePos.Z)
	local d = math.sqrt((a.x - home.x) ^ 2 + (a.z - home.z) ^ 2)
	return a.base * ChaosField.falloff(d, F.anomalyFalloff) >= D.homeShare
end

local function muted(a: Dissonance.Anomaly): boolean
	local scale = (ReplicatedStorage:GetAttribute("TimeScale") :: number?) or 1
	return scale > 1 or (TimeService.snapshot().day < A.firstDay and not forced[a.id])
end

local function beat(a: Dissonance.Anomaly, name: string)
	if muted(a) then
		return
	end
	local home = atHome(a)
	local _, modeName = scopeState()
	local d = math.sqrt((a.x - scopePos.X) ^ 2 + (a.z - scopePos.Z) ^ 2)
	local audible = home or (modeName == "REGIONAL" and d <= MODES.REGIONAL.range)
	DissonanceEventDirector.beat(a, name, home, audible)
end

local function pickFamily(): string
	local total = 0
	for _, w in A.families do
		total += w
	end
	local pick = rng:NextNumber() * total
	for _, name in Dissonance.Families do
		local w = A.families[name] or 0
		if pick < w then
			return name
		end
		pick -= w
	end
	return "Arrival"
end

local function startAnomaly(family: string, home: boolean, isForced: boolean)
	nextId += 1
	local s = if home
		then ChaosField.sectorAt(field, scopePos.X, scopePos.Z)
		else field.list[rng:NextInteger(1, #field.list)]
	local rolls = { rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber() }
	local a = Dissonance.newAnomaly(nextId, family, s.x, s.z, A, rolls)
	if isForced then
		forced[a.id] = true
	end
	table.insert(anomalies, a)
end

local function maybeStart(dt: number)
	if #anomalies > 0 or os.clock() < quietUntil then
		return
	end
	if TimeService.snapshot().day < A.firstDay then
		return
	end
	local scale = (ReplicatedStorage:GetAttribute("TimeScale") :: number?) or 1
	if scale > 1 then
		return
	end
	local nightType = (ReplicatedStorage:GetAttribute("NightType") :: string?) or "Day"
	local perMinute = A.chancePerMinute[nightType] or A.chancePerMinute.Day
	local weather = WeatherService.label()
	if weather == "Rain" or weather == "Storm" then
		perMinute += A.rainBonus
	end
	if rng:NextNumber() < perMinute * dt / 60 then
		startAnomaly(pickFamily(), rng:NextNumber() < A.nearHome, false)
	end
end

local function publishOff()
	local m = scope
	if not m then
		return
	end
	m:SetAttribute("Needle", 0)
	m:SetAttribute("Jitter", 0)
	m:SetAttribute("Wave", 0)
	m:SetAttribute("Level", "")
	m:SetAttribute("Emit", "off")
	shownLevel = nil
	smoothed = nil
end

local function setPowered(on: boolean)
	local m = scope
	if not m or (m:GetAttribute("Powered") == true) == on then
		return
	end
	m:SetAttribute("Powered", on)
	Net.event("SoundCue"):FireAllClients("switch", scopePos, 0.45)
	local prompt = powerPrompt
	if prompt then
		prompt.ActionText = if on then "Switch off" else "Switch on"
	end
	if on then
		sinceRead = math.huge
	else
		publishOff()
		for _, a in anomalies do
			if a.peaked and a.stage ~= "DONE" then
				beat(a, "scopeOff")
			end
		end
	end
end

local function tick(dt: number)
	local powered, modeName, sens = scopeState()
	local mode = MODES[modeName]

	-- The field.
	local sources = {}
	for _, a in anomalies do
		table.insert(sources, Dissonance.source(a))
	end
	ChaosField.step(field, dt, {
		rain = WeatherService.rainIntensity(),
		night = TimeService.nightFactor(),
		collective = collectiveLevel(),
		creatures = creatures(),
		sources = sources,
	}, gauss)

	-- Scan signature: the risk of measuring hard.
	local signature = Dissonance.signature(powered, mode.signature, sens, SENS.min, SENS.max)
	if Dissonance.stepEmitter(emitter, dt, signature, S) then
		workspace:SetAttribute("ChaosSignal", round(emitter.signal, 0.01))
		workspace:SetAttribute("ChaosSignalPosition", scopePos)
		workspace:SetAttribute("ChaosSignalAt", workspace:GetServerTimeNow())
		Net.event("SoundCue"):FireAllClients("radioStatic", scopePos, 0.4)
	elseif emitter.signal == 0 and workspace:GetAttribute("ChaosSignal") ~= 0 then
		workspace:SetAttribute("ChaosSignal", 0)
	end

	-- Anomalies and their beats.
	local home = ChaosField.sectorAt(field, scopePos.X, scopePos.Z)
	local homeLevel = ChaosField.levelIndex(LEVELS, ChaosField.level(LEVELS, RULES, home.current, 0, nil))
	for i = #anomalies, 1, -1 do
		local a = anomalies[i]
		local d = math.sqrt((a.x - scopePos.X) ^ 2 + (a.z - scopePos.Z) ^ 2)
		local reach = ChaosField.falloff(d, math.max(mode.range, F.anomalyFalloff))
		local beats = Dissonance.step(a, dt, signature * reach, A)
		if atHome(a) and a.stage ~= "DONE" and homeLevel > (homePeak[a.id] or 1) then
			homePeak[a.id] = homeLevel
			local name = LEVELS[homeLevel].name
			table.insert(beats, if homeLevel >= 4 then "level_HIGH" else "level_" .. name)
		end
		for _, b in beats do
			beat(a, b)
		end
		if a.stage == "DONE" then
			table.remove(anomalies, i)
			DissonanceEventDirector.finish(a)
			forced[a.id] = nil
			homePeak[a.id] = nil
			quietUntil = os.clock() + A.gapAfter
		end
	end
	maybeStart(dt)

	-- What the needle shows.
	local m = scope
	if not m or not powered then
		return
	end
	m:SetAttribute("Emit", Dissonance.emitterLamp(emitter, signature, S))
	sinceRead += dt
	if sinceRead < mode.update then
		return
	end
	sinceRead = 0
	local r = ChaosField.read(field, scopePos.X, scopePos.Z, mode, sens, SENS.min, SENS.max, gauss())
	local damped = ChaosField.blend(smoothed, r.ceu, mode.blend)
	smoothed = damped
	local shown = ChaosField.quantize(damped, mode.quantize)
	shownLevel = ChaosField.level(LEVELS, RULES, shown, r.uncertainty, shownLevel)
	m:SetAttribute("Needle", round(shown, 0.1))
	m:SetAttribute("Jitter", round(r.uncertainty, 0.1))
	m:SetAttribute("Wave", round(r.irregularity, 0.01))
	m:SetAttribute("Level", shownLevel)
	DissonanceEventDirector.reading(shown, shownLevel :: string, modeName, r.irregularity)
end

local function onRequest(player: Player, action: any, value: any)
	if type(action) ~= "string" or not Net.allow(player, "chaoscope", 4) then
		return
	end
	local m = scope
	local root = PlayerService.root(player)
	if not m or not root or (root.Position - scopePos).Magnitude > D.controlRadius then
		return
	end
	if action == "power" then
		setPowered(m:GetAttribute("Powered") ~= true)
	elseif action == "mode" then
		if type(value) == "string" and MODES[value] and m:GetAttribute("Mode") ~= value then
			m:SetAttribute("Mode", value)
			sinceRead = math.huge
			Net.event("SoundCue"):FireAllClients("switch", scopePos, 0.3)
		end
	elseif action == "sensitivity" then
		if type(value) == "number" and value == value then
			local s = math.clamp(math.floor(value + 0.5), SENS.min, SENS.max)
			if m:GetAttribute("Sensitivity") ~= s then
				m:SetAttribute("Sensitivity", s)
				Net.event("SoundCue"):FireAllClients("latch", scopePos, 0.2)
			end
		end
	end
end

function ChaoticEnergyService.scope(): Model?
	return scope
end

function ChaoticEnergyService.start()
	workspace:SetAttribute("ChaosSignal", 0)
	Net.event("Chaoscope").OnServerEvent:Connect(onRequest)
	-- The scope stands on the cabin table, next to the radio.
	local tableTop: BasePart? = nil
	for _, s in CollectionService:GetTagged("Shelter") do
		if s:GetAttribute("ShelterId") == "Cabin" then
			local t = s:FindFirstChild("TableTop", true)
			if t and t:IsA("BasePart") then
				tableTop = t
			end
		end
	end
	if tableTop then
		local m = Chaoscope.build(tableTop, Vector3.new(0.7, 0, 0.75))
		m:SetAttribute("Powered", true)
		m:SetAttribute("Mode", "PASSIVE")
		m:SetAttribute("Sensitivity", SENS.default)
		scope = m
		scopePos = m:GetPivot().Position
		DissonanceEventDirector.setScope(m)
		local prompt = m:FindFirstChild("ScopePowerPrompt", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			powerPrompt = prompt
			prompt.ActionText = "Switch off"
			prompt.Triggered:Connect(function(player)
				onRequest(player, "power", nil)
			end)
		end
	else
		warn("[Dissonance] no cabin TableTop: the Chaoscope was not placed")
	end
	if RunService:IsStudio() then
		ReplicatedStorage:GetAttributeChangedSignal("DissonanceForce"):Connect(function()
			local v = ReplicatedStorage:GetAttribute("DissonanceForce")
			if type(v) == "string" and A.strength[v] then
				for _, old in anomalies do
					DissonanceEventDirector.finish(old)
				end
				anomalies = {}
				quietUntil = 0
				startAnomaly(v, true, true)
				print("[Dissonance] seeded " .. v .. " at the house")
			end
			if v ~= nil then
				ReplicatedStorage:SetAttribute("DissonanceForce", nil)
			end
		end)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < F.tickSeconds then
			return
		end
		local step = math.min(acc, 3)
		acc = 0
		local ok, err = pcall(tick :: any, step)
		if not ok then
			warn("[Dissonance] " .. tostring(err))
		end
	end)
end

return ChaoticEnergyService

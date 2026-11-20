--!strict
-- Server-authoritative weather. Rain intensity is continuous (0 clear ..
-- 5 violent storm) and drifts toward a per-phase target with slow noise, so
-- showers swell and ease instead of switching. Most rain is calm; storms are
-- rare. Wind gusts are discrete server events that can rattle, force open
-- or damage poorly secured windows. Thunder comes at irregular intervals.
--
-- Published on ReplicatedStorage: Weather, RainIntensity, FogAmount,
-- WindStrength, WindDirection.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local TimeService = require(script.Parent.TimeService)
local NoiseService = require(script.Parent.NoiseService)
local LightService = require(script.Parent.LightService)

local WeatherService = {}

type Target = { label: string, rain: number, fog: number, wind: number }

local rng = Random.new(4242)
local rain = 0
local fog = 0.1
local wind = 0.15
local target: Target = { label = "Clear", rain = 0, fog = 0.1, wind = 0.15 }
local windDir = Vector3.new(0.6, 0, -0.8).Unit
local nextGust = 20
local nextThunder = 40
local t = 0
local gustListeners: { (number, Vector3) -> () } = {}

local function targetFor(label: string): Target
	if label == "Rain" then
		-- Calm rain: drizzle to steady rainfall.
		return { label = "Rain", rain = rng:NextNumber(1, 2.4), fog = 0.25, wind = rng:NextNumber(0.15, 0.35) }
	elseif label == "Storm" then
		return {
			label = "Storm",
			rain = rng:NextNumber(3.6, 4.8),
			fog = 0.4,
			wind = rng:NextNumber(0.6, 0.95),
		}
	elseif label == "Fog" then
		return { label = "Fog", rain = 0, fog = rng:NextNumber(0.55, 0.85), wind = 0.08 }
	end
	return { label = "Clear", rain = 0, fog = 0.08, wind = rng:NextNumber(0.1, 0.25) }
end

local function rollLabel(): string
	local w = GameConfig.Weather.Weights
	local total = w.Clear + w.Fog + w.Rain + w.Storm
	local pick = rng:NextNumber() * total
	for _, name in { "Clear", "Fog", "Rain", "Storm" } do
		local weight = (w :: any)[name] :: number
		if pick < weight then
			return name
		end
		pick -= weight
	end
	return "Clear"
end

local function chooseFor(day: number, phase: string)
	local scripted = GameConfig.Weather.Scripted[day]
	local label = if scripted and scripted[phase] then scripted[phase] else nil
	if not label then
		-- Keep weather for a while: 55% chance to persist across a phase change.
		label = if rng:NextNumber() < 0.55 then target.label else rollLabel()
	end
	target = targetFor(label :: string)
	windDir = (windDir + Vector3.new(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4))).Unit
end

function WeatherService.label(): string
	if rain >= 3.4 then
		return "Storm"
	elseif rain >= 0.6 then
		return "Rain"
	elseif fog >= 0.45 then
		return "Fog"
	end
	return "Clear"
end

function WeatherService.rainIntensity(): number
	return rain
end

function WeatherService.windStrength(): number
	return wind
end

function WeatherService.windDirection(): Vector3
	return windDir
end

-- 0..1 fraction of clear-weather sight distance.
function WeatherService.visibility(): number
	return math.clamp(1 - fog * 0.5 - (rain / 5) * 0.45, 0.25, 1)
end

function WeatherService.onGust(fn: (number, Vector3) -> ())
	table.insert(gustListeners, fn)
end

-- Debug and story hooks.
function WeatherService.force(label: string)
	target = targetFor(label)
end

local function gust(strength: number)
	ReplicatedStorage:SetAttribute("Gust", strength)
	for _, fn in gustListeners do
		task.spawn(fn, strength, windDir)
	end
	-- Windows facing the wind feel the pressure.
	for _, w in CollectionService:GetTagged("Window") do
		if w:IsA("Model") and w.PrimaryPart then
			local glass = w.PrimaryPart :: BasePart
			-- Window glass looks outward (see World/Cabin buildWindow).
			local outward = glass.CFrame.LookVector
			local exposure = math.max(outward:Dot(-windDir), 0) * 0.7 + 0.3
			local pressure = strength * exposure
			w:SetAttribute("LastGust", pressure)
			if pressure > 0.3 then
				Net.event("SoundCue")
					:FireAllClients("windowRattle", glass.Position, math.clamp(pressure, 0.3, 1))
			end
			local closed = w:GetAttribute("Open") ~= true
			local shuttered = w:GetAttribute("Shuttered") == true
			local latched = w:GetAttribute("Latched") == true and w:GetAttribute("LatchBroken") ~= true
			if closed and not shuttered and w:GetAttribute("Installed") == true then
				if not latched and pressure > 0.5 then
					w:SetAttribute("Open", true)
					w:SetAttribute("ForcedOpen", true)
					NoiseService.emit(glass.Position, "doorSlam")
					Net.event("SoundCue"):FireAllClients("windowBang", glass.Position, 1)
					if w:GetAttribute("Shelter") then
						Net.event("Notify"):FireAllClients("A gust forced a window open.", "warning")
						LightService.flicker(w:GetAttribute("Shelter") :: string, 0.8)
					end
				elseif pressure > 0.85 then
					local h = (w:GetAttribute("Health") :: number?) or 100
					if h < 60 then
						w:SetAttribute("Health", math.max(h - 15, 0))
						Net.event("SoundCue"):FireAllClients("glassCrack", glass.Position, 0.8)
					end
				end
			end
		end
	end
end

local function publish()
	ReplicatedStorage:SetAttribute("Weather", WeatherService.label())
	ReplicatedStorage:SetAttribute("RainIntensity", rain)
	ReplicatedStorage:SetAttribute("FogAmount", fog)
	ReplicatedStorage:SetAttribute("WindStrength", wind)
	ReplicatedStorage:SetAttribute("WindDirection", windDir)
	NoiseService.setWeather(WeatherService.label())
end

function WeatherService.start()
	local snap = TimeService.snapshot()
	chooseFor(snap.day, snap.phase)
	rain, fog, wind = target.rain, target.fog, target.wind
	publish()
	TimeService.onPhaseChanged(function(s)
		chooseFor(s.day, s.phase)
	end)
	local sincePublish = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local scale = (ReplicatedStorage:GetAttribute("TimeScale") :: number?) or 1
		local sdt = dt * math.clamp(scale, 0, 200)
		t += dt
		-- Drift toward target; slow noise makes downpours swell and ease.
		local wobble = if target.rain > 0 then math.noise(t / 40, 3.3) * 0.9 else 0
		local goal = math.clamp(target.rain + wobble, 0, 5)
		rain += (goal - rain) * math.min(sdt / 60, 1)
		fog += (target.fog - fog) * math.min(sdt / 50, 1)
		local windGoal = math.clamp(target.wind + math.noise(t / 25, 7.1) * 0.15, 0, 1)
		wind += (windGoal - wind) * math.min(sdt / 30, 1)

		nextGust -= dt
		if nextGust <= 0 then
			if wind > 0.35 then
				gust(math.clamp(wind + rng:NextNumber(-0.1, 0.35), 0, 1.2))
			end
			nextGust = rng:NextNumber(8, 30) / math.max(wind, 0.2)
		end
		nextThunder -= dt
		if nextThunder <= 0 then
			if rain >= 3 then
				local a = rng:NextNumber(0, math.pi * 2)
				local r = rng:NextNumber(120, 420)
				local pos = Vector3.new(math.cos(a) * r, 140, math.sin(a) * r)
				Net.event("Lightning"):FireAllClients(pos)
				ReplicatedStorage:SetAttribute("LightningAt", workspace:GetServerTimeNow())
			end
			-- Irregular: clustered bursts and long pauses.
			nextThunder = if rng:NextNumber() < 0.3 then rng:NextNumber(4, 10) else rng:NextNumber(25, 80)
		end
		sincePublish += dt
		if sincePublish > 0.5 then
			sincePublish = 0
			publish()
		end
	end)
end

return WeatherService

--!strict
-- Presents the server clock and weather as lighting. Smoothly interpolates
-- keyframes; never sets anything gameplay-relevant.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local TimeCycle = require(ReplicatedStorage.Shared.Logic.TimeCycle)

local AIR = WorldConfig.Atmosphere

local LightingController = {}

local function ensure<T>(className: string, name: string, parent: Instance): T
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing :: any
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst :: any
end

local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
end

function LightingController.start()
	local atmosphere: Atmosphere = ensure("Atmosphere", "StillAtmosphere", Lighting)
	local cc: ColorCorrectionEffect = ensure("ColorCorrectionEffect", "StillGrade", Lighting)
	local bloom: BloomEffect = ensure("BloomEffect", "StillBloom", Lighting)
	local rays: SunRaysEffect = ensure("SunRaysEffect", "StillRays", Lighting)
	local sky: Sky = ensure("Sky", "StillSky", Lighting)
	sky.StarCount = 3000
	sky.MoonAngularSize = 9
	bloom.Intensity = 0.6
	bloom.Size = 26
	bloom.Threshold = 1.6
	rays.Intensity = 0.06
	rays.Spread = 0.6
	atmosphere.Offset = AIR.Offset
	atmosphere.Glare = AIR.Glare
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ShadowSoftness = 0.25
	Lighting.GeographicLatitude = 48

	local frames = GameConfig.Time.Lighting :: { TimeCycle.Keyframe }
	local shownClock = (ReplicatedStorage:GetAttribute("ClockTime") :: number?) or 9
	local fogBlend = 0

	RunService.RenderStepped:Connect(function(dt: number)
		local target = (ReplicatedStorage:GetAttribute("ClockTime") :: number?) or shownClock
		-- Interpolate across the 24h wrap so the sun never jumps.
		local diff = (target - shownClock + 12) % 24 - 12
		if math.abs(diff) > 3 then
			shownClock = target
		else
			shownClock = (shownClock + diff * math.min(dt * 4, 1)) % 24
		end
		Lighting.ClockTime = shownClock

		local v = TimeCycle.sampleKeyframes(frames, shownClock)
		local weatherFog = (ReplicatedStorage:GetAttribute("FogAmount") :: number?) or 0
		local rain = (ReplicatedStorage:GetAttribute("RainIntensity") :: number?) or 0
		fogBlend += (math.max(weatherFog, rain / 5) - fogBlend) * math.min(dt * 0.5, 1)
		local gloom = 1 - fogBlend * 0.35

		Lighting.Brightness = v[1] * gloom
		Lighting.Ambient = c3(v[2], v[3], v[4])
		Lighting.OutdoorAmbient = c3(v[5] * gloom, v[6] * gloom, v[7] * gloom)
		atmosphere.Density = math.clamp(v[8] + AIR.DensityAdd + fogBlend * 0.32, 0, 0.85)
		atmosphere.Haze = v[9] + AIR.HazeAdd + fogBlend * 1.5
		atmosphere.Color = c3(
			(v[2] * 1.6 + 20) * AIR.Tint[1],
			(v[3] * 1.6 + 20) * AIR.Tint[2],
			(v[4] * 1.6 + 26) * AIR.Tint[3]
		)
		atmosphere.Decay = c3(v[5] * 0.8, v[6] * 0.8, v[7] * 0.9)
		Lighting.ColorShift_Top = c3(v[10], v[11], v[12])
		Lighting.ExposureCompensation = v[13]
		cc.Saturation = -0.12 - fogBlend * 0.15
		cc.Contrast = 0.06
		cc.TintColor = Color3.new(1, 0.97, 0.94)
	end)
end

return LightingController

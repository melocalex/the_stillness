--!strict
-- Rain and lightning presentation around the camera only (no global
-- particles). Rain streaks are squashed default particles driven by the
-- server's RainIntensity and wind. Indoors the rain stops falling on you;
-- lightning briefly lights the world (and whatever is standing in it).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)

local WeatherController = {}

local function cameraSheltered(pos: Vector3): boolean
	for _, v in CollectionService:GetTagged("ShelterVolume") do
		if v:IsA("BasePart") then
			local p = v.CFrame:PointToObjectSpace(pos)
			local h = v.Size / 2
			if math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y + 6 and math.abs(p.Z) <= h.Z then
				return true
			end
		end
	end
	return false
end
WeatherController.cameraSheltered = cameraSheltered

function WeatherController.start()
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "RainEmitter"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(90, 1, 90)
	emitterPart.Parent = workspace.CurrentCamera

	local rain = Instance.new("ParticleEmitter")
	rain.Name = "Rain"
	rain.Rate = 0
	rain.Lifetime = NumberRange.new(0.9, 1.2)
	rain.Speed = NumberRange.new(70, 90)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Size = NumberSequence.new(0.08)
	rain.Squash = NumberSequence.new(-3.2)
	rain.Transparency = NumberSequence.new(0.55)
	rain.Color = ColorSequence.new(Color3.fromRGB(190, 200, 210))
	rain.LightEmission = 0.15
	rain.LightInfluence = 0.9
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.Parent = emitterPart

	local flash = Instance.new("ColorCorrectionEffect")
	flash.Name = "LightningFlash"
	flash.Parent = Lighting

	RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		local pos = cam.CFrame.Position
		local intensity = (ReplicatedStorage:GetAttribute("RainIntensity") :: number?) or 0
		local windStrength = (ReplicatedStorage:GetAttribute("WindStrength") :: number?) or 0
		local windDir = ReplicatedStorage:GetAttribute("WindDirection")
		local dir = if typeof(windDir) == "Vector3" then windDir else Vector3.new(1, 0, 0)
		emitterPart.CFrame = CFrame.new(pos + Vector3.new(0, 40, 0))
		local inside = cameraSheltered(pos)
		local rate = if intensity < 0.15 or inside then 0 else math.clamp(intensity / 5, 0, 1) * 1400
		rain.Rate = rate
		rain.Acceleration = dir * windStrength * 60
		rain.Transparency = NumberSequence.new(0.7 - math.clamp(intensity / 5, 0, 1) * 0.25)
	end)

	Net.event("Lightning").OnClientEvent:Connect(function(position: any)
		if typeof(position) ~= "Vector3" then
			return
		end
		task.spawn(function()
			for _, strength in { 0.9, 0.3, 0.7 } do
				flash.Brightness = strength
				flash.TintColor = Color3.fromRGB(220, 230, 255)
				task.wait(0.07)
				TweenService:Create(flash, TweenInfo.new(0.12), { Brightness = 0 }):Play()
				task.wait(0.09 + math.random() * 0.12)
			end
			flash.TintColor = Color3.new(1, 1, 1)
		end)
		local d = (workspace.CurrentCamera.CFrame.Position - position).Magnitude
		task.delay(math.clamp(d / 350, 0.3, 4), function()
			local AudioController = require(script.Parent.AudioController)
			AudioController.cue(if d < 200 then "thunderClose" else "thunder", nil, 1)
		end)
	end)
end

return WeatherController

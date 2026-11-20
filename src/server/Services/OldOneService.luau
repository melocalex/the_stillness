--!strict
-- The Old One: in this prototype, only a rare, vast silhouette on the north
-- ridge, a low sound, and its effect on the others (Watchers withdraw).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CreatureConfig = require(ReplicatedStorage.Shared.Config.CreatureConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local CreatureService = require(script.Parent.CreatureService)
local TimeService = require(script.Parent.TimeService)

local OldOneService = {}

local model: Model? = nil
local rng = Random.new(666)
local visibleAt: Vector3? = nil

function OldOneService.visiblePosition(): Vector3?
	return visibleAt
end

local function fade(m: Model, to: number, seconds: number)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			TweenService:Create(d, TweenInfo.new(seconds), { Transparency = to }):Play()
		end
	end
end

local function appear()
	local m = model
	if not m then
		return
	end
	local spot = WorldConfig.OldOneSpots[rng:NextInteger(1, #WorldConfig.OldOneSpots)]
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { m }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(Vector3.new(spot.x, 400, spot.z), Vector3.new(0, -600, 0), params)
	local ground = if hit then hit.Position else Vector3.new(spot.x, 60, spot.z)
	-- Pivot is the body centre (40 studs above the feet in the rig).
	m:PivotTo(CFrame.lookAt(ground + Vector3.new(0, 40, 0), Vector3.new(0, ground.Y + 40, 0)))
	visibleAt = ground + Vector3.new(0, 40, 0)
	ReplicatedStorage:SetAttribute("OldOneVisible", true)
	fade(m, 0.08, 8)
	Net.event("SoundCue"):FireAllClients("oldOneCall", nil, 0.8)
	CreatureService.fleeFrom(ground, CreatureConfig.OldOne.WatcherFleeRadius, "Watcher")
	task.delay(CreatureConfig.OldOne.VisibleSeconds, function()
		fade(m, 1, 10)
		task.wait(10)
		visibleAt = nil
		ReplicatedStorage:SetAttribute("OldOneVisible", false)
		m:PivotTo(CFrame.new(0, -200, 0))
	end)
end

function OldOneService.start()
	for _, m in CollectionService:GetTagged("OldOne") do
		if m:IsA("Model") then
			model = m
		end
	end
	ReplicatedStorage:SetAttribute("OldOneVisible", false)
	TimeService.onPhaseChanged(function(s)
		if s.phase ~= "Night" or s.day < CreatureConfig.OldOne.MinDay then
			return
		end
		local nightType = (ReplicatedStorage:GetAttribute("NightType") :: string?) or "Peaceful"
		local chance = CreatureConfig.OldOne.ChancePerNight[nightType] or 0
		if rng:NextNumber() < chance then
			local delaySeconds = GameConfig.Time.Durations.Night * rng:NextNumber(0.2, 0.7)
			local target = TimeService.elapsed() + delaySeconds
			task.spawn(function()
				while TimeService.elapsed() < target do
					task.wait(1)
				end
				if TimeService.snapshot().phase == "Night" then
					appear()
				end
			end)
		end
	end)
end

return OldOneService

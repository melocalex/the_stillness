--!strict
-- Authoritative clock. Publishes the snapshot as attributes on
-- ReplicatedStorage (Day, Phase, PhaseProgress, ClockTime, NightFactor) and
-- notifies server systems on phase and day changes.
-- Set ReplicatedStorage attribute "TimeScale" (e.g. 20) to fast-forward while testing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local TimeCycle = require(ReplicatedStorage.Shared.Logic.TimeCycle)

local TimeService = {}

type Listener = (TimeCycle.Snapshot, TimeCycle.Snapshot?) -> ()

local elapsed = GameConfig.Time.StartOffset
local current: TimeCycle.Snapshot = TimeCycle.snapshot(GameConfig.Time.Durations, elapsed)
local phaseListeners: { Listener } = {}
local tickListeners: { (TimeCycle.Snapshot, number) -> () } = {}

function TimeService.snapshot(): TimeCycle.Snapshot
	return current
end

function TimeService.elapsed(): number
	return elapsed
end

function TimeService.nightFactor(): number
	return TimeCycle.nightFactor(current)
end

function TimeService.isNight(): boolean
	return current.phase == "Night" or current.phase == "Dusk"
end

function TimeService.onPhaseChanged(fn: Listener)
	table.insert(phaseListeners, fn)
end

-- Called every heartbeat with (snapshot, scaled dt).
function TimeService.onTick(fn: (TimeCycle.Snapshot, number) -> ())
	table.insert(tickListeners, fn)
end

-- Jump forward (sleeping, debug). Never backwards.
function TimeService.skipTo(target: number)
	if target > elapsed then
		elapsed = target
	end
end

function TimeService.skipToPhase(phase: TimeCycle.Phase)
	local day = current.day
	local start = TimeCycle.phaseStart(GameConfig.Time.Durations, day, phase)
	if start <= elapsed then
		start = TimeCycle.phaseStart(GameConfig.Time.Durations, day + 1, phase)
	end
	TimeService.skipTo(start)
end

local function publish(s: TimeCycle.Snapshot)
	ReplicatedStorage:SetAttribute("Day", s.day)
	ReplicatedStorage:SetAttribute("Phase", s.phase)
	ReplicatedStorage:SetAttribute("PhaseProgress", s.phaseProgress)
	ReplicatedStorage:SetAttribute("ClockTime", s.clockTime)
	ReplicatedStorage:SetAttribute("NightFactor", TimeCycle.nightFactor(s))
	ReplicatedStorage:SetAttribute("Elapsed", elapsed)
end

function TimeService.start()
	if ReplicatedStorage:GetAttribute("TimeScale") == nil then
		ReplicatedStorage:SetAttribute("TimeScale", GameConfig.Time.DefaultScale)
	end
	publish(current)
	local sincePublish = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local scale = ReplicatedStorage:GetAttribute("TimeScale")
		local s = if type(scale) == "number" then math.clamp(scale, 0, 200) else 1
		local scaled = dt * s
		elapsed += scaled
		local before = current
		current = TimeCycle.snapshot(GameConfig.Time.Durations, elapsed)
		if current.phase ~= before.phase or current.day ~= before.day then
			publish(current)
			for _, fn in phaseListeners do
				task.spawn(fn, current, before)
			end
		end
		for _, fn in tickListeners do
			fn(current, scaled)
		end
		sincePublish += dt
		if sincePublish >= GameConfig.Time.PublishInterval then
			sincePublish = 0
			publish(current)
		end
	end)
end

return TimeService

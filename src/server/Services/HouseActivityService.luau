--!strict
-- The house across the lake: its nightly routine, its slow mystery, and on
-- bad nights the attack the player can watch from home. Low-cost by design:
-- silhouettes are tweened parts, not AI. State lives on the server so every
-- observer sees the same events; the Broken window persists.
--
-- Recent events are kept for the observation journal.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Mystery = require(ReplicatedStorage.Shared.Logic.Mystery)
local Net = require(ReplicatedStorage.Shared.Net)
local TimeService = require(script.Parent.TimeService)

local HouseActivityService = {}

export type HouseEvent = { id: string, action: string, note: string?, time: number, position: Vector3 }

local GLOW = Color3.fromRGB(255, 190, 120)
local DARK = Color3.fromRGB(26, 30, 34)

local house: Model? = nil
local recent: { HouseEvent } = {}
local lastFraction = 0
local shapes: { Model } = {}
local rng = Random.new(5150)

local function now(): number
	return os.clock()
end

function HouseActivityService.house(): Model?
	return house
end

function HouseActivityService.recentEvents(): { HouseEvent }
	return recent
end

-- Other watched houses: simple, believable nightly light routines.
type RoutineEvent = { house: Model, room: string, at: number, on: boolean }
local others: { Model } = {}
local routine: { RoutineEvent } = {}

local function setRoomIn(h: Model, room: string, on: boolean)
	h:SetAttribute(room, on)
	for _, d in h:GetDescendants() do
		if d:GetAttribute("Room") == room then
			if d:IsA("BasePart") and CollectionService:HasTag(d, "HousePane") then
				if d:GetAttribute("Broken") ~= true then
					d.Material = if on then Enum.Material.Neon else Enum.Material.Glass
					d.Color = if on then GLOW else DARK
					d.Transparency = if on then 0.25 else 0.15
				end
			elseif d:IsA("BasePart") then
				local l = d:FindFirstChildWhichIsA("PointLight")
				if l then
					l.Enabled = on
				end
			end
		end
	end
end

-- MayaService lights her own house with the same pane/bulb rules.
HouseActivityService.setRoomIn = setRoomIn

local function setRoom(room: string, on: boolean)
	local h = house
	if h then
		setRoomIn(h, room, on)
	end
end

local function roomsOf(h: Model): { string }
	local seen: { [string]: boolean } = {}
	local out = {}
	for _, d in h:GetDescendants() do
		local r = d:GetAttribute("Room")
		if type(r) == "string" and not seen[r] then
			seen[r] = true
			table.insert(out, r)
		end
	end
	return out
end

-- On bad nights the neighbors go dark early: a warning the player can see.
local function scheduleOthers(nightType: string)
	table.clear(routine)
	local dangerous = nightType == "Bad" or nightType == "Black"
	for _, h in others do
		if rng:NextNumber() < 0.8 then
			for _, room in roomsOf(h) do
				local onAt = rng:NextNumber(0, 0.25)
				local offAt = if dangerous then rng:NextNumber(0.12, 0.3) else rng:NextNumber(0.5, 0.97)
				table.insert(routine, { house = h, room = room, at = onAt, on = true })
				table.insert(
					routine,
					{ house = h, room = room, at = math.max(offAt, onAt + 0.05), on = false }
				)
			end
		end
	end
end

local function figure(): Model?
	local h = house
	local f = h and h:FindFirstChild("Figure")
	return if f and f:IsA("Model") then f else nil
end

local function showFigure(f: Model, visible: boolean)
	for _, d in f:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = if visible then 0 else 1
		end
	end
end

local function tweenPivot(m: Model, to: CFrame, seconds: number)
	local v = Instance.new("CFrameValue")
	v.Value = m:GetPivot()
	v.Changed:Connect(function(cf)
		m:PivotTo(cf)
	end)
	local t = TweenService:Create(v, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Value = to })
	t.Completed:Connect(function()
		v:Destroy()
	end)
	t:Play()
end

local function shape(pos: Vector3): Model
	local m = Instance.new("Model")
	m.Name = "DistantShape"
	local body = Instance.new("Part")
	body.Size = Vector3.new(1.4, 7, 1)
	body.Color = Color3.fromRGB(8, 8, 10)
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CFrame = CFrame.new(pos + Vector3.new(0, 3.5, 0))
	body.Parent = m
	m.PrimaryPart = body
	m.Parent = house
	CollectionService:AddTag(m, "HouseShape")
	return m
end

local function act(e: Mystery.Event)
	local h = house
	if not h then
		return
	end
	local center = h:GetPivot().Position
	local fig = figure()
	local home = fig and (fig:GetAttribute("Home") :: CFrame?)
	if e.action == "upstairsOn" then
		setRoom("Upstairs", true)
	elseif e.action == "downstairsOn" then
		setRoom("Downstairs", true)
	elseif e.action == "allOff" then
		setRoom("Upstairs", false)
		setRoom("Downstairs", false)
	elseif e.action == "silhouetteCross" and fig and home then
		showFigure(fig, true)
		fig:PivotTo(home)
		tweenPivot(fig, home * CFrame.new(14, 0, 0), 7)
		task.delay(7.5, function()
			showFigure(fig, false)
			fig:PivotTo(home)
		end)
	elseif e.action == "figureStand" and fig and home then
		fig:PivotTo(home * CFrame.new(2, 0, 0.8))
		showFigure(fig, true)
	elseif e.action == "figureLeave" and fig and home then
		showFigure(fig, false)
		fig:PivotTo(home)
	elseif e.action == "flicker" then
		task.spawn(function()
			for _ = 1, 10 do
				local on = rng:NextNumber() < 0.5
				setRoom("Upstairs", on)
				setRoom("Downstairs", not on)
				task.wait(rng:NextNumber(0.08, 0.3))
			end
			setRoom("Upstairs", true)
			setRoom("Downstairs", true)
		end)
	elseif e.action == "creaturesApproach" then
		for i = 1, 4 do
			local a = math.rad(-60 + i * 30)
			local start = center + Vector3.new(math.sin(a) * 70, -2, -math.cos(a) * 60)
			local s = shape(start)
			table.insert(shapes, s)
			tweenPivot(s, CFrame.new(center + Vector3.new(math.sin(a) * 16, 1.5, -math.cos(a) * 12 + 6)), 22)
		end
	elseif e.action == "windowBreak" then
		for _, d in h:GetDescendants() do
			if d:IsA("BasePart") and CollectionService:HasTag(d, "HousePane") and d.Name == "DownPane" then
				d:SetAttribute("Broken", true)
				d.Transparency = 1
				h:SetAttribute("Broken", true)
				Net.event("SoundCue"):FireAllClients("glassBreak", d.Position, 0.5)
			end
		end
	elseif e.action == "interiorMovement" then
		local s = shape(center + Vector3.new(-3, 0, 4))
		table.insert(shapes, s)
		tweenPivot(s, CFrame.new(center + Vector3.new(5, 3.5, 3)), 10)
	elseif e.action == "creaturesLeave" then
		for _, s in shapes do
			tweenPivot(s, CFrame.new(center + Vector3.new(rng:NextNumber(-80, 80), 1.5, -90)), 18)
			task.delay(19, function()
				s:Destroy()
			end)
		end
		table.clear(shapes)
	end
	local pos = center + Vector3.new(0, 9, 0)
	local snap = TimeService.snapshot()
	table.insert(recent, {
		id = string.format("LakeHouse-d%d-%s-%d", snap.day, e.action, math.floor(e.at * 100)),
		action = e.action,
		note = e.note,
		time = now(),
		position = pos,
	})
	while #recent > 12 do
		table.remove(recent, 1)
	end
end

function HouseActivityService.start()
	for _, m in CollectionService:GetTagged("WatchedHouse") do
		if m:IsA("Model") then
			if m.Name == "HillHouse" or house == nil then
				if house then
					table.insert(others, house)
				end
				house = m
			else
				table.insert(others, m)
			end
		end
	end
	if not house and #others == 0 then
		return
	end
	TimeService.onPhaseChanged(function(s)
		if s.phase == "Night" then
			lastFraction = 0
			scheduleOthers((ReplicatedStorage:GetAttribute("NightType") :: string?) or "Peaceful")
		elseif s.phase == "Day" then
			setRoom("Upstairs", false)
			setRoom("Downstairs", false)
			for _, h in others do
				for _, room in roomsOf(h) do
					setRoomIn(h, room, false)
				end
			end
			local f = figure()
			if f then
				showFigure(f, false)
			end
			for _, sh in shapes do
				sh:Destroy()
			end
			table.clear(shapes)
		end
	end)
	TimeService.onTick(function(snap)
		if snap.phase ~= "Night" then
			return
		end
		local frac = snap.phaseProgress
		if frac <= lastFraction then
			return
		end
		if house then
			local nightType = (ReplicatedStorage:GetAttribute("NightType") :: string?) or "Peaceful"
			local events = Mystery.eventsFor(GameConfig.LakeHouse :: any, snap.day, nightType)
			for _, e in Mystery.due(events, lastFraction, frac) do
				task.spawn(act, e)
			end
		end
		for _, r in routine do
			if r.at > lastFraction and r.at <= frac then
				setRoomIn(r.house, r.room, r.on)
			end
		end
		lastFraction = frac
	end)
end

return HouseActivityService

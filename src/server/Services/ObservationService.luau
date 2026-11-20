--!strict
-- Window observation and the observation journal.
--
-- A player looking out of a window (or carefully watching with the
-- binoculars) records what they really see: creatures in clear sight, the
-- lake house's events, the Old One. Entries carry the conditions of the
-- moment. Watchers notice being watched through glass.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Journal = require(ReplicatedStorage.Shared.Logic.Journal)
local Net = require(ReplicatedStorage.Shared.Net)
local CreatureService = require(script.Parent.CreatureService)
local HouseActivityService = require(script.Parent.HouseActivityService)
local OldOneService = require(script.Parent.OldOneService)
local PlayerService = require(script.Parent.PlayerService)
local ProgressBus = require(script.Parent.ProgressBus)
local ShelterService = require(script.Parent.ShelterService)
local TimeService = require(script.Parent.TimeService)
local WeatherService = require(script.Parent.WeatherService)

local ObservationService = {}

local journals: { [Player]: Journal.Journal } = {}
local rng = Random.new(12)

local STATE_TEXT: { [string]: string } = {
	PATROL = "moving slowly between the trees",
	SUSPICIOUS = "standing still, head turned",
	INVESTIGATE = "walking toward something it heard",
	SEARCH = "searching the ground, back and forth",
	HUNT = "running",
	LOST_TARGET = "standing where it lost something",
	RETREAT = "walking away into the forest",
	DORMANT = "not moving at all",
}

local function journalOf(player: Player): Journal.Journal
	local j = journals[player]
	if not j then
		j = Journal.new()
		journals[player] = j
	end
	return j
end

local function landmarkNear(pos: Vector3): string
	local world = workspace:FindFirstChild("World")
	local best, bestD = "in the forest", 90
	if world then
		for _, name in { "Cabin", "LakeHouse", "AbandonedHouse", "RadioTower" } do
			local m = world:FindFirstChild(name)
			if m and m:IsA("Model") then
				local d = (m:GetPivot().Position - pos).Magnitude
				if d < bestD then
					bestD = d
					best = ({
						Cabin = "near the cabin",
						LakeHouse = "by the house across the lake",
						AbandonedHouse = "around the abandoned house",
						RadioTower = "under the radio tower",
					})[name] :: string
				end
			end
		end
	end
	return best
end

local function weatherText(): string
	local w = WeatherService.label()
	if w == "Storm" then
		return "in the storm"
	elseif w == "Rain" then
		return "in the rain"
	elseif w == "Fog" then
		return "in heavy fog"
	end
	return "under a clear sky"
end

local function record(player: Player, id: string, subject: string, text: string)
	local snap = TimeService.snapshot()
	local entry = Journal.record(journalOf(player), {
		id = id,
		subject = subject,
		text = text,
		day = snap.day,
		clock = Journal.formatClock(snap.clockTime),
		weather = WeatherService.label(),
		certainty = "observed",
	})
	if entry then
		Net.event("Journal"):FireClient(player, entry)
		Net.event("SoundCue"):FireClient(player, "journal")
		ProgressBus.emit(player, "observe", subject, nil, id)
	end
end

-- Other systems (the Chaoscope) write observed entries the same way.
-- The id deduplicates: the same event is only ever recorded once.
function ObservationService.note(player: Player, id: string, subject: string, text: string)
	record(player, id, subject, text)
end

-- Eye position and look direction used for this player's observation.
local function viewOf(player: Player): (Vector3?, Vector3?, number, number)
	local s = PlayerService.get(player)
	if not s then
		return nil, nil, 0, 0
	end
	local w = s.observing
	if w then
		local glass = w:FindFirstChild("Glass")
		local att = glass and glass:FindFirstChild("ObservePoint")
		if att and att:IsA("Attachment") then
			local hasBino = PlayerService.count(player, "Binoculars") > 0
			return att.WorldPosition, s.look, if hasBino then 420 else 260, 32
		end
	end
	local head = PlayerService.head(player)
	if head and PlayerService.count(player, "Binoculars") > 0 then
		return head.Position, s.look, 300, 10
	end
	if head then
		return head.Position, s.look, 120, 12
	end
	return nil, nil, 0, 0
end

local function canSee(
	player: Player,
	eye: Vector3,
	look: Vector3,
	range: number,
	cone: number,
	target: Vector3,
	ignore: { Instance }
): boolean
	local to = target - eye
	local d = to.Magnitude
	if d > range or d < 1 then
		return false
	end
	if look:Dot(to.Unit) < math.cos(math.rad(cone)) then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = {}
	if player.Character then
		table.insert(list, player.Character)
	end
	for _, i in ignore do
		table.insert(list, i)
	end
	params.FilterDescendantsInstances = list
	return workspace:Raycast(eye, to, params) == nil
end

local function houseIgnore(): { Instance }
	local h = HouseActivityService.house()
	return if h then { h } else {}
end

local function tickPlayer(player: Player)
	local s = PlayerService.get(player)
	if not s or not PlayerService.isActive(player) then
		return
	end
	local eye, look, range, cone = viewOf(player)
	if not eye or not look then
		return
	end
	local snap = TimeService.snapshot()
	local window = s.observing ~= nil
	for _, c in CreatureService.list() do
		local target = c.root.Position + Vector3.new(0, 2, 0)
		if canSee(player, eye, look, range, cone, target, { c.model }) then
			local cabin = ShelterService.model("Cabin")
			local lit = s.shelter ~= nil and cabin ~= nil and cabin:GetAttribute("Power") ~= false
			local text = string.format(
				"Seen %s %s, %s. %s",
				landmarkNear(c.root.Position),
				weatherText(),
				STATE_TEXT[c.state] or "watching",
				if window and lit and c.kind == "Watcher" then "The cabin lights were on." else ""
			)
			record(
				player,
				string.format("%s-d%d-%s", c.arch.journalSubject, snap.day, c.state),
				c.arch.journalSubject,
				text
			)
			-- The mutual gaze: a Watcher notices the face at the glass.
			if
				window
				and c.kind == "Watcher"
				and c.state ~= "RETREAT"
				and (c.root.Position - eye).Magnitude < 140
			then
				local w = s.observing :: Instance
				if rng:NextNumber() < 0.25 and not c.window then
					c.window = w
					c.windowStare = 0
					c.lastSeenThroughWindow = os.clock()
				end
			end
		end
	end
	local oldPos = OldOneService.visiblePosition()
	if oldPos and canSee(player, eye, look, 700, cone + 8, oldPos, {}) then
		record(
			player,
			"OldOne-d" .. snap.day,
			"The Old One",
			"Something vast stood on the north ridge, taller than the trees. The Watchers left. It did not move. Then it was gone."
		)
	end
	for _, ev in HouseActivityService.recentEvents() do
		if
			os.clock() - ev.time < 40
			and ev.note
			and canSee(player, eye, look, range + 80, cone, ev.position, houseIgnore())
		then
			record(player, ev.id, "House across the lake", ev.note :: string)
		end
	end
end

function ObservationService.start()
	Net.event("SetObserving").OnServerEvent:Connect(function(player, window)
		if not Net.allow(player, "observe", 4) then
			return
		end
		if window == nil then
			PlayerService.setObserving(player, nil)
			return
		end
		if typeof(window) ~= "Instance" or not CollectionService:HasTag(window, "Window") then
			return
		end
		local glass = window:FindFirstChild("Glass")
		local root = PlayerService.root(player)
		if
			not glass
			or not glass:IsA("BasePart")
			or not root
			or (glass.Position - root.Position).Magnitude > 10
		then
			return
		end
		if window:GetAttribute("Shuttered") == true then
			return
		end
		PlayerService.setObserving(player, window)
	end)
	Net.func("GetJournal").OnServerInvoke = function(player)
		return journalOf(player).entries
	end
	Players.PlayerRemoving:Connect(function(p)
		journals[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer :: any, p)
				if not ok then
					warn("[Observation] " .. tostring(err))
				end
			end
		end
	end)
end

return ObservationService

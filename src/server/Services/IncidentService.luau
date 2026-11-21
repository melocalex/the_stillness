--!strict
-- The incident director: small daytime events that give a quiet day
-- something to do. At the start of each day and again at midday it picks
-- one eligible incident (Logic/Incidents: conditions, weights, cooldowns,
-- a daily budget), places it in the world and announces it on the radio.
-- Most are peaceful errands; rewards are capped per player per window in
-- ProgressionService.earn. Nothing happens on day 1: the opening owns it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Incidents = require(ReplicatedStorage.Shared.Logic.Incidents)
local Net = require(ReplicatedStorage.Shared.Net)
local TownConfig = require(ReplicatedStorage.Shared.Config.TownConfig)
local Builder = require(script.Parent.Parent.World.Builder)
local TownWorld = require(script.Parent.Parent.World.Town)
local PlayerService = require(script.Parent.PlayerService)
local ProgressionService = require(script.Parent.ProgressionService)
local TimeService = require(script.Parent.TimeService)
local TownService = require(script.Parent.TownService)
local WeatherService = require(script.Parent.WeatherService)

local IncidentService = {}

type Def = typeof(TownConfig.Incidents[1])

type Active = {
	def: Def,
	folder: Folder,
	spot: Vector3,
	done: { [Player]: boolean },
	carrying: { [Player]: boolean },
	resolved: boolean,
}

local state = Incidents.new()
local active: Active? = nil
local rng = Random.new()
local lastNight: string? = nil
local middayDay = 0
local root: Folder

local function notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

local function ground(x: number, z: number): Vector3
	return Vector3.new(x, TownWorld.groundY(x, z), z)
end

local function clear()
	local a = active
	if a then
		a.folder:Destroy()
		active = nil
		ProgressionService.setIncident(nil)
	end
end

local function resolve(a: Active)
	a.resolved = true
	task.delay(2, function()
		if active == a then
			clear()
		end
	end)
end

local function prompt(part: BasePart, action: string, object: string, hold: number, fn: (Player) -> ())
	local p = Builder.prompt(part, action, object, hold, 9)
	p.Name = "IncidentPrompt"
	p.Triggered:Connect(function(player)
		local r = PlayerService.root(player)
		if r and (r.Position - part.Position).Magnitude < 14 and Net.allow(player, "incident", 2) then
			fn(player)
		end
	end)
end

local function spawnBranch(a: Active)
	local p = Builder.part({
		name = "FallenBranch",
		size = Vector3.new(1.6, 1.6, 12),
		cframe = CFrame.new(a.spot + Vector3.new(0, 0.8, 0))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0.1),
		color = Color3.fromRGB(92, 70, 50),
		material = Enum.Material.Wood,
		parent = a.folder,
	})
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(12, 1.6, 1.6)
	prompt(p, "Clear the branch", "Fallen branch", 2, function(player)
		if a.resolved then
			return
		end
		ProgressionService.earn(player, a.def.reward, a.def.items, "You drag the branch off the trail.")
		resolve(a)
	end)
end

local function spawnMushrooms(a: Active)
	local left = 3
	for i = 1, 3 do
		local ang = i / 3 * math.pi * 2
		local pos = ground(a.spot.X + math.cos(ang) * 9, a.spot.Z + math.sin(ang) * 9)
		local cap = Builder.part({
			name = "MushroomCluster",
			shape = Enum.PartType.Ball,
			size = Vector3.new(1.6, 0.9, 1.6),
			cframe = CFrame.new(pos + Vector3.new(0, 0.4, 0)),
			color = Color3.fromRGB(196, 150, 104),
			material = Enum.Material.SmoothPlastic,
			canCollide = false,
			parent = a.folder,
		})
		CollectionService:AddTag(cap, "TownForage")
		prompt(cap, "Pick mushrooms", "Mushrooms", 0.8, function(player)
			if cap.Parent == nil then
				return
			end
			cap:Destroy()
			ProgressionService.earn(player, a.def.reward, a.def.items, "A handful of fresh mushrooms.")
			left -= 1
			if left <= 0 then
				resolve(a)
			end
		end)
	end
end

local function spawnBasket(a: Active)
	local basket = Builder.part({
		name = "Basket",
		size = Vector3.new(1.8, 1.2, 1.4),
		cframe = CFrame.new(a.spot + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(20)),
		color = Color3.fromRGB(170, 130, 80),
		material = Enum.Material.Fabric,
		parent = a.folder,
	})
	prompt(basket, "Pick up", "Ellen's basket", 0.6, function(player)
		if a.resolved or a.carrying[player] then
			return
		end
		a.carrying[player] = true
		basket.Transparency = 1
		basket.CanCollide = false
		notify(player, "Ellen's basket. Bring it to the diner.", "info")
	end)
end

local function spawnTracks(a: Active)
	for i = 0, 7 do
		local pos = ground(a.spot.X + i * 2.8, a.spot.Z + math.sin(i) * 1.2)
		Builder.part({
			name = "Track",
			size = Vector3.new(1.4, 0.08, 2.4),
			cframe = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, math.rad(90), 0),
			color = Color3.fromRGB(46, 40, 36),
			material = Enum.Material.SmoothPlastic,
			canCollide = false,
			parent = a.folder,
		})
	end
	local look = Builder.part({
		name = "TrackStart",
		size = Vector3.new(2, 2, 2),
		cframe = CFrame.new(a.spot + Vector3.new(0, 1, 0)),
		transparency = 1,
		canCollide = false,
		parent = a.folder,
	})
	prompt(look, "Look closely", "Long tracks", 1.5, function(player)
		if a.done[player] then
			return
		end
		a.done[player] = true
		ProgressionService.earn(
			player,
			a.def.reward,
			nil,
			"Long, narrow prints, far apart. They lead to the water and stop."
		)
	end)
end

local SPAWN: { [string]: (Active) -> () } = {
	fallen_branch = spawnBranch,
	mushroom_flush = spawnMushrooms,
	lost_basket = spawnBasket,
	strange_tracks = spawnTracks,
}

local function unionFlags(): { [string]: boolean }
	local out = {}
	for _, p in ProgressionService.all() do
		for f in p.log.flags do
			out[f] = true
		end
	end
	return out
end

local function direct(day: number)
	if active or day < 2 or #Players:GetPlayers() == 0 then
		return
	end
	local defs: { Incidents.Def } = TownConfig.Incidents :: any
	local list = Incidents.eligible(defs, state, {
		day = day,
		phase = TimeService.snapshot().phase,
		weather = WeatherService.label(),
		lastNight = lastNight,
		flags = unionFlags(),
	}, TownConfig.IncidentsPerDay)
	local pick = Incidents.choose(list, rng:NextNumber())
	if not pick then
		return
	end
	local def: Def
	for _, d in TownConfig.Incidents do
		if d.id == pick.id then
			def = d
		end
	end
	Incidents.fire(state, pick, day)
	local s = def.spots[rng:NextInteger(1, #def.spots)]
	local a: Active = {
		def = def,
		folder = Builder.folder("Incident_" .. def.id, root),
		spot = ground(s.x, s.z),
		done = {},
		carrying = {},
		resolved = false,
	}
	active = a
	local fn = SPAWN[def.id]
	if fn then
		fn(a)
	end
	ProgressionService.setIncident(def.title)
	-- After the morning forecast has had its turn on the radio.
	task.delay(25, function()
		if active == a then
			Net.event("Radio"):FireAllClients(def.radio)
			Net.event("SoundCue"):FireAllClients("radioStatic", nil, 0.3)
		end
	end)
end

local function tick()
	local a = active
	if not a or a.resolved then
		return
	end
	if a.def.id == "deer_meadow" then
		for _, player in Players:GetPlayers() do
			local r = PlayerService.root(player)
			if r and not a.done[player] and (r.Position - a.spot).Magnitude < 45 then
				a.done[player] = true
				ProgressionService.earn(
					player,
					a.def.reward,
					nil,
					"A doe lifts her head, watches you, and goes back to grazing."
				)
			end
		end
	end
end

function IncidentService.start()
	root = Builder.folder("Incidents", workspace)
	TownService.onTalk(function(player: Player, npc: string): { string }?
		local a = active
		if a and a.def.deliverTo == npc and a.carrying[player] and not a.resolved then
			a.carrying[player] = nil
			ProgressionService.earn(player, a.def.reward, nil, "Ellen's basket, delivered.")
			resolve(a)
			return { "Ellen: My basket! Not a single egg broken. You're a treasure." }
		end
		return nil
	end)
	TimeService.onPhaseChanged(function(snap: any)
		if snap.phase == "Day" then
			task.delay(5, direct, snap.day)
		elseif snap.phase == "Dusk" then
			clear()
		elseif snap.phase == "Night" then
			lastNight = ReplicatedStorage:GetAttribute("NightType") :: string?
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			local ok, err = pcall(tick :: any)
			if not ok then
				warn("[Incident] " .. tostring(err))
			end
			-- A second chance at midday if the morning one is finished.
			local snap = TimeService.snapshot()
			if snap.phase == "Day" and snap.phaseProgress >= 0.5 and not active and middayDay ~= snap.day then
				middayDay = snap.day
				direct(snap.day)
			end
		end
	end)
end

-- Studio: start an incident now (bypasses the day-1 rule and conditions).
-- require(game.ServerScriptService.Server.Services.IncidentService).debugStart("fallen_branch")
function IncidentService.debugStart(id: string)
	clear()
	for _, d in TownConfig.Incidents do
		if d.id == id then
			local s = d.spots[1]
			local a: Active = {
				def = d,
				folder = Builder.folder("Incident_" .. d.id, root),
				spot = ground(s.x, s.z),
				done = {},
				carrying = {},
				resolved = false,
			}
			active = a
			local fn = SPAWN[d.id]
			if fn then
				fn(a)
			end
			ProgressionService.setIncident(d.title)
			Net.event("Radio"):FireAllClients(d.radio)
		end
	end
end

return IncidentService

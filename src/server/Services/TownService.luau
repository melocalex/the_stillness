--!strict
-- Pinehaven in the world: Frank, Ellen, Martha and Dr. Hale as R15 NPCs
-- (built the way MayaService builds Maya), their dialogue, quest prompts,
-- restoration visuals, the shops, Biscuit, and Maya's quest talk. All rules
-- and saved state live in ProgressionService.
--
-- The world shows the furthest restoration stage and every quest flag held
-- by any player present, recomputed whenever someone's progress changes and
-- on load, so a rejoin shows the same town.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Dialogue = require(ReplicatedStorage.Shared.Logic.Dialogue)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Restoration = require(ReplicatedStorage.Shared.Logic.Restoration)
local TownConfig = require(ReplicatedStorage.Shared.Config.TownConfig)
local Builder = require(script.Parent.Parent.World.Builder)
local Rigs = require(script.Parent.Parent.Creatures.Rigs)
local TownWorld = require(script.Parent.Parent.World.Town)
local DogService = require(script.Parent.DogService)
local DogTracking = require(script.Parent.DogTracking)
local MayaService = require(script.Parent.MayaService)
local PlayerService = require(script.Parent.PlayerService)
local ProgressionService = require(script.Parent.ProgressionService)
local TimeService = require(script.Parent.TimeService)

local TownService = {}

local npcs: { [string]: Model } = {}
local spots: { [string]: BasePart } = {}
local queues: { [Player]: { string } } = {}
local lostBiscuit: { [Player]: Model } = {}
local homeBiscuit: Model? = nil
local repairPrompts: { [string]: ProximityPrompt } = {}
local talkHandlers: { (Player, string) -> { string }? } = {}
local mayaTable: BasePart? = nil

local LINE_SECONDS = 3.6

local function notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

-- Lines through the HUD radio card, one after another, never overlapping.
function TownService.say(player: Player, lines: { string })
	local q = queues[player]
	if q then
		for _, l in lines do
			table.insert(q, l)
		end
		return
	end
	local queue: { string } = table.clone(lines)
	queues[player] = queue
	task.spawn(function()
		while #queue > 0 and player.Parent do
			Net.event("Radio"):FireClient(player, table.remove(queue, 1))
			task.wait(LINE_SECONDS)
		end
		queues[player] = nil
	end)
end

-- Another service can answer a talk first (e.g. an incident delivery).
function TownService.onTalk(fn: (Player, string) -> { string }?)
	table.insert(talkHandlers, fn)
end

local function within(player: Player, part: BasePart, radius: number): boolean
	local r = PlayerService.root(player)
	return r ~= nil and (r.Position - part.Position).Magnitude <= radius
end

-- Positions ---------------------------------------------------------------------

local function npcPosition(id: string): Vector3?
	if id == "maya" then
		local m = CollectionService:GetTagged("Maya")[1]
		if m and m:IsA("Model") then
			return m:GetPivot().Position
		end
		local h = MayaService.house()
		return if h then h:GetPivot().Position else nil
	end
	local m = npcs[id]
	if m then
		return m:GetPivot().Position
	end
	local s = spots[id]
	return if s then s.Position else nil
end

local function firstWith(attr: string, value: string): BasePart?
	return TownWorld.find(attr, value)[1]
end

local function locate(key: string, player: Player?): Vector3?
	local kind, id = string.match(key, "^(%w+):(.+)$")
	if not kind or not id then
		return nil
	end
	if kind == "npc" then
		return npcPosition(id)
	elseif kind == "site" then
		local a = firstWith("SiteAnchor", id)
		if a then
			return a.Position
		end
		local m = TownWorld.site(id)
		return if m then m:GetPivot().Position else nil
	elseif kind == "project" then
		local a = firstWith("RepairProject", id)
		return if a then a.Position else nil
	elseif kind == "interact" then
		if id == "MayaTable" then
			return if mayaTable then mayaTable.Position else nil
		end
		local a = firstWith("Interaction", id)
		return if a then a.Position else nil
	elseif kind == "missing" then
		local b = if player then lostBiscuit[player] else nil
		if b then
			return b:GetPivot().Position
		end
		local a = firstWith("MissingSpot", id)
		return if a then a.Position else nil
	end
	return nil
end

TownService.locate = locate

-- World state --------------------------------------------------------------------

local function unionFlags(): { [string]: boolean }
	local out = {}
	for _, p in ProgressionService.all() do
		for f in p.log.flags do
			out[f] = true
		end
	end
	return out
end

local function unionStage(projectId: string): number
	local proj = ProgressionService.project(projectId)
	if not proj then
		return 0
	end
	local list = {}
	for _, p in ProgressionService.all() do
		table.insert(list, p.projects)
	end
	return Restoration.union(list, proj)
end

local function setShown(part: BasePart, shown: boolean)
	local base = (part:GetAttribute("BaseTransparency") :: number?) or 0
	part.Transparency = if shown then base else 1
	part.CanCollide = shown and part:GetAttribute("BaseCollide") == true
	part.CanQuery = shown
	for _, c in part:GetChildren() do
		if c:IsA("SurfaceGui") then
			c.Enabled = shown
		end
	end
end

local function refreshWorld()
	local flags = unionFlags()
	local stages: { [string]: number } = {}
	local phase = TimeService.snapshot().phase
	local night = phase == "Dusk" or phase == "Night"
	for _, part in CollectionService:GetTagged("TownVisual") do
		if part:IsA("BasePart") then
			local shown = true
			local project = part:GetAttribute("StageOf") :: string?
			if project then
				local stage = stages[project]
				if not stage then
					stage = unionStage(project)
					stages[project] = stage
				end
				local from = (part:GetAttribute("ShowFrom") :: number?) or 0
				local untilStage = part:GetAttribute("ShowUntil") :: number?
				shown = stage >= from and (untilStage == nil or stage < untilStage)
				local spinFrom = part:GetAttribute("SpinFrom") :: number?
				if spinFrom then
					part:SetAttribute("Spinning", stage >= spinFrom)
				end
			end
			local showFlag = part:GetAttribute("ShowFlag") :: string?
			local hideFlag = part:GetAttribute("HideFlag") :: string?
			if showFlag and not flags[showFlag] then
				shown = false
			end
			if hideFlag and flags[hideFlag] then
				shown = false
			end
			setShown(part, shown)
			local litFlag = part:GetAttribute("LitFlag") :: string?
			local nightOnly = part:GetAttribute("NightOnly") == true
			local lights = litFlag ~= nil or nightOnly or part:GetAttribute("LightWhenShown") == true
			local lit = shown
				and lights
				and (litFlag == nil or flags[litFlag] == true)
				and (not nightOnly or night)
			for _, c in part:GetChildren() do
				if c:IsA("PointLight") then
					c.Enabled = lit
				elseif c:IsA("SurfaceGui") then
					c.LightInfluence = if lit then 0 else 0.6
				end
			end
			if part:GetAttribute("Glow") == true then
				part.Material = if lit then Enum.Material.Neon else Enum.Material.Glass
				part.Color = if lit then Color3.fromRGB(255, 200, 130) else Color3.fromRGB(90, 110, 120)
			elseif part:GetAttribute("NeonWhenLit") == true then
				part.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
	-- Repair prompts name the next step.
	for projectId, prompt in repairPrompts do
		local proj = ProgressionService.project(projectId)
		if proj then
			local stage = unionStage(projectId)
			local action = proj.actions[stage + 1]
			if prompt.Name ~= "InspectPrompt" or stage > 0 then
				prompt.ActionText = if action then action.text else "Restored"
			end
		end
	end
	-- Biscuit sleeps on Martha's porch once anyone present brought him home.
	local home = firstWith("HomeSpot", "Biscuit")
	if flags.biscuitHome and not homeBiscuit and home then
		local ok, rig = pcall(Rigs.dog)
		if ok and rig then
			local m = rig.model
			m.Name = "Biscuit"
			for _, d in m:GetDescendants() do
				if d:IsA("MeshPart") then
					d.TextureID = ""
					d.Color = Color3.fromRGB(236, 232, 224)
				elseif d:IsA("BasePart") and d.Transparency < 1 then
					d.Color = Color3.fromRGB(236, 232, 224)
				end
			end
			m:ScaleTo(m:GetScale() * 0.75)
			m:SetAttribute("Pose", "sleep")
			CollectionService:AddTag(m, "Dog")
			m:PivotTo(home.CFrame)
			rig.root.Anchored = true
			m.Parent = TownWorld.site("MarthaHouse") or workspace
			homeBiscuit = m
		end
	elseif not flags.biscuitHome and homeBiscuit then
		homeBiscuit:Destroy()
		homeBiscuit = nil
	end
end

-- Biscuit, lost ---------------------------------------------------------------------

local function makeBiscuit(at: CFrame): Model?
	local ok, rig = pcall(Rigs.dog)
	if not ok or not rig then
		return nil
	end
	local m = rig.model
	m.Name = "Biscuit"
	for _, d in m:GetDescendants() do
		if d:IsA("MeshPart") then
			d.TextureID = ""
			d.Color = Color3.fromRGB(236, 232, 224)
		elseif d:IsA("BasePart") and d.Transparency < 1 then
			d.Color = Color3.fromRGB(236, 232, 224)
		end
	end
	m:ScaleTo(m:GetScale() * 0.75)
	m:SetAttribute("Pose", "hide")
	CollectionService:AddTag(m, "Dog")
	m:PivotTo(at)
	m.Parent = workspace
	pcall(function()
		rig.root:SetNetworkOwner(nil)
	end)
	return m
end

local function tickBiscuits()
	for _, p in ProgressionService.all() do
		local player = p.player
		local locateDef = ProgressionService.waitingOn(player, "locate", "Biscuit")
		local bringDef = ProgressionService.waitingOn(player, "reach", "MarthaHouse")
		local need = locateDef ~= nil or bringDef ~= nil
		local b: Model? = lostBiscuit[player]
		if need and not b then
			local spot = firstWith("MissingSpot", "Biscuit")
			if spot then
				local made = makeBiscuit(spot.CFrame)
				if made then
					lostBiscuit[player] = made
				end
				b = made
			end
		elseif not need and b then
			b:Destroy()
			lostBiscuit[player] = nil
			b = nil
		end
		if b and bringDef then
			-- Found: he follows close at the player's heels.
			local hum = b:FindFirstChildOfClass("Humanoid")
			local root = PlayerService.root(player)
			if hum and root then
				local pos = b:GetPivot().Position
				local dist = (root.Position - pos).Magnitude
				b:SetAttribute("Pose", "stand")
				hum.WalkSpeed = if dist > 14 then 22 else 14
				if dist > 80 then
					b:PivotTo(root.CFrame * CFrame.new(3, 0, 3))
				elseif dist > 6 then
					hum:MoveTo(root.Position - root.CFrame.LookVector * 3)
				else
					hum:MoveTo(pos)
				end
			end
		end
	end
	for player, b in lostBiscuit do
		if not player.Parent then
			b:Destroy()
			lostBiscuit[player] = nil
		end
	end
end

-- Talking ---------------------------------------------------------------------------

local function npcLines(player: Player, npc: string): { string }
	local entries: { Dialogue.Entry } = (TownConfig.Dialogue[npc] or {}) :: any
	return Dialogue.pick(entries, ProgressionService.facts(player, npc)) or {}
end

-- One conversation. Returns the lines to say; a quest completed by it speaks
-- its own outro through the completion hook.
local function converse(player: Player, npc: string): { string }
	for _, fn in talkHandlers do
		local lines = fn(player, npc)
		if lines then
			return lines
		end
	end
	local talkDef = ProgressionService.waitingOn(player, "talk", npc)
	if talkDef then
		local changes = ProgressionService.event(player, "talk", npc)
		for _, ch in changes do
			if ch.completed then
				return {}
			end
		end
		local obj = talkDef.objectives[(changes[1] and changes[1].step) or 1]
		return if obj and obj.say then obj.say else {}
	end
	local deliverDef, deliverObj = ProgressionService.waitingOn(player, "deliver", npc)
	if deliverDef and deliverObj and deliverObj.items then
		if PlayerService.spend(player, deliverObj.items) then
			local changes = ProgressionService.event(player, "deliver", npc)
			if changes[1] and changes[1].completed then
				return {}
			end
			return deliverObj.say
				or { string.format("%s: Oh, that smells wonderful. Thank you.", TownService.name(npc)) }
		end
		return { deliverDef.reminder or "" }
	end
	local offers = ProgressionService.available(player, npc)
	for _, def in offers do
		if not def.optional then
			ProgressionService.startQuest(player, def.id)
			return def.intro or {}
		end
	end
	local active = ProgressionService.activeFrom(player, npc)
	if active[1] then
		return { active[1].reminder or "" }
	end
	if offers[1] then
		ProgressionService.startQuest(player, offers[1].id)
		return offers[1].intro or {}
	end
	return npcLines(player, npc)
end

function TownService.name(npc: string): string
	if npc == "maya" then
		return TownConfig.MayaInfo.name
	end
	local n = TownConfig.Npcs[npc]
	return if n then n.name else npc
end

local function talkTo(player: Player, npc: string)
	if not Net.allow(player, "townTalk", 1) or queues[player] then
		return
	end
	local lines = converse(player, npc)
	if #lines > 0 then
		TownService.say(player, lines)
	end
end

-- Maya: quest talk, garden gifts and acknowledgements, or nil for her own
-- small talk. Handled lines are spoken here; an empty table means "done".
local function mayaHook(player: Player): { string }?
	if not ProgressionService.get(player) then
		return nil
	end
	local busy = ProgressionService.waitingOn(player, "talk", "maya")
		or ProgressionService.waitingOn(player, "deliver", "maya")
		or ProgressionService.available(player, "maya")[1]
	local lines: { string } = {}
	if busy then
		lines = converse(player, "maya")
	elseif ProgressionService.waitingOn(player, "interact", "MayaTable") then
		lines = { "Maya: The table's set. Sit down whenever you're ready." }
	end
	if ProgressionService.gardenGift(player) then
		table.insert(lines, "Maya: Take some berries from the garden. There are plenty.")
		notify(player, "+2 Berries from Maya's garden", "pickup")
	end
	if #lines == 0 and not busy then
		local ack = npcLines(player, "maya")
		if #ack > 0 and math.random() < 0.5 then
			lines = ack
		end
	end
	if #lines == 0 and not busy then
		return nil
	end
	TownService.say(player, lines)
	return {}
end

-- NPCs ---------------------------------------------------------------------------------

local function hat(m: Model, look: TownConfig.NpcLook)
	local head = m:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local color = Builder.rgb(look.hatColor)
	local p: Part
	if look.hat == "beanie" then
		p = Builder.part({
			name = "Beanie",
			size = Vector3.new(1.25, 0.7, 1.25),
			cframe = head.CFrame * CFrame.new(0, 0.5, 0),
			color = color,
			material = Enum.Material.Fabric,
			anchored = false,
			canCollide = false,
		})
	elseif look.hat == "bun" then
		p = Builder.part({
			name = "Bun",
			shape = Enum.PartType.Ball,
			size = Vector3.new(0.8, 0.8, 0.8),
			cframe = head.CFrame * CFrame.new(0, 0.55, 0.45),
			color = color,
			material = Enum.Material.SmoothPlastic,
			anchored = false,
			canCollide = false,
		})
	elseif look.hat == "scarf" then
		p = Builder.part({
			name = "Headscarf",
			size = Vector3.new(1.3, 0.5, 1.3),
			cframe = head.CFrame * CFrame.new(0, 0.45, 0.05),
			color = color,
			material = Enum.Material.Fabric,
			anchored = false,
			canCollide = false,
		})
	else
		p = Builder.part({
			name = "Cap",
			size = Vector3.new(1.25, 0.4, 1.6),
			cframe = head.CFrame * CFrame.new(0, 0.5, -0.15),
			color = color,
			material = Enum.Material.Fabric,
			anchored = false,
			canCollide = false,
		})
	end
	p.Massless = true
	p.CanQuery = false
	local w = Instance.new("WeldConstraint")
	w.Part0 = head
	w.Part1 = p
	w.Parent = p
	p.Parent = m
end

local IDLE = "rbxassetid://507766666" -- Roblox's default R15 idle (as MayaService)

local function buildNpc(id: string, spec: any, spot: BasePart, parent: Instance): Model?
	local look: TownConfig.NpcLook = spec.look
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = Builder.rgb(look.skin)
	desc.LeftArmColor = Builder.rgb(look.skin)
	desc.RightArmColor = Builder.rgb(look.skin)
	desc.TorsoColor = Builder.rgb(look.torso)
	desc.LeftLegColor = Builder.rgb(look.legs)
	desc.RightLegColor = Builder.rgb(look.legs)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[Town] could not build " .. id .. ": " .. tostring(model))
		return nil
	end
	local m: Model = model
	m.Name = spec.name
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.BreakJointsOnDeath = false
	end
	local root = m.PrimaryPart
	if root then
		root.Anchored = true
	end
	m:SetAttribute("Npc", id)
	CollectionService:AddTag(m, "TownNpc")
	local lift = if hum and root then hum.HipHeight + root.Size.Y / 2 else 3
	m:PivotTo(spot.CFrame + Vector3.new(0, lift, 0))
	hat(m, look)
	m.Parent = parent
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = IDLE
		local okTrack, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if okTrack and track then
			track.Looped = true
			track:Play()
		end
	end
	return m
end

local function setupNpc(id: string, spec: any)
	local spot = firstWith("Npc", id)
	if not spot then
		warn("[Town] no spot for " .. id)
		return
	end
	spots[id] = spot
	local site = TownWorld.site(spec.site) or workspace
	local m = buildNpc(id, spec, spot, site)
	if m then
		npcs[id] = m
	end
	-- Without a rig the prompt sits on the spot, so the NPC still works.
	local anchor: BasePart = if m and m.PrimaryPart then m.PrimaryPart else spot
	local prompt = Builder.prompt(anchor, "Talk", spec.name, 0, 10)
	prompt.Name = "TownTalkPrompt"
	prompt.Triggered:Connect(function(player)
		if within(player, anchor, 14) then
			talkTo(player, id)
		end
	end)
end

-- Prompts on things -----------------------------------------------------------------

local function recipeCost(id: string): { [string]: number }?
	for _, r in ItemConfig.Recipes do
		if r.id == id then
			return r.cost
		end
	end
	return nil
end

local function dogNear(player: Player, part: BasePart, radius: number): boolean
	local dog = DogService.dogOf(player)
	return dog ~= nil and (dog:GetPivot().Position - part.Position).Magnitude <= radius
end

local function onInteract(player: Player, id: string, part: BasePart)
	if id == "DinerStove" then
		if not ProgressionService.waitingOn(player, "interact", "DinerStove") then
			notify(
				player,
				if ProgressionService.hasFlag(player, "dinerOpen")
					then "Ellen's stove is warm. Something good is simmering."
					else "The stove is cold.",
				"info"
			)
			return
		end
		local cost = recipeCost("stew")
		if cost and PlayerService.spend(player, cost) then
			notify(player, "You cook berries and mushroom down into a thick, sweet stew.", "good")
			Net.event("SoundCue"):FireAllClients("cabinet", part.Position, 0.5)
			ProgressionService.event(player, "interact", "DinerStove")
		end
	elseif id == "BiscuitScarf" then
		local first = ProgressionService.waitingOn(player, "interact", "BiscuitScarf")
		-- Again while searching: the trail went cold, let him smell it again.
		local again = ProgressionService.waitingOn(player, "locate", "Biscuit")
		if not first and not again then
			notify(player, "A small red scarf. It smells of dog and wood smoke.", "info")
			return
		end
		if not dogNear(player, part, 20) then
			notify(player, "Caramelo needs to be close to smell it. Call him (G, Come).", "info")
			return
		end
		if first then
			ProgressionService.event(player, "interact", "BiscuitScarf")
		end
		DogTracking.track(player, function(): Vector3?
			return locate("missing:Biscuit", player)
		end, "Biscuit", part.Position, nil)
	elseif id == "MayaTable" then
		if not ProgressionService.waitingOn(player, "interact", "MayaTable") then
			notify(player, "You sit at Maya's table for a moment. It's warm in here.", "info")
			return
		end
		local phase = TimeService.snapshot().phase
		if phase ~= "Day" and phase ~= "Dusk" then
			TownService.say(player, { "Maya: It's late. Go home safe, okay? Tomorrow." })
			return
		end
		ProgressionService.event(player, "interact", "MayaTable")
	end
end

-- Things use F, people E, counters R: Roblox shows one prompt per key, so a
-- stove or a scarf next to someone would otherwise hide behind their Talk.
local function useKey(prompt: ProximityPrompt)
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonR2
end

local function interactPrompt(part: BasePart, id: string, action: string, object: string, hold: number)
	local prompt = Builder.prompt(part, action, object, hold, 9)
	prompt.Name = "TownPrompt"
	useKey(prompt)
	prompt.Triggered:Connect(function(player)
		if within(player, part, 12) and Net.allow(player, "townUse", 2) then
			onInteract(player, id, part)
		end
	end)
end

local function repairPrompt(part: BasePart, projectId: string)
	local proj = ProgressionService.project(projectId)
	if not proj then
		return
	end
	local investigate = part:GetAttribute("SiteAnchor") ~= nil
	local first = proj.actions[1]
	local prompt = Builder.prompt(part, if investigate then "Inspect" else first.text, proj.name, 1.5, 10)
	prompt.Name = if investigate then "InspectPrompt" else "RepairPrompt"
	useKey(prompt)
	repairPrompts[projectId] = prompt
	prompt.Triggered:Connect(function(player)
		if not within(player, part, 14) or not Net.allow(player, "townUse", 2) then
			return
		end
		local site = part:GetAttribute("SiteAnchor") :: string?
		if site and ProgressionService.waitingOn(player, "investigate", site) then
			ProgressionService.event(player, "investigate", site)
			return
		end
		if site and ProgressionService.waitingOn(player, "reach", site) then
			ProgressionService.event(player, "reach", site)
			return
		end
		local ok, message = ProgressionService.repair(player, projectId)
		if message ~= "" then
			notify(player, message, if ok then "good" else "info")
		end
		if ok then
			Net.event("SoundCue"):FireAllClients("chop", part.Position, 0.8)
		end
	end)
end

local function shopPrompt(part: BasePart, vendor: string)
	local prompt = Builder.prompt(part, "Browse", TownService.name(vendor) .. "'s counter", 0, 10)
	prompt.Name = "ShopPrompt"
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonL2
	prompt.Triggered:Connect(function(player)
		if not within(player, part, 14) or not Net.allow(player, "shop", 2) then
			return
		end
		local offers = ProgressionService.offers(player, vendor)
		if #offers == 0 then
			TownService.say(player, { TownService.name(vendor) .. ": Nothing to sell yet, sorry." })
			return
		end
		local p = ProgressionService.get(player)
		Net.event("Shop")
			:FireClient(player, vendor, TownService.name(vendor), offers, if p then p.town.credits else 0)
	end)
end

-- Start ----------------------------------------------------------------------------

function TownService.start()
	ProgressionService.setLocator(locate)
	MayaService.setTalkHook(mayaHook)

	for _, id in TownConfig.Order do
		local spec = TownConfig.Npcs[id]
		-- Rigs load catalog assets and yield: keep server start fast.
		task.spawn(setupNpc, id, spec)
	end
	for _, part in TownWorld.find("Interaction") do
		local id = part:GetAttribute("Interaction") :: string
		if id == "DinerStove" then
			interactPrompt(part, id, "Cook", "Diner stove", 1.5)
		elseif id == "BiscuitScarf" then
			interactPrompt(part, id, "Let Caramelo smell", "Biscuit's scarf", 1)
		end
	end
	local house = MayaService.house()
	local tbl = house and house:FindFirstChild("Table")
	if tbl and tbl:IsA("BasePart") then
		mayaTable = tbl
		interactPrompt(tbl, "MayaTable", "Sit down", "Maya's table", 1)
	end
	for _, part in TownWorld.find("RepairProject") do
		repairPrompt(part, part:GetAttribute("RepairProject") :: string)
	end
	for _, part in TownWorld.find("ShopVendor") do
		shopPrompt(part, part:GetAttribute("ShopVendor") :: string)
	end

	ProgressionService.onChanged(function()
		refreshWorld()
	end)
	ProgressionService.onQuestCompleted(function(player: Player, questId: string)
		local def = ProgressionService.def(questId)
		if def and def.outro then
			TownService.say(player, def.outro)
		end
		refreshWorld()
	end)
	ProgressionService.onProjectAdvanced(
		function(player: Player, projectId: string, _stage: number, finished: boolean)
			local proj = ProgressionService.project(projectId)
			if finished and proj and proj.ack then
				local line = proj.ack.line
				task.delay(4, function()
					if player.Parent then
						Net.event("Radio"):FireClient(player, line)
					end
				end)
			end
			refreshWorld()
		end
	)
	TimeService.onPhaseChanged(function(snap: any)
		refreshWorld()
		-- Maya remembers supper on later nights (never during the day-1 lesson).
		if snap.phase == "Night" and snap.day >= 2 then
			for _, p in ProgressionService.all() do
				if p.log.flags.sharedMeal and math.random() < 0.5 then
					local player = p.player
					task.delay(20, function()
						if player.Parent then
							Net.event("Radio"):FireClient(
								player,
								"Maya: My lamp's on. Thanks again for supper. Sleep well over there."
							)
						end
					end)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		queues[player] = nil
		task.delay(1, refreshWorld)
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 0.3 then
			acc = 0
			local ok, err = pcall(tickBiscuits :: any)
			if not ok then
				warn("[Town] " .. tostring(err))
			end
		end
	end)
	refreshWorld()
end

return TownService

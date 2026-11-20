--!strict
-- Server handlers for every world interaction: the cabin door, windows
-- (curtains, latches, quiet vs. fast closing, repairs, shutters), lights and
-- house power, the fireplace, the bed, the radios, the wardrobe and the story
-- props. Every action is distance-checked, rate-limited and makes the noise
-- it should.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local StoryConfig = require(ReplicatedStorage.Shared.Config.StoryConfig)
local LightService = require(script.Parent.LightService)
local NoiseService = require(script.Parent.NoiseService)
local PlayerService = require(script.Parent.PlayerService)
local StoryService = require(script.Parent.StoryService)
local TimeService = require(script.Parent.TimeService)

local InteractionService = {}

local FIRE_SECONDS_PER_FUEL = 300
local FIRE_MAX = 900

local function notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

local function cue(name: string, pos: Vector3?, volume: number?)
	Net.event("SoundCue"):FireAllClients(name, pos, volume)
end

local function partOf(prompt: ProximityPrompt): BasePart?
	local p = prompt.Parent
	return if p and p:IsA("BasePart") then p else nil
end

-- Engine checks prompt range too; this guards against stale or forged triggers.
local function near(player: Player, prompt: ProximityPrompt): boolean
	local root = PlayerService.root(player)
	local part = partOf(prompt)
	if not root or not part or not PlayerService.isActive(player) then
		return false
	end
	return (root.Position - part.Position).Magnitude <= prompt.MaxActivationDistance + 6
		and Net.allow(player, "prompt", 6)
end

local function addUpgrade()
	ReplicatedStorage:SetAttribute(
		"CabinUpgrades",
		((ReplicatedStorage:GetAttribute("CabinUpgrades") :: number?) or 0) + 1
	)
end

local function newPrompt(
	parent: Instance,
	name: string,
	action: string,
	object: string,
	key: Enum.KeyCode,
	hold: number,
	offset: number
): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = key
	p.HoldDuration = hold
	p.MaxActivationDistance = 7
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Custom
	p.UIOffset = Vector2.new(0, offset)
	p.Parent = parent
	return p
end

-- Door --------------------------------------------------------------------------

type DoorRec = {
	model: Model,
	panel: BasePart,
	bands: { [BasePart]: CFrame },
	broken: BasePart?,
	prompt: ProximityPrompt,
	upgrade: ProximityPrompt,
}

local function doorPanelCFrame(rec: DoorRec, open: boolean): CFrame
	local closed = rec.panel:GetAttribute("ClosedCFrame") :: CFrame
	if not open then
		return closed
	end
	local hinge = rec.panel:GetAttribute("HingeCFrame") :: CFrame
	return hinge * CFrame.Angles(0, math.rad(88), 0) * hinge:ToObjectSpace(closed)
end

local function refreshDoor(rec: DoorRec)
	local m = rec.model
	local installed = m:GetAttribute("Installed") == true
	local health = (m:GetAttribute("Health") :: number?) or 0
	local breached = installed and health <= 0
	local open = m:GetAttribute("Open") == true
	local reinforced = m:GetAttribute("Tier") == "reinforced"
	local present = installed and not breached
	rec.panel.CFrame = doorPanelCFrame(rec, open and present)
	rec.panel.Transparency = if present then 0 else 1
	rec.panel.CanCollide = present
	rec.panel.CanQuery = present
	for band, offset in rec.bands do
		band.CFrame = rec.panel.CFrame * offset
		band.Transparency = if present and reinforced then 0 else 1
	end
	if rec.broken then
		rec.broken.Transparency = if installed then 1 else 0
		rec.broken.CanCollide = not installed
	end
	if not installed or breached then
		rec.prompt.ActionText = "Repair door (5 Wood)"
		rec.prompt.HoldDuration = 1
	else
		rec.prompt.ActionText = if open then "Close door" else "Open door"
		rec.prompt.HoldDuration = 0
	end
	rec.upgrade.Enabled = present and not reinforced and not open
end

local function setupDoor(model: Model)
	local panel = model:FindFirstChild("Panel")
	if not panel or not panel:IsA("BasePart") then
		return
	end
	local prompt = panel:FindFirstChild("DoorPrompt")
	local upgrade = panel:FindFirstChild("UpgradePrompt")
	if not (prompt and prompt:IsA("ProximityPrompt") and upgrade and upgrade:IsA("ProximityPrompt")) then
		return
	end
	local bands: { [BasePart]: CFrame } = {}
	local closed = panel:GetAttribute("ClosedCFrame") :: CFrame
	for _, c in model:GetChildren() do
		if c.Name == "Band" and c:IsA("BasePart") then
			for _, w in c:GetChildren() do
				if w:IsA("WeldConstraint") then
					w:Destroy()
				end
			end
			c.Anchored = true
			bands[c] = closed:ToObjectSpace(c.CFrame)
		end
	end
	local broken = model:FindFirstChild("BrokenDoor")
	local rec: DoorRec = {
		model = model,
		panel = panel,
		bands = bands,
		broken = if broken and broken:IsA("BasePart") then broken else nil,
		prompt = prompt,
		upgrade = upgrade,
	}
	prompt.Triggered:Connect(function(player)
		if not near(player, prompt) then
			return
		end
		local installed = model:GetAttribute("Installed") == true
		local health = (model:GetAttribute("Health") :: number?) or 0
		if not installed or health <= 0 then
			if PlayerService.spend(player, ItemConfig.Upgrades.RepairDoor.cost) then
				model:SetAttribute("Installed", true)
				model:SetAttribute("Health", (model:GetAttribute("MaxHealth") :: number?) or 100)
				model:SetAttribute("Open", false)
				if model:GetAttribute("Tier") == "weak" then
					model:SetAttribute("Tier", "standard")
				end
				NoiseService.emit(panel.Position, "chop", player)
				cue("craft", panel.Position)
				StoryService.setFact("doorRepaired", true)
				addUpgrade()
				notify(player, "The door hangs true again.", "good")
			end
			return
		end
		local open = not (model:GetAttribute("Open") == true)
		model:SetAttribute("Open", open)
		NoiseService.emit(panel.Position, "door", player)
		cue("door", panel.Position)
	end)
	upgrade.Triggered:Connect(function(player)
		if not near(player, upgrade) or model:GetAttribute("Tier") == "reinforced" then
			return
		end
		if PlayerService.spend(player, ItemConfig.Upgrades.ReinforceDoor.cost) then
			model:SetAttribute("Tier", "reinforced")
			model:SetAttribute("Health", (model:GetAttribute("MaxHealth") :: number?) or 100)
			NoiseService.emit(panel.Position, "chop", player)
			StoryService.setFact("cabinPrepared", true)
			addUpgrade()
			notify(player, "Iron bands across the door. It will hold.", "good")
		end
	end)
	model.AttributeChanged:Connect(function()
		refreshDoor(rec)
	end)
	refreshDoor(rec)
end

-- Windows -----------------------------------------------------------------------

type WindowRec = {
	model: Model,
	glass: BasePart,
	baseTransparency: number,
	curtains: { BasePart },
	shutter: BasePart?,
	board: BasePart?,
	observe: ProximityPrompt?,
	curtain: ProximityPrompt?,
	latch: ProximityPrompt?,
	closeQuiet: ProximityPrompt,
	slam: ProximityPrompt,
	repair: ProximityPrompt,
}

local function windowHealth(model: Instance): number
	return (model:GetAttribute("Health") :: number?) or 100
end

local function refreshWindow(rec: WindowRec)
	local m = rec.model
	local health = (m:GetAttribute("Health") :: number?) or 100
	local breached = health <= 0
	local open = m:GetAttribute("Open") == true
	local closedCurtains = m:GetAttribute("CurtainsClosed") == true
	local shuttered = m:GetAttribute("Shuttered") == true
	local shutterBuilt = rec.shutter ~= nil and rec.shutter:GetAttribute("Built") == true
	local latched = m:GetAttribute("Latched") == true
	local latchBroken = m:GetAttribute("LatchBroken") == true

	rec.glass.Transparency = if breached or open then 1 else rec.baseTransparency
	rec.glass.CanCollide = not breached and not open
	for _, c in rec.curtains do
		local offset = (c:GetAttribute(if closedCurtains then "ClosedOffset" else "OpenOffset") :: number?)
			or 0
		local width = (c:GetAttribute(if closedCurtains then "ClosedWidth" else "OpenWidth") :: number?) or 1
		c.Size = Vector3.new(width, c.Size.Y, c.Size.Z)
		c.CFrame = rec.glass.CFrame * CFrame.new(offset, 0, 0.9)
		c.CanQuery = closedCurtains
	end
	if rec.shutter then
		rec.shutter.Transparency = if shutterBuilt and shuttered then 0 else 1
		rec.shutter.CanCollide = shutterBuilt and shuttered
		rec.shutter.CanQuery = shutterBuilt and shuttered
	end
	if rec.board then
		rec.board.Transparency = if health < 100 and not breached then 0 else 1
	end

	if rec.observe then
		rec.observe.Enabled = not shuttered and not open
	end
	if rec.curtain then
		rec.curtain.Enabled = not open or breached
		rec.curtain.ActionText = if closedCurtains then "Open curtains" else "Close curtains"
	end
	if rec.latch then
		rec.latch.Enabled = not open and not breached
		if shutterBuilt then
			rec.latch.ActionText = if shuttered then "Open shutters" else "Close shutters"
		elseif latchBroken then
			rec.latch.ActionText = "Latch is broken"
		else
			rec.latch.ActionText = if latched then "Unlatch" else "Latch"
		end
	end
	rec.closeQuiet.Enabled = open and not breached
	rec.slam.Enabled = open and not breached
	if breached or health < 100 or latchBroken then
		rec.repair.Enabled = true
		rec.repair.ActionText = "Repair window (2 Wood, 1 Scrap)"
	elseif not shutterBuilt then
		rec.repair.Enabled = not open
		rec.repair.ActionText = "Build shutters (4 Wood, 2 Fiber)"
	else
		rec.repair.Enabled = false
	end
end

local function setupWindow(model: Model)
	local glass = model:FindFirstChild("Glass")
	if not glass or not glass:IsA("BasePart") then
		return
	end
	local curtains = {}
	for _, c in model:GetChildren() do
		if c:IsA("BasePart") and string.sub(c.Name, 1, 7) == "Curtain" then
			table.insert(curtains, c)
		end
	end
	local function promptNamed(n: string): ProximityPrompt?
		local p = glass:FindFirstChild(n)
		return if p and p:IsA("ProximityPrompt") then p else nil
	end
	local shutter = model:FindFirstChild("Shutter")
	local board = model:FindFirstChild("Board")
	local rec: WindowRec = {
		model = model,
		glass = glass,
		baseTransparency = glass.Transparency,
		curtains = curtains,
		shutter = if shutter and shutter:IsA("BasePart") then shutter else nil,
		board = if board and board:IsA("BasePart") then board else nil,
		observe = promptNamed("ObservePrompt"),
		curtain = promptNamed("CurtainPrompt"),
		latch = promptNamed("LatchPrompt"),
		closeQuiet = newPrompt(
			glass,
			"CloseQuietPrompt",
			"Close quietly",
			"Open window",
			Enum.KeyCode.E,
			2,
			0
		),
		slam = newPrompt(glass, "SlamPrompt", "Slam shut", "Open window", Enum.KeyCode.R, 0, 70),
		repair = newPrompt(glass, "RepairPrompt", "Repair window", "Window", Enum.KeyCode.V, 1.5, 210),
	}
	rec.baseTransparency = if windowHealth(model) < 100 then 0.45 else 0.6

	if rec.curtain then
		local p = rec.curtain
		p.Triggered:Connect(function(player)
			if not near(player, p) then
				return
			end
			local closed = not (model:GetAttribute("CurtainsClosed") == true)
			model:SetAttribute("CurtainsClosed", closed)
			NoiseService.emit(glass.Position, "curtain", player)
			cue("curtain", glass.Position, 0.6)
			local phase = TimeService.snapshot().phase
			if closed and (phase == "Dusk" or phase == "Night") then
				PlayerService.markRoutine(player, "curtains")
			end
		end)
	end
	if rec.latch then
		local p = rec.latch
		p.Triggered:Connect(function(player)
			if not near(player, p) then
				return
			end
			if rec.shutter and rec.shutter:GetAttribute("Built") == true then
				model:SetAttribute("Shuttered", not (model:GetAttribute("Shuttered") == true))
				NoiseService.emit(glass.Position, "door", player)
				cue("latch", glass.Position)
				return
			end
			if model:GetAttribute("LatchBroken") == true then
				notify(player, "The latch is broken. Repair the window.", "info")
				return
			end
			model:SetAttribute("Latched", not (model:GetAttribute("Latched") == true))
			NoiseService.emit(glass.Position, "switch", player)
			cue("latch", glass.Position, 0.6)
		end)
	end
	rec.closeQuiet.Triggered:Connect(function(player)
		if not near(player, rec.closeQuiet) or windowHealth(model) <= 0 then
			return
		end
		model:SetAttribute("Open", false)
		model:SetAttribute("ForcedOpen", nil)
		NoiseService.emit(glass.Position, "curtain", player)
		cue("latch", glass.Position, 0.3)
	end)
	rec.slam.Triggered:Connect(function(player)
		if not near(player, rec.slam) or windowHealth(model) <= 0 then
			return
		end
		model:SetAttribute("Open", false)
		model:SetAttribute("ForcedOpen", nil)
		NoiseService.emit(glass.Position, "doorSlam", player)
		cue("doorSlam", glass.Position)
	end)
	rec.repair.Triggered:Connect(function(player)
		if not near(player, rec.repair) then
			return
		end
		local health = (model:GetAttribute("Health") :: number?) or 100
		if health < 100 or model:GetAttribute("LatchBroken") == true then
			if PlayerService.spend(player, ItemConfig.Upgrades.RepairWindow.cost) then
				model:SetAttribute("Health", 100)
				model:SetAttribute("LatchBroken", false)
				model:SetAttribute("Latched", true)
				model:SetAttribute("Open", false)
				rec.baseTransparency = 0.6
				NoiseService.emit(glass.Position, "chop", player)
				StoryService.setFact("cabinPrepared", true)
				addUpgrade()
				notify(player, "New glass, a working latch.", "good")
			end
		elseif rec.shutter and rec.shutter:GetAttribute("Built") ~= true then
			if PlayerService.spend(player, ItemConfig.Upgrades.ShutterWindow.cost) then
				rec.shutter:SetAttribute("Built", true)
				model:SetAttribute("Shuttered", true)
				model:SetAttribute("Tier", "shutter")
				NoiseService.emit(glass.Position, "chop", player)
				StoryService.setFact("cabinPrepared", true)
				addUpgrade()
				notify(player, "Storm shutters. Close them with R.", "good")
			end
		end
		refreshWindow(rec)
	end)
	model.AttributeChanged:Connect(function()
		refreshWindow(rec)
	end)
	refreshWindow(rec)
end

-- Lights, power ---------------------------------------------------------------------

local function findLight(scope: Instance, name: string): Instance?
	for _, d in scope:GetDescendants() do
		if d.Name == name and CollectionService:HasTag(d, "StillnessLight") then
			return d
		end
	end
	return nil
end

local function labelFor(prompt: ProximityPrompt, light: Instance)
	local stored = prompt:GetAttribute("BaseLabel")
	local base: string
	if type(stored) == "string" then
		base = stored
	else
		base = (string.gsub(string.gsub(prompt.ActionText, " off$", ""), " on$", ""))
		prompt:SetAttribute("BaseLabel", base)
	end
	prompt.ActionText = base .. (if light:GetAttribute("On") == true then " off" else " on")
end

local function setupSwitch(prompt: ProximityPrompt, scope: Instance)
	local target = prompt:GetAttribute("Target") :: string?
	if not target then
		return
	end
	local light = findLight(scope, target)
	if not light then
		return
	end
	labelFor(prompt, light)
	prompt.Triggered:Connect(function(player)
		if not near(player, prompt) then
			return
		end
		LightService.toggle(light)
		labelFor(prompt, light)
		local part = partOf(prompt) :: BasePart
		NoiseService.emit(part.Position, "switch", player)
		cue("switch", part.Position, 0.5)
	end)
end

local function setupPower(prompt: ProximityPrompt, cabin: Model)
	local circuit = (cabin:GetAttribute("ShelterId") :: string?) or "Cabin"
	local function label()
		prompt.ActionText = if LightService.hasPower(circuit)
			then "Switch off house power"
			else "Switch on house power"
	end
	label()
	prompt.Triggered:Connect(function(player)
		if not near(player, prompt) then
			return
		end
		local on = not LightService.hasPower(circuit)
		LightService.setPower(circuit, on)
		cabin:SetAttribute("Power", on)
		label()
		local part = partOf(prompt) :: BasePart
		NoiseService.emit(part.Position, "switch", player, 10)
		cue("switch", part.Position)
	end)
end

-- Fireplace -------------------------------------------------------------------------

local function fireParts(core: BasePart): (Fire?, Smoke?)
	local fire = core:FindFirstChildOfClass("Fire")
	local smoke: Smoke? = nil
	local fp = core.Parent
	if fp then
		local chimney = fp:FindFirstChild("Chimney")
		if chimney then
			smoke = chimney:FindFirstChildOfClass("Smoke")
		end
	end
	return fire, smoke
end

local function setFire(core: BasePart, on: boolean)
	local fire, smoke = fireParts(core)
	if fire then
		fire.Enabled = on
	end
	if smoke then
		smoke.Enabled = on
	end
	LightService.set(core, on)
end

local function setupFireplace(core: BasePart, firePrompt: ProximityPrompt, cookPrompt: ProximityPrompt?)
	local function label()
		local fuel = (core:GetAttribute("Fuel") :: number?) or 0
		firePrompt.ActionText = if fuel > 0 then "Add firewood (2 Wood)" else "Light fire (2 Wood)"
		if cookPrompt then
			cookPrompt.Enabled = fuel > 0
		end
	end
	label()
	firePrompt.Triggered:Connect(function(player)
		if not near(player, firePrompt) then
			return
		end
		local fuel = (core:GetAttribute("Fuel") :: number?) or 0
		if fuel >= FIRE_MAX - 30 then
			notify(player, "The fire is already roaring.", "info")
			return
		end
		if PlayerService.spend(player, ItemConfig.Upgrades.FuelFire.cost) then
			local wasOut = fuel <= 0
			core:SetAttribute("Fuel", math.min(fuel + FIRE_SECONDS_PER_FUEL, FIRE_MAX))
			setFire(core, true)
			if wasOut then
				cue("fireIgnite", core.Position)
				PlayerService.markRoutine(player, "fire")
			end
			StoryService.setFact("fireLit", true)
			NoiseService.emit(core.Position, "cabinet", player)
			label()
		end
	end)
	if cookPrompt then
		local cp = cookPrompt
		cp.Triggered:Connect(function(player)
			if not near(player, cp) then
				return
			end
			for _, r in ItemConfig.Recipes do
				if r.id == "stew" and PlayerService.spend(player, r.cost) then
					for item, n in r.gives do
						PlayerService.give(player, item, n)
					end
					NoiseService.emit(core.Position, "cabinet", player)
					notify(player, "The stew is ready. Eat it from your pack (Tab).", "good")
				end
			end
		end)
	end
	RunService.Heartbeat:Connect(function(dt: number)
		local fuel = (core:GetAttribute("Fuel") :: number?) or 0
		if fuel > 0 then
			local scale = (ReplicatedStorage:GetAttribute("TimeScale") :: number?) or 1
			fuel -= dt * math.clamp(scale, 0, 200)
			if fuel <= 0 then
				core:SetAttribute("Fuel", 0)
				setFire(core, false)
				label()
			else
				core:SetAttribute("Fuel", fuel)
			end
		end
	end)
end

-- Story props ---------------------------------------------------------------------------

local function radioText(): string
	local nightType = ReplicatedStorage:GetAttribute("NightType")
	local phase = TimeService.snapshot().phase
	local night = phase == "Dusk" or phase == "Night"
	if night and (nightType == "Bad" or nightType == "Black") then
		return "Static... '...stay dark. Lights off. Curtains shut. Don't move when they're close. They talk to each other. They hear you breathe.'"
	end
	if ReplicatedStorage:GetAttribute("Weather") == "Storm" then
		return "Static... '...severe weather. Latch your windows. Wind will open what isn't locked.'"
	end
	if StoryService.getFact("radioFound") then
		if StoryService.getFact("survivedNight3") then
			return "The voice again, clearer: '...north of the ridge. By daylight. North.'"
		end
		return "On the scratched frequency: '...if you can hear this, you are not alone out there. Keep the fire small.'"
	end
	return "Only static. Somewhere under it, something like a voice."
end

local function setupProps(world: Instance)
	for _, prompt in world:GetDescendants() do
		if not prompt:IsA("ProximityPrompt") then
			continue
		end
		local p: ProximityPrompt = prompt
		local part = partOf(p)
		if not part then
			continue
		end
		if p.Name == "SleepPrompt" then
			p.Triggered:Connect(function(player)
				if not near(player, p) then
					return
				end
				local phase = TimeService.snapshot().phase
				local nightType = ReplicatedStorage:GetAttribute("NightType")
				local s = PlayerService.get(player)
				if
					phase ~= "Night" and not (phase == "Dusk" and TimeService.snapshot().phaseProgress > 0.6)
				then
					notify(player, "You're not tired yet. Sleep comes after dark.", "info")
				elseif nightType == "Bad" or nightType == "Black" then
					notify(player, "You can't sleep. Something is out there tonight.", "warning")
				elseif not s or s.shelter == nil or not s.secure then
					notify(player, "Not with the house open like this.", "warning")
				elseif s.threat >= 2 then
					notify(player, "Not now.", "warning")
				else
					PlayerService.setSleeping(player, true)
					local all = true
					for _, other in PlayerService.all() do
						if other.spawned and not PlayerService.isSleeping(other.player) then
							all = false
						end
					end
					if all then
						Net.event("Notify")
							:FireAllClients("You sleep. The rain keeps time on the roof.", "good")
						TimeService.skipToPhase("Dawn")
						for _, other in PlayerService.all() do
							PlayerService.setSleeping(other.player, false)
						end
					else
						notify(player, "You lie down. Waiting for the others.", "info")
					end
				end
			end)
		elseif p.Name == "RadioPrompt" then
			p.Triggered:Connect(function(player)
				if near(player, p) then
					Net.event("Radio"):FireClient(player, radioText())
					cue("radioStatic", part.Position, 0.6)
					NoiseService.emit(part.Position, "radio", player)
				end
			end)
		elseif p.Name == "WardrobePrompt" then
			p.Triggered:Connect(function(player)
				if not near(player, p) then
					return
				end
				NoiseService.emit(part.Position, "cabinet", player)
				local s = PlayerService.get(player)
				if s and not s.coatFound then
					PlayerService.setCoatFound(player)
					Net.event("Note"):FireClient(player, "The coat", StoryConfig.Notes.coat)
					StoryService.setFact("coatFound", true)
					notify(player, "Press Q to wear the coat.", "good")
				else
					notify(player, "Dust, and an empty hanger.", "info")
				end
			end)
		elseif p.Name == "LootPrompt" then
			p.Triggered:Connect(function(player)
				if not near(player, p) or part:GetAttribute("Looted") == true then
					return
				end
				part:SetAttribute("Looted", true)
				p.Enabled = false
				PlayerService.give(player, "Binoculars", 1)
				PlayerService.give(player, "Scrap", 3)
				NoiseService.emit(part.Position, "cabinet", player, 14)
				StoryService.setFact("lootedHouse", true)
				Net.event("Note"):FireClient(
					player,
					"An old crate",
					"Binoculars wrapped in oilcloth, and some scrap metal. Someone kept watch from here once."
				)
			end)
		elseif p.Name == "SignalPrompt" then
			p.Triggered:Connect(function(player)
				if not near(player, p) then
					return
				end
				StoryService.setFact("radioFound", true)
				Net.event("Note"):FireClient(player, "The signal", StoryConfig.Notes.radio)
				NoiseService.emit(part.Position, "radio", player)
				cue("radioVoice", part.Position)
			end)
		elseif p.Name == "CluePrompt" then
			p.Triggered:Connect(function(player)
				if not near(player, p) then
					return
				end
				StoryService.setFact("lakeHouseInvestigated", true)
				Net.event("Note"):FireClient(player, "A journal", StoryConfig.Notes.lakeHouse)
			end)
		end
	end
end

-- Crafting at the workbench ------------------------------------------------------------

local function craft(player: Player, recipeId: any)
	if type(recipeId) ~= "string" or not Net.allow(player, "craft", 2) then
		return
	end
	local root = PlayerService.root(player)
	if not root then
		return
	end
	for _, r in ItemConfig.Recipes do
		if r.id == recipeId then
			local ok = false
			if r.station == "workbench" then
				for _, b in CollectionService:GetTagged("Workbench") do
					if b:IsA("BasePart") and (b.Position - root.Position).Magnitude < 12 then
						ok = true
					end
				end
			elseif r.station == "fireplace" then
				for _, f in CollectionService:GetTagged("Fireplace") do
					if
						f:IsA("BasePart")
						and f:GetAttribute("Lit") == true
						and (f.Position - root.Position).Magnitude < 14
					then
						ok = true
					end
				end
			end
			if not ok then
				notify(player, "You need to be at the " .. r.station .. ".", "info")
				return
			end
			if PlayerService.spend(player, r.cost) then
				for item, n in r.gives do
					PlayerService.give(player, item, n)
				end
				NoiseService.emit(root.Position, "cabinet", player)
				cue("craft", root.Position)
				notify(player, "Made: " .. r.name, "good")
			end
			return
		end
	end
end

function InteractionService.start()
	local world = workspace:WaitForChild("World")
	for _, d in CollectionService:GetTagged("Door") do
		if d:IsA("Model") then
			setupDoor(d)
		end
	end
	for _, w in CollectionService:GetTagged("Window") do
		if w:IsA("Model") then
			setupWindow(w)
		end
	end
	for _, shelter in CollectionService:GetTagged("Shelter") do
		for _, d in shelter:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				if d.Name == "SwitchPrompt" or d.Name == "SwitchPrompt2" or d.Name == "LampPrompt" then
					setupSwitch(d, shelter)
				elseif d.Name == "PowerPrompt" and shelter:IsA("Model") then
					setupPower(d, shelter)
				end
			end
		end
	end
	for _, core in CollectionService:GetTagged("Fireplace") do
		if core:IsA("BasePart") then
			local fp = core.Parent
			local box = fp and fp:FindFirstChild("Firebox")
			local firePrompt = box and box:FindFirstChild("FirePrompt")
			local cookPrompt = box and box:FindFirstChild("CookPrompt")
			if firePrompt and firePrompt:IsA("ProximityPrompt") then
				setupFireplace(
					core,
					firePrompt,
					if cookPrompt and cookPrompt:IsA("ProximityPrompt") then cookPrompt else nil
				)
			end
		end
	end
	setupProps(world)
	Net.event("Craft").OnServerEvent:Connect(craft)
end

return InteractionService

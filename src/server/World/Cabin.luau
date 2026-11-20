--!strict
-- The starter cabin: the player's home and the shelter that the safety rules
-- revolve around. Built from registered modules (door, windows, roof) so the
-- shelter system can reason about each entry point explicitly.
--
-- Layout (local space, floor at y = 0, interior x -14..14, z -11..11):
--   south wall (+z): front door, small window
--   north wall (-z): large window looking across the lake
--   east wall  (+x): cracked window with a broken latch
--   west wall  (-x): fireplace and chimney

local CollectionService = game:GetService("CollectionService")

local Builder = require(script.Parent.Builder)

local Cabin = {}

local H = 11
local WOOD = Color3.fromRGB(104, 74, 50)
local WOOD_DARK = Color3.fromRGB(74, 52, 36)
local WOOD_LIGHT = Color3.fromRGB(140, 104, 72)
local STONE = Color3.fromRGB(110, 106, 100)
local FABRIC = Color3.fromRGB(122, 52, 44)
local CURTAIN = Color3.fromRGB(96, 48, 40)
local GLASS = Color3.fromRGB(160, 190, 200)
local WARM = Color3.fromRGB(255, 176, 110)

export type Built = {
	model: Model,
	origin: CFrame,
	volume: BasePart,
}

local function wall(
	parent: Instance,
	origin: CFrame,
	axis: "x" | "z",
	fixed: number,
	from: number,
	to: number,
	openings: { { number } }
)
	-- openings: { center, width, bottom, top }, along the wall axis
	table.sort(openings, function(a, b)
		return a[1] < b[1]
	end)
	local function seg(a: number, b: number, y0: number, y1: number)
		if b - a < 0.05 or y1 - y0 < 0.05 then
			return
		end
		local mid = (a + b) / 2
		local cy = (y0 + y1) / 2
		local size, pos
		if axis == "x" then
			size = Vector3.new(b - a, y1 - y0, 1)
			pos = Vector3.new(mid, cy, fixed)
		else
			size = Vector3.new(1, y1 - y0, b - a)
			pos = Vector3.new(fixed, cy, mid)
		end
		Builder.part({
			name = "Wall",
			size = size,
			cframe = origin * CFrame.new(pos),
			color = WOOD,
			material = Enum.Material.WoodPlanks,
			parent = parent,
		})
	end
	local cursor = from
	for _, o in openings do
		local c, w, bottom, top = o[1], o[2], o[3], o[4]
		seg(cursor, c - w / 2, 0, H)
		seg(c - w / 2, c + w / 2, 0, bottom)
		seg(c - w / 2, c + w / 2, top, H)
		cursor = c + w / 2
	end
	seg(cursor, to, 0, H)
end

local function setEntry(
	inst: Instance,
	kind: string,
	id: string,
	health: number,
	maxHealth: number,
	installed: boolean
)
	inst:SetAttribute("EntryId", id)
	inst:SetAttribute("EntryKind", kind)
	inst:SetAttribute("Installed", installed)
	inst:SetAttribute("Open", false)
	inst:SetAttribute("Health", health)
	inst:SetAttribute("MaxHealth", maxHealth)
	inst:SetAttribute("Shelter", "Cabin")
	CollectionService:AddTag(inst, "EntryPoint")
end

local function buildWindow(
	parent: Instance,
	origin: CFrame,
	id: string,
	center: Vector3, -- local center of the opening
	outward: Vector3, -- local unit vector pointing outside
	width: number,
	height: number,
	health: number,
	latched: boolean,
	latchBroken: boolean
): Model
	local m = Builder.model("Window_" .. id, parent)
	local facing = origin * CFrame.lookAt(center, center + outward) -- -Z of this frame points outside
	local glass = Builder.part({
		name = "Glass",
		size = Vector3.new(width, height, 0.2),
		cframe = facing,
		color = GLASS,
		material = Enum.Material.Glass,
		transparency = if health < 100 then 0.45 else 0.6,
		canQuery = false,
		castShadow = false,
		parent = m,
	})
	-- Frame
	for _, s in { -1, 1 } do
		Builder.part({
			name = "FrameSide",
			size = Vector3.new(0.35, height + 0.7, 1.2),
			cframe = facing * CFrame.new(s * (width / 2 + 0.17), 0, 0),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = m,
		})
		Builder.part({
			name = "FrameRail",
			size = Vector3.new(width + 0.7, 0.35, 1.2),
			cframe = facing * CFrame.new(0, s * (height / 2 + 0.17), 0),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = m,
		})
	end
	Builder.part({
		name = "Mullion",
		size = Vector3.new(0.2, height, 0.3),
		cframe = facing,
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		canQuery = false,
		castShadow = false,
		parent = m,
	})
	-- Curtains hang inside (+Z of facing is inside). Closed = full cover.
	local curtainHalf = width / 2 + 0.3
	for i, s in { -1, 1 } do
		local c = Builder.part({
			name = "Curtain" .. i,
			size = Vector3.new(0.9, height + 0.6, 0.15),
			cframe = facing * CFrame.new(s * (width / 2 + 0.35), 0, 0.9),
			color = CURTAIN,
			material = Enum.Material.Fabric,
			canCollide = false,
			canQuery = false,
			parent = m,
		})
		c:SetAttribute("OpenOffset", s * (width / 2 + 0.35))
		c:SetAttribute("ClosedOffset", s * (curtainHalf / 2))
		c:SetAttribute("ClosedWidth", curtainHalf + 0.2)
		c:SetAttribute("OpenWidth", 0.9)
	end
	-- Exterior shutters, hidden until built.
	local shutter = Builder.part({
		name = "Shutter",
		size = Vector3.new(width + 0.6, height + 0.6, 0.4),
		cframe = facing * CFrame.new(0, 0, -0.9),
		color = WOOD_DARK,
		material = Enum.Material.WoodPlanks,
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = m,
	})
	shutter:SetAttribute("Built", false)
	-- A plank nailed across a damaged window.
	if health < 100 then
		Builder.part({
			name = "Board",
			size = Vector3.new(width + 0.4, 0.5, 0.2),
			cframe = facing * CFrame.new(0, 0.4, -0.35) * CFrame.Angles(0, 0, math.rad(12)),
			color = WOOD_LIGHT,
			material = Enum.Material.Wood,
			canQuery = false,
			parent = m,
		})
	end
	-- Observation camera: inside, eye height, looking out.
	local inside = center - outward * 1.6
	local eye = Vector3.new(inside.X, 4.8, inside.Z)
	Builder.attachment(
		glass,
		"ObservePoint",
		glass.CFrame:ToObjectSpace(origin * CFrame.lookAt(eye, eye + outward))
	)
	-- Where a creature stands to look in.
	local watch = center + outward * 9
	local watchPart = Builder.part({
		name = "WatchPoint",
		size = Vector3.new(1, 1, 1),
		cframe = origin * CFrame.lookAt(Vector3.new(watch.X, 2, watch.Z), Vector3.new(center.X, 2, center.Z)),
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = m,
	})
	watchPart:SetAttribute("Window", id)
	-- Where a creature lands after climbing through.
	local landing = center - outward * 3
	Builder.part({
		name = "InsidePoint",
		size = Vector3.new(1, 1, 1),
		cframe = origin * CFrame.new(landing.X, 2.5, landing.Z),
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = m,
	})

	m.PrimaryPart = glass
	setEntry(m, "window", id, health, 100, true)
	m:SetAttribute("Latched", latched)
	m:SetAttribute("LatchBroken", latchBroken)
	m:SetAttribute("CurtainsClosed", false)
	m:SetAttribute("Shuttered", false)
	m:SetAttribute("Tier", "standard")
	m:SetAttribute("Wet", 0)
	CollectionService:AddTag(m, "Window")

	local prompt = Builder.prompt(glass, "Look outside", "Window", 0, 7)
	prompt.Name = "ObservePrompt"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("ClientAction", "Observe")
	local curtainPrompt = Builder.prompt(glass, "Close curtains", "Window", 0, 7)
	curtainPrompt.Name = "CurtainPrompt"
	curtainPrompt.KeyboardKeyCode = Enum.KeyCode.F
	curtainPrompt.UIOffset = Vector2.new(0, 70)
	local latchPrompt = Builder.prompt(glass, "Latch", "Window", 0, 7)
	latchPrompt.Name = "LatchPrompt"
	latchPrompt.KeyboardKeyCode = Enum.KeyCode.R
	latchPrompt.UIOffset = Vector2.new(0, 140)
	return m
end

local function buildDoor(parent: Instance, origin: CFrame): Model
	local m = Builder.model("Door", parent)
	local hinge = origin * CFrame.new(1.5, 0, 11.5) -- left edge of the opening
	local panel = Builder.part({
		name = "Panel",
		size = Vector3.new(5, 8, 0.45),
		cframe = hinge * CFrame.new(2.5, 4, 0),
		color = WOOD_LIGHT,
		material = Enum.Material.WoodPlanks,
		parent = m,
	})
	panel:SetAttribute("ClosedCFrame", panel.CFrame)
	panel:SetAttribute("HingeCFrame", hinge)
	for i = 1, 3 do
		local band = Builder.part({
			name = "Band",
			size = Vector3.new(5.1, 0.4, 0.55),
			cframe = panel.CFrame * CFrame.new(0, -3 + (i - 1) * 3, 0),
			color = Color3.fromRGB(58, 58, 60),
			material = Enum.Material.Metal,
			canCollide = false,
			canQuery = false,
			transparency = 1,
			parent = m,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = panel
		weld.Part1 = band
		weld.Parent = band
	end
	-- The broken door lies in the grass at the start.
	local broken = Builder.part({
		name = "BrokenDoor",
		size = Vector3.new(5, 0.45, 7.6),
		cframe = origin * CFrame.new(6.5, -1.3, 16) * CFrame.Angles(0, math.rad(18), math.rad(4)),
		color = WOOD_LIGHT,
		material = Enum.Material.WoodPlanks,
		parent = m,
	})
	broken:SetAttribute("Decor", true)
	m.PrimaryPart = panel
	setEntry(m, "door", "Door", 0, 100, false)
	m:SetAttribute("Tier", "weak")
	CollectionService:AddTag(m, "Door")
	local prompt = Builder.prompt(panel, "Repair door (5 Wood)", "Door", 0.8, 10)
	prompt.Name = "DoorPrompt"
	local upgrade = Builder.prompt(panel, "Reinforce (4 Wood, 3 Stone, 2 Scrap)", "Door", 1.5, 10)
	upgrade.Name = "UpgradePrompt"
	upgrade.KeyboardKeyCode = Enum.KeyCode.R
	upgrade.UIOffset = Vector2.new(0, 70)
	upgrade.Enabled = false
	-- Missing door: panel is not there yet.
	panel.Transparency = 1
	panel.CanCollide = false
	return m
end

local function light(
	parent: Instance,
	name: string,
	cframe: CFrame,
	size: Vector3,
	range: number,
	brightness: number,
	on: boolean,
	electric: boolean,
	indoor: boolean,
	shadows: boolean
): Part
	local bulb = Builder.part({
		name = name,
		size = size,
		cframe = cframe,
		color = Color3.fromRGB(255, 222, 170),
		material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		canCollide = false,
		castShadow = false,
		parent = parent,
	})
	local l = Builder.pointLight(bulb, WARM, range, brightness, shadows)
	l.Enabled = on
	bulb:SetAttribute("On", on)
	bulb:SetAttribute("Electric", electric)
	bulb:SetAttribute("Indoor", indoor)
	bulb:SetAttribute("Circuit", "Cabin")
	bulb:SetAttribute("Shelter", "Cabin")
	bulb:SetAttribute("Brightness", brightness)
	CollectionService:AddTag(bulb, "StillnessLight")
	return bulb
end

function Cabin.build(parent: Instance, position: Vector3): Built
	local model = Builder.model("Cabin", parent)
	local origin = CFrame.new(position)
	local structure = Builder.folder("Structure", model)

	-- Floor and foundation
	Builder.part({
		name = "Floor",
		size = Vector3.new(30, 1, 24),
		cframe = origin * CFrame.new(0, -0.5, 0),
		color = WOOD_LIGHT,
		material = Enum.Material.WoodPlanks,
		parent = structure,
	})
	for _, p in { { -14, -11 }, { 14, -11 }, { -14, 11 }, { 14, 11 }, { 0, -11 }, { 0, 11 } } do
		Builder.part({
			name = "Foundation",
			size = Vector3.new(2.4, 9, 2.4),
			cframe = origin * CFrame.new(p[1], -5.5, p[2]),
			color = STONE,
			material = Enum.Material.Cobblestone,
			parent = structure,
		})
	end
	-- Porch step
	Builder.part({
		name = "Porch",
		size = Vector3.new(10, 1, 5),
		cframe = origin * CFrame.new(4, -0.6, 14.5),
		color = WOOD,
		material = Enum.Material.WoodPlanks,
		parent = structure,
	})
	Builder.part({
		name = "Step",
		size = Vector3.new(6, 1, 2.5),
		cframe = origin * CFrame.new(4, -1.6, 18),
		color = WOOD_DARK,
		material = Enum.Material.WoodPlanks,
		parent = structure,
	})

	-- Walls
	wall(structure, origin, "x", 11.5, -15, 15, { { 4, 5, 0, 8 }, { -7, 4, 3.5, 7.5 } })
	wall(structure, origin, "x", -11.5, -15, 15, { { -2, 9, 3, 8 } })
	wall(structure, origin, "z", 14.5, -11, 11, { { 0, 5, 3.5, 7.5 } })
	wall(structure, origin, "z", -14.5, -11, 11, {})
	-- Log corner posts for character
	for _, p in { { -14.5, -11.5 }, { 14.5, -11.5 }, { -14.5, 11.5 }, { 14.5, 11.5 } } do
		Builder.part({
			name = "CornerPost",
			size = Vector3.new(1.6, H, 1.6),
			cframe = origin * CFrame.new(p[1], H / 2, p[2]),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = structure,
		})
	end

	-- Roof: gable along X.
	local rise, run = 6, 12.8
	local slant = math.sqrt(rise * rise + run * run)
	local angle = math.atan2(rise, run)
	for _, s in { -1, 1 } do
		local roof = Builder.part({
			name = "Roof",
			size = Vector3.new(33, 0.8, slant + 0.6),
			cframe = origin * CFrame.new(0, H + rise / 2, s * run / 2) * CFrame.Angles(s * angle, 0, 0),
			color = Color3.fromRGB(66, 54, 48),
			material = Enum.Material.WoodPlanks,
			parent = structure,
		})
		roof:SetAttribute("RoofMaterial", "Wood")
	end
	Builder.part({
		name = "Ridge",
		size = Vector3.new(33.4, 0.8, 1),
		cframe = origin * CFrame.new(0, H + rise + 0.2, 0),
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		parent = structure,
	})
	for _, x in { -14.5, 14.5 } do
		Builder.wedge({
			name = "Gable",
			size = Vector3.new(1, rise, 11.5),
			cframe = origin * CFrame.new(x, H + rise / 2, 5.75) * CFrame.Angles(0, math.pi, 0),
			color = WOOD,
			material = Enum.Material.WoodPlanks,
			parent = structure,
		})
		Builder.wedge({
			name = "Gable",
			size = Vector3.new(1, rise, 11.5),
			cframe = origin * CFrame.new(x, H + rise / 2, -5.75),
			color = WOOD,
			material = Enum.Material.WoodPlanks,
			parent = structure,
		})
	end
	-- Ceiling beams
	for _, z in { -6, 0, 6 } do
		Builder.part({
			name = "Beam",
			size = Vector3.new(28, 0.8, 0.8),
			cframe = origin * CFrame.new(0, H - 0.4, z),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			canQuery = false,
			parent = structure,
		})
	end

	-- Fireplace and chimney (west wall)
	local fire = Builder.folder("Fireplace", model)
	Builder.part({
		name = "Hearth",
		size = Vector3.new(3, 6.5, 8),
		cframe = origin * CFrame.new(-12.5, 3.25, 0),
		color = STONE,
		material = Enum.Material.Cobblestone,
		parent = fire,
	})
	local firebox = Builder.part({
		name = "Firebox",
		size = Vector3.new(0.4, 3, 4),
		cframe = origin * CFrame.new(-10.85, 1.9, 0),
		color = Color3.fromRGB(22, 18, 16),
		material = Enum.Material.Slate,
		parent = fire,
	})
	Builder.part({
		name = "Mantel",
		size = Vector3.new(3.8, 0.5, 9),
		cframe = origin * CFrame.new(-12.2, 6.75, 0),
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		parent = fire,
	})
	Builder.part({
		name = "Chimney",
		size = Vector3.new(3.2, 22, 5),
		cframe = origin * CFrame.new(-16.2, 9, 0),
		color = STONE,
		material = Enum.Material.Cobblestone,
		parent = fire,
	})
	for i = 1, 3 do
		Builder.part({
			name = "Log",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(3, 0.6, 0.6),
			cframe = origin
				* CFrame.new(-10.4, 0.4 + (i == 3 and 0.5 or 0), (i - 2) * 0.7)
				* CFrame.Angles(0, math.rad(90 + i * 8), 0),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			canCollide = false,
			parent = fire,
		})
	end
	local flame = Builder.part({
		name = "FireCore",
		size = Vector3.new(1, 1, 1),
		cframe = origin * CFrame.new(-10.3, 1.1, 0),
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = fire,
	})
	local fx = Instance.new("Fire")
	fx.Heat = 6
	fx.Size = 3.5
	fx.Color = Color3.fromRGB(255, 140, 60)
	fx.SecondaryColor = Color3.fromRGB(255, 70, 20)
	fx.Enabled = false
	fx.Parent = flame
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(70, 66, 64)
	smoke.Opacity = 0.12
	smoke.RiseVelocity = 4
	smoke.Size = 3
	smoke.Enabled = false
	smoke.Parent = fire:FindFirstChild("Chimney") :: Instance
	local fireLight = Builder.pointLight(flame, Color3.fromRGB(255, 140, 70), 22, 2.2, true)
	fireLight.Enabled = false
	flame:SetAttribute("On", false)
	flame:SetAttribute("Electric", false)
	flame:SetAttribute("Indoor", true)
	flame:SetAttribute("Shelter", "Cabin")
	flame:SetAttribute("Brightness", 1.4)
	flame:SetAttribute("Fuel", 0)
	CollectionService:AddTag(flame, "StillnessLight")
	CollectionService:AddTag(flame, "Fireplace")
	local firePrompt = Builder.prompt(firebox, "Light fire (2 Wood)", "Fireplace", 0.6, 9)
	firePrompt.Name = "FirePrompt"
	local cookPrompt = Builder.prompt(firebox, "Cook stew (2 Berries, 1 Mushroom)", "Fireplace", 1.5, 9)
	cookPrompt.Name = "CookPrompt"
	cookPrompt.KeyboardKeyCode = Enum.KeyCode.R
	cookPrompt.UIOffset = Vector2.new(0, 70)
	cookPrompt.Enabled = false

	-- Door and windows
	local entries = Builder.folder("Entries", model)
	buildDoor(entries, origin)
	buildWindow(
		entries,
		origin,
		"North",
		Vector3.new(-2, 5.5, -11.5),
		Vector3.new(0, 0, -1),
		9,
		5,
		100,
		true,
		false
	)
	buildWindow(
		entries,
		origin,
		"East",
		Vector3.new(14.5, 5.5, 0),
		Vector3.new(1, 0, 0),
		5,
		4,
		40,
		false,
		true
	)
	buildWindow(
		entries,
		origin,
		"South",
		Vector3.new(-7, 5.5, 11.5),
		Vector3.new(0, 0, 1),
		4,
		4,
		100,
		false,
		false
	)
	-- The roof counts as an entry point that is always intact in this prototype.
	local roofEntry = Instance.new("Configuration")
	roofEntry.Name = "RoofEntry"
	roofEntry.Parent = entries
	setEntry(roofEntry, "roof", "Roof", 100, 100, true)

	-- Lights
	local lights = Builder.folder("Lights", model)
	local ceiling = light(
		lights,
		"CeilingLamp",
		origin * CFrame.new(0, H - 1.6, 0),
		Vector3.new(1.2, 0.6, 1.2),
		26,
		1.1,
		true,
		true,
		true,
		true
	)
	Builder.part({
		name = "LampCord",
		size = Vector3.new(0.1, 1.2, 0.1),
		cframe = origin * CFrame.new(0, H - 0.8, 0),
		color = Color3.fromRGB(30, 30, 30),
		canCollide = false,
		canQuery = false,
		parent = lights,
	})
	local porch = light(
		lights,
		"PorchLight",
		origin * CFrame.new(4, 9.3, 12.3),
		Vector3.new(0.8, 0.8, 0.5),
		20,
		1,
		true,
		true,
		false,
		false
	)
	-- Switches by the door
	local switchPlate = Builder.part({
		name = "LightSwitch",
		size = Vector3.new(0.6, 1, 0.2),
		cframe = origin * CFrame.new(7.4, 4.5, 10.85),
		color = Color3.fromRGB(220, 214, 200),
		parent = lights,
	})
	local s1 = Builder.prompt(switchPlate, "Ceiling light off", "Switch", 0, 7)
	s1.Name = "SwitchPrompt"
	s1:SetAttribute("Target", ceiling.Name)
	local s2 = Builder.prompt(switchPlate, "Porch light off", "Switch", 0, 7)
	s2.Name = "SwitchPrompt2"
	s2:SetAttribute("Target", porch.Name)
	s2.KeyboardKeyCode = Enum.KeyCode.R
	s2.UIOffset = Vector2.new(0, 70)
	local fuse = Builder.part({
		name = "FuseBox",
		size = Vector3.new(1.4, 2, 0.5),
		cframe = origin * CFrame.new(10, 5, 10.75),
		color = Color3.fromRGB(70, 74, 72),
		material = Enum.Material.Metal,
		parent = lights,
	})
	local fusePrompt = Builder.prompt(fuse, "Switch off house power", "Fuse box", 0.4, 7)
	fusePrompt.Name = "PowerPrompt"
	model:SetAttribute("Power", true)

	-- Furniture
	local furniture = Builder.folder("Furniture", model)
	Builder.part({
		name = "Rug",
		size = Vector3.new(11, 0.1, 7),
		cframe = origin * CFrame.new(-3, 0.05, -2),
		color = Color3.fromRGB(120, 60, 44),
		material = Enum.Material.Fabric,
		canCollide = false,
		parent = furniture,
	})
	-- Armchair facing the north window
	local chairCF = origin * CFrame.new(-2, 0, -5)
	local seat = Instance.new("Seat")
	seat.Name = "WindowChair"
	seat.Size = Vector3.new(3, 1, 3)
	seat.CFrame = chairCF * CFrame.new(0, 1.6, 0)
	seat.Anchored = true
	seat.Color = FABRIC
	seat.Material = Enum.Material.Fabric
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.Parent = furniture
	seat:SetAttribute("Comfort", true)
	CollectionService:AddTag(seat, "ComfortSeat")
	Builder.part({
		name = "ChairBack",
		size = Vector3.new(3, 3.4, 0.6),
		cframe = chairCF * CFrame.new(0, 3.3, 1.4),
		color = FABRIC,
		material = Enum.Material.Fabric,
		parent = furniture,
	})
	for _, s in { -1, 1 } do
		Builder.part({
			name = "ChairArm",
			size = Vector3.new(0.5, 1.2, 3),
			cframe = chairCF * CFrame.new(s * 1.6, 2.3, 0),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = furniture,
		})
		Builder.part({
			name = "Rocker",
			size = Vector3.new(0.3, 0.4, 3.6),
			cframe = chairCF * CFrame.new(s * 1.3, 0.25, 0),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = furniture,
		})
	end
	Builder.part({
		name = "ChairBase",
		size = Vector3.new(2.6, 1.1, 2.6),
		cframe = chairCF * CFrame.new(0, 0.75, 0),
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		parent = furniture,
	})
	-- Bed (NW corner)
	Builder.part({
		name = "BedFrame",
		size = Vector3.new(4.5, 1.4, 6),
		cframe = origin * CFrame.new(-11.2, 0.7, -7.8),
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		parent = furniture,
	})
	local blanket = Builder.part({
		name = "Blanket",
		size = Vector3.new(4.3, 0.6, 4.6),
		cframe = origin * CFrame.new(-11.2, 1.7, -7.2),
		color = Color3.fromRGB(70, 86, 110),
		material = Enum.Material.Fabric,
		parent = furniture,
	})
	Builder.part({
		name = "Pillow",
		size = Vector3.new(3.4, 0.6, 1.2),
		cframe = origin * CFrame.new(-11.2, 1.8, -10.1),
		color = Color3.fromRGB(220, 214, 196),
		material = Enum.Material.Fabric,
		parent = furniture,
	})
	local sleepPrompt = Builder.prompt(blanket, "Sleep until dawn", "Bed", 1.2, 8)
	sleepPrompt.Name = "SleepPrompt"
	local respawn = Builder.part({
		name = "BedRespawn",
		size = Vector3.new(1, 1, 1),
		cframe = origin * CFrame.new(-8, 3, -7.5),
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = furniture,
	})
	respawn:SetAttribute("Respawn", true)
	-- Dog bed near the fire
	local dogBed = Builder.part({
		name = "DogBed",
		size = Vector3.new(4, 0.7, 3.2),
		cframe = origin * CFrame.new(-8.6, 0.35, 6.5),
		color = Color3.fromRGB(150, 64, 52),
		material = Enum.Material.Fabric,
		parent = furniture,
	})
	CollectionService:AddTag(dogBed, "DogBed")
	-- Table with lamp and radio
	Builder.part({
		name = "TableTop",
		size = Vector3.new(5, 0.4, 3.4),
		cframe = origin * CFrame.new(4, 3.1, 2),
		color = WOOD,
		material = Enum.Material.Wood,
		parent = furniture,
	})
	for _, p in { { -2.2, -1.4 }, { 2.2, -1.4 }, { -2.2, 1.4 }, { 2.2, 1.4 } } do
		Builder.part({
			name = "TableLeg",
			size = Vector3.new(0.4, 2.9, 0.4),
			cframe = origin * CFrame.new(4 + p[1], 1.45, 2 + p[2]),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = furniture,
		})
	end
	local tableLamp = light(
		lights,
		"TableLamp",
		origin * CFrame.new(5.6, 4.3, 1.4),
		Vector3.new(0.9, 0.9, 0.9),
		14,
		0.9,
		true,
		true,
		true,
		false
	)
	local lampPrompt = Builder.prompt(tableLamp, "Lamp off", "Table lamp", 0, 7)
	lampPrompt.Name = "LampPrompt"
	lampPrompt:SetAttribute("Target", tableLamp.Name)
	local radio = Builder.part({
		name = "Radio",
		size = Vector3.new(1.8, 1, 1),
		cframe = origin * CFrame.new(2.8, 3.8, 2.2),
		color = Color3.fromRGB(60, 50, 40),
		material = Enum.Material.Wood,
		parent = furniture,
	})
	CollectionService:AddTag(radio, "CabinRadio")
	local radioPrompt = Builder.prompt(radio, "Listen to the radio", "Radio", 0, 7)
	radioPrompt.Name = "RadioPrompt"
	-- Wardrobe (the coat)
	local wardrobe = Builder.part({
		name = "Wardrobe",
		size = Vector3.new(3, 8, 4.4),
		cframe = origin * CFrame.new(12.4, 4, -8.4),
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		parent = furniture,
	})
	local wardrobePrompt = Builder.prompt(wardrobe, "Search the wardrobe", "Wardrobe", 1, 8)
	wardrobePrompt.Name = "WardrobePrompt"
	-- Workbench
	local bench = Builder.part({
		name = "Workbench",
		size = Vector3.new(6, 3.2, 2.4),
		cframe = origin * CFrame.new(7, 1.6, -9.6),
		color = WOOD,
		material = Enum.Material.WoodPlanks,
		parent = furniture,
	})
	CollectionService:AddTag(bench, "Workbench")
	local benchPrompt = Builder.prompt(bench, "Craft", "Workbench", 0, 8)
	benchPrompt.Name = "CraftPrompt"
	benchPrompt:SetAttribute("ClientAction", "Craft")
	-- Storage chest
	local chest = Builder.part({
		name = "Chest",
		size = Vector3.new(4, 2.4, 2.4),
		cframe = origin * CFrame.new(11.6, 1.2, 6),
		color = Color3.fromRGB(96, 66, 42),
		material = Enum.Material.WoodPlanks,
		parent = furniture,
	})
	CollectionService:AddTag(chest, "Chest")
	local chestPrompt = Builder.prompt(chest, "Open storage", "Chest", 0, 8)
	chestPrompt.Name = "ChestPrompt"
	chestPrompt:SetAttribute("ClientAction", "Storage")
	-- Shelf with jars
	Builder.part({
		name = "Shelf",
		size = Vector3.new(5, 0.3, 1.2),
		cframe = origin * CFrame.new(9, 6.5, 10.4),
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		parent = furniture,
	})

	-- Shelter volume: the registered interior.
	local volume = Builder.part({
		name = "ShelterVolume",
		size = Vector3.new(28, H, 22),
		cframe = origin * CFrame.new(0, H / 2, 0),
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = model,
	})
	volume:SetAttribute("Shelter", "Cabin")
	CollectionService:AddTag(volume, "ShelterVolume")
	model:SetAttribute("ShelterId", "Cabin")
	CollectionService:AddTag(model, "Shelter")

	return { model = model, origin = origin, volume = volume }
end

return Cabin

--!strict
-- The starter cabin: the player's home and the shelter that the safety rules
-- revolve around. Built from registered modules (door, windows, roof) so the
-- shelter system can reason about each entry point explicitly.
--
-- Layout (local space, floor at y = 0, interior x -18..18, z -13..13):
--   living room: west and centre, fireplace on the west wall, big north
--                window looking across the lake, rocking chair facing it
--   bedroom:     north-east (x 8..18, z -13..2), cracked east window with a
--                broken latch (the window storms can force open)
--   nook:        south-east, storage chest, counter, fuse box
--   porch:       covered, south side, front door

local CollectionService = game:GetService("CollectionService")

local Assets = require(script.Parent.Assets)
local Builder = require(script.Parent.Builder)

local Cabin = {}

local HX, HZ, H = 18, 13, 12
local WOOD = Color3.fromRGB(112, 80, 54)
local WOOD_DARK = Color3.fromRGB(70, 49, 34)
local WOOD_LIGHT = Color3.fromRGB(146, 108, 74)
local STONE = Color3.fromRGB(112, 108, 102)
local FABRIC = Color3.fromRGB(122, 52, 44)
local CURTAIN = Color3.fromRGB(98, 50, 42)
local GLASS = Color3.fromRGB(160, 190, 200)
local WARM = Color3.fromRGB(255, 176, 110)
local ROOF = Color3.fromRGB(74, 50, 44)

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
	openings: { { number } },
	color: Color3?
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
			color = color or WOOD,
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

-- Horizontal log-style trim on an exterior wall face.
local function trim(
	parent: Instance,
	origin: CFrame,
	axis: "x" | "z",
	fixed: number,
	from: number,
	to: number
)
	for y = 1.2, H - 0.5, 1.8 do
		local len = to - from
		local size = if axis == "x" then Vector3.new(len, 0.35, 0.3) else Vector3.new(0.3, 0.35, len)
		local pos = if axis == "x"
			then Vector3.new((from + to) / 2, y, fixed)
			else Vector3.new(fixed, y, (from + to) / 2)
		Builder.part({
			name = "Trim",
			size = size,
			cframe = origin * CFrame.new(pos),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			canCollide = false,
			canQuery = false,
			castShadow = false,
			parent = parent,
		})
	end
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
	for _, s in { -1, 1 } do
		Builder.part({
			name = "FrameSide",
			size = Vector3.new(0.4, height + 0.8, 1.3),
			cframe = facing * CFrame.new(s * (width / 2 + 0.2), 0, 0),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = m,
		})
		Builder.part({
			name = "FrameRail",
			size = Vector3.new(width + 0.8, 0.4, 1.3),
			cframe = facing * CFrame.new(0, s * (height / 2 + 0.2), 0),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = m,
		})
	end
	-- Sill and a flower box outside.
	Builder.part({
		name = "Sill",
		size = Vector3.new(width + 1.2, 0.3, 1.8),
		cframe = facing * CFrame.new(0, -height / 2 - 0.45, 0.2),
		color = WOOD_LIGHT,
		material = Enum.Material.Wood,
		canQuery = false,
		parent = m,
	})
	Builder.part({
		name = "FlowerBox",
		size = Vector3.new(width * 0.8, 0.8, 1),
		cframe = facing * CFrame.new(0, -height / 2 - 1.1, -1.1),
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		canQuery = false,
		parent = m,
	})
	for i = 1, math.floor(width) do
		Builder.part({
			name = "Flower",
			shape = Enum.PartType.Ball,
			size = Vector3.new(0.6, 0.6, 0.6),
			cframe = facing * CFrame.new(
				-width * 0.4 + (i - 0.5) * (width * 0.8 / math.floor(width)),
				-height / 2 - 0.6,
				-1.1
			),
			color = if i % 2 == 0 then Color3.fromRGB(200, 120, 60) else Color3.fromRGB(160, 60, 70),
			material = Enum.Material.SmoothPlastic,
			canCollide = false,
			canQuery = false,
			castShadow = false,
			parent = m,
		})
	end
	for k = 1, 2 do
		Builder.part({
			name = "Mullion",
			size = if k == 1 then Vector3.new(0.2, height, 0.3) else Vector3.new(width, 0.2, 0.3),
			cframe = facing,
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			canQuery = false,
			castShadow = false,
			parent = m,
		})
	end
	-- Curtains hang inside (+Z of facing is inside). Closed = full cover.
	local curtainHalf = width / 2 + 0.3
	for i, s in { -1, 1 } do
		local c = Builder.part({
			name = "Curtain" .. i,
			size = Vector3.new(0.9, height + 0.8, 0.15),
			cframe = facing * CFrame.new(s * (width / 2 + 0.35), 0, 0.95),
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
	Builder.part({
		name = "CurtainRod",
		size = Vector3.new(width + 2.4, 0.15, 0.15),
		cframe = facing * CFrame.new(0, height / 2 + 0.5, 0.95),
		color = Color3.fromRGB(40, 36, 32),
		material = Enum.Material.Metal,
		canCollide = false,
		canQuery = false,
		parent = m,
	})
	-- Exterior shutters, hidden until built.
	local shutter = Builder.part({
		name = "Shutter",
		size = Vector3.new(width + 0.6, height + 0.6, 0.4),
		cframe = facing * CFrame.new(0, 0, -0.95),
		color = WOOD_DARK,
		material = Enum.Material.WoodPlanks,
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = m,
	})
	shutter:SetAttribute("Built", false)
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
	local hinge = origin * CFrame.new(1.5, 0, HZ + 0.5) -- left edge of the opening
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
	-- The broken door lies in the grass beside the porch at the start.
	local broken = Builder.part({
		name = "BrokenDoor",
		size = Vector3.new(5, 0.45, 7.6),
		cframe = origin * CFrame.new(14, -1.6, 19) * CFrame.Angles(0, math.rad(18), math.rad(4)),
		color = WOOD_LIGHT,
		material = Enum.Material.WoodPlanks,
		parent = m,
	})
	-- The home is complete at the start (Revision 2.0): the door is hung and
	-- shut. The broken-door prop stays hidden for later storm damage.
	broken:SetAttribute("Decor", true)
	broken.Transparency = 1
	broken.CanCollide = false
	m.PrimaryPart = panel
	setEntry(m, "door", "Door", 100, 100, true)
	m:SetAttribute("Tier", "standard")
	CollectionService:AddTag(m, "Door")
	local prompt = Builder.prompt(panel, "Open door", "Door", 0, 10)
	prompt.Name = "DoorPrompt"
	local upgrade = Builder.prompt(panel, "Reinforce (4 Wood, 3 Stone, 2 Scrap)", "Door", 1.5, 10)
	upgrade.Name = "UpgradePrompt"
	upgrade.KeyboardKeyCode = Enum.KeyCode.R
	upgrade.UIOffset = Vector2.new(0, 70)
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

-- Places a vetted asset at a local position on the cabin floor. Returns nil
-- (and the caller builds a procedural stand-in) when the asset is missing.
local function asset(
	name: string,
	parent: Instance,
	origin: CFrame,
	x: number,
	z: number,
	yaw: number,
	scale: number?
): Model?
	local m = Assets.clone(name)
	if not m then
		return nil
	end
	if scale and scale ~= 1 then
		m:ScaleTo(m:GetScale() * scale)
	end
	local world = origin * CFrame.new(x, 0, z)
	Assets.place(m, world.X, origin.Y, world.Z, yaw, 0)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = true
			d.CanQuery = true
		end
	end
	m.Parent = parent
	return m
end

local function buildPorch(parent: Instance, origin: CFrame)
	local porch = Builder.folder("Porch", parent)
	local x0, x1, z0, z1 = -3, 11, HZ + 1, HZ + 7
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	Builder.part({
		name = "Deck",
		size = Vector3.new(x1 - x0, 1, z1 - z0),
		cframe = origin * CFrame.new(cx, -0.5, cz),
		color = WOOD,
		material = Enum.Material.WoodPlanks,
		parent = porch,
	})
	for i, dy in { -1.5, -2.5 } do
		Builder.part({
			name = "Step",
			size = Vector3.new(6, 1, 2),
			cframe = origin * CFrame.new(4, dy, z1 + 1 + (i - 1) * 2),
			color = WOOD_DARK,
			material = Enum.Material.WoodPlanks,
			parent = porch,
		})
	end
	for _, p in
		{ { x0 + 0.4, z1 - 0.4 }, { x1 - 0.4, z1 - 0.4 }, { x0 + 0.4, z0 + 0.4 }, { x1 - 0.4, z0 + 0.4 } }
	do
		Builder.part({
			name = "Post",
			size = Vector3.new(0.8, 9.5, 0.8),
			cframe = origin * CFrame.new(p[1], 4.75, p[2]),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = porch,
		})
	end
	Builder.part({
		name = "PorchRoof",
		size = Vector3.new(x1 - x0 + 1.5, 0.6, z1 - z0 + 1.5),
		cframe = origin * CFrame.new(cx, 9.8, cz) * CFrame.Angles(math.rad(-8), 0, 0),
		color = ROOF,
		material = Enum.Material.WoodPlanks,
		parent = porch,
	})
	-- Railings, with a gap for the steps.
	local function rail(a: Vector3, b: Vector3)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		Builder.part({
			name = "Rail",
			size = Vector3.new(0.35, 0.35, len),
			cframe = origin * CFrame.lookAt(mid, b),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = porch,
		})
		local n = math.floor(len / 1.2)
		for i = 1, n - 1 do
			local p = a + (b - a) * (i / n) - Vector3.new(0, 1.3, 0)
			Builder.part({
				name = "Baluster",
				size = Vector3.new(0.2, 2.6, 0.2),
				cframe = origin * CFrame.new(p),
				color = WOOD,
				material = Enum.Material.Wood,
				canQuery = false,
				parent = porch,
			})
		end
	end
	rail(Vector3.new(x0 + 0.4, 3, z0 + 0.4), Vector3.new(x0 + 0.4, 3, z1 - 0.4))
	rail(Vector3.new(x1 - 0.4, 3, z0 + 0.4), Vector3.new(x1 - 0.4, 3, z1 - 0.4))
	rail(Vector3.new(x0 + 0.4, 3, z1 - 0.4), Vector3.new(1, 3, z1 - 0.4))
	rail(Vector3.new(7, 3, z1 - 0.4), Vector3.new(x1 - 0.4, 3, z1 - 0.4))
	-- Firewood stack against the wall: the outdoor wood corner.
	for row = 0, 2 do
		for i = 0, 5 do
			Builder.part({
				name = "Firewood",
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(3, 0.8, 0.8),
				cframe = origin
					* CFrame.new(-16 + i * 0.85, 0.5 + row * 0.75, HZ + 2)
					* CFrame.Angles(0, math.rad(90), 0),
				color = Color3.fromRGB(110 + (i * 7) % 20, 78, 50),
				material = Enum.Material.Wood,
				parent = porch,
			})
		end
	end
end

function Cabin.build(parent: Instance, position: Vector3): Built
	local model = Builder.model("Cabin", parent)
	local origin = CFrame.new(position)
	local structure = Builder.folder("Structure", model)

	-- Floor, stone skirt and foundation
	Builder.part({
		name = "Floor",
		size = Vector3.new(2 * HX + 2, 1, 2 * HZ + 2),
		cframe = origin * CFrame.new(0, -0.5, 0),
		color = WOOD_LIGHT,
		material = Enum.Material.WoodPlanks,
		parent = structure,
	})
	for _, s in { { 0, -(HZ + 0.6), 2 * HX + 3, 1.4 }, { 0, HZ + 0.6, 2 * HX + 3, 1.4 } } do
		Builder.part({
			name = "Skirt",
			size = Vector3.new(s[3], 4, s[4]),
			cframe = origin * CFrame.new(s[1], -2.6, s[2]),
			color = STONE,
			material = Enum.Material.Cobblestone,
			parent = structure,
		})
	end
	for _, x in { -(HX + 0.6), HX + 0.6 } do
		Builder.part({
			name = "Skirt",
			size = Vector3.new(1.4, 4, 2 * HZ + 3),
			cframe = origin * CFrame.new(x, -2.6, 0),
			color = STONE,
			material = Enum.Material.Cobblestone,
			parent = structure,
		})
	end
	for _, p in { { -HX, -HZ }, { HX, -HZ }, { -HX, HZ }, { HX, HZ }, { 0, -HZ }, { 0, HZ }, { 0, 0 } } do
		Builder.part({
			name = "Foundation",
			size = Vector3.new(2.4, 10, 2.4),
			cframe = origin * CFrame.new(p[1], -6, p[2]),
			color = STONE,
			material = Enum.Material.Cobblestone,
			parent = structure,
		})
	end

	-- Exterior walls
	local wz, wx = HZ + 0.5, HX + 0.5
	wall(structure, origin, "x", wz, -(HX + 1), HX + 1, { { 4, 5, 0, 8.5 }, { -10, 5, 3.5, 8 } })
	wall(structure, origin, "x", -wz, -(HX + 1), HX + 1, { { -4, 11, 3, 8.5 }, { 13, 4, 3.5, 8 } })
	wall(structure, origin, "z", wx, -HZ, HZ, { { -6, 5, 3.5, 8 } })
	wall(structure, origin, "z", -wx, -HZ, HZ, {})
	trim(structure, origin, "x", wz + 0.55, -(HX + 1), -12.6)
	trim(structure, origin, "x", wz + 0.55, -7.4, 1.4)
	trim(structure, origin, "x", wz + 0.55, 6.6, HX + 1)
	trim(structure, origin, "x", -wz - 0.55, -(HX + 1), -9.6)
	trim(structure, origin, "x", -wz - 0.55, 1.6, 10.6)
	trim(structure, origin, "x", -wz - 0.55, 15.4, HX + 1)
	trim(structure, origin, "z", -wx - 0.55, -HZ, -3)
	trim(structure, origin, "z", -wx - 0.55, 3, HZ)
	trim(structure, origin, "z", wx + 0.55, -HZ, -8.6)
	trim(structure, origin, "z", wx + 0.55, -3.4, HZ)
	for _, p in { { -wx, -wz }, { wx, -wz }, { -wx, wz }, { wx, wz } } do
		Builder.part({
			name = "CornerPost",
			size = Vector3.new(1.8, H, 1.8),
			cframe = origin * CFrame.new(p[1], H / 2, p[2]),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = structure,
		})
	end
	-- Interior walls: bedroom (north-east) with a doorway.
	local interior = Color3.fromRGB(150, 116, 82)
	wall(structure, origin, "z", 8, -HZ, 2, { { -3, 4, 0, 8.5 } }, interior)
	wall(structure, origin, "x", 2, 8.5, HX, {}, interior)

	-- Roof: gable along X with overhangs.
	local rise, run = 7.5, HZ + 2.2
	local slant = math.sqrt(rise * rise + run * run)
	local angle = math.atan2(rise, run)
	for _, s in { -1, 1 } do
		local roof = Builder.part({
			name = "Roof",
			size = Vector3.new(2 * HX + 5, 0.9, slant + 0.6),
			cframe = origin * CFrame.new(0, H + rise / 2, s * run / 2) * CFrame.Angles(s * angle, 0, 0),
			color = ROOF,
			material = Enum.Material.WoodPlanks,
			parent = structure,
		})
		roof:SetAttribute("RoofMaterial", "Wood")
		-- Shingle rows for texture.
		for i = 1, 6 do
			Builder.part({
				name = "Shingles",
				size = Vector3.new(2 * HX + 5.2, 0.25, 0.6),
				cframe = roof.CFrame * CFrame.new(0, 0.5, -slant / 2 + i * slant / 7),
				color = Color3.fromRGB(60, 40, 36),
				material = Enum.Material.Slate,
				canCollide = false,
				canQuery = false,
				castShadow = false,
				parent = structure,
			})
		end
	end
	Builder.part({
		name = "Ridge",
		size = Vector3.new(2 * HX + 5.4, 0.9, 1.2),
		cframe = origin * CFrame.new(0, H + rise + 0.25, 0),
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		parent = structure,
	})
	for _, x in { -wx, wx } do
		Builder.wedge({
			name = "Gable",
			size = Vector3.new(1, rise, HZ + 0.5),
			cframe = origin * CFrame.new(x, H + rise / 2, (HZ + 0.5) / 2) * CFrame.Angles(0, math.pi, 0),
			color = WOOD,
			material = Enum.Material.WoodPlanks,
			parent = structure,
		})
		Builder.wedge({
			name = "Gable",
			size = Vector3.new(1, rise, HZ + 0.5),
			cframe = origin * CFrame.new(x, H + rise / 2, -(HZ + 0.5) / 2),
			color = WOOD,
			material = Enum.Material.WoodPlanks,
			parent = structure,
		})
	end
	for _, z in { -8, -2.5, 3, 8.5 } do
		Builder.part({
			name = "Beam",
			size = Vector3.new(2 * HX, 0.8, 0.8),
			cframe = origin * CFrame.new(0, H - 0.4, z),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			canQuery = false,
			parent = structure,
		})
	end
	buildPorch(model, origin)

	-- Fireplace and chimney (west wall)
	local fire = Builder.folder("Fireplace", model)
	local hx = -(HX - 1.5)
	Builder.part({
		name = "Hearth",
		size = Vector3.new(3, 7, 9),
		cframe = origin * CFrame.new(hx, 3.5, 0),
		color = STONE,
		material = Enum.Material.Cobblestone,
		parent = fire,
	})
	local firebox = Builder.part({
		name = "Firebox",
		size = Vector3.new(0.4, 3.2, 4.4),
		cframe = origin * CFrame.new(hx + 1.65, 2, 0),
		color = Color3.fromRGB(22, 18, 16),
		material = Enum.Material.Slate,
		parent = fire,
	})
	Builder.part({
		name = "HearthStone",
		size = Vector3.new(3, 0.3, 9),
		cframe = origin * CFrame.new(hx + 2.8, 0.15, 0),
		color = Color3.fromRGB(90, 86, 82),
		material = Enum.Material.Slate,
		canCollide = false,
		parent = fire,
	})
	Builder.part({
		name = "Mantel",
		size = Vector3.new(3.8, 0.5, 10),
		cframe = origin * CFrame.new(hx + 0.3, 7.25, 0),
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		parent = fire,
	})
	Builder.part({
		name = "Chimney",
		size = Vector3.new(3.6, 27, 5.5),
		cframe = origin * CFrame.new(-(HX + 2.4), 11, 0),
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
				* CFrame.new(hx + 2.1, 0.4 + (if i == 3 then 0.5 else 0), (i - 2) * 0.7)
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
		cframe = origin * CFrame.new(hx + 2.2, 1.1, 0),
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
	-- The morning fire is still going, but low: feeding it is the first chore.
	fx.Enabled = true
	fx.Parent = flame
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(70, 66, 64)
	smoke.Opacity = 0.12
	smoke.RiseVelocity = 4
	smoke.Size = 3
	smoke.Enabled = true
	smoke.Parent = fire:FindFirstChild("Chimney") :: Instance
	local fireLight = Builder.pointLight(flame, Color3.fromRGB(255, 140, 70), 24, 2.2, true)
	fireLight.Enabled = true
	flame:SetAttribute("On", true)
	flame:SetAttribute("Electric", false)
	flame:SetAttribute("Indoor", true)
	flame:SetAttribute("Shelter", "Cabin")
	flame:SetAttribute("Brightness", 1.4)
	flame:SetAttribute("Fuel", 150) -- seconds of burn left at the start
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
		Vector3.new(-4, 5.75, -wz),
		Vector3.new(0, 0, -1),
		11,
		5.5,
		100,
		true,
		false
	)
	buildWindow(
		entries,
		origin,
		"East",
		Vector3.new(wx, 5.75, -6),
		Vector3.new(1, 0, 0),
		5,
		4.5,
		100,
		true,
		false
	)
	-- Bedroom window facing the lake: Maya's lights are visible from the bed.
	buildWindow(
		entries,
		origin,
		"BedroomNorth",
		Vector3.new(13, 5.75, -wz),
		Vector3.new(0, 0, -1),
		4,
		4,
		100,
		true,
		false
	)
	buildWindow(
		entries,
		origin,
		"South",
		Vector3.new(-10, 5.75, wz),
		Vector3.new(0, 0, 1),
		5,
		4.5,
		100,
		false,
		false
	)
	local roofEntry = Instance.new("Configuration")
	roofEntry.Name = "RoofEntry"
	roofEntry.Parent = entries
	setEntry(roofEntry, "roof", "Roof", 100, 100, true)

	-- Lights
	local lights = Builder.folder("Lights", model)
	local ceiling = light(
		lights,
		"CeilingLamp",
		origin * CFrame.new(-3, H - 1.8, -1),
		Vector3.new(1.4, 0.6, 1.4),
		30,
		1.1,
		true,
		true,
		true,
		true
	)
	Builder.part({
		name = "LampCord",
		size = Vector3.new(0.1, 1.4, 0.1),
		cframe = origin * CFrame.new(-3, H - 0.8, -1),
		color = Color3.fromRGB(30, 30, 30),
		canCollide = false,
		canQuery = false,
		parent = lights,
	})
	local bedroomLamp = light(
		lights,
		"BedroomLamp",
		origin * CFrame.new(13, H - 1.8, -5.5),
		Vector3.new(1.2, 0.6, 1.2),
		18,
		0.8,
		false,
		true,
		true,
		false
	)
	local bedroomPrompt = Builder.prompt(bedroomLamp, "Lamp on", "Bedroom lamp", 0, 9)
	bedroomPrompt.Name = "LampPrompt"
	bedroomPrompt:SetAttribute("Target", bedroomLamp.Name)
	local porch = light(
		lights,
		"PorchLight",
		origin * CFrame.new(4, 9.2, wz + 0.9),
		Vector3.new(0.8, 0.8, 0.5),
		22,
		1,
		true,
		true,
		false,
		false
	)
	local switchPlate = Builder.part({
		name = "LightSwitch",
		size = Vector3.new(0.6, 1, 0.2),
		cframe = origin * CFrame.new(7.6, 4.5, HZ - 0.15),
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
		cframe = origin * CFrame.new(10.5, 5, HZ - 0.25),
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
		size = Vector3.new(14, 0.1, 9),
		cframe = origin * CFrame.new(-6, 0.05, -2),
		color = Color3.fromRGB(124, 62, 46),
		material = Enum.Material.Fabric,
		canCollide = false,
		parent = furniture,
	})
	-- Rocking chair facing the north window. The Seat is what the player uses.
	local chairCF = origin * CFrame.new(-4, 0, -7.5)
	local seat = Instance.new("Seat")
	seat.Name = "WindowChair"
	seat.Size = Vector3.new(2.6, 0.6, 2.6)
	seat.CFrame = chairCF * CFrame.new(0, 1.6, 0)
	seat.Anchored = true
	seat.Color = FABRIC
	seat.Material = Enum.Material.Fabric
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.Parent = furniture
	seat:SetAttribute("Comfort", true)
	CollectionService:AddTag(seat, "ComfortSeat")
	local rocker = asset("RockingChair", furniture, origin, -4, -7.5, math.pi)
	if rocker then
		seat.Transparency = 1
		for _, d in rocker:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
			end
		end
	else
		Builder.part({
			name = "ChairBack",
			size = Vector3.new(3, 3.4, 0.6),
			cframe = chairCF * CFrame.new(0, 3.3, 1.4),
			color = FABRIC,
			material = Enum.Material.Fabric,
			parent = furniture,
		})
	end
	-- Armchair by the fire (faces the hearth)
	local armCF = origin * CFrame.new(-11, 0, 6) * CFrame.Angles(0, math.rad(-120), 0)
	local arm = Instance.new("Seat")
	arm.Name = "FireChair"
	arm.Size = Vector3.new(3, 1, 3)
	arm.CFrame = armCF * CFrame.new(0, 1.6, 0)
	arm.Anchored = true
	arm.Color = Color3.fromRGB(94, 70, 52)
	arm.Material = Enum.Material.Fabric
	arm.Parent = furniture
	CollectionService:AddTag(arm, "ComfortSeat")
	Builder.part({
		name = "ArmchairBack",
		size = Vector3.new(3.2, 3.6, 0.8),
		cframe = armCF * CFrame.new(0, 3.2, 1.5),
		color = Color3.fromRGB(94, 70, 52),
		material = Enum.Material.Fabric,
		parent = furniture,
	})
	Builder.part({
		name = "ArmchairBase",
		size = Vector3.new(3.2, 1.1, 3.2),
		cframe = armCF * CFrame.new(0, 0.55, 0),
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		parent = furniture,
	})
	-- Bookshelves flanking the fireplace
	for _, z in { -8, 8 } do
		if not asset("Bookshelf", furniture, origin, -(HX - 1.2), z, math.rad(90)) then
			Builder.part({
				name = "Shelf",
				size = Vector3.new(1.6, 8, 4),
				cframe = origin * CFrame.new(-(HX - 0.8), 4, z),
				color = WOOD_DARK,
				material = Enum.Material.Wood,
				parent = furniture,
			})
		end
	end
	-- Bed (bedroom)
	local bedModel = asset("Bed", furniture, origin, 13.4, -7, 0, 0.8)
	if not bedModel then
		Builder.part({
			name = "BedFrame",
			size = Vector3.new(5, 1.4, 8),
			cframe = origin * CFrame.new(13.4, 0.7, -7),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = furniture,
		})
	end
	local blanket = Builder.part({
		name = "Blanket",
		size = Vector3.new(5, 0.6, 6),
		cframe = origin * CFrame.new(13.4, 2.2, -6),
		color = Color3.fromRGB(70, 86, 110),
		material = Enum.Material.Fabric,
		transparency = if bedModel then 1 else 0,
		canCollide = false,
		parent = furniture,
	})
	local sleepPrompt = Builder.prompt(blanket, "Sleep until dawn", "Bed", 1.2, 8)
	sleepPrompt.Name = "SleepPrompt"
	local respawn = Builder.part({
		name = "BedRespawn",
		size = Vector3.new(1, 1, 1),
		cframe = origin * CFrame.new(11, 3, -1),
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
		cframe = origin * CFrame.new(-12.5, 0.35, 8.5),
		color = Color3.fromRGB(150, 64, 52),
		material = Enum.Material.Fabric,
		parent = furniture,
	})
	CollectionService:AddTag(dogBed, "DogBed")
	-- Table with lamp, radio and a lantern
	local tableTop = Builder.part({
		name = "TableTop",
		size = Vector3.new(6, 0.4, 3.6),
		cframe = origin * CFrame.new(2, 3.1, 4),
		color = WOOD,
		material = Enum.Material.Wood,
		parent = furniture,
	})
	for _, p in { { -2.6, -1.5 }, { 2.6, -1.5 }, { -2.6, 1.5 }, { 2.6, 1.5 } } do
		Builder.part({
			name = "TableLeg",
			size = Vector3.new(0.4, 2.9, 0.4),
			cframe = origin * CFrame.new(2 + p[1], 1.45, 4 + p[2]),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = furniture,
		})
	end
	for _, x in { -0.5, 4.5 } do
		Builder.part({
			name = "Stool",
			size = Vector3.new(1.6, 2, 1.6),
			cframe = origin * CFrame.new(x, 1, 6.6),
			color = WOOD_DARK,
			material = Enum.Material.Wood,
			parent = furniture,
		})
	end
	local tableLamp = light(
		lights,
		"TableLamp",
		origin * CFrame.new(3.8, 4.3, 3.4),
		Vector3.new(0.9, 0.9, 0.9),
		16,
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
		cframe = origin * CFrame.new(0.6, 3.8, 4.2),
		color = Color3.fromRGB(60, 50, 40),
		material = Enum.Material.Wood,
		parent = furniture,
	})
	CollectionService:AddTag(radio, "CabinRadio")
	local radioPrompt = Builder.prompt(radio, "Listen to the radio", "Radio", 0, 7)
	radioPrompt.Name = "RadioPrompt"
	local lantern = Assets.clone("Lantern")
	if lantern then
		lantern:ScaleTo(lantern:GetScale() * 1.3)
		local w = origin * CFrame.new(-(HX - 1.8), 0, 3)
		Assets.place(lantern, w.X, origin.Y + 7.5, w.Z, 0, 0)
		lantern.Parent = furniture
	end
	local _ = tableTop
	-- Wardrobe (the coat) in the bedroom
	local wardrobe = Builder.part({
		name = "Wardrobe",
		size = Vector3.new(3, 8.5, 4.4),
		cframe = origin * CFrame.new(HX - 1.6, 4.25, -0.4),
		color = WOOD_DARK,
		material = Enum.Material.Wood,
		parent = furniture,
	})
	Builder.part({
		name = "WardrobeTrim",
		size = Vector3.new(0.2, 7.6, 0.2),
		cframe = origin * CFrame.new(HX - 3.15, 4.25, -0.4),
		color = Color3.fromRGB(180, 150, 90),
		material = Enum.Material.Metal,
		canCollide = false,
		parent = furniture,
	})
	local wardrobePrompt = Builder.prompt(wardrobe, "Search the wardrobe", "Wardrobe", 1, 8)
	wardrobePrompt.Name = "WardrobePrompt"
	-- Workbench against the north wall, east of the window
	local bench = Builder.part({
		name = "Workbench",
		size = Vector3.new(5, 3.2, 2.4),
		cframe = origin * CFrame.new(4.6, 1.6, -(HZ - 1.3)),
		color = WOOD,
		material = Enum.Material.WoodPlanks,
		parent = furniture,
	})
	CollectionService:AddTag(bench, "Workbench")
	local benchPrompt = Builder.prompt(bench, "Craft", "Workbench", 0, 8)
	benchPrompt.Name = "CraftPrompt"
	benchPrompt:SetAttribute("ClientAction", "Craft")
	-- Nook: counter and storage chest
	Builder.part({
		name = "Counter",
		size = Vector3.new(2.6, 3.4, 8),
		cframe = origin * CFrame.new(HX - 1.4, 1.7, 7.5),
		color = WOOD,
		material = Enum.Material.WoodPlanks,
		parent = furniture,
	})
	local chest = Builder.part({
		name = "Chest",
		size = Vector3.new(4, 2.4, 2.4),
		cframe = origin * CFrame.new(12, 1.2, 4),
		color = Color3.fromRGB(96, 66, 42),
		material = Enum.Material.WoodPlanks,
		parent = furniture,
	})
	CollectionService:AddTag(chest, "Chest")
	local chestPrompt = Builder.prompt(chest, "Open storage", "Chest", 0, 8)
	chestPrompt.Name = "ChestPrompt"
	chestPrompt:SetAttribute("ClientAction", "Storage")

	-- Shelter volume: the registered interior.
	local volume = Builder.part({
		name = "ShelterVolume",
		size = Vector3.new(2 * HX, H, 2 * HZ),
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

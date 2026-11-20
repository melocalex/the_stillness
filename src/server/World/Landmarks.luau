--!strict
-- Landmarks: the house across the lake, the abandoned house, the radio tower,
-- the north ridge marker, the Old One's silhouette and the map boundary.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local Assets = require(script.Parent.Assets)
local Builder = require(script.Parent.Builder)
local Terrain = require(script.Parent.Terrain)

local Landmarks = {}

local W = WorldConfig
local SIDING = Color3.fromRGB(122, 116, 104)
local SIDING_DARK = Color3.fromRGB(70, 66, 62)
local GLOW = Color3.fromRGB(255, 196, 120)

local function box(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	return Builder.part({
		name = name,
		size = size,
		cframe = cf,
		color = color,
		material = material or Enum.Material.WoodPlanks,
		parent = parent,
	})
end

-- A window pane that can glow from far away when its room light is on.
local function pane(parent: Instance, name: string, cf: CFrame, w: number, h: number): Part
	local p = Builder.part({
		name = name,
		size = Vector3.new(w, h, 0.3),
		cframe = cf,
		color = Builder.PaneUnlit.color,
		material = Enum.Material.Glass,
		transparency = Builder.PaneUnlit.transparency,
		reflectance = Builder.PaneUnlit.reflectance,
		canQuery = false,
		castShadow = false,
		parent = parent,
	})
	CollectionService:AddTag(p, "HousePane")
	return p
end

-- Invisible marker MayaService walks between. Spot names are the contract.
local function spot(parent: Instance, name: string, cf: CFrame)
	local p = Builder.part({
		name = "MayaSpot",
		size = Vector3.new(1, 1, 1),
		cframe = cf,
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = parent,
	})
	p:SetAttribute("Spot", name)
end

-- Maya's house (Revision 2.0): she lives here, across the lake from you.
function Landmarks.lakeHouse(parent: Instance): Model
	local m = Builder.model("LakeHouse", parent)
	local y = W.LakeHouse.height
	local o = CFrame.new(W.LakeHouse.x, y, W.LakeHouse.z) -- front faces +z (toward the cabin)
	local wd, dp, fh = 22, 16, 9
	box(m, "Floor", o * CFrame.new(0, -0.5, 0), Vector3.new(wd + 1, 1, dp + 1), SIDING_DARK)
	box(m, "Floor2", o * CFrame.new(0, fh, 0), Vector3.new(wd, 0.6, dp), SIDING_DARK)
	-- Walls (two stories), front wall has 3 window openings and the back a door.
	local function wallX(z: number, openings: { { number } })
		for storey = 0, 1 do
			local yb = storey * fh
			local cursor = -wd / 2
			for _, op in openings do
				if op[3] == storey then
					local c, w = op[1], op[2]
					local a, b = cursor, c - w / 2
					if b > a then
						box(
							m,
							"Wall",
							o * CFrame.new((a + b) / 2, yb + fh / 2, z),
							Vector3.new(b - a, fh, 1),
							SIDING
						)
					end
					box(m, "Wall", o * CFrame.new(c, yb + 1.5, z), Vector3.new(w, 3, 1), SIDING)
					box(m, "Wall", o * CFrame.new(c, yb + fh - 1, z), Vector3.new(w, 2, 1), SIDING)
					cursor = c + w / 2
				end
			end
			box(
				m,
				"Wall",
				o * CFrame.new((cursor + wd / 2) / 2, yb + fh / 2, z),
				Vector3.new(wd / 2 - cursor, fh, 1),
				SIDING
			)
		end
	end
	wallX(dp / 2, { { -5, 4, 0 }, { -5, 4, 1 }, { 5, 4, 1 } })
	wallX(-dp / 2, {})
	for _, x in { -wd / 2, wd / 2 } do
		for storey = 0, 1 do
			local yb = storey * fh
			if x > 0 and storey == 0 then
				-- side door opening on the east wall
				box(m, "Wall", o * CFrame.new(x, yb + fh / 2, -4.5), Vector3.new(1, fh, dp / 2 - 2.5), SIDING)
				box(m, "Wall", o * CFrame.new(x, yb + fh / 2, 5), Vector3.new(1, fh, dp / 2 - 2), SIDING)
				box(m, "Wall", o * CFrame.new(x, yb + fh - 1, 0.5), Vector3.new(1, 2, 5), SIDING)
			else
				box(m, "Wall", o * CFrame.new(x, yb + fh / 2, 0), Vector3.new(1, fh, dp), SIDING)
			end
		end
	end
	-- Roof
	for _, s in { -1, 1 } do
		box(
			m,
			"Roof",
			o * CFrame.new(0, 2 * fh + 2.5, s * dp / 4) * CFrame.Angles(s * math.rad(32), 0, 0),
			Vector3.new(wd + 2, 0.8, dp / 2 / math.cos(math.rad(32)) + 1.5),
			Color3.fromRGB(52, 46, 44),
			Enum.Material.Slate
		)
	end
	box(
		m,
		"Chimney",
		o * CFrame.new(-7, 2 * fh + 4, -3),
		Vector3.new(2.4, 8, 2.4),
		Color3.fromRGB(96, 70, 60),
		Enum.Material.Brick
	)
	-- Stairs inside (west side)
	for i = 1, 9 do
		box(
			m,
			"Stair",
			o * CFrame.new(-wd / 2 + 2, i, -dp / 2 + 1.5 + i * 1.1),
			Vector3.new(3, 1, 1.2),
			SIDING_DARK,
			Enum.Material.Wood
		)
	end
	-- Window panes (front)
	local down = pane(m, "DownPane", o * CFrame.new(-5, 4.5, dp / 2), 4, 4)
	local upL = pane(m, "UpPaneL", o * CFrame.new(-5, fh + 4.5, dp / 2), 4, 4)
	local upR = pane(m, "UpPaneR", o * CFrame.new(5, fh + 4.5, dp / 2), 4, 4)
	down:SetAttribute("Room", "Downstairs")
	upL:SetAttribute("Room", "Upstairs")
	upR:SetAttribute("Room", "Upstairs")
	-- Room lights
	local rooms: { { name: string, y: number } } =
		{ { name = "Downstairs", y = 4 }, { name = "Upstairs", y = fh + 5 } }
	for _, room in rooms do
		local bulb = Builder.part({
			name = room.name .. "Light",
			size = Vector3.new(0.6, 0.6, 0.6),
			cframe = o * CFrame.new(0, room.y, 2),
			color = GLOW,
			transparency = 1,
			canCollide = false,
			canQuery = false,
			parent = m,
		})
		local l = Builder.pointLight(bulb, GLOW, 18, 1.4, false)
		l.Enabled = false
		bulb:SetAttribute("Room", room.name)
	end
	-- Upstairs desk and a kitchen table for lunch.
	box(m, "Desk", o * CFrame.new(6, fh + 1.6, -5), Vector3.new(4, 2.6, 2), SIDING_DARK, Enum.Material.Wood)
	box(
		m,
		"Table",
		o * CFrame.new(4, 1.5, -2),
		Vector3.new(5, 0.4, 3),
		Color3.fromRGB(120, 86, 58),
		Enum.Material.Wood
	)
	for _, dx in { 2, 6 } do
		box(
			m,
			"TableLeg",
			o * CFrame.new(dx, 0.65, -2),
			Vector3.new(0.4, 1.3, 2.4),
			SIDING_DARK,
			Enum.Material.Wood
		)
	end
	-- Where Maya stands through her day. Front faces the cabin (+z).
	spot(m, "Kitchen", o * CFrame.new(4, 0, -4.5) * CFrame.Angles(0, math.pi, 0))
	spot(m, "Window", o * CFrame.new(-5, 0, dp / 2 - 2) * CFrame.Angles(0, math.pi, 0))
	spot(m, "Porch", o * CFrame.new(wd / 2 + 4, 0, 0.5) * CFrame.Angles(0, -math.pi / 2, 0))
	spot(m, "Upstairs", o * CFrame.new(5, fh + 0.3, dp / 2 - 2) * CFrame.Angles(0, math.pi, 0))
	-- Interior volume
	local vol = Builder.part({
		name = "Interior",
		size = Vector3.new(wd - 1, 2 * fh, dp - 1),
		cframe = o * CFrame.new(0, fh, 0),
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = m,
	})
	vol:SetAttribute("Zone", "LakeHouse")
	CollectionService:AddTag(vol, "Zone")
	m:SetAttribute("Upstairs", false)
	m:SetAttribute("Downstairs", false)
	m:SetAttribute("Broken", false)
	CollectionService:AddTag(m, "MayaHouse")
	return m
end

function Landmarks.abandonedHouse(parent: Instance): Model
	local m = Builder.model("AbandonedHouse", parent)
	local y = W.AbandonedHouse.height
	local o = CFrame.new(W.AbandonedHouse.x, y, W.AbandonedHouse.z) * CFrame.Angles(0, math.rad(90), 0)
	local wd, dp, h = 30, 22, 10
	local rot = Color3.fromRGB(84, 74, 64)
	box(m, "Floor", o * CFrame.new(0, -0.5, 0), Vector3.new(wd + 1, 1, dp + 1), Color3.fromRGB(60, 52, 46))
	-- Front (+z) with a missing door at x=0 and two broken windows.
	local function frontWall(z: number, door: boolean)
		local pieces: { { number } } = if door
			then { { -wd / 2, -10 }, { -6, -2.5 }, { 2.5, 6 }, { 10, wd / 2 } }
			else { { -wd / 2, -10 }, { -6, 6 }, { 10, wd / 2 } }
		for _, p in pieces do
			box(m, "Wall", o * CFrame.new((p[1] + p[2]) / 2, h / 2, z), Vector3.new(p[2] - p[1], h, 1), rot)
		end
		for _, c in { -8, 8 } do
			box(m, "Wall", o * CFrame.new(c, 1.75, z), Vector3.new(4, 3.5, 1), rot)
			box(m, "Wall", o * CFrame.new(c, h - 1.25, z), Vector3.new(4, 2.5, 1), rot)
		end
		if door then
			box(m, "Wall", o * CFrame.new(0, h - 1, z), Vector3.new(5, 2, 1), rot)
		end
	end
	frontWall(dp / 2, true)
	frontWall(-dp / 2, false)
	for _, x in { -wd / 2, wd / 2 } do
		box(m, "Wall", o * CFrame.new(x, h / 2, 0), Vector3.new(1, h, dp), rot)
	end
	-- Interior walls: hallway down the middle, two rooms on each side.
	box(m, "InnerWall", o * CFrame.new(-5.5, h / 2, -5.5), Vector3.new(1, h, 11), rot)
	box(m, "InnerWall", o * CFrame.new(5.5, h / 2, -5.5), Vector3.new(1, h, 11), rot)
	box(m, "InnerWall", o * CFrame.new(-10.5, h / 2, 0), Vector3.new(9, h, 1), rot)
	box(m, "InnerWall", o * CFrame.new(10.5, h / 2, 0), Vector3.new(9, h, 1), rot)
	-- Sagging roof with a hole
	box(
		m,
		"Roof",
		o * CFrame.new(-7, h + 0.4, 0) * CFrame.Angles(0, 0, math.rad(4)),
		Vector3.new(17, 0.8, dp + 2),
		Color3.fromRGB(46, 42, 40),
		Enum.Material.Slate
	)
	box(
		m,
		"Roof",
		o * CFrame.new(9, h + 0.2, -4),
		Vector3.new(13, 0.8, dp - 6),
		Color3.fromRGB(46, 42, 40),
		Enum.Material.Slate
	)
	-- Debris
	box(
		m,
		"Table",
		o * CFrame.new(-10, 1.2, -6) * CFrame.Angles(0, 0, math.rad(80)),
		Vector3.new(4, 0.4, 3),
		Color3.fromRGB(70, 56, 44),
		Enum.Material.Wood
	)
	box(
		m,
		"Cabinet",
		o * CFrame.new(12, 3, -8),
		Vector3.new(3, 6, 2),
		Color3.fromRGB(60, 50, 42),
		Enum.Material.Wood
	)
	-- Loot crate in the back-left room
	local crate = box(
		m,
		"Crate",
		o * CFrame.new(-11, 1.2, -8.5),
		Vector3.new(3.4, 2.4, 2.4),
		Color3.fromRGB(90, 72, 46),
		Enum.Material.WoodPlanks
	)
	local p = Builder.prompt(crate, "Search crate", "Old crate", 2.2, 8)
	p.Name = "LootPrompt"
	crate:SetAttribute("Looted", false)
	CollectionService:AddTag(crate, "LootCrate")
	-- Scrap piles
	for i, pos in { { 11, -3 }, { -12, 4 }, { 4, 9 } } do
		local s = box(
			m,
			"ScrapPile",
			o * CFrame.new(pos[1], 0.6, pos[2]),
			Vector3.new(2.2, 1.2, 2.2),
			Color3.fromRGB(96, 84, 74),
			Enum.Material.CorrodedMetal
		)
		s:SetAttribute("ResourceKind", "Scrap")
		s:SetAttribute("HitsLeft", 1)
		s:SetAttribute("Depleted", false)
		CollectionService:AddTag(s, "ResourceNode")
		local _ = i
	end
	-- Dweller patrol points
	local pts = Builder.folder("DwellerPoints", m)
	for i, pos in { { 0, 6 }, { 0, -6 }, { -10, -6 }, { 10, -6 }, { -10, 6 }, { 10, 6 }, { 0, 0 } } do
		local pt = Builder.part({
			name = "Point" .. i,
			size = Vector3.new(1, 1, 1),
			cframe = o * CFrame.new(pos[1], 2.5, pos[2]),
			transparency = 1,
			canCollide = false,
			canQuery = false,
			parent = pts,
		})
		CollectionService:AddTag(pt, "DwellerPoint")
	end
	-- Interior zone for objectives and the dweller's territory
	local vol = Builder.part({
		name = "Interior",
		size = Vector3.new(wd - 1, h, dp - 1),
		cframe = o * CFrame.new(0, h / 2, 0),
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = m,
	})
	vol:SetAttribute("Zone", "AbandonedHouse")
	CollectionService:AddTag(vol, "Zone")
	return m
end

function Landmarks.radioTower(parent: Instance): Model
	local m = Builder.model("RadioTower", parent)
	local x, z = W.RadioTower.x, W.RadioTower.z
	local y = Terrain.heightAt(x, z)
	local o = CFrame.new(x, y, z)
	local steel = Color3.fromRGB(110, 40, 36)
	local height = 64
	for _, c in { { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } } do
		box(
			m,
			"Leg",
			o * CFrame.new(c[1] * 0.6, height / 2, c[2] * 0.6),
			Vector3.new(0.5, height, 0.5),
			steel,
			Enum.Material.Metal
		)
	end
	for i = 1, 10 do
		box(
			m,
			"Brace",
			o * CFrame.new(0, i * 6, 0) * CFrame.Angles(0, math.rad(i * 37), 0),
			Vector3.new(3.4, 0.3, 0.3),
			steel,
			Enum.Material.Metal
		)
	end
	local beacon = Builder.part({
		name = "Beacon",
		shape = Enum.PartType.Ball,
		size = Vector3.new(1.4, 1.4, 1.4),
		cframe = o * CFrame.new(0, height + 1, 0),
		color = Color3.fromRGB(255, 50, 40),
		material = Enum.Material.Neon,
		canCollide = false,
		parent = m,
	})
	Builder.pointLight(beacon, Color3.fromRGB(255, 60, 40), 16, 2, false)
	CollectionService:AddTag(beacon, "Beacon")
	-- Shack with the console
	local shack = o * CFrame.new(7, 0, 4)
	box(m, "ShackFloor", shack * CFrame.new(0, 0.2, 0), Vector3.new(8, 0.6, 7), SIDING_DARK)
	box(m, "ShackWall", shack * CFrame.new(0, 3.5, -3.5), Vector3.new(8, 7, 0.6), SIDING)
	box(m, "ShackWall", shack * CFrame.new(-4, 3.5, 0), Vector3.new(0.6, 7, 7), SIDING)
	box(m, "ShackWall", shack * CFrame.new(4, 3.5, 0), Vector3.new(0.6, 7, 7), SIDING)
	box(
		m,
		"ShackRoof",
		shack * CFrame.new(0, 7.2, 0),
		Vector3.new(9, 0.6, 8),
		Color3.fromRGB(60, 60, 62),
		Enum.Material.Metal
	)
	local console = box(
		m,
		"Console",
		shack * CFrame.new(0, 1.8, -2.4),
		Vector3.new(4, 3, 1.4),
		Color3.fromRGB(64, 70, 66),
		Enum.Material.Metal
	)
	local light = Builder.part({
		name = "ConsoleLamp",
		size = Vector3.new(0.4, 0.4, 0.2),
		cframe = shack * CFrame.new(1.2, 3, -1.7),
		color = Color3.fromRGB(120, 255, 140),
		material = Enum.Material.Neon,
		canCollide = false,
		parent = m,
	})
	Builder.pointLight(light, Color3.fromRGB(120, 255, 140), 6, 0.8, false)
	local prompt = Builder.prompt(console, "Listen to the signal", "Radio console", 1, 8)
	prompt.Name = "SignalPrompt"
	return m
end

function Landmarks.oldOne(parent: Instance): Model
	local m = Builder.model("OldOne", parent)
	local o = CFrame.new(0, -200, 0)
	local black = Color3.fromRGB(6, 6, 8)
	local body = Builder.part({
		name = "Body",
		size = Vector3.new(14, 46, 10),
		cframe = o * CFrame.new(0, 40, 0),
		color = black,
		canCollide = false,
		canQuery = false,
		castShadow = false,
		parent = m,
	})
	Builder.part({
		name = "Head",
		shape = Enum.PartType.Ball,
		size = Vector3.new(11, 14, 11),
		cframe = o * CFrame.new(0, 69, -2),
		color = black,
		canCollide = false,
		canQuery = false,
		castShadow = false,
		parent = m,
	})
	for _, s in { -1, 1 } do
		Builder.part({
			name = "Arm",
			size = Vector3.new(3, 52, 3),
			cframe = o * CFrame.new(s * 10, 36, -2) * CFrame.Angles(0, 0, s * math.rad(8)),
			color = black,
			canCollide = false,
			canQuery = false,
			castShadow = false,
			parent = m,
		})
		Builder.part({
			name = "Leg",
			size = Vector3.new(4, 24, 4),
			cframe = o * CFrame.new(s * 4, 8, 0),
			color = black,
			canCollide = false,
			canQuery = false,
			castShadow = false,
			parent = m,
		})
	end
	m.PrimaryPart = body
	-- The Watcher mesh, vast and black, replaces the stand-in shape. The
	-- parts stay (Body is the pivot) but are marked Skeleton so OldOneService
	-- never fades them in.
	local mesh = Assets.clone("Creature_Watcher")
	if mesh then
		for _, d in mesh:GetDescendants() do
			if d:IsA("Humanoid") or (d:IsA("BasePart") and d.Name == "HumanoidRootPart") then
				d:Destroy()
			end
		end
		local _, size = mesh:GetBoundingBox()
		mesh:ScaleTo(mesh:GetScale() * (74 / size.Y))
		local cf, scaled = mesh:GetBoundingBox()
		mesh:PivotTo(mesh:GetPivot() + ((o * CFrame.new(0, -4 + scaled.Y / 2, 0)).Position - cf.Position))
		for _, d in mesh:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = black
				d.CastShadow = false
			elseif d:IsA("SurfaceAppearance") then
				d.Color = Color3.fromRGB(14, 14, 16)
			end
		end
		for _, d in m:GetChildren() do
			if d:IsA("BasePart") then
				d:SetAttribute("Skeleton", true)
			end
		end
		mesh.Parent = m
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
		end
	end
	CollectionService:AddTag(m, "OldOne")
	return m
end

function Landmarks.boundary(parent: Instance)
	local f = Builder.folder("Boundary", parent)
	local r = W.PlayableRadius
	for _, b in { { r, 0, 2, r * 2 }, { -r, 0, 2, r * 2 }, { 0, r, r * 2, 2 }, { 0, -r, r * 2, 2 } } do
		Builder.part({
			name = "Wall",
			size = Vector3.new(b[3], 600, b[4]),
			cframe = CFrame.new(b[1], 200, b[2]),
			transparency = 1,
			canQuery = false,
			castShadow = false,
			parent = f,
		})
	end
	-- Kill floor far below in case anything falls through
	Builder.part({
		name = "Floor",
		size = Vector3.new(r * 2, 2, r * 2),
		cframe = CFrame.new(0, -60, 0),
		transparency = 1,
		canQuery = false,
		castShadow = false,
		parent = f,
	})
	-- North signal zone (end of prototype)
	local north = Builder.part({
		name = "NorthSignal",
		size = Vector3.new(120, 80, 30),
		cframe = CFrame.new(
			W.NorthRidge.x,
			Terrain.heightAt(W.NorthRidge.x, W.NorthRidge.z + 30) + 10,
			W.NorthRidge.z + 30
		),
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = f,
	})
	north:SetAttribute("Zone", "North")
	CollectionService:AddTag(north, "Zone")
	-- Threat area zone
	local threat = Builder.part({
		name = "ThreatZone",
		size = Vector3.new(W.ThreatArea.radius * 2, 120, W.ThreatArea.radius * 2),
		cframe = CFrame.new(W.ThreatArea.x, 20, W.ThreatArea.z),
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = f,
	})
	threat:SetAttribute("Zone", "Threat")
	CollectionService:AddTag(threat, "Zone")
end

return Landmarks

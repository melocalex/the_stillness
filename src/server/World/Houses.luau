--!strict
-- Procedural neighbors: cottages, two-storey houses, a ranger station with a
-- lookout, a barn, small sheds (emergency storm shelters) and a chapel ruin.
--
-- Watched houses follow the lake house conventions so the house-activity and
-- observation systems can drive them: tag "WatchedHouse", window panes
-- tagged "HousePane" with a Room attribute, a "<Room>Light" part per room
-- holding a disabled PointLight, a hidden "Figure" silhouette, and an
-- "Interior" zone part.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local Builder = require(script.Parent.Builder)
local Terrain = require(script.Parent.Terrain)

local Houses = {}

local GLOW = Color3.fromRGB(255, 196, 120)

type Style = {
	width: number,
	depth: number,
	storeyHeight: number,
	storeys: number,
	wall: Color3,
	wallMaterial: Enum.Material,
	trim: Color3,
	roof: Color3,
	roofMaterial: Enum.Material,
	roofPitch: number,
	porch: boolean,
	chimney: boolean,
	ruined: boolean,
}

local STYLES: { [string]: Style } = {
	Cottage = {
		width = 20,
		depth = 16,
		storeyHeight = 10,
		storeys = 1,
		wall = Color3.fromRGB(176, 168, 150),
		wallMaterial = Enum.Material.WoodPlanks,
		trim = Color3.fromRGB(70, 60, 52),
		roof = Color3.fromRGB(58, 64, 70),
		roofMaterial = Enum.Material.Slate,
		roofPitch = 34,
		porch = true,
		chimney = true,
		ruined = false,
	},
	TwoStorey = {
		width = 24,
		depth = 18,
		storeyHeight = 9,
		storeys = 2,
		wall = Color3.fromRGB(140, 150, 156),
		wallMaterial = Enum.Material.WoodPlanks,
		trim = Color3.fromRGB(226, 220, 206),
		roof = Color3.fromRGB(64, 46, 42),
		roofMaterial = Enum.Material.Slate,
		roofPitch = 32,
		porch = true,
		chimney = true,
		ruined = false,
	},
	Ranger = {
		width = 18,
		depth = 14,
		storeyHeight = 10,
		storeys = 1,
		wall = Color3.fromRGB(96, 84, 60),
		wallMaterial = Enum.Material.WoodPlanks,
		trim = Color3.fromRGB(60, 84, 60),
		roof = Color3.fromRGB(56, 74, 56),
		roofMaterial = Enum.Material.Metal,
		roofPitch = 24,
		porch = true,
		chimney = false,
		ruined = false,
	},
	Barn = {
		width = 30,
		depth = 22,
		storeyHeight = 15,
		storeys = 1,
		wall = Color3.fromRGB(128, 44, 38),
		wallMaterial = Enum.Material.WoodPlanks,
		trim = Color3.fromRGB(230, 224, 210),
		roof = Color3.fromRGB(70, 66, 64),
		roofMaterial = Enum.Material.Metal,
		roofPitch = 36,
		porch = false,
		chimney = false,
		ruined = false,
	},
	Shed = {
		width = 12,
		depth = 10,
		storeyHeight = 9,
		storeys = 1,
		wall = Color3.fromRGB(120, 122, 118),
		wallMaterial = Enum.Material.Concrete,
		trim = Color3.fromRGB(60, 62, 60),
		roof = Color3.fromRGB(80, 82, 80),
		roofMaterial = Enum.Material.Metal,
		roofPitch = 8,
		porch = false,
		chimney = false,
		ruined = false,
	},
	Chapel = {
		width = 16,
		depth = 28,
		storeyHeight = 14,
		storeys = 1,
		wall = Color3.fromRGB(150, 146, 136),
		wallMaterial = Enum.Material.Cobblestone,
		trim = Color3.fromRGB(90, 88, 84),
		roof = Color3.fromRGB(52, 48, 46),
		roofMaterial = Enum.Material.Slate,
		roofPitch = 45,
		porch = false,
		chimney = false,
		ruined = true,
	},
}

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

local function pane(parent: Instance, cf: CFrame, w: number, h: number, room: string?, trim: Color3): Part
	local p = Builder.part({
		name = "Pane",
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
	-- Frame
	for _, s in { -1, 1 } do
		box(
			parent,
			"Frame",
			cf * CFrame.new(s * (w / 2 + 0.15), 0, 0),
			Vector3.new(0.3, h + 0.6, 0.6),
			trim,
			Enum.Material.Wood
		)
		box(
			parent,
			"Frame",
			cf * CFrame.new(0, s * (h / 2 + 0.15), 0),
			Vector3.new(w + 0.6, 0.3, 0.6),
			trim,
			Enum.Material.Wood
		)
	end
	if room then
		p:SetAttribute("Room", room)
		CollectionService:AddTag(p, "HousePane")
	end
	return p
end

-- One wall with window/door openings: openings = { center, width, bottom, top, kind }
local function wallWithOpenings(
	parent: Instance,
	o: CFrame,
	style: Style,
	axis: "x" | "z",
	fixed: number,
	from: number,
	to: number,
	y0: number,
	openings: { { any } },
	room: string?,
	outward: number
)
	local h = style.storeyHeight
	local function seg(a: number, b: number, ya: number, yb: number)
		if b - a < 0.05 or yb - ya < 0.05 then
			return
		end
		local size = if axis == "x" then Vector3.new(b - a, yb - ya, 1) else Vector3.new(1, yb - ya, b - a)
		local pos = if axis == "x"
			then Vector3.new((a + b) / 2, y0 + (ya + yb) / 2, fixed)
			else Vector3.new(fixed, y0 + (ya + yb) / 2, (a + b) / 2)
		box(parent, "Wall", o * CFrame.new(pos), size, style.wall, style.wallMaterial)
	end
	local cursor = from
	for _, op in openings do
		local c, w, bottom, top, kind =
			op[1] :: number, op[2] :: number, op[3] :: number, op[4] :: number, op[5] :: string
		seg(cursor, c - w / 2, 0, h)
		seg(c - w / 2, c + w / 2, 0, bottom)
		seg(c - w / 2, c + w / 2, top, h)
		cursor = c + w / 2
		if kind == "window" and not style.ruined then
			local center = if axis == "x"
				then Vector3.new(c, y0 + (bottom + top) / 2, fixed)
				else Vector3.new(fixed, y0 + (bottom + top) / 2, c)
			local facing = if axis == "x"
				then CFrame.new(center) * CFrame.Angles(0, if outward > 0 then 0 else math.pi, 0)
				else CFrame.new(center) * CFrame.Angles(
					0,
					if outward > 0 then math.rad(90) else math.rad(-90),
					0
				)
			pane(parent, o * facing, w, top - bottom, room, style.trim)
		end
	end
	seg(cursor, to, 0, h)
end

local function figure(parent: Instance, cf: CFrame, height: number): Model
	local m = Builder.model("Figure", parent)
	local body = Builder.part({
		name = "Body",
		size = Vector3.new(1.6, height * 0.62, 0.8),
		cframe = cf * CFrame.new(0, height * 0.31, 0),
		color = Color3.fromRGB(8, 8, 10),
		canCollide = false,
		canQuery = false,
		castShadow = false,
		transparency = 1,
		parent = m,
	})
	Builder.part({
		name = "Head",
		shape = Enum.PartType.Ball,
		size = Vector3.new(1.1, 1.3, 1.1),
		cframe = cf * CFrame.new(0, height * 0.7, 0),
		color = Color3.fromRGB(8, 8, 10),
		canCollide = false,
		canQuery = false,
		castShadow = false,
		transparency = 1,
		parent = m,
	})
	m.PrimaryPart = body
	m:SetAttribute("Home", m:GetPivot())
	return m
end

local function roof(parent: Instance, o: CFrame, style: Style, topY: number)
	local w, d = style.width, style.depth
	local pitch = math.rad(style.roofPitch)
	local run = d / 2 + 1.4
	local rise = math.tan(pitch) * run
	local slant = run / math.cos(pitch)
	for _, s in { -1, 1 } do
		local slab = box(
			parent,
			"Roof",
			o * CFrame.new(0, topY + rise / 2, s * run / 2) * CFrame.Angles(s * pitch, 0, 0),
			Vector3.new(w + 2.4, 0.8, slant + 0.4),
			style.roof,
			style.roofMaterial
		)
		if style.ruined and s == 1 then
			slab:Destroy() -- half the chapel roof has fallen in
		end
	end
	if not style.ruined then
		for _, x in { -w / 2, w / 2 } do
			Builder.wedge({
				name = "Gable",
				size = Vector3.new(1, rise, d / 2),
				cframe = o * CFrame.new(x, topY + rise / 2, d / 4) * CFrame.Angles(0, math.pi, 0),
				color = style.wall,
				material = style.wallMaterial,
				parent = parent,
			})
			Builder.wedge({
				name = "Gable",
				size = Vector3.new(1, rise, d / 2),
				cframe = o * CFrame.new(x, topY + rise / 2, -d / 4),
				color = style.wall,
				material = style.wallMaterial,
				parent = parent,
			})
		end
	end
end

function Houses.build(parent: Instance, spec: { [string]: any }): Model
	local style = STYLES[spec.style :: string] or STYLES.Cottage
	local m = Builder.model(spec.id :: string, parent)
	local x, z = spec.x :: number, spec.z :: number
	local y = Terrain.clearingHeight(x, z) or Terrain.heightAt(x, z)
	local o = CFrame.new(x, y + 1, z) * CFrame.Angles(0, math.rad(spec.yaw :: number), 0)
	local w, d, sh = style.width, style.depth, style.storeyHeight
	local watched = spec.watched == true

	-- Foundation and floors
	box(
		m,
		"Foundation",
		o * CFrame.new(0, -2, 0),
		Vector3.new(w + 1.4, 4, d + 1.4),
		Color3.fromRGB(100, 96, 90),
		Enum.Material.Cobblestone
	)
	box(m, "Floor", o * CFrame.new(0, -0.25, 0), Vector3.new(w, 0.5, d), Color3.fromRGB(110, 84, 60))
	for storey = 1, style.storeys - 1 do
		box(
			m,
			"UpperFloor",
			o * CFrame.new(-2, storey * sh, 0),
			Vector3.new(w - 4, 0.6, d),
			Color3.fromRGB(100, 76, 56)
		)
	end

	for storey = 0, style.storeys - 1 do
		local y0 = storey * sh
		local room = if storey == 0 then "Downstairs" else "Upstairs"
		local winTop, winBottom = math.min(sh - 2, 7), 3
		local front: { { any } } = {}
		local function op(c: number, width: number, b: number, t: number, kind: string): { any }
			return { c, width, b, t, kind }
		end
		if storey == 0 then
			table.insert(front, op(0, 4.5, 0, 8, "door"))
			table.insert(front, op(-w / 4 - 1, 4, winBottom, winTop, "window"))
			table.insert(front, op(w / 4 + 1, 4, winBottom, winTop, "window"))
		else
			table.insert(front, op(-w / 4, 4, winBottom, winTop, "window"))
			table.insert(front, op(w / 4, 4, winBottom, winTop, "window"))
		end
		if style.ruined then
			front = { { 0, 6, 0, 11, "door" }, { -5, 2.5, 4, 11, "window" }, { 5, 2.5, 4, 11, "window" } }
		end
		wallWithOpenings(m, o, style, "x", d / 2, -w / 2, w / 2, y0, front, room, 1)
		wallWithOpenings(
			m,
			o,
			style,
			"x",
			-d / 2,
			-w / 2,
			w / 2,
			y0,
			{ { 0, 5, winBottom, winTop, "window" } },
			room,
			-1
		)
		wallWithOpenings(
			m,
			o,
			style,
			"z",
			w / 2,
			-d / 2,
			d / 2,
			y0,
			{ { 0, 4, winBottom, winTop, "window" } },
			room,
			1
		)
		wallWithOpenings(
			m,
			o,
			style,
			"z",
			-w / 2,
			-d / 2,
			d / 2,
			y0,
			{ { 0, 4, winBottom, winTop, "window" } },
			room,
			-1
		)
		if watched and not style.ruined then
			local bulb = Builder.part({
				name = room .. "Light",
				size = Vector3.new(0.6, 0.6, 0.6),
				cframe = o * CFrame.new(0, y0 + sh - 3, 1),
				color = GLOW,
				transparency = 1,
				canCollide = false,
				canQuery = false,
				parent = m,
			})
			local l = Builder.pointLight(bulb, GLOW, 18, 1.4, false)
			l.Enabled = false
			bulb:SetAttribute("Room", room)
		end
	end
	local topY = style.storeys * sh
	roof(m, o, style, topY)
	if style.chimney then
		box(
			m,
			"Chimney",
			o * CFrame.new(-w / 2 + 3, topY + 4, -d / 4),
			Vector3.new(2.4, 10, 2.4),
			Color3.fromRGB(110, 76, 62),
			Enum.Material.Brick
		)
	end
	if style.storeys > 1 then
		for i = 1, 9 do
			box(
				m,
				"Stair",
				o * CFrame.new(w / 2 - 2, i * (sh / 9), -d / 2 + 1.5 + i * 1.2),
				Vector3.new(3, 0.8, 1.3),
				Color3.fromRGB(90, 68, 50),
				Enum.Material.Wood
			)
		end
	end
	if style.porch then
		box(
			m,
			"Porch",
			o * CFrame.new(0, -0.4, d / 2 + 3),
			Vector3.new(10, 0.8, 6),
			Color3.fromRGB(104, 76, 52)
		)
		for _, px in { -4.6, 4.6 } do
			box(
				m,
				"Post",
				o * CFrame.new(px, 4, d / 2 + 5.6),
				Vector3.new(0.6, 8, 0.6),
				style.trim,
				Enum.Material.Wood
			)
		end
		box(
			m,
			"PorchRoof",
			o * CFrame.new(0, 8.2, d / 2 + 3) * CFrame.Angles(math.rad(-10), 0, 0),
			Vector3.new(11, 0.5, 7),
			style.roof,
			style.roofMaterial
		)
	end

	-- Style extras
	if spec.style == "Ranger" then
		-- Lookout tower with a lit cab (good sightlines, poor protection).
		local tower = o * CFrame.new(w / 2 + 8, 0, 0)
		for _, c in { { -2.5, -2.5 }, { 2.5, -2.5 }, { -2.5, 2.5 }, { 2.5, 2.5 } } do
			box(
				m,
				"TowerLeg",
				tower * CFrame.new(c[1], 13, c[2]),
				Vector3.new(0.8, 26, 0.8),
				Color3.fromRGB(90, 70, 50),
				Enum.Material.Wood
			)
		end
		box(m, "TowerCab", tower * CFrame.new(0, 26.5, 0), Vector3.new(8, 0.6, 8), Color3.fromRGB(96, 74, 52))
		box(
			m,
			"TowerRoof",
			tower * CFrame.new(0, 32, 0),
			Vector3.new(9, 0.6, 9),
			style.roof,
			style.roofMaterial
		)
		for i = 1, 12 do
			box(
				m,
				"Ladder",
				tower * CFrame.new(0, i * 2.1, 2.9),
				Vector3.new(2, 0.3, 0.3),
				Color3.fromRGB(70, 56, 44),
				Enum.Material.Wood
			)
		end
	elseif spec.style == "Barn" then
		box(
			m,
			"HayBale",
			o * CFrame.new(-8, 1.5, -5),
			Vector3.new(5, 3, 3),
			Color3.fromRGB(196, 170, 96),
			Enum.Material.Fabric
		)
		box(
			m,
			"HayBale",
			o * CFrame.new(-8, 4.5, -5),
			Vector3.new(5, 3, 3),
			Color3.fromRGB(186, 160, 90),
			Enum.Material.Fabric
		)
		box(
			m,
			"Cart",
			o * CFrame.new(7, 1.5, 4),
			Vector3.new(4, 2, 7),
			Color3.fromRGB(90, 66, 46),
			Enum.Material.Wood
		)
	elseif spec.style == "Chapel" then
		local tower = o * CFrame.new(0, 0, -d / 2 - 3)
		box(
			m,
			"BellTower",
			tower * CFrame.new(0, 12, 0),
			Vector3.new(6, 24, 6),
			style.wall,
			style.wallMaterial
		)
		box(
			m,
			"BellRoof",
			tower * CFrame.new(0, 25.5, 0) * CFrame.Angles(0, math.rad(45), 0),
			Vector3.new(6, 3, 6),
			style.roof,
			style.roofMaterial
		)
		for i = 1, 6 do
			box(
				m,
				"Rubble",
				o * CFrame.new((i - 3.5) * 2, 0.6, 6 - i),
				Vector3.new(2, 1.2, 1.6),
				style.wall,
				Enum.Material.Cobblestone
			)
		end
	end

	-- Interior zone (objectives, emergency shelter checks)
	local vol = Builder.part({
		name = "Interior",
		size = Vector3.new(w - 1, style.storeys * sh, d - 1),
		cframe = o * CFrame.new(0, style.storeys * sh / 2, 0),
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = m,
	})
	vol:SetAttribute("Zone", spec.id)
	CollectionService:AddTag(vol, "Zone")
	if spec.emergency then
		-- Roofed and walled but the doorway is open: dry, not safe.
		vol:SetAttribute("RainShelter", true)
		m:SetAttribute("EmergencyShelter", true)
	end
	if watched and not style.ruined then
		figure(m, o * CFrame.new(-w / 4 - 1, if style.storeys > 1 then sh else 0, d / 2 - 2), 6.2)
		m:SetAttribute("Upstairs", false)
		m:SetAttribute("Downstairs", false)
		m:SetAttribute("Broken", false)
		CollectionService:AddTag(m, "WatchedHouse")
	elseif watched and style.ruined then
		-- The chapel: a light that should not be there, sometimes.
		local candle = Builder.part({
			name = "DownstairsLight",
			size = Vector3.new(0.4, 0.4, 0.4),
			cframe = o * CFrame.new(0, 3, -d / 2 + 3),
			color = GLOW,
			transparency = 1,
			canCollide = false,
			canQuery = false,
			parent = m,
		})
		local l = Builder.pointLight(candle, Color3.fromRGB(255, 160, 90), 14, 1, false)
		l.Enabled = false
		candle:SetAttribute("Room", "Downstairs")
		m:SetAttribute("Downstairs", false)
		CollectionService:AddTag(m, "WatchedHouse")
	end
	m:SetAttribute("Style", spec.style)
	return m
end

function Houses.buildAll(parent: Instance): { Model }
	local folder = Builder.folder("Neighbors", parent)
	local out = {}
	for _, spec in WorldConfig.Houses do
		table.insert(out, Houses.build(folder, spec :: any))
	end
	return out
end

return Houses

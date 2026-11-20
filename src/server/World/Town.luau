--!strict
-- Chapter 37 sites: the edge of Pinehaven (hardware store, Frank's tool
-- shed, the diner, the weather station), the sensor mast, Martha's cottage,
-- the old wood shed where Biscuit hides, and Maya's garden. Positions come
-- from TownConfig.Sites; ground height from a raycast on the terrain, so the
-- sites follow whatever valley the terrain builder makes.
--
-- Contracts with TownService (all are attributes on parts):
--   NpcSpot = npc id            where the NPC stands, facing out
--   Interaction = id            an interaction prompt anchor
--   RepairProject = project id  a restoration prompt anchor
--   SiteAnchor = site id        reach / investigate anchor
--   ShopVendor = npc id         shop counter
--   MissingSpot = id            where a missing animal hides
--   HomeSpot = id               where it rests once home
--   StageOf, ShowFrom, ShowUntil   visible for project stages [from, until)
--   ShowFlag / HideFlag         visible only with / without a quest flag
--   LitFlag, NightOnly          lights and glow on with a flag (at night)
--   Spin                        client spins this part (deg/s) when shown
-- Every part with a visual attribute is tagged "TownVisual".

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TownConfig = require(ReplicatedStorage.Shared.Config.TownConfig)
local Builder = require(script.Parent.Builder)

local Town = {}

local C = {
	plank = Color3.fromRGB(122, 88, 60),
	plankDark = Color3.fromRGB(84, 62, 44),
	plankGrey = Color3.fromRGB(112, 104, 94),
	white = Color3.fromRGB(226, 222, 210),
	roof = Color3.fromRGB(70, 60, 58),
	roofRed = Color3.fromRGB(120, 52, 44),
	stone = Color3.fromRGB(104, 100, 96),
	glass = Color3.fromRGB(90, 110, 120),
	warm = Color3.fromRGB(255, 196, 120),
	metal = Color3.fromRGB(150, 150, 154),
	soil = Color3.fromRGB(70, 52, 38),
	leaf = Color3.fromRGB(86, 140, 70),
	dead = Color3.fromRGB(110, 92, 60),
}

local built: { [string]: Model } = {}

local function groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1200, 0), params)
	return if hit then hit.Position.Y else 6
end

local function wet(x: number, z: number): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1200, 0), params)
	return hit ~= nil and hit.Material == Enum.Material.Water
end

-- The configured spot, or the nearest one around it whose footprint is
-- all dry land: a site never ends up standing in a creek.
local function dryNear(x: number, z: number, r: number): (number, number)
	-- Centre, a ring at r and the four points at 1.6 r (porches face any way).
	local function dry(cx: number, cz: number): boolean
		if wet(cx, cz) then
			return false
		end
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			local far = if i % 2 == 0 then 1.6 else 1
			if wet(cx + math.cos(a) * r * far, cz + math.sin(a) * r * far) then
				return false
			end
		end
		return true
	end
	if dry(x, z) then
		return x, z
	end
	for ring = 1, 10 do
		local d = ring * 12
		for i = 0, 11 do
			local a = i / 12 * math.pi * 2
			local cx, cz = x + math.cos(a) * d, z + math.sin(a) * d
			if dry(cx, cz) then
				return cx, cz
			end
		end
	end
	return x, z
end

local function box(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?
): Part
	return Builder.part({
		name = name,
		cframe = cf,
		size = size,
		color = color,
		material = material or Enum.Material.WoodPlanks,
		parent = parent,
		canCollide = if collide == nil then true else collide,
	})
end

local function marker(parent: Instance, name: string, cf: CFrame, attrs: { [string]: any }): Part
	local p = Builder.part({
		name = name,
		cframe = cf,
		size = Vector3.new(2, 2, 2),
		transparency = 1,
		canCollide = false,
		canQuery = false,
		castShadow = false,
		parent = parent,
	})
	for k, v in attrs do
		p:SetAttribute(k, v)
	end
	return p
end

local function visual(p: BasePart, attrs: { [string]: any }): BasePart
	for k, v in attrs do
		p:SetAttribute(k, v)
	end
	p:SetAttribute("BaseTransparency", p.Transparency)
	p:SetAttribute("BaseCollide", p.CanCollide)
	CollectionService:AddTag(p, "TownVisual")
	return p
end

local function staged(p: BasePart, project: string, from: number, untilStage: number?): BasePart
	return visual(p, { StageOf = project, ShowFrom = from, ShowUntil = untilStage })
end

-- A sign facing the building's front (+Z of the site frame).
local function sign(parent: Instance, cf: CFrame, size: Vector3, text: string, bg: Color3, fg: Color3): Part
	local p = box(parent, "Sign", cf, size, bg, Enum.Material.Wood, false)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = fg
	label.FontFace = Font.fromEnum(Enum.Font.Merriweather)
	label.Parent = gui
	return p
end

local function lamp(parent: Instance, cf: CFrame, attrs: { [string]: any }): Part
	local p = box(parent, "Lamp", cf, Vector3.new(0.8, 1, 0.8), C.warm, Enum.Material.Glass, false)
	local light = Builder.pointLight(p, C.warm, 22, 1.6, true)
	light.Enabled = false
	visual(p, attrs)
	return p
end

-- Site frame on the ground: floor height is the highest corner, with a
-- foundation down to the lowest so nothing floats on a slope.
local function frame(parent: Instance, x: number, z: number, yaw: number, w: number, d: number): CFrame
	local rot = CFrame.Angles(0, math.rad(yaw), 0)
	local hi, lo = -math.huge, math.huge
	for _, c in { { 0, 0 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local off = rot:VectorToWorldSpace(Vector3.new(c[1] * w / 2, 0, c[2] * d / 2))
		local y = groundY(x + off.X, z + off.Z)
		hi = math.max(hi, y)
		lo = math.min(lo, y)
	end
	local o = CFrame.new(x, hi + 0.3, z) * rot
	local depth = hi - lo + 3
	box(
		parent,
		"Foundation",
		o * CFrame.new(0, -depth / 2, 0),
		Vector3.new(w, depth, d),
		C.stone,
		Enum.Material.Cobblestone
	)
	return o
end

local function clearAround(x: number, z: number, r: number)
	local world = workspace:FindFirstChild("World")
	local forest = world and world:FindFirstChild("Forest")
	if not forest or r <= 0 then
		return
	end
	for _, group in forest:GetChildren() do
		for _, item in group:GetChildren() do
			local pos: Vector3? = nil
			if item:IsA("Model") then
				pos = item:GetPivot().Position
			elseif item:IsA("BasePart") then
				pos = item.Position
			end
			if pos and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(x, 0, z)).Magnitude < r then
				item:Destroy()
			end
		end
	end
end

local function facingOut(o: CFrame, pos: Vector3): CFrame
	return o * CFrame.new(pos) * CFrame.Angles(0, math.pi, 0)
end

-- Four walls with a door gap in the front (+Z) wall.
local function walls(
	m: Model,
	o: CFrame,
	w: number,
	d: number,
	h: number,
	door: number,
	color: Color3,
	windows: boolean?
)
	box(m, "WallBack", o * CFrame.new(0, h / 2, -d / 2 + 0.5), Vector3.new(w, h, 1), color)
	box(m, "WallL", o * CFrame.new(-w / 2 + 0.5, h / 2, 0), Vector3.new(1, h, d), color)
	box(m, "WallR", o * CFrame.new(w / 2 - 0.5, h / 2, 0), Vector3.new(1, h, d), color)
	local side = (w - door) / 2
	if windows then
		-- Front wall pieces around two windows, one each side of the door.
		local win = math.min(side - 2, 5)
		local edge = (side - win) / 2
		for _, s in { -1, 1 } do
			local cx = s * (door / 2 + side / 2)
			box(
				m,
				"WallF",
				o * CFrame.new(s * (w / 2 - edge / 2), h / 2, d / 2 - 0.5),
				Vector3.new(edge, h, 1),
				color
			)
			box(
				m,
				"WallF",
				o * CFrame.new(s * (door / 2 + edge / 2), h / 2, d / 2 - 0.5),
				Vector3.new(edge, h, 1),
				color
			)
			box(m, "WallF", o * CFrame.new(cx, 1.5, d / 2 - 0.5), Vector3.new(win, 3, 1), color)
			box(m, "WallF", o * CFrame.new(cx, h - 1.5, d / 2 - 0.5), Vector3.new(win, 3, 1), color)
			local pane = box(
				m,
				"Window",
				o * CFrame.new(cx, h / 2, d / 2 - 0.5),
				Vector3.new(win, h - 6, 0.3),
				C.glass,
				Enum.Material.Glass
			)
			pane.Transparency = 0.35
			pane:SetAttribute("Glow", true)
		end
	else
		for _, s in { -1, 1 } do
			box(
				m,
				"WallF",
				o * CFrame.new(s * (door / 2 + side / 2), h / 2, d / 2 - 0.5),
				Vector3.new(side, h, 1),
				color
			)
		end
	end
	box(m, "Lintel", o * CFrame.new(0, h - 1, d / 2 - 0.5), Vector3.new(door, 2, 1), color)
end

local function flatRoof(m: Model, o: CFrame, w: number, d: number, h: number, color: Color3)
	box(
		m,
		"Roof",
		o * CFrame.new(0, h + 0.4, 0.5),
		Vector3.new(w + 2, 0.8, d + 3),
		color,
		Enum.Material.Slate
	)
end

local function gableRoof(m: Model, o: CFrame, w: number, d: number, h: number, color: Color3)
	local rise = w * 0.35
	for _, s in { -1, 1 } do
		local wedge = Builder.wedge({
			name = "Roof",
			size = Vector3.new(d + 2, rise, w / 2 + 1),
			cframe = o
				* CFrame.new(s * (w / 4 + 0.5), h + rise / 2, 0)
				* CFrame.Angles(0, math.rad(s * -90), 0),
			color = color,
			material = Enum.Material.Slate,
		})
		wedge.Parent = m
	end
end

local function porch(m: Model, o: CFrame, w: number, d: number, depth: number, h: number)
	box(m, "Porch", o * CFrame.new(0, 0.25, d / 2 + depth / 2), Vector3.new(w, 0.5, depth), C.plankDark)
	for _, s in { -1, 1 } do
		box(
			m,
			"Post",
			o * CFrame.new(s * (w / 2 - 0.5), h / 2, d / 2 + depth - 0.5),
			Vector3.new(0.6, h, 0.6),
			C.plankDark
		)
	end
	box(
		m,
		"Awning",
		o * CFrame.new(0, h, d / 2 + depth / 2),
		Vector3.new(w, 0.4, depth + 0.5),
		C.roof,
		Enum.Material.Slate
	)
end

-- Sites -------------------------------------------------------------------

local function hardwareStore(parent: Instance, s: any): Model
	local m = Builder.model("HardwareStore", parent)
	local w, d, h = 20, 14, 10
	local o = frame(m, s.x, s.z, s.yaw, w + 2, d + 8)
	box(m, "Floor", o * CFrame.new(0, 0.25, 0), Vector3.new(w, 0.5, d), C.plankDark)
	walls(m, o, w, d, h, 5, Color3.fromRGB(96, 110, 92), true)
	flatRoof(m, o, w, d, h, C.roof)
	porch(m, o, w, d, 6, h - 1)
	sign(
		m,
		o * CFrame.new(0, h + 1.6, d / 2 + 0.6),
		Vector3.new(14, 2.2, 0.4),
		"PINEHAVEN HARDWARE",
		C.plankDark,
		C.white
	)
	-- Frank works a counter of crates on the porch.
	local counter = box(m, "Counter", o * CFrame.new(-4, 1.6, d / 2 + 4.2), Vector3.new(6, 2.2, 1.6), C.plank)
	counter:SetAttribute("ShopVendor", "frank")
	marker(m, "NpcSpot", facingOut(o, Vector3.new(-4, 0.5, d / 2 + 2.4)), { Npc = "frank" })
	box(m, "Barrel", o * CFrame.new(5, 1.6, d / 2 + 3), Vector3.new(2, 2.6, 2), C.plankDark)
	lamp(m, o * CFrame.new(0, h - 2, d / 2 + 5.4), { NightOnly = true })
	return m
end

local function frankShed(parent: Instance, s: any): Model
	local m = Builder.model("FrankShed", parent)
	local w, d, h = 8, 8, 7
	local o = frame(m, s.x, s.z, s.yaw, w, d)
	local P = "FrankShed"
	box(m, "Floor", o * CFrame.new(0, 0.2, 0), Vector3.new(w, 0.4, d), C.plankDark)
	-- Storm-wrecked: walls leaning, boards on the ground, no roof, no door.
	staged(
		box(
			m,
			"Leaning",
			o * CFrame.new(0, h / 2 - 0.6, -d / 2 + 1.4) * CFrame.Angles(math.rad(-22), 0, 0),
			Vector3.new(w, h, 0.8),
			C.plankGrey
		),
		P,
		0,
		1
	)
	staged(
		box(
			m,
			"Leaning",
			o * CFrame.new(-w / 2 + 1.2, h / 2 - 0.8, 0) * CFrame.Angles(0, 0, math.rad(18)),
			Vector3.new(0.8, h, d),
			C.plankGrey
		),
		P,
		0,
		1
	)
	staged(
		box(
			m,
			"Fallen",
			o * CFrame.new(w / 2 + 2, 0.5, 1) * CFrame.Angles(0, 0, math.rad(84)),
			Vector3.new(0.8, h, d - 1),
			C.plankGrey
		),
		P,
		0,
		1
	)
	for i = 1, 5 do
		staged(
			box(
				m,
				"Board",
				o
					* CFrame.new(-3 + i * 1.3, 0.35, d / 2 + 2 + (i % 2))
					* CFrame.Angles(0, math.rad(i * 23), 0),
				Vector3.new(0.6, 0.3, 5),
				C.plank,
				nil,
				false
			),
			P,
			0,
			2
		)
	end
	-- Walls straight (stage 1+).
	staged(box(m, "Wall", o * CFrame.new(0, h / 2, -d / 2 + 0.4), Vector3.new(w, h, 0.8), C.plank), P, 1)
	staged(box(m, "Wall", o * CFrame.new(-w / 2 + 0.4, h / 2, 0), Vector3.new(0.8, h, d), C.plank), P, 1)
	staged(box(m, "Wall", o * CFrame.new(w / 2 - 0.4, h / 2, 0), Vector3.new(0.8, h, d), C.plank), P, 1)
	for _, sx in { -1, 1 } do
		staged(
			box(m, "Wall", o * CFrame.new(sx * 2.75, h / 2, d / 2 - 0.4), Vector3.new(2.5, h, 0.8), C.plank),
			P,
			1
		)
	end
	-- Roof (stage 2+).
	staged(
		box(
			m,
			"Roof",
			o * CFrame.new(0, h + 0.6, 0) * CFrame.Angles(math.rad(-8), 0, 0),
			Vector3.new(w + 1.4, 0.5, d + 1.6),
			C.roofRed,
			Enum.Material.Slate
		),
		P,
		2
	)
	-- Door, lantern and a fresh toolbox (stage 3).
	staged(
		box(m, "Door", o * CFrame.new(0, h / 2 - 0.5, d / 2 - 0.3), Vector3.new(3, h - 1, 0.4), C.plankDark),
		P,
		3
	)
	lamp(m, o * CFrame.new(2.6, h - 1.4, d / 2 + 0.2), { StageOf = P, ShowFrom = 3, NightOnly = true })
	staged(
		box(
			m,
			"Toolbox",
			o * CFrame.new(-2.6, 0.9, d / 2 + 1),
			Vector3.new(1.6, 1, 0.8),
			Color3.fromRGB(160, 40, 36),
			Enum.Material.Metal
		),
		P,
		3
	)
	marker(m, "RepairPoint", o * CFrame.new(0, 2, d / 2 + 1.5), { RepairProject = P })
	return m
end

local function diner(parent: Instance, s: any): Model
	local m = Builder.model("Diner", parent)
	local w, d, h = 22, 14, 10
	local o = frame(m, s.x, s.z, s.yaw, w + 2, d + 6)
	box(
		m,
		"Floor",
		o * CFrame.new(0, 0.25, 0),
		Vector3.new(w, 0.5, d),
		Color3.fromRGB(180, 170, 150),
		Enum.Material.Marble
	)
	walls(m, o, w, d, h, 5, Color3.fromRGB(196, 176, 140), true)
	flatRoof(m, o, w, d, h, C.roofRed)
	porch(m, o, w, d, 4, h - 1)
	local sg = sign(
		m,
		o * CFrame.new(0, h + 1.8, d / 2 + 0.6),
		Vector3.new(14, 2.6, 0.4),
		"ELLEN'S DINER",
		Color3.fromRGB(40, 30, 28),
		Color3.fromRGB(255, 120, 100)
	)
	visual(sg, { LitFlag = "dinerOpen" })
	Builder.pointLight(sg, Color3.fromRGB(255, 120, 100), 16, 1.2).Enabled = false
	local open = sign(
		m,
		o * CFrame.new(3.6, 3.4, d / 2 + 0.1),
		Vector3.new(2, 0.9, 0.2),
		"OPEN",
		C.white,
		Color3.fromRGB(40, 120, 60)
	)
	visual(open, { ShowFlag = "dinerOpen" })
	local closed = sign(
		m,
		o * CFrame.new(3.6, 3.4, d / 2 + 0.1),
		Vector3.new(2, 0.9, 0.2),
		"CLOSED",
		C.white,
		Color3.fromRGB(150, 50, 40)
	)
	visual(closed, { HideFlag = "dinerOpen" })
	-- Inside: counter, stools, the stove at the back.
	local counter =
		box(m, "Counter", o * CFrame.new(2, 1.6, -2), Vector3.new(12, 2.6, 1.6), Color3.fromRGB(150, 60, 50))
	counter:SetAttribute("ShopVendor", "ellen")
	for i = 0, 3 do
		box(
			m,
			"Stool",
			o * CFrame.new(-2 + i * 3, 1.1, 0.2),
			Vector3.new(1.2, 1.6, 1.2),
			Color3.fromRGB(200, 60, 50),
			Enum.Material.Fabric
		)
	end
	local stove = box(
		m,
		"Stove",
		o * CFrame.new(-7.5, 1.8, -d / 2 + 2),
		Vector3.new(4, 3, 2.4),
		Color3.fromRGB(40, 40, 44),
		Enum.Material.Metal
	)
	stove:SetAttribute("Interaction", "DinerStove")
	local glow = box(
		m,
		"Burner",
		o * CFrame.new(-7.5, 3.35, -d / 2 + 2),
		Vector3.new(2.6, 0.1, 1.4),
		Color3.fromRGB(255, 110, 40),
		Enum.Material.Neon,
		false
	)
	visual(glow, { ShowFlag = "dinerOpen" })
	local inside = box(
		m,
		"CeilingLamp",
		o * CFrame.new(0, h - 1, 0),
		Vector3.new(1.2, 0.6, 1.2),
		C.warm,
		Enum.Material.Glass,
		false
	)
	Builder.pointLight(inside, C.warm, 26, 1.4, true).Enabled = false
	visual(inside, { LitFlag = "dinerOpen" })
	for _, d2 in m:GetDescendants() do
		if d2:IsA("BasePart") and d2:GetAttribute("Glow") == true then
			visual(d2, { LitFlag = "dinerOpen", NightOnly = true })
		end
	end
	marker(m, "NpcSpot", facingOut(o, Vector3.new(4, 0.5, -3.6)), { Npc = "ellen" })
	return m
end

local function weatherStation(parent: Instance, s: any): Model
	local m = Builder.model("WeatherStation", parent)
	local w, d, h = 12, 10, 8
	local o = frame(m, s.x, s.z, s.yaw, w + 8, d + 6)
	box(m, "Floor", o * CFrame.new(0, 0.25, 0), Vector3.new(w, 0.5, d), C.plankDark)
	walls(m, o, w, d, h, 4, C.white)
	gableRoof(m, o, w, d, h, Color3.fromRGB(60, 80, 100))
	porch(m, o, w, d, 4, h - 1)
	sign(
		m,
		o * CFrame.new(0, h - 2.6, d / 2 + 4.3),
		Vector3.new(10, 1.4, 0.3),
		"PINEHAVEN WEATHER STATION",
		Color3.fromRGB(40, 60, 80),
		C.white
	)
	-- A louvred instrument screen on legs beside the hut.
	box(
		m,
		"Screen",
		o * CFrame.new(w / 2 + 3, 4, 2),
		Vector3.new(2.4, 2.4, 2.4),
		C.white,
		Enum.Material.WoodPlanks
	)
	for _, sx in { -0.9, 0.9 } do
		for _, sz in { -0.9, 0.9 } do
			box(m, "Leg", o * CFrame.new(w / 2 + 3 + sx, 1.4, 2 + sz), Vector3.new(0.3, 2.8, 0.3), C.white)
		end
	end
	local status = box(
		m,
		"StatusLamp",
		o * CFrame.new(-3, h - 2, d / 2 + 0.6),
		Vector3.new(0.7, 0.7, 0.3),
		Color3.fromRGB(80, 220, 120),
		Enum.Material.Neon,
		false
	)
	Builder.pointLight(status, Color3.fromRGB(80, 220, 120), 8, 1).Enabled = false
	-- Dark until the forecast works (TownService swaps the material).
	status.Material = Enum.Material.SmoothPlastic
	visual(status, { LitFlag = "forecastUnlocked", NeonWhenLit = true })
	marker(m, "NpcSpot", facingOut(o, Vector3.new(2.5, 0.5, d / 2 + 1.8)), { Npc = "hale" })
	lamp(m, o * CFrame.new(0, h - 2.2, d / 2 + 3.4), { NightOnly = true })
	return m
end

local function sensorMast(parent: Instance, s: any): Model
	local m = Builder.model("SensorMast", parent)
	local o = frame(m, s.x, s.z, s.yaw, 6, 6)
	local P = "WeatherSensor"
	box(m, "Pad", o * CFrame.new(0, 0.3, 0), Vector3.new(6, 0.6, 6), C.stone, Enum.Material.Concrete)
	box(m, "Mast", o * CFrame.new(0, 8, 0), Vector3.new(0.6, 16, 0.6), C.metal, Enum.Material.Metal)
	box(m, "Arm", o * CFrame.new(0, 13, 0), Vector3.new(4, 0.3, 0.3), C.metal, Enum.Material.Metal)
	box(m, "Box", o * CFrame.new(0, 3, 0.6), Vector3.new(1.6, 2, 0.8), C.white, Enum.Material.Metal)
	-- Broken: bent cups in the grass, wires hanging.
	for i = 1, 3 do
		staged(
			box(
				m,
				"BrokenCup",
				o * CFrame.new(-2 + i * 1.2, 0.8, 2.2),
				Vector3.new(0.7, 0.4, 0.7),
				C.metal,
				Enum.Material.Metal,
				false
			),
			P,
			0,
			1
		)
	end
	for _, sx in { -0.4, 0.5 } do
		staged(
			box(
				m,
				"LooseWire",
				o * CFrame.new(sx, 9, 0.5) * CFrame.Angles(math.rad(10), 0, math.rad(sx * 20)),
				Vector3.new(0.12, 6, 0.12),
				Color3.fromRGB(30, 30, 30),
				Enum.Material.Plastic,
				false
			),
			P,
			0,
			2
		)
	end
	-- Cups fitted (stage 1+), spinning once reporting (stage 2).
	local hub = staged(
		box(
			m,
			"Cups",
			o * CFrame.new(0, 16.6, 0),
			Vector3.new(0.5, 0.6, 0.5),
			C.metal,
			Enum.Material.Metal,
			false
		),
		P,
		1
	)
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3
		local arm = box(
			m,
			"CupArm",
			hub.CFrame * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -1),
			Vector3.new(0.15, 0.15, 2),
			C.metal,
			Enum.Material.Metal,
			false
		)
		local cup = box(
			m,
			"Cup",
			hub.CFrame * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -2),
			Vector3.new(0.7, 0.5, 0.7),
			C.metal,
			Enum.Material.Metal,
			false
		)
		-- Welded and unanchored, so spinning the hub on the client turns them too.
		for _, p in { arm, cup } do
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hub
			weld.Part1 = p
			weld.Parent = p
			p.Massless = true
			p.Anchored = false
			staged(p, P, 1)
		end
	end
	hub:SetAttribute("Spin", 240)
	hub:SetAttribute("SpinFrom", 2)
	staged(
		box(
			m,
			"Conduit",
			o * CFrame.new(0.45, 8, 0),
			Vector3.new(0.25, 14, 0.25),
			Color3.fromRGB(40, 40, 40),
			Enum.Material.Plastic,
			false
		),
		P,
		2
	)
	local beacon = box(
		m,
		"Beacon",
		o * CFrame.new(0, 16.1, 0),
		Vector3.new(0.4, 0.3, 0.4),
		Color3.fromRGB(255, 60, 50),
		Enum.Material.Neon,
		false
	)
	Builder.pointLight(beacon, Color3.fromRGB(255, 60, 50), 10, 1.2).Enabled = false
	beacon:SetAttribute("LightWhenShown", true)
	staged(beacon, P, 2)
	marker(m, "MastBase", o * CFrame.new(0, 2, 1.8), { SiteAnchor = "SensorMast", RepairProject = P })
	return m
end

local function marthaHouse(parent: Instance, s: any): Model
	local m = Builder.model("MarthaHouse", parent)
	local w, d, h = 16, 12, 8
	local o = frame(m, s.x, s.z, s.yaw, w + 2, d + 7)
	box(m, "Floor", o * CFrame.new(0, 0.25, 0), Vector3.new(w, 0.5, d), C.plankDark)
	walls(m, o, w, d, h, 4, Color3.fromRGB(176, 150, 170), true)
	gableRoof(m, o, w, d, h, Color3.fromRGB(90, 70, 80))
	porch(m, o, w, d, 5, h - 1)
	box(m, "Rail", o * CFrame.new(-w / 4 - 1, 1.8, d / 2 + 4.7), Vector3.new(w / 2 - 2, 0.3, 0.3), C.white)
	local scarf = box(
		m,
		"Scarf",
		o * CFrame.new(-4, 1.6, d / 2 + 4.7),
		Vector3.new(1.4, 0.8, 0.4),
		Color3.fromRGB(190, 50, 50),
		Enum.Material.Fabric,
		false
	)
	scarf:SetAttribute("Interaction", "BiscuitScarf")
	local bed = box(
		m,
		"DogBasket",
		o * CFrame.new(4, 0.75, d / 2 + 2.4),
		Vector3.new(3, 0.5, 2.2),
		Color3.fromRGB(150, 110, 70),
		Enum.Material.Fabric
	)
	marker(m, "HomeSpot", bed.CFrame * CFrame.new(0, 0.8, 0), { HomeSpot = "Biscuit" })
	marker(m, "NpcSpot", facingOut(o, Vector3.new(0, 0.5, d / 2 + 1.6)), { Npc = "martha" })
	lamp(m, o * CFrame.new(w / 2 - 1.5, h - 2.4, d / 2 + 4.4), { LitFlag = "biscuitHome", NightOnly = true })
	marker(m, "Anchor", o * CFrame.new(0, 2, d / 2 + 3), { SiteAnchor = "MarthaHouse" })
	return m
end

local function oldWoodShed(parent: Instance, s: any): Model
	local m = Builder.model("OldWoodShed", parent)
	local w, d, h = 7, 6, 6
	local o = frame(m, s.x, s.z, s.yaw, w, d)
	local grey = C.plankGrey
	box(m, "Floor", o * CFrame.new(0, 0.2, 0), Vector3.new(w, 0.4, d), C.plankDark)
	box(m, "Wall", o * CFrame.new(0, h / 2, -d / 2 + 0.3), Vector3.new(w, h, 0.6), grey)
	box(m, "Wall", o * CFrame.new(-w / 2 + 0.3, h / 2, 0), Vector3.new(0.6, h, d), grey)
	box(m, "Wall", o * CFrame.new(w / 2 - 0.3, h / 2 - 1, 0.6), Vector3.new(0.6, h - 2, d - 1.2), grey)
	box(
		m,
		"Roof",
		o * CFrame.new(1, h - 0.6, 0) * CFrame.Angles(0, 0, math.rad(-24)),
		Vector3.new(w + 1, 0.4, d + 1),
		C.roof,
		Enum.Material.WoodPlanks
	)
	box(m, "Woodpile", o * CFrame.new(-1.8, 1, -1.4), Vector3.new(2.4, 1.6, 2), C.plank, Enum.Material.Wood)
	box(
		m,
		"Hay",
		o * CFrame.new(1.5, 0.6, -1),
		Vector3.new(2.2, 0.6, 2.2),
		Color3.fromRGB(196, 170, 100),
		Enum.Material.Grass,
		false
	)
	marker(m, "MissingSpot", o * CFrame.new(1.5, 1.4, -1), { MissingSpot = "Biscuit" })
	return m
end

local function mayaGarden(parent: Instance, s: any): Model?
	local house = CollectionService:GetTagged("MayaHouse")[1]
	if not house or not house:IsA("Model") then
		return nil
	end
	local m = Builder.model("MayaGarden", parent)
	local hp = house:GetPivot()
	local spot = hp * CFrame.new(s.dx or 16, 0, s.dz or 0)
	local o = CFrame.new(spot.X, groundY(spot.X, spot.Z) + 0.2, spot.Z)
		* hp.Rotation
		* CFrame.Angles(0, math.rad(s.yaw), 0)
	local P = "MayaGarden"
	-- Raised bed.
	box(m, "Bed", o * CFrame.new(0, 0.6, 0), Vector3.new(8, 1.2, 3.6), C.plank)
	box(m, "Soil", o * CFrame.new(0, 1.15, 0), Vector3.new(7.4, 0.2, 3), C.soil, Enum.Material.Ground, false)
	-- Flattened: poles in the grass, wilted vines.
	for i = -1, 1 do
		staged(
			box(
				m,
				"FallenPole",
				o * CFrame.new(i * 2.4, 0.3, 2.8) * CFrame.Angles(0, math.rad(80 + i * 8), math.rad(90)),
				Vector3.new(0.3, 6, 0.3),
				C.plankDark,
				Enum.Material.Wood,
				false
			),
			P,
			0,
			1
		)
		staged(
			box(
				m,
				"Wilted",
				o * CFrame.new(i * 2.2, 1.35, 0.4),
				Vector3.new(1.6, 0.3, 0.8),
				C.dead,
				Enum.Material.Grass,
				false
			),
			P,
			0,
			2
		)
	end
	-- Frame up (stage 1+).
	for _, x in { -3.4, 0, 3.4 } do
		staged(
			box(
				m,
				"Pole",
				o * CFrame.new(x, 4, -0.6),
				Vector3.new(0.3, 6, 0.3),
				C.plankDark,
				Enum.Material.Wood
			),
			P,
			1
		)
	end
	staged(
		box(
			m,
			"Crossbar",
			o * CFrame.new(0, 6.9, -0.6),
			Vector3.new(7.4, 0.3, 0.3),
			C.plankDark,
			Enum.Material.Wood
		),
		P,
		1
	)
	for i = 0, 5 do
		staged(
			box(
				m,
				"String",
				o * CFrame.new(-3 + i * 1.2, 4.3, -0.6),
				Vector3.new(0.06, 5.2, 0.06),
				C.white,
				Enum.Material.Fabric,
				false
			),
			P,
			1
		)
	end
	-- Climbing again (stage 2): vines, leaves, flowers and pods.
	for i = 0, 5 do
		staged(
			box(
				m,
				"Vine",
				o * CFrame.new(-3 + i * 1.2, 3.2 + (i % 3) * 0.6, -0.5),
				Vector3.new(0.5, 3 + (i % 3), 0.5),
				C.leaf,
				Enum.Material.Grass,
				false
			),
			P,
			2
		)
		local flower = Builder.part({
			name = "Flower",
			shape = Enum.PartType.Ball,
			size = Vector3.new(0.45, 0.45, 0.45),
			cframe = o * CFrame.new(-3 + i * 1.2, 4.6 + (i % 2), -0.3),
			color = if i % 2 == 0 then Color3.fromRGB(230, 120, 150) else Color3.fromRGB(250, 240, 230),
			material = Enum.Material.SmoothPlastic,
			canCollide = false,
			parent = m,
		})
		staged(flower, P, 2)
	end
	marker(m, "RepairPoint", o * CFrame.new(0, 2, 2), { RepairProject = P })
	return m
end

local BUILDERS: { [string]: (Instance, any) -> Model? } = {
	HardwareStore = hardwareStore,
	FrankShed = frankShed,
	Diner = diner,
	WeatherStation = weatherStation,
	SensorMast = sensorMast,
	MarthaHouse = marthaHouse,
	OldWoodShed = oldWoodShed,
	MayaGarden = mayaGarden,
}

-- Builds every site. Call after the world exists and before GatherService
-- starts, so cleared trees never become resource prompts.
function Town.build(parent: Instance): { [string]: Model }
	local root = Builder.folder("Town", parent)
	for id, cfg in TownConfig.Sites do
		local fn = BUILDERS[id]
		if fn then
			-- One failing site never takes the others (or their NPCs) down.
			local ok, result = pcall(function(): Model?
				local s = table.clone(cfg)
				if s.x and s.z then
					local x, z = dryNear(s.x, s.z, math.max(s.clear * 0.6, 6))
					if x ~= s.x or z ~= s.z then
						print(string.format("[Town] %s moved off water to (%d, %d)", id, x, z))
					end
					s.x, s.z = x, z
					clearAround(x, z, s.clear)
				end
				return fn(root, s)
			end)
			if ok and result then
				result:SetAttribute("Site", id)
				CollectionService:AddTag(result, "TownSite")
				built[id] = result
			elseif not ok then
				warn("[Town] could not build " .. id .. ": " .. tostring(result))
			end
		end
	end
	return built
end

function Town.site(id: string): Model?
	return built[id]
end

Town.groundY = groundY

-- All parts in the town carrying an attribute (optionally with a value).
function Town.find(attr: string, value: any?): { BasePart }
	local out = {}
	for _, m in built do
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				local v = d:GetAttribute(attr)
				if v ~= nil and (value == nil or v == value) then
					table.insert(out, d)
				end
			end
		end
	end
	return out
end

return Town

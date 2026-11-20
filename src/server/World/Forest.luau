--!strict
-- The forest, seeded and deterministic: groves placed cell by cell from a
-- density field (glades, meadows, a deep-forest region, open lakeshore), with
-- species by biome; understory of bushes, ferns, rocks, logs, stumps and
-- mushrooms; and a cheap shadowless fringe on the slopes outside the play
-- area. Roads, building pads, the lake, reserved regions and the sightlines
-- in WorldConfig stay clear. A share of trees, rocks and bushes are
-- gatherable resource nodes.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local Assets = require(script.Parent.Assets)
local Builder = require(script.Parent.Builder)
local Terrain = require(script.Parent.Terrain)

local Forest = {}

local W = WorldConfig
local BARK = Color3.fromRGB(70, 52, 40)

-- Scale range per asset kind so trees tower over the player (5 studs).
local KIND_SCALE: { [string]: { number } } = {
	Ponderosa = { 1.25, 1.7 },
	Cedar = { 1.0, 1.35 },
	Birch = { 0.9, 1.25 },
	Oak = { 0.85, 1.1 },
	SnowPine = { 0.55, 0.9 },
}

local function regionWeight(x: number, z: number, kind: string): number
	for _, r in W.Regions do
		if r.kind == kind then
			local d = math.sqrt((x - r.x) ^ 2 + (z - r.z) ^ 2)
			if d < r.r then
				return 1 - (d / r.r) ^ 2
			end
		end
	end
	return 0
end

-- Species mix by biome: [kind, cumulative share].
local MIX: { [string]: { { any } } } = {
	Shore = { { "Cedar", 0.4 }, { "Birch", 0.7 }, { "Oak", 0.85 }, { "Ponderosa", 1 } },
	Deep = { { "Cedar", 0.55 }, { "Ponderosa", 1 } },
	Hill = { { "Ponderosa", 0.6 }, { "Cedar", 0.9 }, { "Birch", 1 } },
	High = { { "Ponderosa", 0.75 }, { "Cedar", 1 } },
	Valley = { { "Ponderosa", 0.45 }, { "Cedar", 0.7 }, { "Birch", 0.9 }, { "Oak", 1 } },
}

local function biomeKind(x: number, z: number, h: number, rng: Random): string
	-- No snow-laden pines: there is no snow anywhere trees grow.
	local mix = if h > 110
		then MIX.High
		elseif Terrain.lakeMetric(x, z) < 45 then MIX.Shore
		elseif regionWeight(x, z, "DeepForest") > 0.2 then MIX.Deep
		elseif h > 30 then MIX.Hill
		else MIX.Valley
	local r = rng:NextNumber()
	for _, entry in mix do
		if r <= entry[2] then
			return entry[1]
		end
	end
	return "Ponderosa"
end

-- A real tree from the asset pack, with a simple invisible trunk collider as
-- PrimaryPart (cheap collisions, a stable anchor for prompts). Falls back to
-- the procedural pine when assets are missing.
function Forest.tree(parent: Instance, x: number, z: number, rng: Random, kind: string?): Model
	local h = Terrain.heightAt(x, z)
	local k = kind or biomeKind(x, z, h, rng)
	local range = KIND_SCALE[k] or { 1, 1 }
	local m = Assets.tree(k, rng, rng:NextNumber(range[1], range[2]))
	if not m then
		return Forest.pine(parent, x, z, rng, false)
	end
	m.Name = k
	Assets.place(m, x, h, z, rng:NextNumber(0, math.pi * 2))
	local collider = Builder.part({
		name = "Collider",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(14, 2.2, 2.2),
		cframe = CFrame.new(x, h + 6, z) * CFrame.Angles(0, 0, math.rad(90)),
		transparency = 1,
		canQuery = true,
		castShadow = false,
		parent = m,
	})
	m.PrimaryPart = collider
	m:SetAttribute("TreeKind", k)
	m.Parent = parent
	return m
end

-- Places that stay clear of everything: building pads, roads, the lake and
-- its beach, reserved regions, beyond the play area.
type Circle = { x: number, z: number, r: number }
local PADS: { Circle } = {
	{ x = W.Cabin.x, z = W.Cabin.z, r = 34 },
	{ x = W.Spawn.x, z = W.Spawn.z, r = 8 },
	{ x = W.LakeHouse.x, z = W.LakeHouse.z, r = 22 },
	{ x = W.AbandonedHouse.x, z = W.AbandonedHouse.z, r = 22 },
	{ x = W.RadioTower.x, z = W.RadioTower.z, r = 16 },
}
for _, house in W.Houses do
	table.insert(PADS, { x = house.x, z = house.z, r = 20 })
end

local function blocked(x: number, z: number, extra: number): boolean
	local edge = W.PlayableRadius - 6
	if math.abs(x) > edge or math.abs(z) > edge then
		return true
	end
	for _, c in PADS do
		if (x - c.x) ^ 2 + (z - c.z) ^ 2 < (c.r + extra) ^ 2 then
			return true
		end
	end
	for _, r in W.Regions do
		if r.reserved and (x - r.x) ^ 2 + (z - r.z) ^ 2 < r.r * r.r then
			return true
		end
	end
	return Terrain.trailDistance(x, z) < 5 + extra or Terrain.lakeMetric(x, z) < 4 + extra
end

-- Inside a view corridor (WorldConfig.Sightlines)?
local function inSightline(x: number, z: number): boolean
	for _, s in W.Sightlines do
		local vx, vz = s.b.x - s.a.x, s.b.z - s.a.z
		local len2 = vx * vx + vz * vz
		local t = math.clamp(((x - s.a.x) * vx + (z - s.a.z) * vz) / len2, 0, 1)
		local px, pz = s.a.x + vx * t - x, s.a.z + vz * t - z
		local width = s.near + (s.far - s.near) * t
		if px * px + pz * pz < width * width then
			return true
		end
	end
	return false
end

-- Where a tree may stand: also not in a view corridor, on a cliff or above
-- the treeline.
local function treeOk(x: number, z: number, extra: number): boolean
	if blocked(x, z, extra) or inSightline(x, z) then
		return false
	end
	return Terrain.heightAt(x, z) < W.Forest.Treeline and Terrain.slopeAt(x, z) < 0.95
end

-- Forest density 0..1: groves and glades from two noise scales, thinner on
-- the open valley floor and the shore, thick in the deep forest and on hills.
local function density(x: number, z: number, h: number): number
	if Terrain.inMeadow(x, z) then
		return 0.04
	end
	local d = 0.5 + math.noise(x / 180, z / 180, 6.6) * 0.75 + math.noise(x / 55, z / 55, 3.9) * 0.3
	d += regionWeight(x, z, "DeepForest") * 0.45
	if h > 30 then
		d += 0.12
	end
	if Terrain.lakeMetric(x, z) < 40 then
		d *= 0.75
	end
	if x * x + z * z < 90 * 90 then
		d = math.max(d, 0.45) -- the cabin sits in a forest clearing
	end
	return math.clamp(d, 0, 1)
end

local function randomSpot(rng: Random, extra: number): (number, number)
	for _ = 1, 40 do
		local x = rng:NextNumber(-W.PlayableRadius + 10, W.PlayableRadius - 10)
		local z = rng:NextNumber(-W.PlayableRadius + 10, W.PlayableRadius - 10)
		if not blocked(x, z, extra) then
			return x, z
		end
	end
	return 9999, 9999
end

function Forest.pine(parent: Instance, x: number, z: number, rng: Random, dead: boolean?): Model
	local m = Builder.model(if dead then "DeadTree" else "Pine", parent)
	local y = Terrain.heightAt(x, z) - 1
	local height = rng:NextNumber(16, 28)
	local radius = rng:NextNumber(0.9, 1.6)
	local trunk = Builder.part({
		name = "Trunk",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, radius * 2, radius * 2),
		cframe = CFrame.new(x, y + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		color = if dead then Color3.fromRGB(56, 50, 46) else BARK,
		material = Enum.Material.Wood,
		parent = m,
	})
	m.PrimaryPart = trunk
	local tint = rng:NextNumber(-8, 8)
	if dead then
		for i = 1, 4 do
			local by = y + height * rng:NextNumber(0.45, 0.9)
			local yaw = rng:NextNumber(0, math.pi * 2)
			Builder.part({
				name = "Branch",
				size = Vector3.new(rng:NextNumber(4, 8), 0.5, 0.5),
				cframe = CFrame.new(x, by, z)
					* CFrame.Angles(0, yaw, math.rad(rng:NextNumber(10, 35)))
					* CFrame.new(2.5, 0, 0),
				color = Color3.fromRGB(52, 46, 42),
				material = Enum.Material.Wood,
				canCollide = false,
				parent = m,
			})
			local _ = i
		end
		return m
	end
	local tiers = 4
	local base = y + height * 0.32
	for i = 1, tiers do
		local f = (i - 1) / tiers
		local w = (radius * 6.5 + 4) * (1 - f * 0.72)
		local ty = base + (height * 0.68) * f
		local green = Color3.fromRGB(36 + tint, 62 + tint + i * 3, 42 + tint)
		for k = 0, 1 do
			Builder.part({
				name = "Needles",
				size = Vector3.new(w, height * 0.2, w),
				cframe = CFrame.new(x, ty, z) * CFrame.Angles(0, math.rad(45 * k + i * 20), 0),
				color = green,
				material = Enum.Material.Grass,
				canCollide = false,
				castShadow = true,
				parent = m,
			})
		end
	end
	Builder.part({
		name = "Tip",
		size = Vector3.new(radius * 2, height * 0.22, radius * 2),
		cframe = CFrame.new(x, y + height + 1, z) * CFrame.Angles(0, math.rad(45), 0),
		color = Color3.fromRGB(34 + tint, 60 + tint, 40 + tint),
		material = Enum.Material.Grass,
		canCollide = false,
		parent = m,
	})
	return m
end

local function rock(parent: Instance, x: number, z: number, rng: Random, scale: number): Part
	local y = Terrain.heightAt(x, z)
	local s = scale * rng:NextNumber(0.7, 1.4)
	return Builder.part({
		name = "Rock",
		size = Vector3.new(s * rng:NextNumber(3, 5), s * rng:NextNumber(2, 3.4), s * rng:NextNumber(3, 5)),
		cframe = CFrame.new(x, y + s * 0.6, z)
			* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4)),
		color = Color3.fromRGB(100 + rng:NextInteger(-10, 10), 98, 94),
		material = Enum.Material.Slate,
		parent = parent,
	})
end

local function bush(parent: Instance, x: number, z: number, rng: Random, berries: boolean): Model
	local m = Builder.model("Bush", parent)
	local y = Terrain.heightAt(x, z)
	local core = Builder.part({
		name = "Leaves",
		shape = Enum.PartType.Ball,
		size = Vector3.new(4.5, 4.5, 4.5) * rng:NextNumber(0.8, 1.2),
		cframe = CFrame.new(x, y + 1.2, z),
		color = Color3.fromRGB(52, 78, 44),
		material = Enum.Material.Grass,
		canCollide = false,
		parent = m,
	})
	m.PrimaryPart = core
	Builder.part({
		name = "Leaves2",
		shape = Enum.PartType.Ball,
		size = Vector3.new(3.4, 3.4, 3.4),
		cframe = CFrame.new(x + 1.4, y + 0.9, z + 0.6),
		color = Color3.fromRGB(58, 84, 46),
		material = Enum.Material.Grass,
		canCollide = false,
		parent = m,
	})
	if berries then
		for i = 1, 6 do
			local a = i * 1.05
			Builder.part({
				name = "Berry",
				shape = Enum.PartType.Ball,
				size = Vector3.new(0.45, 0.45, 0.45),
				cframe = CFrame.new(x + math.cos(a) * 2, y + 1.4 + (i % 2) * 0.5, z + math.sin(a) * 2),
				color = Color3.fromRGB(150, 30, 46),
				material = Enum.Material.SmoothPlastic,
				canCollide = false,
				canQuery = false,
				parent = m,
			})
		end
	end
	return m
end

local function mushroom(parent: Instance, x: number, z: number): Model
	local m = Builder.model("Mushroom", parent)
	local y = Terrain.heightAt(x, z)
	local stem = Builder.part({
		name = "Stem",
		size = Vector3.new(0.35, 0.8, 0.35),
		cframe = CFrame.new(x, y + 0.4, z),
		color = Color3.fromRGB(220, 212, 190),
		canCollide = false,
		parent = m,
	})
	m.PrimaryPart = stem
	Builder.part({
		name = "Cap",
		shape = Enum.PartType.Ball,
		size = Vector3.new(1.1, 0.6, 1.1),
		cframe = CFrame.new(x, y + 0.85, z),
		color = Color3.fromRGB(156, 92, 54),
		canCollide = false,
		parent = m,
	})
	return m
end

local function makeResource(inst: Instance, kind: string, hits: number)
	inst:SetAttribute("ResourceKind", kind)
	inst:SetAttribute("HitsLeft", hits)
	inst:SetAttribute("Depleted", false)
	CollectionService:AddTag(inst, "ResourceNode")
end

-- A fern: five thin fronds arching out from the ground. Decoration only.
local function fern(parent: Instance, x: number, z: number, rng: Random)
	local m = Builder.model("Fern", parent)
	local y = Terrain.heightAt(x, z)
	local s = rng:NextNumber(0.8, 1.3)
	local green = Color3.fromRGB(56 + rng:NextInteger(-6, 6), 92 + rng:NextInteger(-8, 8), 48)
	local turn = rng:NextNumber(0, math.pi * 2)
	for i = 1, 5 do
		Builder.part({
			name = "Frond",
			size = Vector3.new(0.7 * s, 0.08, 2.6 * s),
			cframe = CFrame.new(x, y + 0.35, z)
				* CFrame.Angles(0, turn + i * math.pi * 2 / 5, 0)
				* CFrame.Angles(math.rad(28), 0, 0)
				* CFrame.new(0, 0, -1.1 * s),
			color = green,
			material = Enum.Material.Grass,
			canCollide = false,
			canQuery = false,
			castShadow = false,
			parent = m,
		})
	end
end

local function stump(parent: Instance, x: number, z: number, rng: Random)
	local y = Terrain.heightAt(x, z)
	local hgt = rng:NextNumber(0.9, 2)
	Builder.part({
		name = "OldStump",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(hgt + 0.6, rng:NextNumber(1.6, 2.8), rng:NextNumber(1.6, 2.8)),
		cframe = CFrame.new(x, y + hgt / 2 - 0.3, z) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(78 + rng:NextInteger(-8, 8), 62, 48),
		material = Enum.Material.Wood,
		canQuery = false,
		parent = parent,
	})
end

-- Scenery tree outside the play area: no collider, no shadows, never a
-- resource, so the slopes read as forest at little cost.
local function farTree(parent: Instance, x: number, z: number, rng: Random, kind: string)
	local range = KIND_SCALE[kind] or { 1, 1 }
	local m = Assets.tree(kind, rng, rng:NextNumber(range[1], range[2]) * 1.15)
	if not m then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
	m.Name = kind
	Assets.place(m, x, Terrain.heightAt(x, z), z, rng:NextNumber(0, math.pi * 2))
	m.Parent = parent
end

function Forest.build(parent: Instance, seed: number)
	local started = os.clock()
	local rng = Random.new(seed)
	local trees = Builder.folder("Trees", parent)
	local rocks = Builder.folder("Rocks", parent)
	local plants = Builder.folder("Plants", parent)
	local scenery = Builder.folder("Scenery", parent)
	local cfg = W.Forest
	local P = W.PlayableRadius

	-- Spacing: no two trunks closer than MinSpacing (8-stud hash).
	local placed: { [number]: { Vector2 } } = {}
	local function key(gx: number, gz: number): number
		return gx * 4096 + gz
	end
	local function spaced(x: number, z: number): boolean
		local gx, gz = x // 8, z // 8
		for dx = -1, 1 do
			for dz = -1, 1 do
				local list: { Vector2 } = placed[key(gx + dx, gz + dz)] or {}
				for _, p in list do
					if (p.X - x) ^ 2 + (p.Y - z) ^ 2 < cfg.MinSpacing ^ 2 then
						return false
					end
				end
			end
		end
		return true
	end
	local function mark(x: number, z: number)
		local k = key(x // 8, z // 8)
		local list = placed[k] or {}
		placed[k] = list
		table.insert(list, Vector2.new(x, z))
	end

	-- Groves: each grid cell gets 0..MaxPerCell trees by local density,
	-- scattered around a jittered centre. Remember dense spots for the
	-- understory.
	local standing: { Vector3 } = {}
	local count, resources = 0, 0
	local cell = cfg.CellSize
	for gx = -P, P - cell, cell do
		for gz = -P, P - cell, cell do
			local cx, cz = gx + rng:NextNumber(0, cell), gz + rng:NextNumber(0, cell)
			local d = density(cx, cz, Terrain.heightAt(cx, cz))
			local n = math.floor(d * cfg.MaxPerCell + rng:NextNumber())
			for _ = 1, n do
				local x = cx + (rng:NextNumber() + rng:NextNumber() - 1) * cell * 0.6
				local z = cz + (rng:NextNumber() + rng:NextNumber() - 1) * cell * 0.6
				local bog = (x - W.ThreatArea.x) ^ 2 + (z - W.ThreatArea.z) ^ 2 < W.ThreatArea.radius ^ 2
				if not bog and treeOk(x, z, 0) and spaced(x, z) then
					mark(x, z)
					local t = Forest.tree(trees, x, z, rng)
					table.insert(standing, Vector3.new(x, d, z))
					count += 1
					-- Gatherable trees are denser near the cabin.
					local near = x * x + z * z < 140 * 140
					if rng:NextNumber() < cfg.ResourceTreeFraction * (if near then 2 else 0.5) then
						makeResource(t, "Tree", 3)
						resources += 1
					end
				end
			end
		end
	end
	-- A dense dark stand of dead and dying pines marks the bog.
	for _ = 1, 60 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, W.ThreatArea.radius)
		local x, z = W.ThreatArea.x + math.cos(a) * r, W.ThreatArea.z + math.sin(a) * r
		if not blocked(x, z, 0) then
			Forest.pine(trees, x, z, rng, rng:NextNumber() < 0.6)
		end
	end
	-- Guaranteed wood near the cabin for the first task (never in the view
	-- from the north windows).
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2 + 0.3
		local x, z = math.cos(a) * 44, math.sin(a) * 44 + 4
		if not blocked(x, z, -20) and not inSightline(x, z) then
			local t = Forest.tree(trees, x, z, rng, if i % 3 == 0 then "Birch" else "Ponderosa")
			makeResource(t, "Tree", 3)
		end
	end

	-- Understory near standing trees: bushes at grove edges, ferns and
	-- mushrooms in the dense parts, fallen logs.
	local function nearTree(minDensity: number, spread: number): (number, number)
		for _ = 1, 20 do
			local t = standing[rng:NextInteger(1, #standing)]
			if t.Y >= minDensity then
				local a = rng:NextNumber(0, math.pi * 2)
				local r = rng:NextNumber(3, spread)
				local x, z = t.X + math.cos(a) * r, t.Z + math.sin(a) * r
				if not blocked(x, z, 0) then
					return x, z
				end
			end
		end
		return 9999, 9999
	end
	if #standing > 0 then
		for i = 1, cfg.Bushes do
			local x, z = nearTree(0, 12)
			if x < 9000 then
				local berries = i % 3 == 0
				makeResource(bush(plants, x, z, rng, berries), if berries then "BerryBush" else "Bush", 1)
			end
		end
		local ferns = 0
		while ferns < cfg.Ferns do
			local x, z = nearTree(0.55, 10)
			if x >= 9000 then
				break
			end
			for _ = 1, rng:NextInteger(3, 6) do
				local fx, fz = x + rng:NextNumber(-4, 4), z + rng:NextNumber(-4, 4)
				if not blocked(fx, fz, 0) then
					fern(plants, fx, fz, rng)
					ferns += 1
				end
			end
		end
		for _ = 1, cfg.Mushrooms do
			local x, z = nearTree(0.5, 6)
			if x < 9000 then
				makeResource(mushroom(plants, x, z), "Mushroom", 1)
			end
		end
		for _ = 1, cfg.Logs do
			local x, z = nearTree(0.45, 14)
			if x < 9000 and not blocked(x, z, 2) then
				local y = Terrain.heightAt(x, z)
				Builder.part({
					name = "FallenLog",
					shape = Enum.PartType.Cylinder,
					size = Vector3.new(rng:NextNumber(8, 16), 1.8, 1.8),
					cframe = CFrame.new(x, y + 0.6, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
					color = Color3.fromRGB(66, 50, 38),
					material = Enum.Material.Wood,
					parent = trees,
				})
			end
		end
	end
	for _, p in { { 24, 30 }, { -26, 18 }, { 36, 8 }, { -20, -30 }, { 10, 52 } } do
		makeResource(bush(plants, p[1], p[2], rng, false), "Bush", 1)
	end

	-- Rocks: more on slopes and rocky shores.
	local rockCount, tries = 0, 0
	while rockCount < cfg.Rocks and tries < cfg.Rocks * 20 do
		tries += 1
		local x, z = randomSpot(rng, 0)
		if x < 9000 then
			local m = Terrain.lakeMetric(x, z)
			local chance = 0.12 + Terrain.slopeAt(x, z) * 0.9 + (if m < 14 then 0.5 else 0)
			if rng:NextNumber() < chance then
				rockCount += 1
				local r = rock(rocks, x, z, rng, if m < 14 then 1 else 1.3)
				if rng:NextNumber() < cfg.ResourceRockFraction or rockCount <= 10 then
					makeResource(r, "Rock", 3)
				end
			end
		end
	end
	-- A few stones near the cabin.
	for _, p in { { 38, -20 }, { -40, 24 }, { 30, 40 }, { -30, -36 } } do
		makeResource(rock(rocks, p[1], p[2], rng, 1.2), "Rock", 3)
	end

	-- Old stumps: someone logged around the cabin and the settlement once.
	for _ = 1, cfg.Stumps do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(40, 260)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if not blocked(x, z, 0) and not inSightline(x, z) then
			stump(trees, x, z, rng)
		end
	end

	-- Scenery fringe: clusters on the slopes just outside the play area,
	-- below the treeline.
	local far = 0
	for _ = 1, cfg.FarTrees * 4 do
		if far >= cfg.FarTrees then
			break
		end
		local x, z = rng:NextNumber(-P - 520, P + 520), rng:NextNumber(-P - 520, P + 520)
		local outside = math.max(math.abs(x), math.abs(z)) > P + 10
		local h = Terrain.heightAt(x, z)
		if outside and h < W.Forest.Treeline and h > W.WaterLevel + 2 and density(x, z, h) > 0.45 then
			for _ = 1, rng:NextInteger(4, 8) do
				local tx, tz = x + rng:NextNumber(-22, 22), z + rng:NextNumber(-22, 22)
				local th = Terrain.heightAt(tx, tz)
				if th < W.Forest.Treeline and Terrain.slopeAt(tx, tz) < 0.9 then
					farTree(scenery, tx, tz, rng, biomeKind(tx, tz, th, rng))
					far += 1
				end
			end
		end
	end
	print(
		string.format(
			"[Forest] %d trees (%d gatherable), %d scenery trees, %d rocks in %.2fs",
			count,
			resources,
			far,
			rockCount,
			os.clock() - started
		)
	)
end

return Forest

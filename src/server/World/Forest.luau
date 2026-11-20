--!strict
-- Procedural forest: pines and firs, rocks, bushes, mushrooms, fallen logs.
-- A share of trees, rocks and bushes are gatherable resource nodes.

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

local function biomeKind(x: number, z: number, h: number, rng: Random): string
	if h > 55 then
		return "SnowPine"
	end
	if Terrain.lakeMetric(x, z) < 70 and rng:NextNumber() < 0.22 then
		return "Oak"
	end
	local r = rng:NextNumber()
	if r < 0.5 then
		return "Ponderosa"
	elseif r < 0.72 then
		return "Cedar"
	end
	return "Birch"
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

local function clearOk(x: number, z: number, extra: number): boolean
	for _, c in W.Forest.KeepClear do
		local dx, dz = x - c.x, z - c.z
		if dx * dx + dz * dz < (c.r + extra) ^ 2 then
			return false
		end
	end
	for _, h in W.Houses do
		local dx, dz = x - h.x, z - h.z
		if dx * dx + dz * dz < (20 + extra) ^ 2 then
			return false
		end
	end
	if Terrain.trailDistance(x, z) < 5 + extra then
		return false
	end
	if Terrain.isWater(x, z) then
		return false
	end
	return math.max(math.abs(x), math.abs(z)) < W.PlayableRadius
end

-- Forest density 0..1: groves and open glades instead of an even spread.
local function forestDensity(x: number, z: number): number
	if Terrain.inMeadow(x, z) then
		return 0.05
	end
	local n = math.noise(x / 120, z / 120, 6.6) * 0.5 + math.noise(x / 40, z / 40, 3.9) * 0.25
	return math.clamp(0.55 + n, 0.05, 1)
end

local function randomSpot(rng: Random, extra: number): (number, number)
	for _ = 1, 40 do
		local x = rng:NextNumber(-W.PlayableRadius + 10, W.PlayableRadius - 10)
		local z = rng:NextNumber(-W.PlayableRadius + 10, W.PlayableRadius - 10)
		if clearOk(x, z, extra) then
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

function Forest.build(parent: Instance, seed: number)
	local rng = Random.new(seed)
	local trees = Builder.folder("Trees", parent)
	local rocks = Builder.folder("Rocks", parent)
	local plants = Builder.folder("Plants", parent)
	local cfg = W.Forest

	for _ = 1, cfg.Trees do
		local x, z = randomSpot(rng, 0)
		-- Groves and glades: accept by local forest density.
		if x < 9000 and rng:NextNumber() < forestDensity(x, z) then
			local threat = (x - W.ThreatArea.x) ^ 2 + (z - W.ThreatArea.z) ^ 2 < W.ThreatArea.radius ^ 2
			local t = if threat then Forest.pine(trees, x, z, rng, true) else Forest.tree(trees, x, z, rng)
			-- Gatherable trees are denser near the cabin.
			local near = math.sqrt(x * x + z * z) < 140
			local chance = cfg.ResourceTreeFraction * (if near then 2 else 0.5)
			if not threat and rng:NextNumber() < chance then
				makeResource(t, "Tree", 3)
			end
		end
	end
	-- A dense dark stand marks the threat area.
	for _ = 1, 60 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, W.ThreatArea.radius)
		local x, z = W.ThreatArea.x + math.cos(a) * r, W.ThreatArea.z + math.sin(a) * r
		if not Terrain.isWater(x, z) then
			Forest.pine(trees, x, z, rng, rng:NextNumber() < 0.6)
		end
	end
	-- Guaranteed wood near the cabin for the first task.
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2 + 0.3
		local x, z = math.cos(a) * 44, math.sin(a) * 44 + 4
		if clearOk(x, z, -20) then
			local t = Forest.tree(trees, x, z, rng, if i % 3 == 0 then "Birch" else "Ponderosa")
			makeResource(t, "Tree", 3)
		end
	end
	for i = 1, cfg.Rocks do
		local x, z = randomSpot(rng, 0)
		if x < 9000 then
			local r = rock(rocks, x, z, rng, 1.3)
			if rng:NextNumber() < cfg.ResourceRockFraction or i <= 10 then
				makeResource(r, "Rock", 3)
			end
		end
	end
	-- A few stones near the cabin.
	for _, p in { { 38, -20 }, { -40, 24 }, { 30, 40 }, { -30, -36 } } do
		makeResource(rock(rocks, p[1], p[2], rng, 1.2), "Rock", 3)
	end

	for i = 1, cfg.Bushes do
		local x, z = randomSpot(rng, 0)
		if x < 9000 then
			local berries = i % 3 == 0
			local b = bush(plants, x, z, rng, berries)
			makeResource(b, if berries then "BerryBush" else "Bush", 1)
		end
	end
	for _, p in { { 24, 30 }, { -26, 18 }, { 36, 8 }, { -20, -30 }, { 10, 52 } } do
		makeResource(bush(plants, p[1], p[2], rng, false), "Bush", 1)
	end
	for _ = 1, cfg.Mushrooms do
		local x, z = randomSpot(rng, 0)
		if x < 9000 then
			makeResource(mushroom(plants, x, z), "Mushroom", 1)
		end
	end
	for _ = 1, cfg.Logs do
		local x, z = randomSpot(rng, 2)
		if x < 9000 then
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

return Forest

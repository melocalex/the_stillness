--!strict
-- Procedural terrain: rolling forest floor, meadows, a lake basin, a hill for
-- the radio tower, a highland plateau beyond the north ridge, flattened
-- clearings for buildings, dirt roads, and distant snow-capped mountains that
-- close the map. Height is a pure function so every placement can query it.

local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.Config.WorldConfig)

local Terrain = {}

local W = WorldConfig
local CELL = 4

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function dist(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

type Segment = {
	ax: number,
	az: number,
	bx: number,
	bz: number,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}
local segments: { Segment } = {}
for _, trail in W.Trails do
	for i = 1, #trail - 1 do
		local a, b = trail[i], trail[i + 1]
		table.insert(segments, {
			ax = a.x,
			az = a.z,
			bx = b.x,
			bz = b.z,
			minX = math.min(a.x, b.x) - 12,
			maxX = math.max(a.x, b.x) + 12,
			minZ = math.min(a.z, b.z) - 12,
			maxZ = math.max(a.z, b.z) + 12,
		})
	end
end

function Terrain.trailDistance(x: number, z: number): number
	local best = math.huge
	for _, s in segments do
		if x >= s.minX and x <= s.maxX and z >= s.minZ and z <= s.maxZ then
			local vx, vz = s.bx - s.ax, s.bz - s.az
			local len2 = vx * vx + vz * vz
			local t = if len2 > 0 then math.clamp(((x - s.ax) * vx + (z - s.az) * vz) / len2, 0, 1) else 0
			local d = dist(x, z, s.ax + vx * t, s.az + vz * t)
			if d < best then
				best = d
			end
		end
	end
	return best
end

-- Height before clearings and roads are carved.
local function rawHeight(x: number, z: number): number
	local h = W.BaseHeight
		+ math.noise(x / 170, z / 170, 0.31) * 12
		+ math.noise(x / 52, z / 52, 1.73) * 3.5
		+ math.noise(x / 17, z / 17, 4.11) * 0.7

	-- Radio hill.
	local rd = dist(x, z, W.RadioTower.x, W.RadioTower.z)
	h += W.RadioTower.hill * math.exp(-(rd * rd) / (2 * 55 * 55))

	-- North ridge rises behind the lake house to a highland plateau.
	local ridgeD = z - W.NorthRidge.z
	if ridgeD < 0 then
		h += math.min(-ridgeD * 0.45, W.NorthRidge.plateau)
	end

	-- Lake basin.
	local ld = dist(x, z, W.Lake.x, W.Lake.z)
	local basin = 1 - smoothstep(W.Lake.radius - 18, W.Lake.radius + 22, ld)
	h = h + ((W.WaterLevel - W.Lake.depth) - h) * basin

	-- Distant mountains close the map: foothills, then jagged snowy peaks.
	local edge = math.max(math.abs(x), math.abs(z))
	local foot = edge - (W.MountainStart - 120)
	if foot > 0 then
		h += (foot / 120) ^ 2 * 18
	end
	if edge > W.MountainStart then
		local k = (edge - W.MountainStart) / 70
		local ridge = 1 - math.abs(math.noise(x / 90, z / 90, 2.6))
		local peaks = ridge * ridge * 80 * math.min(k, 1.6)
		h += k * k * 40 + peaks + math.noise(x / 30, z / 30, 9.2) * 8 * math.min(k, 1)
	end
	return h
end

type Clearing = { x: number, z: number, r: number, h: number }
local clearings: { Clearing } = {
	{ x = W.Cabin.x, z = W.Cabin.z, r = W.Cabin.clearing, h = W.Cabin.floorY - 1.5 },
	{ x = W.LakeHouse.x, z = W.LakeHouse.z, r = W.LakeHouse.clearing, h = W.LakeHouse.height },
	{
		x = W.AbandonedHouse.x,
		z = W.AbandonedHouse.z,
		r = W.AbandonedHouse.clearing,
		h = W.AbandonedHouse.height,
	},
}
for _, house in W.Houses do
	table.insert(clearings, { x = house.x, z = house.z, r = 22, h = rawHeight(house.x, house.z) })
end

function Terrain.clearingHeight(x: number, z: number): number?
	for _, c in clearings do
		if dist(x, z, c.x, c.z) < 4 then
			return c.h
		end
	end
	return nil
end

function Terrain.heightAt(x: number, z: number): number
	local h = rawHeight(x, z)
	for _, c in clearings do
		local d = dist(x, z, c.x, c.z)
		if d < c.r + 24 then
			local w = 1 - smoothstep(c.r, c.r + 24, d)
			h = h + (c.h - h) * w
		end
	end
	local td = Terrain.trailDistance(x, z)
	if td < 6 then
		h -= 0.4 * (1 - td / 6)
	end
	return h
end

function Terrain.inMeadow(x: number, z: number): boolean
	for _, m in W.Meadows do
		if dist(x, z, m.x, m.z) < m.r then
			return true
		end
	end
	return false
end

-- Forest density 0..1: groves and open glades instead of an even spread.
function Terrain.forestDensity(x: number, z: number): number
	if Terrain.inMeadow(x, z) then
		return 0.05
	end
	local n = math.noise(x / 120, z / 120, 6.6) * 0.5 + math.noise(x / 40, z / 40, 3.9) * 0.25
	return math.clamp(0.55 + n, 0.05, 1)
end

local function materialAt(x: number, z: number, h: number): Enum.Material
	local edge = math.max(math.abs(x), math.abs(z))
	if edge > W.MountainStart - 30 then
		if h > 150 + math.noise(x / 110, z / 110, 5.5) * 12 then
			return Enum.Material.Snow
		end
		if h > 70 then
			return Enum.Material.Rock
		end
	end
	local slope = math.abs(Terrain.heightAt(x + 2, z) - Terrain.heightAt(x - 2, z))
		+ math.abs(Terrain.heightAt(x, z + 2) - Terrain.heightAt(x, z - 2))
	if slope > 6 then
		return Enum.Material.Slate
	end
	local ld = dist(x, z, W.Lake.x, W.Lake.z)
	if ld < W.Lake.radius + 8 then
		return if h < W.WaterLevel + 1.5 then Enum.Material.Mud else Enum.Material.Ground
	end
	if Terrain.trailDistance(x, z) < 3.5 then
		return Enum.Material.Ground
	end
	if dist(x, z, W.ThreatArea.x, W.ThreatArea.z) < W.ThreatArea.radius then
		return Enum.Material.Mud
	end
	if Terrain.inMeadow(x, z) or dist(x, z, W.Cabin.x, W.Cabin.z) < W.Cabin.clearing + 10 then
		return Enum.Material.Grass
	end
	local n = math.noise(x / 35, z / 35, 7.7)
	if n > 0.42 then
		return Enum.Material.Ground
	end
	return if n < -0.2 then Enum.Material.Grass else Enum.Material.LeafyGrass
end

-- Writes all terrain voxels, chunk by chunk, only over each chunk's height
-- band (most of the valley is a thin layer, so this stays fast).
function Terrain.generate()
	local terrain = workspace.Terrain
	terrain:Clear()
	local half = W.HalfSize
	local chunk = 32 -- cells per chunk side
	local total = (2 * half) // CELL
	for cx = 0, total - 1, chunk do
		for cz = 0, total - 1, chunk do
			local nx = math.min(chunk, total - cx)
			local nz = math.min(chunk, total - cz)
			-- Heights for every column in the chunk, and the band to write.
			local heights = table.create(nx)
			local lo, hi = math.huge, -math.huge
			for ix = 1, nx do
				local col = table.create(nz)
				local x = -half + (cx + ix - 1) * CELL + CELL / 2
				for iz = 1, nz do
					local z = -half + (cz + iz - 1) * CELL + CELL / 2
					local h = Terrain.heightAt(x, z)
					col[iz] = h
					lo = math.min(lo, h)
					hi = math.max(hi, h)
				end
				heights[ix] = col
			end
			local yMin = math.floor((math.min(lo, W.WaterLevel) - 10) / CELL) * CELL
			local yMax = math.ceil((math.max(hi, W.WaterLevel) + 4) / CELL) * CELL
			local cellsY = (yMax - yMin) // CELL
			local materials = table.create(nx)
			local occupancy = table.create(nx)
			for ix = 1, nx do
				local mx = table.create(cellsY)
				local ox = table.create(cellsY)
				for iy = 1, cellsY do
					mx[iy] = table.create(nz)
					ox[iy] = table.create(nz)
				end
				local x = -half + (cx + ix - 1) * CELL + CELL / 2
				for iz = 1, nz do
					local z = -half + (cz + iz - 1) * CELL + CELL / 2
					local h = heights[ix][iz]
					local surfaceMat = materialAt(x, z, h)
					for iy = 1, cellsY do
						local bottom = yMin + (iy - 1) * CELL
						local occ = math.clamp((h - bottom) / CELL, 0, 1)
						if occ > 0.02 then
							local depth = h - (bottom + CELL)
							mx[iy][iz] = if depth > 6 then Enum.Material.Rock else surfaceMat
							ox[iy][iz] = occ
						elseif bottom < W.WaterLevel then
							mx[iy][iz] = Enum.Material.Water
							ox[iy][iz] = 1
						else
							mx[iy][iz] = Enum.Material.Air
							ox[iy][iz] = 0
						end
					end
				end
				materials[ix] = mx
				occupancy[ix] = ox
			end
			local x0 = -half + cx * CELL
			local z0 = -half + cz * CELL
			local region = Region3.new(
				Vector3.new(x0, yMin, z0),
				Vector3.new(x0 + nx * CELL, yMin + cellsY * CELL, z0 + nz * CELL)
			)
			terrain:WriteVoxels(region, CELL, materials, occupancy)
			-- Solid rock below the band so nothing can fall through.
			terrain:FillBlock(
				CFrame.new(x0 + nx * CELL / 2, yMin - 6, z0 + nz * CELL / 2),
				Vector3.new(nx * CELL, 12, nz * CELL),
				Enum.Material.Rock
			)
			task.wait()
		end
	end
	pcall(function()
		(terrain :: any).Decoration = true
	end)
	terrain.WaterColor = Color3.fromRGB(28, 46, 52)
	terrain.WaterTransparency = 0.35
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 6
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(84, 104, 56))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(64, 86, 46))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(92, 76, 58))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(60, 50, 42))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(88, 90, 88))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(100, 100, 98))
	terrain:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(226, 232, 238))
end

function Terrain.isWater(x: number, z: number): boolean
	return Terrain.heightAt(x, z) < W.WaterLevel - 0.5
end

return Terrain

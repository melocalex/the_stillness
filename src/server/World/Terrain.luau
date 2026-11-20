--!strict
-- Procedural terrain: rolling forest floor, a lake basin, a hill for the radio
-- tower, flattened clearings for buildings, dirt trails, and mountains that
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

local function segDist(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local vx, vz = bx - ax, bz - az
	local len2 = vx * vx + vz * vz
	local t = if len2 > 0 then math.clamp(((px - ax) * vx + (pz - az) * vz) / len2, 0, 1) else 0
	return dist(px, pz, ax + vx * t, az + vz * t)
end

function Terrain.trailDistance(x: number, z: number): number
	local best = math.huge
	for _, trail in W.Trails do
		for i = 1, #trail - 1 do
			local a, b = trail[i], trail[i + 1]
			best = math.min(best, segDist(x, z, a.x, a.z, b.x, b.z))
		end
	end
	return best
end

local clearings = {
	{ x = W.Cabin.x, z = W.Cabin.z, r = W.Cabin.clearing, h = W.Cabin.floorY - 1.5 },
	{ x = W.LakeHouse.x, z = W.LakeHouse.z, r = W.LakeHouse.clearing, h = W.LakeHouse.height },
	{
		x = W.AbandonedHouse.x,
		z = W.AbandonedHouse.z,
		r = W.AbandonedHouse.clearing,
		h = W.AbandonedHouse.height,
	},
}

function Terrain.heightAt(x: number, z: number): number
	local h = W.BaseHeight
		+ math.noise(x / 150, z / 150, 0.31) * 10
		+ math.noise(x / 46, z / 46, 1.73) * 3
		+ math.noise(x / 17, z / 17, 4.11) * 0.7

	-- Radio hill.
	local rd = dist(x, z, W.RadioTower.x, W.RadioTower.z)
	h += W.RadioTower.hill * math.exp(-(rd * rd) / (2 * 55 * 55))

	-- North ridge rises behind the lake house.
	local ridgeD = z - W.NorthRidge.z
	if ridgeD < 0 then
		h += -ridgeD * 0.45
	end

	-- Lake basin.
	local ld = dist(x, z, W.Lake.x, W.Lake.z)
	local basin = 1 - smoothstep(W.Lake.radius - 18, W.Lake.radius + 22, ld)
	h = h + ((W.WaterLevel - W.Lake.depth) - h) * basin

	-- Flatten clearings.
	for _, c in clearings do
		local d = dist(x, z, c.x, c.z)
		local w = 1 - smoothstep(c.r, c.r + 22, d)
		h = h + (c.h - h) * w
	end

	-- Trails are slightly sunk and smoothed.
	local td = Terrain.trailDistance(x, z)
	if td < 6 then
		h -= 0.4 * (1 - td / 6)
	end

	-- Mountains close the map.
	local edge = math.max(math.abs(x), math.abs(z))
	if edge > W.MountainStart then
		local k = (edge - W.MountainStart) / 60
		h += k * k * 55 + math.noise(x / 30, z / 30, 9.2) * 8 * math.min(k, 1)
	end
	return h
end

local function materialAt(x: number, z: number, h: number, depthBelowSurface: number): Enum.Material
	if depthBelowSurface > 6 then
		return Enum.Material.Rock
	end
	local edge = math.max(math.abs(x), math.abs(z))
	if edge > W.MountainStart + 25 then
		return if depthBelowSurface > 1 or h > 60 then Enum.Material.Rock else Enum.Material.Slate
	end
	local slope = math.abs(Terrain.heightAt(x + 2, z) - Terrain.heightAt(x - 2, z))
		+ math.abs(Terrain.heightAt(x, z + 2) - Terrain.heightAt(x, z - 2))
	if slope > 5 then
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
	if dist(x, z, W.Cabin.x, W.Cabin.z) < W.Cabin.clearing then
		return Enum.Material.Grass
	end
	local n = math.noise(x / 35, z / 35, 7.7)
	if n > 0.25 then
		return Enum.Material.Ground
	end
	return Enum.Material.LeafyGrass
end

-- Writes all terrain voxels. Runs in chunks so the server stays responsive.
function Terrain.generate()
	local terrain = workspace.Terrain
	terrain:Clear()
	local half = W.HalfSize
	local yMin, yMax = -24, 120
	local chunk = 32 -- cells per chunk side
	local cellsY = (yMax - yMin) // CELL
	local total = (2 * half) // CELL
	for cx = 0, total - 1, chunk do
		for cz = 0, total - 1, chunk do
			local nx = math.min(chunk, total - cx)
			local nz = math.min(chunk, total - cz)
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
					local h = Terrain.heightAt(x, z)
					local surfaceMat = materialAt(x, z, h, 0)
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
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(78, 98, 54))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(62, 82, 46))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(88, 72, 56))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(60, 50, 42))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(86, 88, 86))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(96, 96, 94))
end

function Terrain.isWater(x: number, z: number): boolean
	return Terrain.heightAt(x, z) < W.WaterLevel - 0.5
end

return Terrain

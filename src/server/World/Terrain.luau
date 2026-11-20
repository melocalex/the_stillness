--!strict
-- Writes the Pinehaven valley into Roblox terrain at server start. Heights
-- come from the pure, deterministic height function in
-- Shared.Logic.Heightfield (Lune-tested, also rendered to docs/world-map.svg);
-- this module adds surface materials and writes voxels chunk by chunk, only
-- over each chunk's height band.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local Heightfield = require(ReplicatedStorage.Shared.Logic.Heightfield)

local Terrain = {}

local W = WorldConfig
local CELL = 4
local CHUNK = 16 -- cells per chunk side
local YIELD_BUDGET = 0.1 -- seconds of work between yields
local FAR = W.PlayableRadius + 140 -- beyond this nobody walks: thin band, no rock floor

-- WorldConfig carries more fields than the height function reads (Luau arrays
-- are invariant, so the house list does not narrow); the Lune specs pin the
-- shape instead.
local field = Heightfield.new(W :: any)
Terrain.field = field

function Terrain.heightAt(x: number, z: number): number
	return field.heightAt(x, z)
end

function Terrain.isWater(x: number, z: number): boolean
	return field.isWater(x, z)
end

function Terrain.lakeMetric(x: number, z: number): number
	return field.lakeMetric(x, z)
end

-- Distance to the nearest trail or road edge (0 on the path).
function Terrain.trailDistance(x: number, z: number): number
	local d, width = field.pathDistance(x, z)
	return math.max(d - width + 3.5, 0)
end

function Terrain.clearingHeight(x: number, z: number): number?
	return field.padHeight(x, z)
end

function Terrain.inMeadow(x: number, z: number): boolean
	return field.inMeadow(x, z)
end

-- Rise per stud across 4 studs.
function Terrain.slopeAt(x: number, z: number): number
	local dx = field.heightAt(x + 2, z) - field.heightAt(x - 2, z)
	local dz = field.heightAt(x, z + 2) - field.heightAt(x, z - 2)
	return math.sqrt(dx * dx + dz * dz) / 4
end

local function inBog(x: number, z: number): boolean
	return (x - W.ThreatArea.x) ^ 2 + (z - W.ThreatArea.z) ^ 2 < W.ThreatArea.radius ^ 2
end

-- Surface material from height, slope (rise per stud), shoreline and paths.
local function materialAt(x: number, z: number, h: number, slope: number): Enum.Material
	local far = math.max(math.abs(x), math.abs(z)) > FAR
	local m = if far then math.huge else field.lakeMetric(x, z)
	if m < -1.5 then
		return if m > -10 and math.noise(x / 90, z / 90, 31.7) > 0.05
			then Enum.Material.Sand
			else Enum.Material.Mud
	end
	local snow = field.snowLine(x, z)
	if h > snow then
		return if slope > 1.25 then Enum.Material.Rock else Enum.Material.Snow
	end
	if h > snow - 45 and slope < 0.7 and math.noise(x / 36, z / 36, 33.1) > 0.3 then
		return Enum.Material.Snow -- lingering patches below the line
	end
	if slope > 1.1 then
		return if h > 110 then Enum.Material.Rock else Enum.Material.Slate
	end
	if h > 175 then
		return if math.noise(x / 50, z / 50, 34.3) > 0.15 then Enum.Material.Rock else Enum.Material.Ground
	end
	if m < 8 then
		local shore = math.noise(x / 90, z / 90, 31.7)
		if shore > 0.05 then
			return Enum.Material.Sand
		elseif shore < -0.2 then
			return Enum.Material.Mud
		end
		return Enum.Material.Pebble
	end
	if not far then
		local pd, width = field.pathDistance(x, z)
		if pd < width then
			return Enum.Material.Ground
		end
	end
	if slope > 0.65 then
		return Enum.Material.Ground
	end
	local n = math.noise(x / 35, z / 35, 7.7)
	if not far then
		if inBog(x, z) then
			return if n > -0.1 then Enum.Material.Mud else Enum.Material.LeafyGrass
		end
		if
			field.inMeadow(x, z) or (x - W.Cabin.x) ^ 2 + (z - W.Cabin.z) ^ 2 < (W.Cabin.clearing + 10) ^ 2
		then
			return Enum.Material.Grass
		end
	end
	if n > 0.38 then
		return Enum.Material.Ground
	end
	return if n < -0.25 then Enum.Material.Grass else Enum.Material.LeafyGrass
end

-- Writes all terrain voxels. Heights are evaluated once per 4-stud column
-- into a grid (slopes read neighbours from it), then written in 64-stud
-- chunks, each only over its own height band.
function Terrain.generate()
	local started = os.clock()
	local terrain = workspace.Terrain
	terrain:Clear()
	local half = W.HalfSize
	local total = (2 * half) // CELL
	local lastYield = os.clock()
	local function budget()
		if os.clock() - lastYield > YIELD_BUDGET then
			task.wait()
			lastYield = os.clock()
		end
	end

	local grid: { { number } } = table.create(total)
	for ix = 1, total do
		local col = table.create(total)
		local x = -half + (ix - 1) * CELL + CELL / 2
		for iz = 1, total do
			col[iz] = field.heightAt(x, -half + (iz - 1) * CELL + CELL / 2)
		end
		grid[ix] = col
		budget()
	end
	local heightsDone = os.clock() - started

	local voxels = 0
	for cx = 0, total - 1, CHUNK do
		for cz = 0, total - 1, CHUNK do
			local nx = math.min(CHUNK, total - cx)
			local nz = math.min(CHUNK, total - cz)
			local x0 = -half + cx * CELL
			local z0 = -half + cz * CELL
			local far = math.abs(x0 + nx * CELL / 2) > FAR or math.abs(z0 + nz * CELL / 2) > FAR
			local lo, hi = math.huge, -math.huge
			for ix = 1, nx do
				local col = grid[cx + ix]
				for iz = 1, nz do
					local h = col[cz + iz]
					lo = math.min(lo, h)
					hi = math.max(hi, h)
				end
			end
			local wet = lo < W.WaterLevel
			local yMin = math.floor((lo - (if far then 6 else 10)) / CELL) * CELL
			local yMax = math.ceil(((if wet then math.max(hi, W.WaterLevel) else hi) + 4) / CELL) * CELL
			local cellsY = (yMax - yMin) // CELL
			local materials = table.create(nx)
			local occupancy = table.create(nx)
			for ix = 1, nx do
				local gx = cx + ix
				local col = grid[gx]
				local left = grid[math.max(gx - 1, 1)]
				local right = grid[math.min(gx + 1, total)]
				local mx = table.create(cellsY)
				local ox = table.create(cellsY)
				for iy = 1, cellsY do
					mx[iy] = table.create(nz)
					ox[iy] = table.create(nz)
				end
				local x = x0 + (ix - 1) * CELL + CELL / 2
				for iz = 1, nz do
					local gz = cz + iz
					local h = col[gz]
					local dx = right[gz] - left[gz]
					local dz = col[math.min(gz + 1, total)] - col[math.max(gz - 1, 1)]
					local slope = math.sqrt(dx * dx + dz * dz) / (4 * CELL)
					local surface = materialAt(x, z0 + (iz - 1) * CELL + CELL / 2, h, slope)
					for iy = 1, cellsY do
						local bottom = yMin + (iy - 1) * CELL
						local occ = math.clamp((h - bottom) / CELL, 0, 1)
						if occ > 0.02 then
							mx[iy][iz] = if h - (bottom + CELL) > 6 then Enum.Material.Rock else surface
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
			local region = Region3.new(
				Vector3.new(x0, yMin, z0),
				Vector3.new(x0 + nx * CELL, yMin + cellsY * CELL, z0 + nz * CELL)
			)
			terrain:WriteVoxels(region, CELL, materials, occupancy)
			voxels += nx * nz * cellsY
			if not far then
				-- Solid rock below the band so nothing can fall through.
				terrain:FillBlock(
					CFrame.new(x0 + nx * CELL / 2, yMin - 6, z0 + nz * CELL / 2),
					Vector3.new(nx * CELL, 12, nz * CELL),
					Enum.Material.Rock
				)
			end
			budget()
		end
	end
	pcall(function()
		(terrain :: any).Decoration = true
	end)
	-- Muted, slightly green lake that does not mirror the sky as flat blue.
	terrain.WaterColor = Color3.fromRGB(38, 52, 50)
	terrain.WaterTransparency = 0.3
	terrain.WaterReflectance = 0.3
	terrain.WaterWaveSize = 0.06
	terrain.WaterWaveSpeed = 5
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(80, 98, 56))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(56, 76, 44))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(86, 72, 56))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(58, 50, 42))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(148, 136, 112))
	terrain:SetMaterialColor(Enum.Material.Pebble, Color3.fromRGB(112, 108, 100))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(86, 88, 88))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(104, 104, 102))
	terrain:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(232, 236, 240))
	print(
		string.format(
			"[Terrain] %d columns, %.1fM voxels: heights %.2fs, total %.2fs",
			total * total,
			voxels / 1e6,
			heightsDone,
			os.clock() - started
		)
	)
end

return Terrain

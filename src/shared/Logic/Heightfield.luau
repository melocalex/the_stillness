--!strict
-- The Pinehaven valley as one deterministic height function. Pure: takes the
-- world config as a value, requires nothing and uses only math (math.noise is
-- part of Luau), so Lune tests and the image tool run exactly what the server
-- writes into terrain voxels.
--
-- Layers, from broad to fine:
--   1. Valley floor: base height plus a slight tilt toward the south-east
--      outlet. Hills are damped near the valley spine (livable lowlands) and
--      roll freely away from it.
--   2. Authored forms (config data): hills, asymmetric ridges with saddles,
--      far snowy peaks. Distances are domain-warped so no form is a perfect
--      circle or straight line.
--   3. Detail noise, crags on high ground only.
--   4. The lake: elliptical lobes plus shoreline noise give coves, shelves
--      and beaches; islands are negative lobes.
--   5. Building pads (fixed heights the gameplay code builds on) and road beds.

local Heightfield = {}

export type Point = { x: number, z: number }
export type Hill = { x: number, z: number, height: number, rx: number, rz: number, yaw: number? }
export type Saddle = { x: number, z: number, depth: number, radius: number }
export type Ridge = {
	name: string,
	points: { Point },
	crest: number,
	width: number,
	-- Width multiplier on the left side of the polyline (direction of travel).
	-- Above 1 the left flank is the long gentle one.
	asym: number?,
	saddles: { Saddle }?,
	-- 0 = smooth forested ridge, 1 = alpine: ridged noise carves spurs and gullies.
	rough: number?,
}
export type Peak = {
	name: string,
	x: number,
	z: number,
	height: number,
	radius: number,
	sharp: number?,
	rough: number?,
}
export type Lobe = { x: number, z: number, rx: number, rz: number, yaw: number? }
export type Road = { width: number, points: { Point } }
export type Pad = { x: number, z: number, r: number, h: number, blend: number? }

export type Config = {
	Seed: number,
	WaterLevel: number,
	BaseHeight: number,
	Cabin: { x: number, z: number, floorY: number, clearing: number },
	LakeHouse: { x: number, z: number, clearing: number, height: number },
	AbandonedHouse: { x: number, z: number, clearing: number, height: number },
	Houses: { { x: number, z: number } },
	Trails: { { Point } },
	Roads: { Road },
	Meadows: { { x: number, z: number, r: number } },
	Lake: { depth: number, lobes: { Lobe }, islands: { Lobe }, shoreNoise: number },
	Terrain: {
		Tilt: Point,
		Spine: { Point },
		SpineInner: number,
		SpineOuter: number,
		HillsNear: number,
		HillsFar: number,
		Hills: { Hill },
		Ridges: { Ridge },
		Peaks: { Peak },
		SnowLine: number,
		CragStart: number,
	},
}

export type Field = {
	config: Config,
	-- Natural ground (lake included), before pads and roads.
	rawHeight: (x: number, z: number) -> number,
	-- Final ground height: what terrain voxels are written to.
	heightAt: (x: number, z: number) -> number,
	-- Signed shoreline distance: negative in the lake, positive on land.
	lakeMetric: (x: number, z: number) -> number,
	isWater: (x: number, z: number) -> boolean,
	-- Distance to the nearest trail or road centreline, and that path's half width.
	pathDistance: (x: number, z: number) -> (number, number),
	-- Fixed pad height under (x, z) when inside a building pad's core.
	padHeight: (x: number, z: number) -> number?,
	snowLine: (x: number, z: number) -> number,
	inMeadow: (x: number, z: number) -> boolean,
}

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Distance from (x, z) to segment a-b, the parameter t along it, and the
-- side: 1 fully left, -1 fully right (looking from a to b), in between
-- around the end caps so nothing that depends on the side jumps there.
local function segment(
	x: number,
	z: number,
	ax: number,
	az: number,
	bx: number,
	bz: number
): (number, number, number)
	local vx, vz = bx - ax, bz - az
	local len2 = vx * vx + vz * vz
	local t = if len2 > 0 then math.clamp(((x - ax) * vx + (z - az) * vz) / len2, 0, 1) else 0
	local px, pz = ax + vx * t - x, az + vz * t - z
	local d = math.sqrt(px * px + pz * pz)
	local perp = if len2 > 0 then -(vx * (z - az) - vz * (x - ax)) / math.sqrt(len2) else 0
	return d, t, if d > 1e-6 then math.clamp(perp / d, -1, 1) else 0
end

type Seg = { ax: number, az: number, bx: number, bz: number, len: number, start: number }
type Poly = { segs: { Seg }, total: number, minX: number, maxX: number, minZ: number, maxZ: number }

local function poly(points: { Point }, margin: number): Poly
	local segs: { Seg } = {}
	local total = 0
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i, p in points do
		minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
		minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
		local q = points[i + 1]
		if q then
			local len = math.sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2)
			table.insert(segs, { ax = p.x, az = p.z, bx = q.x, bz = q.z, len = len, start = total })
			total += len
		end
	end
	return {
		segs = segs,
		total = total,
		minX = minX - margin,
		maxX = maxX + margin,
		minZ = minZ - margin,
		maxZ = maxZ + margin,
	}
end

-- Nearest point on a polyline: distance, arc length along it, side.
local function nearest(pl: Poly, x: number, z: number): (number, number, number)
	local best, along, side = math.huge, 0, 1
	for _, s in pl.segs do
		local d, t, sd = segment(x, z, s.ax, s.az, s.bx, s.bz)
		if d < best then
			best, along, side = d, s.start + t * s.len, sd
		end
	end
	return best, along, side
end

local function inBox(pl: Poly, x: number, z: number): boolean
	return x >= pl.minX and x <= pl.maxX and z >= pl.minZ and z <= pl.maxZ
end

-- Ridge cross-section: 1 on the crest, 0 at u = 1, smooth everywhere.
local function profile(u: number): number
	return (0.5 + 0.5 * math.cos(math.pi * u)) ^ 1.25
end

function Heightfield.new(cfg: Config): Field
	local T = cfg.Terrain
	local W = cfg.WaterLevel
	-- Seed-dependent noise planes (math.noise is 0 on integer lattices, so
	-- every offset is fractional).
	local s0 = (cfg.Seed % 997) * 0.1373 + 0.371
	local function n(x: number, z: number, k: number): number
		return math.noise(x, z, s0 + k * 1.618)
	end

	-- Ridged multi-octave noise, about 0..0.9: sharp crests, branching gullies.
	local function ridged(x: number, z: number): number
		local sum, amp, freq, weight = 0, 0.5, 1, 1
		for o = 1, 4 do
			local v = 1 - math.abs(n(x * freq, z * freq, 20 + o))
			v = v * v * weight
			weight = math.clamp(v * 2, 0, 1)
			sum += v * amp
			amp *= 0.5
			freq *= 2.1
		end
		return sum
	end
	local function roughen(rough: number?, wx: number, wz: number): number
		local r = rough or 0
		if r <= 0 then
			return 1
		end
		return lerp(1, 0.6 + 0.95 * ridged(wx / 260, wz / 260), r)
	end

	local spine = poly(T.Spine, 0)

	type RidgeC = { r: Ridge, pl: Poly, asym: number, reach: number }
	local ridges: { RidgeC } = {}
	for _, r in T.Ridges do
		local asym = r.asym or 1
		local reach = r.width * math.max(asym, 1)
		table.insert(ridges, { r = r, pl = poly(r.points, reach + 80), asym = asym, reach = reach })
	end

	type LobeC = { x: number, z: number, rx: number, rz: number, c: number, s: number }
	local function lobes(list: { Lobe }): { LobeC }
		local out: { LobeC } = {}
		for _, l in list do
			local a = math.rad(l.yaw or 0)
			table.insert(out, { x = l.x, z = l.z, rx = l.rx, rz = l.rz, c = math.cos(a), s = math.sin(a) })
		end
		return out
	end
	local lakeLobes = lobes(cfg.Lake.lobes)
	local islands = lobes(cfg.Lake.islands)
	local lakeMinX, lakeMaxX, lakeMinZ, lakeMaxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, l in lakeLobes do
		local r = math.max(l.rx, l.rz) + 70
		lakeMinX, lakeMaxX = math.min(lakeMinX, l.x - r), math.max(lakeMaxX, l.x + r)
		lakeMinZ, lakeMaxZ = math.min(lakeMinZ, l.z - r), math.max(lakeMaxZ, l.z + r)
	end

	-- Approximate signed distance to an ellipse lobe (negative inside).
	local function lobeDist(l: LobeC, x: number, z: number): number
		local dx, dz = x - l.x, z - l.z
		local lx = dx * l.c + dz * l.s
		local lz = -dx * l.s + dz * l.c
		local q = math.sqrt((lx / l.rx) ^ 2 + (lz / l.rz) ^ 2)
		return (q - 1) * math.min(l.rx, l.rz)
	end

	local function lakeMetric(x: number, z: number): number
		if x < lakeMinX or x > lakeMaxX or z < lakeMinZ or z > lakeMaxZ then
			return math.huge
		end
		local m = math.huge
		for _, l in lakeLobes do
			m = math.min(m, lobeDist(l, x, z))
		end
		m += (n(x / 48, z / 48, 11) * 0.75 + n(x / 17, z / 17, 12) * 0.25) * cfg.Lake.shoreNoise
		for _, l in islands do
			m = math.max(m, -lobeDist(l, x, z))
		end
		return m
	end

	-- Broad natural ground without lake, pads or roads.
	local function naturalHeight(x: number, z: number): number
		-- Domain warp for the authored forms.
		local wx = x + n(x / 520, z / 520, 1) * 90
		local wz = z + n(x / 520, z / 520, 2) * 90

		local ds = nearest(spine, x, z)
		local lowland = 1 - smoothstep(T.SpineInner, T.SpineOuter, ds)
		local amp = lerp(T.HillsFar, T.HillsNear, lowland)
		local rolling = n(wx / 300, wz / 300, 3)
			+ 0.5 * n(wx / 140, wz / 140, 4)
			+ 0.25 * n(wx / 70, wz / 70, 5)
		local h = cfg.BaseHeight + x * T.Tilt.x + z * T.Tilt.z + amp * (0.45 + rolling)

		local forms = 0
		-- Hills carry landmarks (radio tower, hill house), so they are not warped.
		for _, hl in T.Hills do
			local a = math.rad(hl.yaw or 0)
			local dx, dz = x - hl.x, z - hl.z
			local lx = dx * math.cos(a) + dz * math.sin(a)
			local lz = -dx * math.sin(a) + dz * math.cos(a)
			local q2 = (lx / hl.rx) ^ 2 + (lz / hl.rz) ^ 2
			if q2 < 9 then
				forms += hl.height * math.exp(-q2)
			end
		end
		for i, rc in ridges do
			if inBox(rc.pl, wx, wz) then
				local d, along, side = nearest(rc.pl, wx, wz)
				local width = lerp(rc.r.width, rc.r.width * rc.asym, smoothstep(-1, 1, side))
				if d < width then
					local frac = along / rc.pl.total
					local taper = smoothstep(0, 0.16, frac) * smoothstep(1, 0.84, frac)
					local crest = rc.r.crest * (0.5 + 0.5 * taper) * (1 + 0.18 * n(along / 170, i * 3.1, 6))
					-- Saddles are anchored in world space (not warped) so a pass
					-- stays exactly where a trail crosses it.
					local saddles: { Saddle } = rc.r.saddles or {}
					for _, sd in saddles do
						crest *= 1 - sd.depth * math.exp(-((x - sd.x) ^ 2 + (z - sd.z) ^ 2) / sd.radius ^ 2)
					end
					forms += crest * profile(d / width) * roughen(rc.r.rough, wx, wz)
				end
			end
		end
		for _, p in T.Peaks do
			local dx, dz = wx - p.x, wz - p.z
			local u = math.sqrt(dx * dx + dz * dz) / p.radius
			if u < 1 then
				forms += p.height * (1 - u) ^ (p.sharp or 2) * roughen(p.rough, wx, wz)
			end
		end
		-- Crags and arêtes only where the ground is already high.
		if forms > T.CragStart then
			local ridged = 1 - math.abs(n(wx / 110, wz / 110, 7))
			forms += ridged * ridged * 0.24 * (forms - T.CragStart)
		end
		h += forms
		h += n(x / 38, z / 38, 8) * 1.6 + n(x / 15, z / 15, 9) * 0.45
		return h
	end

	local function rawHeight(x: number, z: number): number
		local h = naturalHeight(x, z)
		local m = lakeMetric(x, z)
		if m < 44 then
			local target = if m >= 0
				then W - 0.6 + m * 0.2
				else W - 0.6 - cfg.Lake.depth * smoothstep(0, 36, -m)
			local w = 1 - smoothstep(6, 44, m)
			h = lerp(h, target, w)
		elseif h < W + 1.2 then
			h = W + 1.2 -- no stray ponds outside the lake
		end
		return h
	end

	local pads: { Pad } = {
		{ x = cfg.Cabin.x, z = cfg.Cabin.z, r = cfg.Cabin.clearing, h = cfg.Cabin.floorY - 1.5 },
		{ x = cfg.LakeHouse.x, z = cfg.LakeHouse.z, r = cfg.LakeHouse.clearing, h = cfg.LakeHouse.height },
		{
			x = cfg.AbandonedHouse.x,
			z = cfg.AbandonedHouse.z,
			r = cfg.AbandonedHouse.clearing,
			h = cfg.AbandonedHouse.height,
		},
	}
	-- Neighbor houses sit at the mean ground of their footprint (cut and
	-- fill), with a wider blend so a house on a slope does not raise a mound.
	for _, house in cfg.Houses do
		local sum, count = rawHeight(house.x, house.z), 1
		for a = 0, 315, 45 do
			for _, r in { 11, 22 } do
				sum += rawHeight(house.x + math.cos(math.rad(a)) * r, house.z + math.sin(math.rad(a)) * r)
				count += 1
			end
		end
		table.insert(pads, { x = house.x, z = house.z, r = 22, h = sum / count, blend = 40 })
	end

	-- Paths carry a bed profile: the ground sampled every 4 studs along the
	-- path and averaged over about 50 studs, so the bed cuts through bumps and
	-- fills dips (cut and fill) while keeping the overall climb.
	local PATH_STEP = 4
	type PathC = { pl: Poly, width: number, bed: { number } }
	local paths: { PathC } = {}
	local function addPath(points: { Point }, width: number)
		local pl = poly(points, width + 16)
		local samples: { number } = {}
		for _, s in pl.segs do
			for d = 0, s.len - 0.01, PATH_STEP do
				local f = d / s.len
				table.insert(samples, rawHeight(s.ax + (s.bx - s.ax) * f, s.az + (s.bz - s.az) * f))
			end
		end
		local last = points[#points]
		table.insert(samples, rawHeight(last.x, last.z))
		-- The window shrinks to nothing at both ends, so paths that meet share
		-- the ground height at the junction.
		local bed = samples
		for _ = 1, 2 do
			local out = table.create(#bed)
			for i = 1, #bed do
				local r = math.min(6, i - 1, #bed - i)
				local sum = 0
				for j = i - r, i + r do
					sum += bed[j]
				end
				out[i] = math.max(sum / (2 * r + 1), W + 1)
			end
			bed = out
		end
		table.insert(paths, { pl = pl, width = width, bed = bed })
	end
	for _, trail in cfg.Trails do
		addPath(trail, 3.5)
	end
	for _, road in cfg.Roads do
		addPath(road.points, road.width)
	end

	-- Nearest path: distance to its centreline and its half width; plus the
	-- bed height blended over every path in reach (no steps at junctions) and
	-- the strongest path weight there.
	local function nearestPath(x: number, z: number): (number, number, number, number)
		local best, width = math.huge, 0
		local bedSum, weightSum, weight = 0, 0, 0
		for _, p in paths do
			if inBox(p.pl, x, z) then
				local d, along = nearest(p.pl, x, z)
				if d - p.width < best - width then
					best, width = d, p.width
				end
				if d < p.width + 8 then
					local i = along / PATH_STEP + 1
					local i0 = math.clamp(math.floor(i), 1, #p.bed)
					local i1 = math.min(i0 + 1, #p.bed)
					local w = 1 - smoothstep(p.width, p.width + 8, d)
					bedSum += lerp(p.bed[i0], p.bed[i1], i - math.floor(i)) * w
					weightSum += w
					weight = math.max(weight, w)
				end
			end
		end
		return best, width, if weightSum > 0 then bedSum / weightSum else 0, weight
	end

	local function pathDistance(x: number, z: number): (number, number)
		local d, width = nearestPath(x, z)
		return d, width
	end

	local function padHeight(x: number, z: number): number?
		for _, c in pads do
			if (x - c.x) ^ 2 + (z - c.z) ^ 2 < 16 then
				return c.h
			end
		end
		return nil
	end

	local function heightAt(x: number, z: number): number
		local h = rawHeight(x, z)
		local padW = 0
		for _, c in pads do
			local d = math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2)
			local blend = c.blend or 24
			if d < c.r + blend then
				local w = 1 - smoothstep(c.r, c.r + blend, d)
				h = lerp(h, c.h, w)
				padW = math.max(padW, w)
			end
		end
		-- Path beds win over natural ground (pads win over both); every path
		-- is worn in slightly.
		local _, _, bed, w = nearestPath(x, z)
		if w > 0 then
			h = lerp(h, bed, w * (1 - padW))
			h -= 0.3 * w
		end
		return h
	end

	local function snowLine(x: number, z: number): number
		return T.SnowLine + n(x / 130, z / 130, 10) * 50
	end

	local function inMeadow(x: number, z: number): boolean
		for _, m in cfg.Meadows do
			if (x - m.x) ^ 2 + (z - m.z) ^ 2 < m.r * m.r then
				return true
			end
		end
		return false
	end

	return {
		config = cfg,
		rawHeight = rawHeight,
		heightAt = heightAt,
		lakeMetric = lakeMetric,
		isWater = function(x: number, z: number): boolean
			return heightAt(x, z) < W - 0.5
		end,
		pathDistance = pathDistance,
		padHeight = padHeight,
		snowLine = snowLine,
		inMeadow = inMeadow,
	}
end

return Heightfield

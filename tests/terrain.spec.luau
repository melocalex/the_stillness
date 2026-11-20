--!strict
-- Specs for the valley height function (src/shared/Logic/Heightfield.luau)
-- against the gameplay that depends on world coordinates. The pre-rebuild
-- height function runs alongside as a control where a check is about the
-- old "arena" shape. Run: lune run tests/terrain.spec

local process = require("@lune/process")
local t = require("./harness")
local describe, it, eq, truthy, falsy = t.describe, t.it, t.eq, t.truthy, t.falsy

local WorldConfig = require("../src/shared/Config/WorldConfig")
local Heightfield = require("../src/shared/Logic/Heightfield")
local Legacy = require("./fixtures/legacy_terrain")

local W = WorldConfig :: any
local field = Heightfield.new(W)
local h = field.heightAt
local WATER = W.WaterLevel

-- Highest terrain elevation angle (degrees) seen from an eye, per bearing.
local function horizon(
	height: (number, number) -> number,
	half: number,
	ex: number,
	ez: number,
	ey: number
): { number }
	local out = {}
	for b = 0, 358, 2 do
		local a = math.rad(b)
		local best = -90
		local d = 30
		while true do
			local x, z = ex + math.sin(a) * d, ez - math.cos(a) * d
			if math.abs(x) > half or math.abs(z) > half then
				break
			end
			best = math.max(best, math.deg(math.atan((height(x, z) - ey) / d)))
			d += 8
		end
		table.insert(out, best)
	end
	return out
end

local function fractionBelow(list: { number }, limit: number): number
	local n = 0
	for _, v in list do
		if v < limit then
			n += 1
		end
	end
	return n / #list
end

-- True when terrain stays below the straight line between two points.
local function clearLine(ax: number, ay: number, az: number, bx: number, by: number, bz: number): boolean
	local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	for s = 4, len - 4, 4 do
		local f = s / len
		if h(ax + (bx - ax) * f, az + (bz - az) * f) > ay + (by - ay) * f - 0.5 then
			return false
		end
	end
	return true
end

-- Same point as CreatureService.edgePoint (bearing 0 = north, clockwise).
local function edge(bearing: number, distance: number): (number, number)
	local a = math.rad(bearing)
	return W.Cabin.x + math.sin(a) * distance, W.Cabin.z - math.cos(a) * distance
end

local CABIN_EYE = 13
local WINDOW = { x = 0, y = W.Cabin.floorY + 5, z = -14 } -- the cabin's north window

describe("Heightfield", function()
	it("is deterministic and follows the seed", function()
		local again = Heightfield.new(W)
		for _, p in { { 0, 0 }, { 123.4, -567.8 }, { -900, 1200 }, { 1400, -1400 } } do
			eq(again.heightAt(p[1], p[2]), h(p[1], p[2]))
		end
		local reseeded = table.clone(W)
		reseeded.Seed = W.Seed + 1
		truthy(Heightfield.new(reseeded).heightAt(300, 300) ~= h(300, 300), "seed has no effect")
	end)

	it("keeps the fixed building pads flat at the heights gameplay builds on", function()
		for _, pad in
			{ { W.Cabin, W.Cabin.floorY - 1.5, 36 }, { W.LakeHouse, 8, 22 }, { W.AbandonedHouse, 6, 22 } }
		do
			local c, height, r = pad[1], pad[2], pad[3]
			for a = 0, 330, 30 do
				for _, d in { 0, r / 2, r } do
					local y = h(c.x + math.cos(math.rad(a)) * d, c.z + math.sin(math.rad(a)) * d)
					truthy(math.abs(y - height) < 0.35, string.format("pad at %d,%d is %.2f", c.x, c.z, y))
				end
			end
		end
	end)

	it("sits the fixed pads close to the ground around them", function()
		for _, c in { W.Cabin, W.LakeHouse, W.AbandonedHouse } do
			local sum = 0
			for a = 0, 330, 30 do
				sum += field.rawHeight(c.x + math.cos(math.rad(a)) * 70, c.z + math.sin(math.rad(a)) * 70)
			end
			local pad = field.padHeight(c.x, c.z) :: number
			truthy(math.abs(sum / 12 - pad) < 5, string.format("pad %.1f vs ground %.1f", pad, sum / 12))
		end
	end)

	it("has a lake deep enough to read as water, and water only in the lake", function()
		truthy(h(0, -158) < WATER - 8, "lake centre too shallow")
		local P = W.PlayableRadius
		for x = -P, P, 8 do
			for z = -P, P, 8 do
				if field.isWater(x, z) then
					truthy(field.lakeMetric(x, z) < 8, string.format("stray water at %d,%d", x, z))
				end
			end
		end
	end)

	it("gives the lake an irregular shoreline, not a circle", function()
		local lo, hi = math.huge, 0
		for a = 0, 355, 5 do
			local r = 0
			while
				field.isWater(
					W.Lake.x + math.cos(math.rad(a)) * (r + 2),
					W.Lake.z + math.sin(math.rad(a)) * (r + 2)
				)
			do
				r += 2
			end
			lo, hi = math.min(lo, r), math.max(hi, r)
		end
		truthy(lo > 20, "lake pinches shut")
		truthy(hi / lo > 1.8, string.format("shore radius %d..%d is too round", lo, hi))
	end)

	it("keeps every building, landmark and meadow on dry land", function()
		local spots = {
			{ "Cabin", W.Cabin.x, W.Cabin.z },
			{ "LakeHouse", W.LakeHouse.x, W.LakeHouse.z },
			{ "Maya porch", W.LakeHouse.x + 15, W.LakeHouse.z + 0.5 },
			{ "AbandonedHouse", W.AbandonedHouse.x, W.AbandonedHouse.z },
			{ "RadioTower", W.RadioTower.x, W.RadioTower.z },
			{ "Spawn", W.Spawn.x, W.Spawn.z },
		}
		for _, house in W.Houses do
			table.insert(spots, { house.id, house.x, house.z })
		end
		for _, m in W.Meadows do
			table.insert(spots, { "meadow", m.x, m.z })
		end
		for _, s in spots do
			truthy(field.rawHeight(s[2], s[3]) > WATER + 1.5, s[1] .. " is in the water")
			truthy(field.lakeMetric(s[2], s[3]) > 12, s[1] .. " is on the shoreline")
		end
	end)

	it("keeps zones inside their volumes and above the kill floor", function()
		local T = W.ThreatArea
		for a = 0, 330, 30 do
			for _, d in { 0, T.radius / 2, T.radius } do
				local y = h(T.x + math.cos(math.rad(a)) * d, T.z + math.sin(math.rad(a)) * d)
				truthy(y > -30 and y < 70, "bog ground outside the ThreatZone part")
			end
		end
		local P = W.PlayableRadius
		for x = -P, P, 16 do
			for z = -P, P, 16 do
				truthy(h(x, z) > -40, "ground near the kill floor")
			end
		end
	end)
end)

describe("Valley shape", function()
	local new = horizon(h, W.HalfSize, W.Cabin.x, W.Cabin.z, CABIN_EYE)
	local old = horizon(Legacy.height, Legacy.HalfSize, 0, 0, CABIN_EYE)

	it("frames the cabin with an uneven horizon that opens down the valley", function()
		local lo, hi = math.huge, -math.huge
		for _, v in new do
			lo, hi = math.min(lo, v), math.max(hi, v)
		end
		truthy(hi < 21, string.format("a wall rises to %.1f degrees", hi))
		truthy(hi - lo > 10, "horizon is uniform")
		truthy(fractionBelow(new, 4.5) >= 0.1, "no open, low bearings")
	end)

	it("control: the old terrain enclosed the cabin on every bearing", function()
		truthy(fractionBelow(old, 4.5) < 0.1, "legacy unexpectedly open")
		local lo = math.huge
		for _, v in old do
			lo = math.min(lo, v)
		end
		truthy(lo > 15, "legacy horizon had a gap")
	end)

	it("never shows the end of the world below the horizon from the lowlands", function()
		local eyes = {
			{ "cabin", W.Cabin.x, W.Cabin.z },
			{ "lake shore", -30, -98 },
			{ "radio hill", W.RadioTower.x, W.RadioTower.z },
			{ "hill house", 235, -170 },
			{ "valley road", 340, 410 },
		}
		for _, e in eyes do
			local list = horizon(h, W.HalfSize, e[2], e[3], h(e[2], e[3]) + 6)
			for i, v in list do
				truthy(v > 0.3, string.format("%s: bearing %d sees past the terrain edge", e[1], (i - 1) * 2))
			end
		end
	end)

	it("keeps snow and alpine walls out of the playable square", function()
		local P = W.PlayableRadius
		-- The writer's own rule, at slope 0 (where snow patches are likeliest),
		-- plus a margin below the line itself.
		for x = -P, P, 8 do
			for z = -P, P, 8 do
				local y = h(x, z)
				falsy(field.isSnow(x, z, y, 0), string.format("snow inside the play area at %d,%d", x, z))
				truthy(y < field.snowLine(x, z) - 25, string.format("close to the snow line at %d,%d", x, z))
			end
		end
		local legacyMax = -math.huge
		for x = -P, P, 20 do
			legacyMax = math.max(legacyMax, Legacy.height(x, -P), Legacy.height(-P, x))
		end
		truthy(legacyMax > 150, "control: legacy walls stood inside the play area")
	end)

	it("puts dramatic snowy peaks only far away", function()
		local peak = -math.huge
		for x = -W.HalfSize, W.HalfSize, 16 do
			for z = -W.HalfSize, W.HalfSize, 16 do
				local y = h(x, z)
				peak = math.max(peak, y)
				if y > field.snowLine(x, z) then
					truthy(math.sqrt(x * x + z * z) > 1000, string.format("snow %d studs from the cabin", x))
				end
			end
		end
		truthy(peak > 400, "no dramatic peak")
	end)

	it("has no radial ramp at the playable boundary", function()
		-- Compare each boundary point with the point 30% further in.
		local P = W.PlayableRadius
		local function rampFraction(height: (number, number) -> number): (number, number, number)
			local ramp, total, lo, hi = 0, 0, math.huge, -math.huge
			for s = -P, P, 20 do
				for _, p in { { s, -P }, { s, P }, { -P, s }, { P, s } } do
					local y = height(p[1], p[2])
					total += 1
					if y > height(p[1] * 0.7, p[2] * 0.7) + 40 then
						ramp += 1
					end
					lo, hi = math.min(lo, y), math.max(hi, y)
				end
			end
			return ramp / total, lo, hi
		end
		local ramp, lo, hi = rampFraction(h)
		truthy(ramp < 0.1, string.format("%.0f%% of the boundary rises like a wall", ramp * 100))
		truthy(hi - lo > 30, "boundary heights are uniform")
		truthy(rampFraction(Legacy.height) > 0.9, "control: the legacy ring rose all round")
	end)
end)

describe("Gameplay geometry", function()
	it("keeps creature spawn and patrol points walkable and under the raycast origin", function()
		-- NightDirector Watchers: bearing -35..35 at 55..100; Opening: home,
		-- patrols and retreat.
		for b = -35, 35, 5 do
			for d = 55, 100, 5 do
				local x, z = edge(b, d)
				truthy(
					h(x, z) > WATER + 0.3,
					string.format("watcher point %d deg %d studs is in the lake", b, d)
				)
			end
		end
		local opening = { { 0, 85 }, { 75, 240 } }
		for i = 1, 6 do
			table.insert(opening, { (i - 3) * 22, 70 + (i % 2) * 18 })
			table.insert(opening, { (i - 2.5) * 18, 22 + (i % 2) * 6 })
		end
		for _, p in opening do
			local x, z = edge(p[1], p[2])
			truthy(
				h(x, z) > WATER + 0.3,
				string.format("opening point %d deg %d studs is in the lake", p[1], p[2])
			)
		end
		-- Crawlers and patrols pick any bearing at 50..290 studs: never more of
		-- those points may fall in the lake than before the rebuild.
		local wetNew, wetOld = 0, 0
		for b = 0, 355, 5 do
			for d = 20, 290, 10 do
				local x, z = edge(b, d)
				truthy(h(x, z) < 160, "ground above the edgePoint raycast origin")
				if d >= 50 then
					wetNew += if h(x, z) < WATER - 0.5 then 1 else 0
					wetOld += if Legacy.height(x, z) < WATER - 0.5 then 1 else 0
				end
			end
		end
		truthy(wetNew <= wetOld, string.format("%d spawn samples in the lake, %d before", wetNew, wetOld))
	end)

	it("lets the cabin window see Maya's house across the lake", function()
		local m = W.LakeHouse
		truthy(
			clearLine(WINDOW.x, WINDOW.y, WINDOW.z, m.x - 5, m.height + 4.5, m.z + 8),
			"downstairs window hidden"
		)
		truthy(
			clearLine(WINDOW.x, WINDOW.y, WINDOW.z, m.x + 5, m.height + 13.5, m.z + 8),
			"upstairs window hidden"
		)
		local hill = W.Houses[1]
		eq(hill.id, "HillHouse")
		local pad = field.padHeight(hill.x, hill.z) :: number
		truthy(clearLine(12, WINDOW.y, -10, hill.x, pad + 14, hill.z), "hill house hidden")
	end)

	it("keeps the Old One's spots under the raycast origin and in view of the cabin", function()
		for _, s in W.OldOneSpots do
			local ground = h(s.x, s.z)
			truthy(ground < 380, "Old One spot above the raycast origin")
			truthy(
				clearLine(WINDOW.x, WINDOW.y, WINDOW.z, s.x, ground + 60, s.z),
				"Old One hidden at " .. s.x
			)
		end
	end)

	it("routes a dry, walkable path around the lake to Maya's porch", function()
		local route
		for _, trail in W.Trails do
			local last = trail[#trail]
			if math.abs(last.x - (W.LakeHouse.x + 15)) < 8 and math.abs(last.z - W.LakeHouse.z) < 8 then
				route = trail
			end
		end
		truthy(route ~= nil, "no trail ends at Maya's porch")
		local length = 0
		for i = 1, #route - 1 do
			local a, b = route[i], route[i + 1]
			local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
			length += len
			local prev = h(a.x, a.z)
			for s = 2, len, 2 do
				local y = h(a.x + (b.x - a.x) * s / len, a.z + (b.z - a.z) * s / len)
				truthy(y > WATER + 0.5, "the path to Maya crosses water")
				truthy(math.abs(y - prev) / 2 < 0.35, "the path to Maya is too steep")
				prev = y
			end
		end
		truthy(length > 250 and length < 450, string.format("path length %.0f", length))
	end)

	it("keeps every trail and road dry and walkable", function()
		local function check(points: { { x: number, z: number } })
			for i = 1, #points - 1 do
				local a, b = points[i], points[i + 1]
				local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
				local prev = h(a.x, a.z)
				for s = 4, len, 4 do
					local y = h(a.x + (b.x - a.x) * s / len, a.z + (b.z - a.z) * s / len)
					truthy(y > WATER + 0.5, string.format("path under water near %d,%d", a.x, a.z))
					truthy(math.abs(y - prev) / 4 < 0.5, string.format("path too steep near %d,%d", a.x, a.z))
					prev = y
				end
			end
		end
		for _, trail in W.Trails do
			check(trail)
		end
		for _, road in W.Roads do
			check(road.points)
		end
	end)
end)

if not t.report() then
	process.exit(1)
end

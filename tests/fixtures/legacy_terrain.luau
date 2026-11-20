--!strict
-- The height function the world used before the valley rebuild (commit
-- ba2d2a0, src/server/World/Terrain.luau rawHeight), kept only as a control:
-- the terrain specs show it fails the checks the new valley passes (an
-- enclosing ring of jagged walls, snow inside the playable square).

local Legacy = {}

Legacy.HalfSize = 1000
Legacy.PlayableRadius = 860
Legacy.MountainStart = 780

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

function Legacy.height(x: number, z: number): number
	local h = 4 + math.noise(x / 170, z / 170, 0.31) * 12 + math.noise(x / 52, z / 52, 1.73) * 3.5
	h += math.noise(x / 17, z / 17, 4.11) * 0.7
	local rd = math.sqrt((x + 215) ^ 2 + (z + 55) ^ 2)
	h += 18 * math.exp(-(rd * rd) / (2 * 55 * 55))
	local ridgeD = z + 345
	if ridgeD < 0 then
		h += math.min(-ridgeD * 0.45, 46)
	end
	local ld = math.sqrt(x * x + (z + 150) ^ 2)
	local basin = 1 - smoothstep(42, 82, ld)
	h += (-11 - h) * basin
	local edge = math.max(math.abs(x), math.abs(z))
	local foot = edge - (Legacy.MountainStart - 120)
	if foot > 0 then
		h += (foot / 120) ^ 2 * 18
	end
	if edge > Legacy.MountainStart then
		local k = (edge - Legacy.MountainStart) / 70
		local ridge = 1 - math.abs(math.noise(x / 90, z / 90, 2.6))
		h += k * k * 40 + ridge * ridge * 80 * math.min(k, 1.6)
		h += math.noise(x / 30, z / 30, 9.2) * 8 * math.min(k, 1)
	end
	return h
end

return Legacy

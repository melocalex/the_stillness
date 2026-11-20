--!strict
-- Renders the terrain height function to images, from the same code the
-- server runs:
--   docs/world-heightmap.png  grayscale height (black = lake bottom,
--                             white = highest summit)
--   docs/world-map.svg        shaded relief with water, snow, roads,
--                             regions, landmarks and labels
-- Usage (from the repository root):
--   lune run tools/terrain/render_map [out-dir] [pixels]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local WorldConfig = require("../../src/shared/Config/WorldConfig")
local Heightfield = require("../../src/shared/Logic/Heightfield")

local outDir = process.args[1] or "docs"
local PX = tonumber(process.args[2]) or 400
local W = WorldConfig
local field = Heightfield.new(W :: any)
local half = tonumber(process.args[3]) or W.HalfSize -- window half size, centred on the cabin
local step = 2 * half / PX

-- PNG ------------------------------------------------------------------------

local crcTable: { number } = {}
for i = 0, 255 do
	local c = i
	for _ = 1, 8 do
		c = if bit32.band(c, 1) == 1 then bit32.bxor(0xEDB88320, bit32.rshift(c, 1)) else bit32.rshift(c, 1)
	end
	crcTable[i + 1] = c
end
local function crc32(s: string): number
	local c = 0xFFFFFFFF
	for i = 1, #s do
		c = bit32.bxor(crcTable[bit32.band(bit32.bxor(c, string.byte(s, i)), 0xFF) + 1], bit32.rshift(c, 8))
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end
local function chunk(kind: string, data: string): string
	return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
end
local function png(w: number, h: number, channels: number, pixels: buffer): string
	local raw = buffer.create((w * channels + 1) * h)
	for y = 0, h - 1 do
		local row = y * (w * channels + 1)
		buffer.writeu8(raw, row, 0)
		buffer.copy(raw, row + 1, pixels, y * w * channels, w * channels)
	end
	local colorType = if channels == 1 then 0 else 2
	return "\137PNG\r\n\26\n"
		.. chunk("IHDR", string.pack(">I4I4BBBBB", w, h, 8, colorType, 0, 0, 0))
		.. chunk("IDAT", serde.compress("zlib", buffer.tostring(raw)))
		.. chunk("IEND", "")
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(s: string): string
	local out = table.create(math.ceil(#s / 3))
	for i = 1, #s, 3 do
		local a, b, c = string.byte(s, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local q = {}
		for k = 3, 0, -1 do
			local idx = bit32.band(bit32.rshift(n, k * 6), 63) + 1
			table.insert(q, string.sub(B64, idx, idx))
		end
		if not b then
			q[3], q[4] = "=", "="
		elseif not c then
			q[4] = "="
		end
		table.insert(out, table.concat(q))
	end
	return table.concat(out)
end

-- Sample ---------------------------------------------------------------------

local started = os.clock()
local heights = table.create(PX * PX)
local lo, hi = math.huge, -math.huge
for py = 0, PX - 1 do
	local z = -half + (py + 0.5) * step
	for px = 0, PX - 1 do
		local x = -half + (px + 0.5) * step
		local h = field.heightAt(x, z)
		heights[py * PX + px + 1] = h
		lo, hi = math.min(lo, h), math.max(hi, h)
	end
end
print(string.format("sampled %dx%d in %.2fs, height %.1f..%.1f", PX, PX, os.clock() - started, lo, hi))

local function hAt(px: number, py: number): number
	px = math.clamp(px, 0, PX - 1)
	py = math.clamp(py, 0, PX - 1)
	return heights[py * PX + px + 1]
end

local gray = buffer.create(PX * PX)
for i = 1, PX * PX do
	buffer.writeu8(gray, i - 1, math.floor((heights[i] - lo) / (hi - lo) * 255 + 0.5))
end
fs.writeFile(outDir .. "/world-heightmap.png", png(PX, PX, 1, gray))

-- Shaded relief: elevation tint times a north-west light, water and snow.
local function tint(h: number, x: number, z: number): (number, number, number)
	if h > field.snowLine(x, z) then
		return 236, 240, 244
	elseif h > 170 then
		return 128, 124, 116
	elseif h > 90 then
		return 78, 96, 66
	elseif h > 30 then
		return 64, 92, 56
	end
	return 82, 112, 64
end
local rgb = buffer.create(PX * PX * 3)
for py = 0, PX - 1 do
	local z = -half + (py + 0.5) * step
	for px = 0, PX - 1 do
		local x = -half + (px + 0.5) * step
		local h = hAt(px, py)
		local r, g, b
		if h < W.WaterLevel - 0.5 then
			local depth = math.clamp((W.WaterLevel - h) / 12, 0, 1)
			r, g, b = 70 - depth * 30, 92 - depth * 30, 96 - depth * 26
		else
			r, g, b = tint(h, x, z)
			local dx = (hAt(px + 1, py) - hAt(px - 1, py)) / (2 * step)
			local dz = (hAt(px, py + 1) - hAt(px, py - 1)) / (2 * step)
			local shade = math.clamp(1 + (dx + dz) * -0.9 * 0.7, 0.45, 1.35)
			r, g, b = r * shade, g * shade, b * shade
			local pd, width = field.pathDistance(x, z)
			if pd < math.max(width, step * 0.6) then
				r, g, b = 168, 140, 100
			end
		end
		local o = (py * PX + px) * 3
		buffer.writeu8(rgb, o, math.clamp(math.floor(r), 0, 255))
		buffer.writeu8(rgb, o + 1, math.clamp(math.floor(g), 0, 255))
		buffer.writeu8(rgb, o + 2, math.clamp(math.floor(b), 0, 255))
	end
end
local relief = png(PX, PX, 3, rgb)
fs.writeFile(outDir .. "/world-relief.png", relief)

-- SVG overlay ----------------------------------------------------------------

local S = 1000 / (2 * half) -- svg units per stud (the svg is 1000 wide)
local function sx(x: number): string
	return string.format("%.1f", (x + half) * S)
end
local function sz(z: number): string
	return string.format("%.1f", (z + half) * S)
end
local parts: { string } = {
	'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000"'
		.. ' font-family="Helvetica, Arial, sans-serif">',
	'<image href="data:image/png;base64,' .. base64(relief) .. '" width="1000" height="1000"/>',
}
local function add(s: string)
	table.insert(parts, s)
end
local function label(x: number, z: number, text: string, size: number, color: string?)
	add(
		string.format(
			'<text x="%s" y="%s" font-size="%d" fill="%s" stroke="#000" stroke-width="0.6"'
				.. ' paint-order="stroke" text-anchor="middle">%s</text>',
			sx(x),
			sz(z),
			size,
			color or "#fff",
			text
		)
	)
end
local function dot(x: number, z: number, color: string, r: number?)
	add(
		string.format(
			'<circle cx="%s" cy="%s" r="%.1f" fill="%s" stroke="#000" stroke-width="0.8"/>',
			sx(x),
			sz(z),
			r or 4,
			color
		)
	)
end

local P = W.PlayableRadius
add(
	string.format(
		'<rect x="%s" y="%s" width="%.1f" height="%.1f" fill="none" stroke="#ffd34d"'
			.. ' stroke-width="1.5" stroke-dasharray="6 4"/>',
		sx(-P),
		sz(-P),
		2 * P * S,
		2 * P * S
	)
)
label(0, -P - 14, "playable boundary", 11, "#ffd34d")
for _, region in W.Regions do
	add(
		string.format(
			'<circle cx="%s" cy="%s" r="%.1f" fill="none" stroke="#9fd3ff" stroke-width="1.2"'
				.. ' stroke-dasharray="3 3"/>',
			sx(region.x),
			sz(region.z),
			region.r * S
		)
	)
	label(
		region.x,
		region.z + region.r + 22,
		region.id .. (if region.reserved then " (later)" else ""),
		10,
		"#9fd3ff"
	)
end
for _, s in W.Sightlines do
	add(
		string.format(
			'<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="#ff8cf0" stroke-width="1" stroke-dasharray="2 2"/>',
			sx(s.a.x),
			sz(s.a.z),
			sx(s.b.x),
			sz(s.b.z)
		)
	)
end
for _, r in W.Terrain.Ridges do
	local mid = r.points[math.ceil(#r.points / 2)]
	label(mid.x, mid.z - 30, r.name, 11, "#e8f0d8")
end
for _, p in W.Terrain.Peaks do
	add(
		string.format(
			'<path d="M%s %s l-5 8 h10 z" fill="#fff" stroke="#000" stroke-width="0.6"/>',
			sx(p.x),
			sz(p.z - 25)
		)
	)
	label(p.x, p.z + 30, p.name, 11)
end
dot(W.Cabin.x, W.Cabin.z, "#ff7a3d", 5)
label(W.Cabin.x + 70, W.Cabin.z + 10, "Cabin", 12, "#ffb38a")
dot(W.LakeHouse.x, W.LakeHouse.z, "#ff5ad1", 5)
label(W.LakeHouse.x, W.LakeHouse.z - 22, "Maya", 12, "#ffb3ec")
dot(W.AbandonedHouse.x, W.AbandonedHouse.z, "#b0b0b0")
label(W.AbandonedHouse.x + 30, W.AbandonedHouse.z + 50, "Abandoned house", 9)
dot(W.RadioTower.x, W.RadioTower.z, "#ff4040")
label(W.RadioTower.x, W.RadioTower.z - 30, "Radio tower", 9)
for _, house in W.Houses do
	dot(house.x, house.z, "#e6d7b0", 3)
	label(house.x, house.z + 34, house.id, 8, "#f2ead6")
end
for _, s in W.OldOneSpots do
	dot(s.x, s.z, "#202020", 3)
end
label(W.OldOneSpots[1].x, W.OldOneSpots[1].z - 26, "Old One spots", 9, "#ddd")
label(-half + 60, half - 20, "N up. 1 px = " .. string.format("%.0f", step) .. " studs", 11)
add("</svg>")
fs.writeFile(outDir .. "/world-map.svg", table.concat(parts, "\n"))
print("wrote " .. outDir .. "/world-heightmap.png, world-relief.png, world-map.svg")

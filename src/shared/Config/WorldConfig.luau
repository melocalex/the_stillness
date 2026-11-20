--!strict
-- World layout. Positions are {x, z} in studs (north is -z); heights come from
-- the terrain height function (src/shared/Logic/Heightfield.luau). The cabin's
-- north window looks across the lake to Maya's house, with the forested
-- Hemlock Ridge and the far Northern Range behind it. A sparse settlement of
-- neighbors sits along dirt roads; Pinehaven lies down the valley to the
-- south-east. Region map: docs/WORLD.md. Pure data.

local WorldConfig = {}

-- Shapes of the terrain data (read by Logic/Heightfield and World/*).
type Point = { x: number, z: number }
type Lobe = { x: number, z: number, rx: number, rz: number, yaw: number? }
type Hill = { x: number, z: number, height: number, rx: number, rz: number, yaw: number? }
type Ridge = {
	name: string,
	points: { Point },
	crest: number,
	width: number,
	asym: number?,
	saddles: { { x: number, z: number, depth: number, radius: number } }?,
	rough: number?,
}
type Peak = {
	name: string,
	x: number,
	z: number,
	height: number,
	radius: number,
	sharp: number?,
	rough: number?,
}
type TerrainSpec = {
	Tilt: Point,
	Spine: { Point },
	SpineInner: number,
	SpineOuter: number,
	HillsNear: number,
	HillsFar: number,
	SnowLine: number,
	CragStart: number,
	Hills: { Hill },
	Ridges: { Ridge },
	Peaks: { Peak },
}
type Region = { id: string, kind: string, x: number, z: number, r: number, reserved: boolean? }
type Sightline = { id: string, a: Point, b: Point, near: number, far: number }

WorldConfig.Seed = 1907
WorldConfig.HalfSize = 1600 -- terrain extends from -HalfSize to +HalfSize
WorldConfig.PlayableRadius = 860 -- invisible boundary walls (square)
WorldConfig.WaterLevel = 1
WorldConfig.BaseHeight = 5

-- Gameplay code hard-codes these positions and pad heights (creature bearings
-- around the cabin, the Dweller's house, Maya's spots). Move them only together
-- with every consumer.
WorldConfig.Cabin = { x = 0, z = 0, floorY = 7, clearing = 40 }
WorldConfig.Spawn = { x = 14, z = 78 }
WorldConfig.LakeHouse = { x = 0, z = -248, clearing = 26, height = 8 }
WorldConfig.AbandonedHouse = { x = 178, z = 42, clearing = 26, height = 6 }
WorldConfig.RadioTower = { x = -215, z = -55, clearing = 20 }
WorldConfig.NorthRidge = { x = 0, z = -345 }
WorldConfig.ThreatArea = { x = -150, z = -300, radius = 70 }
WorldConfig.OldOneSpots = {
	{ x = -160, z = -620 },
	{ x = 140, z = -600 },
	{ x = 0, z = -680 },
	{ x = 520, z = -300 },
}

-- The lake: elliptical lobes (main basin, west cove, a bay below the cabin)
-- plus shoreline noise; islands are land lobes. x, z is the nominal centre.
local lake: { x: number, z: number, depth: number, shoreNoise: number, lobes: { Lobe }, islands: { Lobe } } =
	{
		x = 0,
		z = -158,
		depth = 12,
		shoreNoise = 11,
		lobes = {
			{ x = 0, z = -158, rx = 74, rz = 50, yaw = 8 },
			{ x = -80, z = -192, rx = 36, rz = 24, yaw = -32 },
			{ x = 44, z = -122, rx = 22, rz = 13, yaw = 20 },
		},
		islands = {
			{ x = 40, z = -170, rx = 9, rz = 6, yaw = 30 },
		},
	}

-- Terrain forms. Ridges are polylines (crest height, half width, flank
-- asymmetry, saddles anchored at world points); peaks are far snowy
-- summits. The valley spine is the lowland axis where hills stay gentle.
local terrain: TerrainSpec = {
	Tilt = { x = -0.0018, z = -0.0018 }, -- the valley floor drains to the south-east
	Spine = {
		{ x = -130, z = -340 },
		{ x = -20, z = -170 },
		{ x = 0, z = 0 },
		{ x = 110, z = 190 },
		{ x = 340, z = 410 },
		{ x = 700, z = 700 },
		{ x = 1100, z = 1060 },
	},
	SpineInner = 170,
	SpineOuter = 560,
	HillsNear = 5,
	HillsFar = 34,
	SnowLine = 240,
	CragStart = 190,
	Hills = {
		{ x = -215, z = -55, height = 38, rx = 92, rz = 82, yaw = 20 }, -- Radio Hill
		{ x = 240, z = -176, height = 30, rx = 100, rz = 76, yaw = -25 }, -- the hill house's hill
		{ x = -150, z = -300, height = -3, rx = 70, rz = 60 }, -- the bog hollow
		{ x = -470, z = -560, height = 50, rx = 105, rz = 95 }, -- Lookout knoll (later phase)
		{ x = 470, z = 160, height = 18, rx = 120, rz = 80, yaw = 40 },
		{ x = -330, z = 230, height = 16, rx = 110, rz = 90 },
	},
	Ridges = {
		{
			name = "Hemlock Ridge",
			points = {
				{ x = -540, z = -420 },
				{ x = -270, z = -470 },
				{ x = -80, z = -445 },
				{ x = 120, z = -500 },
				{ x = 380, z = -470 },
				{ x = 560, z = -400 },
			},
			crest = 82,
			width = 190,
			asym = 0.8,
			saddles = { { x = -84, z = -450, depth = 0.75, radius = 140 } }, -- Hemlock Pass
			rough = 0.3,
		},
		{
			name = "Old One's Crest",
			points = {
				{ x = -430, z = -650 },
				{ x = -160, z = -660 },
				{ x = 60, z = -710 },
				{ x = 300, z = -650 },
				{ x = 480, z = -570 },
			},
			crest = 120,
			width = 300, -- long gentle south flank, the north side drops faster
			asym = 0.7,
			rough = 0.3,
		},
		{
			name = "Cedar Ridge",
			points = {
				{ x = 470, z = -440 },
				{ x = 590, z = -260 },
				{ x = 640, z = -40 },
				{ x = 690, z = 150 },
			},
			crest = 92,
			width = 170,
			asym = 1.5,
			rough = 0.35,
		},
		{
			name = "Wolf Ridge",
			points = {
				{ x = -500, z = -390 },
				{ x = -640, z = -150 },
				{ x = -690, z = 80 },
				{ x = -640, z = 320 },
				{ x = -560, z = 520 },
			},
			crest = 108,
			width = 190,
			asym = 0.7,
			saddles = { { x = -690, z = 82, depth = 0.75, radius = 130 } }, -- the west pass
			rough = 0.35,
		},
		-- Far ranges, beyond the playable square: high and snowy in the north,
		-- broken massifs east and west, low hazy hills to the south where the
		-- valley opens. Spurs run toward the valley so the ranges never read
		-- as one ring.
		{
			name = "Northern Range",
			points = {
				{ x = -1050, z = -1180 },
				{ x = -460, z = -1360 },
				{ x = 100, z = -1470 },
				{ x = 660, z = -1350 },
				{ x = 1080, z = -1240 },
			},
			crest = 130,
			width = 380,
			saddles = { { x = 380, z = -1410, depth = 0.35, radius = 130 } },
			rough = 1,
		},
		{
			name = "Halden Spur",
			points = { { x = 160, z = -1290 }, { x = 200, z = -1180 }, { x = 240, z = -1060 } },
			crest = 110,
			width = 200,
			rough = 1,
		},
		{
			name = "Sister Spur",
			points = { { x = 660, z = -1350 }, { x = 820, z = -1150 }, { x = 950, z = -1000 } },
			crest = 95,
			width = 190,
			rough = 1,
		},
		{
			name = "Western Range",
			points = {
				{ x = -1300, z = -950 },
				{ x = -1430, z = -380 },
				{ x = -1470, z = 180 },
				{ x = -1390, z = 640 },
			},
			crest = 115,
			width = 330,
			saddles = { { x = -1455, z = -180, depth = 0.4, radius = 130 } },
			rough = 1,
		},
		{
			name = "Kettle Spur",
			points = { { x = -1430, z = -520 }, { x = -1230, z = -420 }, { x = -1060, z = -360 } },
			crest = 90,
			width = 200,
			rough = 0.8,
		},
		{
			name = "Eastwatch Massif",
			points = { { x = 1150, z = -1030 }, { x = 1380, z = -600 }, { x = 1430, z = -180 } },
			crest = 130,
			width = 300,
			rough = 1,
		},
		{
			name = "East Hills",
			points = {
				{ x = 1290, z = 60 },
				{ x = 1470, z = 420 },
				{ x = 1500, z = 860 },
				{ x = 1430, z = 1180 },
			},
			crest = 105,
			width = 300,
			rough = 0.6,
		},
		{
			name = "Southern Hills",
			points = {
				{ x = -1450, z = 980 },
				{ x = -940, z = 1400 },
				{ x = -260, z = 1550 },
				{ x = 380, z = 1560 },
				{ x = 820, z = 1620 },
			},
			crest = 90,
			width = 300,
			rough = 0.6,
		},
	},
	Peaks = {
		{ name = "Grey Tooth", x = -520, z = -1380, height = 200, radius = 330, rough = 1 },
		{ name = "Mount Halden", x = 90, z = -1480, height = 230, radius = 400, rough = 1 }, -- behind Maya's house
		{ name = "Sister Peak", x = 660, z = -1360, height = 180, radius = 300, rough = 1 },
		{ name = "Kettle Peak", x = -1430, z = -520, height = 180, radius = 300, rough = 1 },
		{ name = "Lone Pine Peak", x = -1470, z = 160, height = 150, radius = 280, rough = 1 },
		{ name = "Eastwatch", x = 1380, z = -620, height = 200, radius = 290, rough = 1 },
		{ name = "Widow's Knob", x = -1260, z = 1260, height = 110, radius = 330, rough = 0.8 },
		{ name = "Mount Ashby", x = 1000, z = 1340, height = 500, radius = 620, sharp = 1.7, rough = 0.3 }, -- the volcano
	},
}

-- Neighbors. style picks the generator preset in World/Houses.luau.
-- watched = visible activity at night (lights, silhouettes) for the
-- observation and neighborhood-mystery systems.
WorldConfig.Houses = {
	{ id = "HillHouse", style = "TwoStorey", x = 235, z = -170, yaw = 200, watched = true },
	{ id = "ForestCottage", style = "Cottage", x = -170, z = 140, yaw = 30, watched = true },
	{ id = "RangerStation", style = "Ranger", x = 40, z = 330, yaw = 180, watched = false },
	{ id = "OldBarn", style = "Barn", x = 330, z = 120, yaw = 80, watched = false },
	{ id = "MaintenanceShed", style = "Shed", x = 95, z = 175, yaw = 10, watched = false, emergency = true },
	{ id = "ChapelRuin", style = "Chapel", x = -330, z = -260, yaw = 120, watched = true },
	{ id = "WestCabin", style = "Cottage", x = -420, z = 40, yaw = 95, watched = true },
	{ id = "SouthFarm", style = "TwoStorey", x = -260, z = 420, yaw = 160, watched = false },
	{ id = "LakeshoreHut", style = "Shed", x = 110, z = -175, yaw = 250, watched = false, emergency = true },
}

-- Open meadows: grass, flowers, few trees, where deer graze.
WorldConfig.Meadows = {
	{ x = 95, z = 75, r = 55 },
	{ x = -140, z = -130, r = 46 },
	{ x = 300, z = 140, r = 80 },
	{ x = -240, z = 380, r = 70 },
	{ x = 60, z = 280, r = 45 },
	{ x = -380, z = -60, r = 60 },
}

-- Footpaths (half width 3.5) as polylines.
WorldConfig.Trails = {
	{ { x = 14, z = 78 }, { x = 8, z = 30 }, { x = 4, z = 20 } },
	{ { x = 14, z = 22 }, { x = 70, z = 30 }, { x = 130, z = 40 }, { x = 160, z = 42 } },
	{ { x = -14, z = -6 }, { x = -80, z = -20 }, { x = -150, z = -45 }, { x = -200, z = -55 } },
	-- Down to the beach below the cabin.
	{ { x = 0, z = -16 }, { x = -6, z = -50 }, { x = 2, z = -92 } },
	-- Settlement road: a long loop linking the neighbors.
	{
		{ x = 14, z = 78 },
		{ x = 30, z = 170 },
		{ x = 85, z = 175 },
		{ x = 40, z = 310 },
		{ x = -120, z = 360 },
		{ x = -250, z = 400 },
	},
	{ { x = 160, z = 42 }, { x = 250, z = 90 }, { x = 320, z = 115 } },
	{ { x = 160, z = 42 }, { x = 200, z = -60 }, { x = 230, z = -150 } },
	{
		{ x = -14, z = 40 },
		{ x = -90, z = 100 },
		{ x = -165, z = 135 },
		{ x = -300, z = 80 },
		{ x = -410, z = 45 },
	},
	{ { x = -200, z = -55 }, { x = -280, z = -170 }, { x = -320, z = -250 } },
	-- Around the lake to Maya's porch, past the lakeshore hut.
	{
		{ x = 14, z = -16 },
		{ x = 52, z = -62 },
		{ x = 94, z = -98 },
		{ x = 122, z = -140 },
		{ x = 126, z = -196 },
		{ x = 96, z = -232 },
		{ x = 52, z = -254 },
		{ x = 18, z = -250 },
	},
	-- Up from Maya's house, past the bog, with switchbacks over Hemlock Pass
	-- to the foot of the Old One's Crest. The crest and lookout trails belong
	-- to the highland phase (docs/WORLD.md).
	{
		{ x = -12, z = -262 },
		{ x = -60, z = -300 },
		{ x = -72, z = -350 },
		{ x = -130, z = -385 },
		{ x = -60, z = -408 },
		{ x = -118, z = -432 },
		{ x = -84, z = -452 },
		{ x = -66, z = -530 },
	},
	-- West pass, out of the valley over Wolf Ridge's saddle.
	{ { x = -410, z = 45 }, { x = -560, z = 70 }, { x = -700, z = 85 }, { x = -880, z = 95 } },
}

-- Gravel roads (half width in studs).
WorldConfig.Roads = {
	-- Valley Road: from the settlement down to Pinehaven and out of the
	-- valley to the south-east.
	{
		width = 6,
		points = {
			{ x = 30, z = 170 },
			{ x = 120, z = 255 },
			{ x = 230, z = 330 },
			{ x = 340, z = 410 },
			{ x = 480, z = 505 },
			{ x = 650, z = 615 },
			{ x = 920, z = 790 },
		},
	},
}

-- Named areas for the region map and the forest. Later phases build in the
-- reserved ones; the forest keeps them clear now.
local regions: { Region } = {
	{ id = "Pinehaven", kind = "Town", x = 360, z = 440, r = 150, reserved = true },
	{ id = "DeepForest", kind = "DeepForest", x = -470, z = 260, r = 240 },
	{ id = "Lookout", kind = "Lookout", x = -470, z = -560, r = 30, reserved = true },
	{ id = "Bog", kind = "Bog", x = -150, z = -300, r = 70 },
}

-- Views that must stay open: no trees within a corridor that widens from
-- `near` to `far` half width along a -> b.
local sightlines: { Sightline } = {
	{ id = "CabinToMaya", a = { x = 0, z = -14 }, b = { x = 0, z = -236 }, near = 12, far = 34 },
	{ id = "CabinToHillHouse", a = { x = 12, z = -10 }, b = { x = 226, z = -164 }, near = 6, far = 18 },
}

WorldConfig.Lake = lake
WorldConfig.Terrain = terrain
WorldConfig.Regions = regions
WorldConfig.Sightlines = sightlines

WorldConfig.Forest = {
	CellSize = 34, -- grove grid (studs)
	MaxPerCell = 1.6, -- trees in a fully dense cell
	MinSpacing = 6, -- between trunks
	Treeline = 150, -- no trees above this height
	FrostLine = 135, -- frosted pines above this height
	FarTrees = 420, -- shadowless scenery trees outside the play area
	Rocks = 220,
	Bushes = 380,
	Ferns = 650,
	Mushrooms = 120,
	Logs = 80,
	Stumps = 60,
	ResourceTreeFraction = 0.35,
	ResourceRockFraction = 0.6,
}

return WorldConfig

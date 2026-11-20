--!strict
-- World layout. Positions are {x, z} in studs; heights come from the terrain
-- generator. The cabin's north window looks across the lake to the lake
-- house, with the north ridge behind it. Pure data.

local WorldConfig = {}

WorldConfig.Seed = 1907
WorldConfig.HalfSize = 448 -- terrain extends from -HalfSize to +HalfSize
WorldConfig.PlayableRadius = 395 -- invisible boundary walls
WorldConfig.MountainStart = 320
WorldConfig.WaterLevel = 1
WorldConfig.BaseHeight = 4

WorldConfig.Cabin = { x = 0, z = 0, floorY = 7, clearing = 34 }
WorldConfig.Spawn = { x = 14, z = 78 }
WorldConfig.Lake = { x = 0, z = -150, radius = 60, depth = 12 }
WorldConfig.LakeHouse = { x = 0, z = -248, clearing = 26, height = 8 }
WorldConfig.AbandonedHouse = { x = 178, z = 42, clearing = 26, height = 6 }
WorldConfig.RadioTower = { x = -215, z = -55, clearing = 20, hill = 18 }
WorldConfig.NorthRidge = { x = 0, z = -345, radius = 60 }
WorldConfig.ThreatArea = { x = -150, z = -300, radius = 70 }
WorldConfig.OldOneSpots = {
	{ x = -140, z = -420 },
	{ x = 120, z = -415 },
	{ x = 0, z = -430 },
}

-- Dirt trails as polylines.
WorldConfig.Trails = {
	{ { x = 14, z = 78 }, { x = 8, z = 30 }, { x = 4, z = 14 } },
	{ { x = 14, z = 12 }, { x = 70, z = 24 }, { x = 130, z = 40 }, { x = 160, z = 42 } },
	{ { x = -14, z = -6 }, { x = -80, z = -20 }, { x = -150, z = -45 }, { x = -200, z = -55 } },
	{ { x = 0, z = -12 }, { x = -6, z = -50 }, { x = 4, z = -82 } },
}

WorldConfig.Forest = {
	Trees = 520,
	Rocks = 70,
	Bushes = 110,
	Mushrooms = 40,
	Logs = 24,
	ResourceTreeFraction = 0.35,
	ResourceRockFraction = 0.6,
	-- No trees in these circles.
	KeepClear = {
		{ x = 0, z = 0, r = 30 },
		{ x = 14, z = 78, r = 8 },
		{ x = 0, z = -150, r = 66 },
		{ x = 0, z = -248, r = 22 },
		{ x = 178, z = 42, r = 22 },
		{ x = -215, z = -55, r = 16 },
	},
}

return WorldConfig

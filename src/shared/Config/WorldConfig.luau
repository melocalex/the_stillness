--!strict
-- World layout. Positions are {x, z} in studs; heights come from the terrain
-- generator. The cabin's north window looks across the lake to the lake
-- house, with the north ridge behind it. A sparse settlement of neighbors
-- sits along dirt roads, close enough to watch at night, far enough to feel
-- alone. Pure data.

local WorldConfig = {}

WorldConfig.Seed = 1907
WorldConfig.HalfSize = 1000 -- terrain extends from -HalfSize to +HalfSize
WorldConfig.PlayableRadius = 860 -- invisible boundary walls
WorldConfig.MountainStart = 780
WorldConfig.WaterLevel = 1
WorldConfig.BaseHeight = 4

WorldConfig.Cabin = { x = 0, z = 0, floorY = 7, clearing = 40 }
WorldConfig.Spawn = { x = 14, z = 78 }
WorldConfig.Lake = { x = 0, z = -150, radius = 60, depth = 12 }
WorldConfig.LakeHouse = { x = 0, z = -248, clearing = 26, height = 8 }
WorldConfig.AbandonedHouse = { x = 178, z = 42, clearing = 26, height = 6 }
WorldConfig.RadioTower = { x = -215, z = -55, clearing = 20, hill = 18 }
WorldConfig.NorthRidge = { x = 0, z = -345, radius = 60, plateau = 46 }
WorldConfig.ThreatArea = { x = -150, z = -300, radius = 70 }
WorldConfig.OldOneSpots = {
	{ x = -160, z = -620 },
	{ x = 140, z = -600 },
	{ x = 0, z = -680 },
	{ x = 520, z = -300 },
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
	{ x = -110, z = -150, r = 50 },
	{ x = 300, z = 140, r = 80 },
	{ x = -240, z = 380, r = 70 },
	{ x = 60, z = 280, r = 45 },
	{ x = -380, z = -60, r = 60 },
}

-- Dirt roads and trails as polylines.
WorldConfig.Trails = {
	{ { x = 14, z = 78 }, { x = 8, z = 30 }, { x = 4, z = 20 } },
	{ { x = 14, z = 22 }, { x = 70, z = 30 }, { x = 130, z = 40 }, { x = 160, z = 42 } },
	{ { x = -14, z = -6 }, { x = -80, z = -20 }, { x = -150, z = -45 }, { x = -200, z = -55 } },
	{ { x = 0, z = -16 }, { x = -6, z = -50 }, { x = 4, z = -82 } },
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
	{ { x = 40, z = -110 }, { x = 105, z = -165 } },
}

WorldConfig.Forest = {
	Trees = 2600, -- attempts; local forest density decides how many stand
	Rocks = 220,
	Bushes = 380,
	Mushrooms = 120,
	Logs = 80,
	ResourceTreeFraction = 0.35,
	ResourceRockFraction = 0.6,
	-- No trees in these circles (buildings and the lake).
	KeepClear = {
		{ x = 0, z = 0, r = 34 },
		{ x = 14, z = 78, r = 8 },
		{ x = 0, z = -150, r = 66 },
		{ x = 0, z = -248, r = 22 },
		{ x = 178, z = 42, r = 22 },
		{ x = -215, z = -55, r = 16 },
	},
}

return WorldConfig

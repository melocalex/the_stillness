--!strict
-- Tunable gameplay values. Pure data: no requires, no Roblox types, so tests
-- can load it. Colors are {r, g, b} 0-255; positions are {x, z} studs.

local GameConfig = {}

GameConfig.Time = {
	Durations = { Day = 720, Dusk = 180, Night = 480, Dawn = 120 },
	-- Seconds into Day 1 at server start (morning light, not dawn).
	StartOffset = 40,
	-- Debug multiplier on the clock. Set the "TimeScale" attribute on
	-- ReplicatedStorage at runtime to speed up testing.
	DefaultScale = 1,
	PublishInterval = 0.5,
	-- Lighting keyframes by clock hour. values = {
	--   brightness, ambientR, ambientG, ambientB, outdoorR, outdoorG, outdoorB,
	--   atmosphereDensity, atmosphereHaze, colorShiftR, colorShiftG, colorShiftB, exposure }
	Lighting = {
		{ at = 0, values = { 0.05, 14, 16, 26, 24, 28, 44, 0.42, 0.6, 20, 24, 40, -0.2 } },
		{ at = 4.8, values = { 0.05, 14, 16, 26, 24, 28, 44, 0.42, 0.6, 20, 24, 40, -0.2 } },
		{ at = 6, values = { 1.2, 70, 56, 50, 120, 96, 90, 0.38, 1.6, 255, 160, 110, 0.0 } },
		{ at = 8, values = { 2.4, 96, 92, 88, 128, 128, 120, 0.3, 0.6, 255, 230, 200, 0.1 } },
		{ at = 15, values = { 2.6, 100, 98, 94, 132, 132, 126, 0.28, 0.4, 255, 240, 220, 0.1 } },
		{ at = 18, values = { 1.6, 92, 70, 56, 130, 98, 82, 0.34, 1.4, 255, 150, 90, 0.0 } },
		{ at = 19.3, values = { 0.5, 40, 34, 42, 62, 50, 60, 0.4, 1.8, 180, 90, 90, -0.1 } },
		{ at = 20.5, values = { 0.08, 16, 18, 28, 26, 30, 46, 0.42, 0.8, 20, 24, 40, -0.2 } },
	},
}

GameConfig.Player = {
	WalkSpeed = 14,
	SneakSpeed = 7,
	RunSpeed = 23,
	StaminaMax = 100,
	StaminaDrainPerSecond = 16,
	StaminaRegenPerSecond = 9,
	CaptureRespawnDelay = 4,
	CaptureLossFraction = 0.5,
	CaptureLostItems = { "Wood", "Stone", "Fiber", "Scrap", "Berries", "Mushroom" },
	-- Starlight and moon on a player outdoors at night, before lamps.
	NightSkyLight = 0.18,
}

GameConfig.Weather = {
	-- Scripted weather per day for the story; later days roll from Weights.
	-- Each entry is { phase, weather }.
	Scripted = {
		-- Night 1 starts clear so the Watcher can be seen; the opening forces
		-- calm rain once it leaves.
		[1] = { Day = "Clear", Dusk = "Clear", Night = "Clear", Dawn = "Fog" },
		[2] = { Day = "Clear", Dusk = "Clear", Night = "Fog", Dawn = "Fog" },
		[3] = { Day = "Fog", Dusk = "Rain", Night = "Rain", Dawn = "Rain" },
	} :: { [number]: { [string]: string } },
	Weights = { Clear = 50, Fog = 25, Rain = 18, Storm = 7 },
	-- How far creatures and players can see, as a fraction of clear weather.
	Visibility = { Clear = 1, Fog = 0.55, Rain = 0.75, Storm = 0.6 } :: { [string]: number },
	ThunderMinGap = 25,
}

-- Design rule (Revision 2.0): most nights are safe and cozy. Night 1 is the
-- guided first-Watcher lesson; nights 2-3 stay gentle; Black Nights are
-- story-level and never early.
GameConfig.Nights = {
	scripted = { [1] = "Peaceful", [2] = "Peaceful", [3] = "Uneasy" },
	weights = { Peaceful = 65, Uneasy = 25, Bad = 9, Black = 1 },
	blackMinDay = 14,
}

-- How many creatures each night type allows, and when warnings start.
GameConfig.NightProfiles =
	{
		Peaceful = { watchers = 1, crawlers = 0, watcherChance = 0.6, warningLead = 0 },
		Uneasy = { watchers = 1, crawlers = 1, watcherChance = 1, warningLead = 0 },
		Bad = { watchers = 2, crawlers = 4, watcherChance = 1, warningLead = 240 },
		Black = { watchers = 3, crawlers = 6, watcherChance = 1, warningLead = 300 },
	} :: { [string]: { watchers: number, crawlers: number, watcherChance: number, warningLead: number } }

GameConfig.Collective = {
	halfLife = 20,
	reporterWindow = 45,
	investigateStrength = 0.4,
	convergeStrength = 1.0,
	convergeReporters = 2,
	breachStrength = 1.6,
	breachReporters = 3,
	disperseStrength = 0.3,
	forgetStrength = 0.05,
	baseError = 6,
	errorPerSecond = 0.8,
}

GameConfig.Breach = {
	groupThreshold = 3,
	soloDamageFloor = 0.85,
	damagePerAttacker = 2.2,
	-- Resistance divides damage. Higher lasts longer.
	Resistance = { weak = 0.7, standard = 1, reinforced = 2.6, shutter = 3.2 } :: { [string]: number },
}

GameConfig.Comfort = {
	RatePerSecond = 4,
	HomeComingSeconds = 90,
	PetDogSeconds = 120,
	ChasedSeconds = 45,
}

GameConfig.Gather = {
	TreeWood = 2,
	TreeHits = 3,
	TreeRespawn = 240,
	RockStone = 2,
	RockHits = 3,
	RockRespawn = 300,
	BushFiber = 2,
	BushBerries = 1,
	BushRespawn = 180,
	MushroomRespawn = 200,
	ScrapRespawn = 900,
	MaxDistance = 14,
	Cooldown = 0.6,
}

GameConfig.Build = {
	Grid = 2,
	MaxDistance = 40,
	MaxPerPlayer = 60,
}

GameConfig.Net = {
	-- Max requests per second, per player, per remote.
	DefaultRate = 8,
	LookRate = 6,
}

GameConfig.Dog = {
	FollowDistance = 7,
	CatchUpDistance = 18,
	TeleportDistance = 120,
	StuckSeconds = 4,
	WalkSpeed = 15,
	RunSpeed = 24,
	AlertRange = 75,
	BarkRange = 32,
	BarkCooldown = 18,
}

-- The watched house on the hill (HillHouse; Maya lives in the lake house
-- now). Fractions are of the Night phase.
GameConfig.LakeHouse = {
	nights = {
		[1] = {
			{ at = 0.08, action = "upstairsOn" },
			{
				at = 0.3,
				action = "silhouetteCross",
				note = "A figure crossed the upstairs window of the house on the hill.",
			},
			{ at = 0.55, action = "silhouetteCross" },
			{ at = 0.82, action = "allOff" },
		},
		[2] = {
			{ at = 0.04, action = "upstairsOn" },
			{ at = 0.06, action = "downstairsOn" },
			{
				at = 0.35,
				action = "figureStand",
				note = "Someone stood in the upstairs window of the hill house for a long time. Facing this way.",
			},
			{ at = 0.62, action = "figureLeave" },
		},
	},
	fallback = {
		{ at = 0.1, action = "upstairsOn" },
		{ at = 0.4, action = "silhouetteCross" },
		{ at = 0.85, action = "allOff" },
	},
	badNight = {
		{ at = 0.02, action = "upstairsOn" },
		{ at = 0.03, action = "downstairsOn" },
		{
			at = 0.22,
			action = "creaturesApproach",
			note = "Several shapes left the treeline and gathered around the hill house.",
		},
		{ at = 0.3, action = "flicker" },
		{
			at = 0.34,
			action = "windowBreak",
			note = "A window broke at the hill house. Its lights went out.",
		},
		{ at = 0.35, action = "allOff" },
		{ at = 0.45, action = "interiorMovement" },
		{ at = 0.7, action = "creaturesLeave" },
	},
}

return GameConfig

--!strict
-- Chapter 37: Pinehaven's people, places, restoration projects, shop,
-- reputation, incidents and Caramelo's training. Pure data.
--
-- Site positions are {x, z} studs and yaw in degrees (the building's front
-- faces local +Z, yaw 90 faces +X). Ground height comes from a raycast at
-- runtime, so these can move freely when the valley layout changes.
-- MayaGarden is placed relative to Maya's house instead.

local TownConfig = {}

TownConfig.Sites = {
	HardwareStore = { x = 84, z = 250, yaw = 270, clear = 20 },
	FrankShed = { x = 106, z = 268, yaw = 270, clear = 12 },
	Diner = { x = 32, z = 240, yaw = 90, clear = 20 },
	WeatherStation = { x = 24, z = 286, yaw = 90, clear = 16 },
	SensorMast = { x = 165, z = 205, yaw = 0, clear = 12 },
	MarthaHouse = { x = -76, z = 122, yaw = 180, clear = 18 },
	OldWoodShed = { x = -140, z = 214, yaw = 40, clear = 12 },
	MayaGarden = { anchor = "MayaHouse", dx = 17, dz = 3, yaw = 0, clear = 0 },
} :: {
	[string]: {
		x: number?,
		z: number?,
		yaw: number,
		clear: number,
		anchor: string?,
		dx: number?,
		dz: number?,
	},
}

-- Within this many studs of a site counts as "reached".
TownConfig.ReachRadius = 16
TownConfig.LocateRadius = 12

-- Interaction targets used by quest objectives, and the site that holds each.
-- "MayaHouse" is Maya's lake house (built by the world, not by Town).
TownConfig.Interactions = {
	DinerStove = "Diner",
	BiscuitScarf = "MarthaHouse",
	MayaTable = "MayaHouse",
} :: { [string]: string }

-- Missing animals or people a "locate" objective can look for: where they hide.
TownConfig.Missing = { Biscuit = "OldWoodShed" } :: { [string]: string }

export type NpcLook = {
	skin: { number },
	torso: { number },
	legs: { number },
	hat: string, -- "beanie" | "bun" | "scarf" | "cap"
	hatColor: { number },
}

TownConfig.Npcs = {
	frank = {
		name = "Frank",
		role = "Pinehaven Hardware",
		place = "the hardware store in town",
		site = "HardwareStore",
		look = {
			skin = { 214, 170, 140 },
			torso = { 120, 46, 40 },
			legs = { 60, 52, 46 },
			hat = "beanie",
			hatColor = { 150, 40, 36 },
		},
	},
	ellen = {
		name = "Ellen",
		role = "Ellen's Diner",
		place = "the diner in town",
		site = "Diner",
		look = {
			skin = { 196, 140, 104 },
			torso = { 230, 220, 200 },
			legs = { 70, 80, 110 },
			hat = "scarf",
			hatColor = { 196, 70, 70 },
		},
	},
	martha = {
		name = "Martha",
		role = "Neighbour up the lane",
		place = "her cottage up the lane from your cabin",
		site = "MarthaHouse",
		look = {
			skin = { 232, 196, 170 },
			torso = { 120, 110, 150 },
			legs = { 90, 80, 100 },
			hat = "bun",
			hatColor = { 200, 200, 204 },
		},
	},
	hale = {
		name = "Dr. Hale",
		role = "Weather station",
		place = "the weather station in town",
		site = "WeatherStation",
		look = {
			skin = { 150, 104, 78 },
			torso = { 70, 96, 80 },
			legs = { 50, 50, 56 },
			hat = "cap",
			hatColor = { 40, 60, 90 },
		},
	},
} :: {
	[string]: { name: string, role: string, place: string, site: string, look: NpcLook },
}

-- Maya is built by MayaService; listed for names and the journal.
TownConfig.MayaInfo = { name = "Maya", role = "Across the lake", place = "her house across the lake" }

TownConfig.Order = { "frank", "ellen", "martha", "hale" }

-- What each NPC says when no quest line applies. First match wins.
TownConfig.Dialogue = {
	frank = {
		{
			quest = "hale_sensor",
			status = "active",
			lines = { "Frank: Hale's mast? Scrap's on my counter if you're short." },
		},
		{
			flag = "frankShedRepaired",
			lines = {
				"Frank: Shed's holding up fine. Best roof in Pinehaven, don't tell anyone.",
				"Frank: Hale over at the weather station could use a hand, if you're bored.",
			},
		},
		{ lines = { "Frank: Mind the woods after dark. Lights off, curtains shut. Old habits." } },
	},
	ellen = {
		{ flag = "dinerOpen", trust = 5, lines = { "Ellen: The usual? I'm teasing. There's only stew." } },
		{ flag = "dinerOpen", lines = { "Ellen: Stove's warm. People keep coming in just to smell it." } },
		{ lines = { "Ellen: Everything's cold in here, including me." } },
	},
	martha = {
		{
			flag = "biscuitHome",
			lines = { "Martha: Biscuit hasn't left the porch since. Nor have I, really." },
		},
		{ lines = { "Martha: Biscuit always comes home for supper. Always." } },
	},
	hale = {
		{
			flag = "forecastUnlocked",
			lines = { "Dr. Hale: The station's humming. Listen for me on the radio each morning." },
		},
		{
			quest = "frank_shed",
			status = "done",
			lines = { "Dr. Hale: Frank's shed has a roof? Then he'll have my spare parts." },
		},
		{
			lines = {
				"Dr. Hale: My ridge sensor's dead and I've no parts.",
				"Dr. Hale: Frank keeps my spares in his shed, if it ever gets a roof again.",
			},
		},
	},
	maya = {
		{
			flag = "sharedMeal",
			lines = { "Maya: Supper was nice. We should make it a habit. Sometimes." },
		},
		{
			flag = "gardenRepaired",
			lines = { "Maya: The beans found the strings overnight. Told you." },
		},
	},
} :: {
	[string]: {
		{
			lines: { string },
			quest: string?,
			status: string?,
			flag: string?,
			notFlag: string?,
			trust: number?,
		}
	},
}

-- Restoration projects. Each action costs resources; stage = actions done.
TownConfig.Projects = {
	{
		id = "FrankShed",
		name = "Frank's tool shed",
		site = "FrankShed",
		quest = "frank_shed",
		actions = {
			{ id = "walls", text = "Straighten the walls", cost = { Wood = 3 } },
			{ id = "roof", text = "Lay the roof boards", cost = { Wood = 3 } },
			{ id = "door", text = "Hang the door", cost = { Wood = 2 } },
		},
		stages = { "Storm-wrecked", "Walls straight", "Roofed", "Repaired" },
		benefit = "Frank's counter restocks: scrap, fiber, binoculars",
		ack = { npc = "frank", line = "Frank: I heard hammering. Sounded like a real carpenter." },
	},
	{
		id = "MayaGarden",
		name = "Maya's trellis",
		site = "MayaGarden",
		quest = "maya_garden",
		actions = {
			{ id = "frame", text = "Raise the trellis frame", cost = { Wood = 4 } },
			{ id = "tie", text = "Tie up the bean vines", cost = { Fiber = 2 } },
		},
		stages = { "Flattened", "Frame up", "Climbing again" },
		benefit = "Maya shares berries from her garden",
		ack = { npc = "maya", line = "Maya: I can see it from the kitchen window. It looks lovely." },
	},
	{
		id = "WeatherSensor",
		name = "Ridge weather sensor",
		site = "SensorMast",
		quest = "hale_sensor",
		actions = {
			{ id = "cups", text = "Fit new anemometer cups", cost = { Scrap = 1 } },
			{ id = "wiring", text = "Splice the wiring", cost = { Scrap = 1, Fiber = 1 } },
		},
		stages = { "Silent", "Cups fitted", "Reporting" },
		benefit = "Dr. Hale radios a forecast every morning",
		ack = { npc = "hale", line = "Dr. Hale: Readings are coming in! Come by the station." },
	},
} :: {
	{
		id: string,
		name: string,
		site: string,
		quest: string?,
		scope: string?, -- nil/"player": each player's story; "town": SharedTown
		actions: { { id: string, text: string, cost: { [string]: number } } },
		stages: { string },
		benefit: string,
		ack: { npc: string, line: string }?,
	}
}

-- Town changes the journal lists, by quest flag.
TownConfig.Changes = {
	{ flag = "frankShedRepaired", text = "Frank's tool shed stands straight again" },
	{ flag = "dinerOpen", text = "Ellen's Diner is open, its sign lit at dusk" },
	{ flag = "biscuitHome", text = "Biscuit sleeps on Martha's porch again" },
	{ flag = "gardenRepaired", text = "Maya's beans climb a new trellis" },
	{ flag = "forecastUnlocked", text = "The weather station reports every morning" },
	{ flag = "sharedMeal", text = "You shared supper at Maya's table" },
}

TownConfig.MayaMilestones = {
	{ flag = "metMaya", name = "Lunch at the lake house" },
	{ flag = "gardenRepaired", name = "Fixed her garden trellis" },
	{ flag = "sharedMeal", name = "Shared a meal" },
}

TownConfig.Tiers = {
	{ name = "Stranger", min = 0 },
	{ name = "Newcomer", min = 10 },
	{ name = "Neighbour", min = 25 },
	{ name = "Friend of Pinehaven", min = 50 },
	{ name = "One of Pinehaven", min = 90 },
}

TownConfig.Limits = { maxCredits = 999, maxReputation = 200, maxTrust = 10 }

-- Real-time window for shop limits and small earnings: one game day.
TownConfig.WindowSeconds = 1500
TownConfig.EarnCap = { credits = 8, reputation = 3 }

-- Maya's garden gift after the trellis, once per window.
TownConfig.GardenGift = { Berries = 2 } :: { [string]: number }

TownConfig.Shop = {
	{ id = "frank_scrap", vendor = "frank", item = "Scrap", amount = 1, price = 3, limit = 4 },
	{ id = "frank_fiber", vendor = "frank", item = "Fiber", amount = 2, price = 2, limit = 3 },
	{
		id = "frank_binoculars",
		vendor = "frank",
		item = "Binoculars",
		amount = 1,
		price = 15,
		once = true,
		minTier = 3,
		flag = "frankShedRepaired",
	},
	{
		id = "ellen_stew",
		vendor = "ellen",
		item = "Stew",
		amount = 1,
		price = 4,
		limit = 2,
		flag = "dinerOpen",
	},
	{
		id = "ellen_berries",
		vendor = "ellen",
		item = "Berries",
		amount = 2,
		price = 2,
		limit = 2,
		flag = "dinerOpen",
	},
	{
		id = "ellen_mushroom",
		vendor = "ellen",
		item = "Mushroom",
		amount = 1,
		price = 2,
		limit = 2,
		flag = "dinerOpen",
	},
} :: {
	{
		id: string,
		vendor: string,
		item: string,
		amount: number,
		price: number,
		limit: number?,
		once: boolean?,
		minTier: number?,
		flag: string?,
	}
}

-- Caramelo's skills that progression saves. Only Tracking, raised as a
-- quest reward; his training and behaviour belong to DogService/DogMind.
TownConfig.DogSkills = {
	tracking = { name = "Tracking", max = 3 },
} :: { [string]: { name: string, max: number } }

-- Incidents. Peaceful ones are everyday errands. Spots are {x, z}.
TownConfig.Incidents = {
	{
		id = "fallen_branch",
		title = "A fallen branch blocks a trail",
		weight = 3,
		peaceful = true,
		cooldownDays = 1,
		phases = { "Day" },
		spots = { { x = 11, z = 56 }, { x = 72, z = 31 }, { x = -82, z = -20 } },
		radio = "Maya: A big branch came down across a trail near you. Careful out there.",
		reward = { credits = 2, reputation = 1 },
		items = { Wood = 3 },
	},
	{
		id = "mushroom_flush",
		title = "Mushrooms after the rain",
		weight = 3,
		peaceful = true,
		cooldownDays = 2,
		phases = { "Day" },
		weather = { "Rain", "Fog" },
		spots = { { x = 96, z = 70 }, { x = 120, z = 90 }, { x = 76, z = 96 } },
		radio = "Maya: After rain like that, the meadow east of you will be full of mushrooms.",
		reward = { credits = 0, reputation = 0 },
		items = { Mushroom = 2 },
	},
	{
		id = "lost_basket",
		title = "Ellen's delivery basket fell off a cart",
		weight = 2,
		peaceful = true,
		cooldownDays = 2,
		phases = { "Day" },
		flags = { "dinerOpen" },
		spots = { { x = 55, z = 172 }, { x = 30, z = 150 } },
		radio = "Ellen: Has anyone seen a basket on the road? It bounced off Hank's cart.",
		deliverTo = "ellen",
		reward = { credits = 4, reputation = 1 },
	},
	{
		id = "deer_meadow",
		title = "Deer in the east meadow",
		weight = 2,
		peaceful = true,
		cooldownDays = 2,
		phases = { "Day" },
		spots = { { x = 300, z = 140 } },
		radio = "Dr. Hale: A family of deer is grazing in the big meadow east. Worth a look, quietly.",
		reward = { credits = 1, reputation = 1 },
	},
	{
		id = "strange_tracks",
		title = "Strange tracks at the treeline",
		weight = 1,
		peaceful = false,
		cooldownDays = 3,
		phases = { "Day" },
		afterNights = { "Uneasy", "Bad", "Black" },
		spots = { { x = -60, z = -70 }, { x = 60, z = -60 } },
		radio = "Dr. Hale: Something left long tracks by the lake last night. Look if you like. Optional.",
		reward = { credits = 2, reputation = 0 },
	},
} :: {
	{
		id: string,
		title: string,
		weight: number,
		peaceful: boolean,
		cooldownDays: number,
		phases: { string }?,
		weather: { string }?,
		afterNights: { string }?,
		flags: { string }?,
		spots: { { x: number, z: number } },
		radio: string,
		reward: { credits: number, reputation: number },
		items: { [string]: number }?,
		deliverTo: string?,
	}
}
TownConfig.IncidentsPerDay = 2

return TownConfig

--!strict
-- Chapter 37 quests: five missions for the vertical slice, plus follow-ups
-- they open. Every quest is plain data run by Logic/Quests with the shared
-- objective components in Logic/Objectives. These are separate from the
-- day-1 story steps in StoryConfig, which keep working on their own.
--
-- Lines are "Speaker: text" for the HUD radio card. Pure data.

local QuestConfig = {}

-- Same shape as Logic/Quests' Def (config stays require-free).
type Objective = {
	kind: string,
	text: string,
	target: string?,
	items: { [string]: number }?,
	count: number?,
	phases: { string }?,
	hint: string?,
	say: { string }?,
}

type Quest = {
	id: string,
	giver: string,
	category: string,
	optional: boolean?,
	title: string,
	context: string,
	requires: { quests: { string }?, flags: { string }?, reputation: number?, trust: { [string]: number }? }?,
	objectives: { Objective },
	rewards: {
		credits: number?,
		reputation: number?,
		trust: { [string]: number }?,
		items: { [string]: number }?,
		dogSkill: { [string]: number }?,
		comfort: number?,
	},
	expiresAfter: number?,
	consequences: { string }?,
	followUps: { string }?,
	intro: { string }?,
	outro: { string }?,
	reminder: string?,
}

QuestConfig.List = {
	{
		id = "frank_shed",
		giver = "frank",
		category = "town",
		title = "Frank's tool shed",
		context = "The storm tore the roof off the shed behind the hardware store.",
		objectives = {
			{
				kind = "collect",
				items = { Wood = 8 },
				text = "Gather 8 wood for Frank's shed",
				hint = "Chop ribboned trees with your axe (1).",
			},
			{
				kind = "repair",
				target = "FrankShed",
				count = 3,
				text = "Repair the shed: walls, roof, door",
				hint = "Hold F at the shed behind the store.",
			},
			{ kind = "talk", target = "frank", text = "Tell Frank the shed is fixed" },
		},
		rewards = { credits = 15, reputation = 10, trust = { frank = 3 }, items = { Scrap = 2 } },
		consequences = { "frankShedRepaired" },
		followUps = { "hale_sensor" },
		intro = {
			"Frank: You took the lake cabin. I'm Frank. Hardware, bait, and the town gossip.",
			"Frank: The storm peeled the roof off my tool shed out back. My knees don't do ladders.",
			"Frank: Bring eight good pieces of wood and fix it up. I pay in Pinehaven credits.",
		},
		reminder = "Frank: Eight pieces of wood, then the shed out back. No rush.",
		outro = {
			"Frank: Well, I'll be. That roof isn't going anywhere.",
			"Frank: Credits, and some scrap I won't miss. My counter has stock again.",
		},
	},
	{
		id = "ellen_meal",
		giver = "ellen",
		category = "town",
		title = "A warm plate at the diner",
		context = "The supply truck hasn't come up the pass. Ellen's stove is cold.",
		objectives = {
			{
				kind = "collect",
				items = { Berries = 2, Mushroom = 1 },
				text = "Gather 2 berries and a mushroom",
				hint = "Berry bushes and mushrooms grow in the forest and meadows.",
			},
			{
				kind = "interact",
				target = "DinerStove",
				text = "Cook at the diner stove",
				hint = "Hold F at the stove inside the diner.",
			},
			{ kind = "talk", target = "ellen", text = "Serve the plate to Ellen" },
		},
		rewards = { credits = 10, reputation = 8, trust = { ellen = 3 } },
		consequences = { "dinerOpen" },
		intro = {
			"Ellen: A new face! Sit anywhere. There's nothing to eat, mind you.",
			"Ellen: The truck hasn't made it up the pass all week, and my regulars are hungry.",
			"Ellen: Bring two handfuls of berries and a good mushroom. We'll cook together.",
		},
		reminder = "Ellen: Two berries and a mushroom, then the stove's all yours.",
		outro = {
			"Ellen: Smells like a Tuesday in the old days. Thank you.",
			"Ellen: I'm opening again. Your credits are good here, and so is your company.",
			"Ellen: Oh, and Martha, up the lane from your cabin, lost her little dog in the storm.",
		},
	},
	{
		id = "martha_dog",
		giver = "martha",
		category = "dog",
		title = "Biscuit is missing",
		context = "Martha's little dog bolted the night of the storm.",
		objectives = {
			{
				kind = "interact",
				target = "BiscuitScarf",
				text = "Let Caramelo smell Biscuit's scarf",
				hint = "Hold F at the scarf on Martha's porch rail, with Caramelo close.",
			},
			{
				kind = "locate",
				target = "Biscuit",
				text = "Find Biscuit",
				hint = "Follow Caramelo's nose. If he loses the trail, let him smell the scarf again.",
			},
			{
				kind = "reach",
				target = "MarthaHouse",
				text = "Bring Biscuit home to Martha",
				hint = "Biscuit follows you now. Walk him back.",
			},
			{ kind = "talk", target = "martha", text = "Tell Martha" },
		},
		rewards = {
			credits = 10,
			reputation = 8,
			trust = { martha = 4 },
			dogSkill = { tracking = 1 },
		},
		consequences = { "biscuitHome" },
		intro = {
			"Martha: You're the new neighbour! Have you seen a little white dog? Biscuit?",
			"Martha: He bolted the night of the storm. He's never been gone two nights.",
			"Martha: His scarf is on the porch rail. Maybe your dog can follow his nose?",
		},
		reminder = "Martha: Let your dog smell the scarf. He'll know what to do.",
		outro = {
			"Martha: Biscuit! You silly thing, look at your paws.",
			"Martha: Thank you, both of you. Caramelo has a gift for finding things.",
			"Martha: My porch light stays on now. If you're ever caught out late, knock.",
		},
	},
	{
		id = "maya_garden",
		giver = "maya",
		category = "maya",
		title = "Maya's bean trellis",
		context = "The wind flattened the trellis in Maya's garden.",
		requires = { flags = { "metMaya" } },
		objectives = {
			{
				kind = "collect",
				items = { Wood = 4, Fiber = 2 },
				text = "Gather 4 wood and 2 fiber",
				hint = "Bushes give fiber. Trees give wood.",
			},
			{
				kind = "repair",
				target = "MayaGarden",
				count = 2,
				text = "Rebuild Maya's trellis",
				hint = "Hold F at the garden beside her house.",
			},
			{ kind = "talk", target = "maya", text = "Show Maya the trellis" },
		},
		rewards = { reputation = 3, trust = { maya = 3 }, items = { Berries = 2 } },
		consequences = { "gardenRepaired" },
		followUps = { "maya_meal" },
		intro = {
			"Maya: Did you see my garden? The wind knocked the bean trellis flat.",
			"Maya: It's a two-person job. Four pieces of wood and some fiber for ties?",
		},
		reminder = "Maya: Four wood and a little fiber. The beans are sulking.",
		outro = {
			"Maya: It's better than before. The beans will find the strings by tomorrow.",
			"Maya: Take some berries. And come for supper soon? Bring something warm.",
		},
	},
	{
		id = "maya_meal",
		giver = "maya",
		category = "maya",
		title = "Supper at Maya's",
		context = "Maya wants to share a meal at her table.",
		requires = { quests = { "maya_garden" } },
		objectives = {
			{
				kind = "deliver",
				target = "maya",
				items = { Stew = 1 },
				text = "Bring Maya a warm stew",
				hint = "Cook one at your fireplace, or buy one at Ellen's.",
			},
			{
				kind = "interact",
				target = "MayaTable",
				phases = { "Day", "Dusk" },
				text = "Sit down to supper at Maya's table",
				hint = "Her kitchen table, before night falls.",
			},
		},
		rewards = { trust = { maya = 4 }, comfort = 30 },
		consequences = { "sharedMeal" },
		intro = {
			"Maya: Supper, then. You bring a stew, I'll set the table.",
			"Maya: Your fireplace, Ellen's, wherever. Just come before dark.",
		},
		reminder = "Maya: Bring a stew and sit with me. Before dark, okay?",
		outro = {
			"Maya: This is nice. Just this.",
			"Maya: Go on home before the dark gets serious. I'll call you.",
		},
	},
	{
		id = "hale_sensor",
		giver = "hale",
		category = "town",
		title = "The silent anemometer",
		context = "Dr. Hale's sensor mast went quiet. No data, no forecast.",
		requires = { quests = { "frank_shed" } },
		objectives = {
			{ kind = "reach", target = "SensorMast", text = "Hike to the sensor mast east of town" },
			{
				kind = "investigate",
				target = "SensorMast",
				text = "Inspect the sensor",
				hint = "Hold F at the mast.",
				say = { "The cups are bent off and the wiring is chewed through." },
			},
			{
				kind = "collect",
				items = { Scrap = 2, Fiber = 1 },
				text = "Get 2 scrap and 1 fiber",
				hint = "Frank paid you in scrap. His counter sells more.",
			},
			{
				kind = "repair",
				target = "WeatherSensor",
				count = 2,
				text = "Repair the sensor: cups, then wiring",
				hint = "Hold F at the mast.",
			},
			{ kind = "talk", target = "hale", text = "Report to Dr. Hale" },
		},
		rewards = { credits = 15, reputation = 10, trust = { hale = 3 } },
		consequences = { "forecastUnlocked" },
		followUps = { "hale_rain", "hale_watchers" },
		intro = {
			"Dr. Hale: Frank says you have steady hands. Good.",
			"Dr. Hale: My sensor mast east of town went silent in the storm. No data, no forecast.",
			"Dr. Hale: Look at it for me, then patch it with scrap and fiber.",
		},
		reminder = "Dr. Hale: The mast is east of town, past the trees. Scrap and fiber should do it.",
		outro = {
			"Dr. Hale: There. Data. Lovely, lovely data.",
			"Dr. Hale: Every morning I'll radio what the night looks like. Plan around it.",
		},
	},
	{
		id = "hale_rain",
		giver = "hale",
		category = "weather",
		optional = true,
		title = "Rain log",
		context = "Optional. Sit somewhere dry through a spell of rain and listen.",
		requires = { quests = { "hale_sensor" } },
		objectives = {
			{
				kind = "weather",
				target = "Rain",
				count = 60,
				text = "Stay sheltered through a minute of rain",
				hint = "Any rain will do. Stay indoors and listen.",
			},
			{ kind = "talk", target = "hale", text = "Tell Dr. Hale what you heard" },
		},
		rewards = { credits = 6, reputation = 3, trust = { hale = 1 } },
		intro = {
			"Dr. Hale: If you like, log a rainy spell for me. Sit somewhere dry for a minute.",
			"Dr. Hale: The station hears the rain. You hear what's in it.",
		},
		reminder = "Dr. Hale: Next time it rains, sit somewhere dry and listen.",
		outro = { "Dr. Hale: Rain hides sound both ways. Remember that on bad nights." },
	},
	{
		id = "hale_watchers",
		giver = "hale",
		category = "mystery",
		optional = true,
		title = "Notes on the tall ones",
		context = "Optional research. A careful sighting from behind glass.",
		requires = { quests = { "hale_sensor" } },
		objectives = {
			{
				kind = "observe",
				target = "Watcher",
				text = "Observe a Watcher from a window",
				hint = "Only from inside. Nobody goes out there for research.",
			},
			{ kind = "talk", target = "hale", text = "Tell Dr. Hale what you saw" },
		},
		rewards = { credits = 8, reputation = 4, trust = { hale = 2 } },
		consequences = { "haleResearch" },
		intro = {
			"Dr. Hale: Off the record. The tall ones. I'd value a careful sighting.",
			"Dr. Hale: Only from a window, mind. Nobody goes out there for me.",
		},
		reminder = "Dr. Hale: Only from behind glass. If you never do it, that's fine too.",
		outro = { "Dr. Hale: Still as a post, and patient. Thank you. Stay inside when they come." },
	},
} :: { Quest }

return QuestConfig

--!strict
-- The opening (Revision 2.0) and the days after it. Steps complete in order
-- when their fact reaches the target. Every fact stays satisfiable later, so
-- a slow player is delayed, never soft-locked. Pure data.
--
-- Day 1: wake alone in the cabin with Caramelo; Maya radios from her house
-- across the lake; gather firewood with the axe; feed the fire; visit Maya;
-- home before dark; the first Watcher, with Maya coaching over the radio;
-- a calm rainy night.

local StoryConfig = {}

type Step = { id: string, text: string, fact: string, target: number?, hint: string? }

StoryConfig.Steps = {
	{
		id = "morning_call",
		text = "Answer the radio",
		fact = "mayaMorning",
		hint = "It's on the table. Someone is calling.",
	},
	{
		id = "firewood",
		text = "Gather firewood for tonight",
		fact = "woodGathered",
		target = 6,
		hint = "Press 1 for your axe. Marked trees have an orange ribbon.",
	},
	{
		id = "feed_fire",
		text = "Feed the fireplace",
		fact = "fireFed",
		hint = "The fire is almost out. Add wood at the hearth.",
	},
	{
		id = "visit_maya",
		text = "Visit Maya across the lake",
		fact = "talkedToMaya",
		hint = "Follow the path around the lake. Caramelo knows the way.",
	},
	{
		id = "home_before_dark",
		text = "Head home before dark",
		fact = "homeAtDusk1",
		hint = "The light is going. Get inside the cabin.",
	},
	{
		id = "look_outside",
		text = "Something is outside. Look through the north window",
		fact = "watcherSeen",
		hint = "Press E at the big window.",
	},
	{ id = "coat_on", text = "Put on your coat", fact = "tutorialCoat", hint = "Press Q. Slowly." },
	{
		id = "darken",
		text = "Darken the house: lights off, curtains closed",
		fact = "tutorialDark",
		hint = "The fuse box by the door cuts every light. F closes the curtains.",
	},
	{
		id = "stay_still",
		text = "Stay still until it leaves",
		fact = "watcherGone",
		hint = "Crouch (C). If it comes close, hold your breath (H).",
	},
	{
		id = "survive_1",
		text = "Survive your first night",
		fact = "survivedNight1",
		hint = "Rest, cook, sit with Caramelo, or watch the rain. Sleep in the bed to wake at dawn.",
	},
	{ id = "gather_stone", text = "Gather stone for repairs", fact = "stoneGathered", target = 4 },
	{
		id = "explore_house",
		text = "Search the abandoned house to the east",
		fact = "lootedHouse",
		hint = "Something lives there. Crouch (C) and move slowly. Wear the coat (Q).",
	},
	{ id = "survive_2", text = "Survive the second night", fact = "survivedNight2" },
	{ id = "radio", text = "Find the source of the radio signal on the west hill", fact = "radioFound" },
	{
		id = "prepare_cabin",
		text = "Strengthen the cabin: shutters or a reinforced door",
		fact = "cabinPrepared",
	},
	{ id = "survive_3", text = "Survive the third night", fact = "survivedNight3" },
	{ id = "go_north", text = "Follow the signal north", fact = "reachedNorth" },
} :: { Step }

StoryConfig.KnownFacts = {
	mayaMorning = true,
	woodGathered = true,
	fireFed = true,
	fireLit = true,
	talkedToMaya = true,
	homeAtDusk1 = true,
	watcherSeen = true,
	tutorialCoat = true,
	tutorialDark = true,
	watcherGone = true,
	survivedNight1 = true,
	foundCabin = true,
	doorRepaired = true,
	dogInside = true,
	coatFound = true,
	stoneGathered = true,
	fiberGathered = true,
	lootedHouse = true,
	homeAtDusk = true,
	survivedNight2 = true,
	cabinPrepared = true,
	radioFound = true,
	preparedForNight = true,
	survivedNight3 = true,
	reachedNorth = true,
} :: { [string]: boolean }

StoryConfig.Notes = {
	coat = "Your grandfather's coat. The lining is stitched with symbols you never understood. A note is still pinned inside: 'They do not see the one who wears it. Not truly. Stay still.'",
	radio = "Static, then a voice: '...if you can hear this, stay dark tonight. Lights off. Do not move when they come close. They talk to each other...' The loop repeats. A frequency is scratched into the console. Your cabin radio can find it.",
	ending = "THE STILLNESS - prototype complete. The signal points north, past the ridge. Keep playing: the nights continue.",
}

return StoryConfig

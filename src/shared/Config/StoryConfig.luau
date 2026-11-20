--!strict
-- "Survive three nights": the first playable story. Steps complete in order
-- when their fact reaches the target. Every fact stays satisfiable later, so
-- a slow player is delayed, never soft-locked. Pure data.

local StoryConfig = {}

StoryConfig.Steps = {
	{ id = "find_cabin", text = "Find shelter: the cabin in the clearing", fact = "foundCabin" },
	{ id = "collect_wood", text = "Collect wood from the trees", fact = "woodGathered", target = 8 },
	{ id = "repair_door", text = "Repair the cabin door", fact = "doorRepaired" },
	{ id = "light_fire", text = "Light the fireplace", fact = "fireLit" },
	{
		id = "dog_inside",
		text = "Bring your dog inside",
		fact = "dogInside",
		hint = "Use the dog menu (G): Come, then Stay.",
	},
	{
		id = "survive_1",
		text = "Survive the first night",
		fact = "survivedNight1",
		hint = "Stay inside. The chair by the window is comfortable.",
	},
	{ id = "find_coat", text = "Search the old wardrobe", fact = "coatFound" },
	{ id = "gather_stone", text = "Gather stone", fact = "stoneGathered", target = 4 },
	{ id = "gather_fiber", text = "Gather fiber from the bushes", fact = "fiberGathered", target = 4 },
	{
		id = "explore_house",
		text = "Search the abandoned house to the east",
		fact = "lootedHouse",
		hint = "Something lives there. Crouch (C) and move slowly. Wear the coat (Q).",
	},
	{ id = "home_dusk", text = "Return home before dark", fact = "homeAtDusk" },
	{ id = "survive_2", text = "Survive the second night", fact = "survivedNight2" },
	{
		id = "prepare_cabin",
		text = "Strengthen the cabin: repair the window or reinforce the door",
		fact = "cabinPrepared",
	},
	{ id = "radio", text = "Find the source of the radio signal on the west hill", fact = "radioFound" },
	{
		id = "bad_night_prep",
		text = "Prepare: power off, curtains closed, coat on, inside",
		fact = "preparedForNight",
		hint = "Something is wrong tonight. Darkness and silence will hide you.",
	},
	{ id = "survive_3", text = "Survive the third night", fact = "survivedNight3" },
	{ id = "lake_house", text = "Investigate the house across the lake", fact = "lakeHouseInvestigated" },
	{ id = "go_north", text = "Follow the signal north", fact = "reachedNorth" },
}

StoryConfig.KnownFacts = {
	foundCabin = true,
	woodGathered = true,
	doorRepaired = true,
	fireLit = true,
	dogInside = true,
	survivedNight1 = true,
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
	lakeHouseInvestigated = true,
	reachedNorth = true,
} :: { [string]: boolean }

StoryConfig.Notes = {
	coat = "A heavy coat, older than the cabin. The lining is stitched with symbols you do not recognize. A note is pinned inside: 'They do not see the one who wears it. Not truly. Stay still.'",
	radio = "Static, then a voice: '...if you can hear this, stay dark tonight. Lights off. Do not move when they come close. They talk to each other...' The loop repeats. A frequency is scratched into the console. Your cabin radio can find it.",
	lakeHouse = "The upstairs room is torn apart. On the desk, a journal: 'Day 41. The lights draw them. I know that now. The signal is coming from north of the ridge. If anyone reads this - go north, by daylight.'",
	ending = "THE STILLNESS - prototype complete. The signal points north, past the ridge. Keep playing: the nights continue.",
}

return StoryConfig

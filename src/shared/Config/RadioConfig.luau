--!strict
-- What the cabin radio says, always tied to what is happening. Pure data.
--
-- Every line lists the conditions (`need`) that must all hold right now.
-- InteractionService computes the conditions from the live game, keeps the
-- lines whose needs are met, prefers the more specific ones, and skips lines
-- the player heard recently. Text is "Speaker: text" for the HUD radio card.
--
-- Conditions:
--   time:      morning, day, evening, night, dawn
--   weather:   clear, fog, rain, storm
--   night:     badNight (Bad/Black after dusk), uneasy, peaceful
--   creatures: creatureNear, watcherNear, crawlerNear, creatureFed, oldOne
--   house:     cabinLit, cabinDark, dogAlert, scared (your fear is high)
--   Maya:      mayaKnown (you have visited her), mayaLit (her lamps are on)
--   story:     fact:<name> (a story fact is true), !<anything> negates

local RadioConfig = {}

export type Line = { text: string, need: { string }, weight: number? }

-- Lines the player will not hear again until this many others have played.
RadioConfig.NoRepeat = 6

RadioConfig.Fallback = "Static: Only static. Somewhere under it, something like a voice."

RadioConfig.Lines = {
	-- Danger tonight
	{
		need = { "badNight" },
		weight = 5,
		text = "Static: ...stay dark. Lights off. Curtains shut. Don't move when they're close...",
	},
	{
		need = { "badNight" },
		weight = 5,
		text = "Unknown voice: ...they talk to each other. They hear you breathe. Stay low, stay quiet...",
	},
	{
		need = { "badNight" },
		weight = 5,
		text = "Static: ...whatever knocks tonight, it isn't someone you know...",
	},
	{
		need = { "badNight", "cabinLit" },
		weight = 6,
		text = "Unknown voice: ...your lights. Every light you leave on, they can see from the trees.",
	},
	{
		need = { "uneasy", "night" },
		weight = 3,
		text = "KPHN: Folks on the east side say the birds went quiet early. Probably nothing. Probably.",
	},

	-- Creatures near the cabin
	{
		need = { "watcherNear", "cabinLit" },
		weight = 5,
		text = "Static: ...a lit window is a lantern to it. It will come and look. Douse the lights...",
	},
	{
		need = { "watcherNear", "cabinDark" },
		weight = 4,
		text = "Unknown voice: ...good. Dark and still. It is only looking. Let it look.",
	},
	{
		need = { "watcherNear" },
		weight = 3,
		text = "KPHN: A caller by the lake says someone's standing at the treeline and won't answer. Don't go out to check.",
	},
	{
		need = { "watcherNear" },
		weight = 3,
		text = "Unknown voice: ...don't stare at it too long. It knows when you're looking.",
	},
	{
		need = { "crawlerNear" },
		weight = 4,
		text = "Static: ...something low and fast near the north road... keep off the floorboards...",
	},
	{
		need = { "creatureFed" },
		weight = 4,
		text = "Unknown voice: ...it likes it when you're afraid. Breathe slow. Give it nothing.",
	},
	{
		need = { "oldOne" },
		weight = 6,
		text = "Static: ...the ridge... something on the ridge, taller than the pines... don't signal it...",
	},
	{
		need = { "dogAlert", "night" },
		weight = 3,
		text = "KPHN: Dogs all over town are restless tonight. Trust yours.",
	},
	{
		need = { "scared" },
		weight = 3,
		text = "KPHN: If your heart's racing, sit by the fire, hold the dog, count your breaths. It helps more than you'd think.",
	},

	-- Weather (the reports with a forecast are added separately)
	{
		need = { "storm" },
		weight = 4,
		text = "KPHN: Severe weather over the ridge. Latch your windows; wind opens what isn't locked.",
	},
	{
		need = { "storm" },
		weight = 4,
		text = "KPHN: Gusts in the valley tonight. Shutters if you have them.",
	},
	{
		need = { "rain", "night", "!creatureNear" },
		weight = 2,
		text = "KPHN: Good rain tonight. If you hear tapping, it's the gutters. Mostly.",
	},
	{
		need = { "fog", "day" },
		weight = 2,
		text = "KPHN: Fog on the trail. Keep the lake on your left and you'll find your way.",
	},

	-- The day, and where the story stands
	{
		need = { "morning", "!fact:fireFed" },
		weight = 3,
		text = "KPHN: Out for firewood this morning? The ribboned trees near the lake are fair game.",
	},
	{
		need = { "day", "fact:survivedNight1", "!fact:lootedHouse" },
		weight = 3,
		text = "KPHN: Stay away from the old house east of the lake. Something's been living in it since summer.",
	},
	{
		need = { "fact:lootedHouse", "!fact:radioFound" },
		weight = 3,
		text = "Static: ...a faint voice on a frequency that drifts west, toward the hill with the tower...",
	},
	{
		need = { "fact:radioFound", "!fact:survivedNight3" },
		weight = 3,
		text = "Unknown voice: ...if you can hear this, you are not alone out there. Keep the fire small.",
	},
	{
		need = { "fact:radioFound", "night", "!fact:survivedNight3" },
		weight = 3,
		text = "Unknown voice: ...it will not cross a closed door tonight. Close yours.",
	},
	{
		need = { "fact:survivedNight3", "!fact:reachedNorth" },
		weight = 3,
		text = "Unknown voice: ...north of the ridge. By daylight. North.",
	},
	{
		need = { "evening" },
		weight = 2,
		text = "KPHN: The sun's going down. Bring the dog in, bring yourself in.",
	},
	{
		need = { "evening", "!fact:cabinPrepared", "fact:survivedNight2" },
		weight = 3,
		text = "KPHN: If your door's still the old one, Frank says a reinforced frame takes an afternoon.",
	},
	{
		need = { "dawn" },
		weight = 2,
		text = "KPHN: First light, Pinehaven. Whatever was out there is gone with the dark.",
	},

	-- Maya, from across the lake
	{
		need = { "mayaKnown", "morning" },
		weight = 2,
		text = "Maya: Morning. Smoke from your chimney again. I like knowing you're up.",
	},
	{
		need = { "mayaKnown", "night", "cabinLit", "!badNight" },
		weight = 3,
		text = "Maya: I can see every one of your windows from here. Maybe turn a few off?",
	},
	{
		need = { "mayaKnown", "night", "cabinDark", "mayaLit" },
		weight = 3,
		text = "Maya: Your house is dark. Good. I'm keeping my lamp on so you know I'm fine.",
	},
	{
		need = { "mayaKnown", "watcherNear" },
		weight = 4,
		text = "Maya: There's something by the trees on your side. Don't move much. I'll keep watching it.",
	},
	{
		need = { "mayaKnown", "rain", "!creatureNear" },
		weight = 2,
		text = "Maya: Listen to that rain. Best sound in the world when you're inside.",
	},
	{
		need = { "mayaKnown", "night", "!mayaLit" },
		weight = 2,
		text = "Static: Maya's channel is quiet. Across the lake, her windows are dark.",
	},

	-- Calm nights
	{
		need = { "night", "!creatureNear", "!badNight" },
		weight = 1,
		text = "KPHN: (an old piano piece drifts in and out under the static)",
	},
	{
		need = { "night", "rain", "!creatureNear" },
		weight = 1,
		text = "KPHN: (a music box tune, slow, almost in time with the rain)",
	},
	{
		need = { "night", "!creatureNear", "!badNight" },
		weight = 1,
		text = "KPHN: Night shift here. Just me and the records. Nothing on the wire tonight.",
	},
} :: { Line }

-- Weather reports: {next} is the known forecast for the next part of the day.
RadioConfig.Weather = {
	Clear = { "KPHN: Clear and still over the lake. Later: {next}." },
	Fog = { "KPHN: Fog in the valley, visibility poor. Later: {next}." },
	Rain = { "KPHN: Steady rain, nothing to worry about. Later: {next}." },
	Storm = { "KPHN: Storm overhead. Stay inside. Later: {next}." },
} :: { [string]: { string } }

RadioConfig.Forecast = {
	Clear = "clear",
	Fog = "fog rolling in",
	Rain = "rain",
	Storm = "a storm",
	Unknown = "hard to say past the ridge",
} :: { [string]: string }

return RadioConfig

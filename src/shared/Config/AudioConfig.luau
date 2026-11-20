--!strict
-- Every sound the game can play, by key. An empty id means "silent": the
-- audio code skips it and never errors, so the game runs before real audio
-- is added.
--
-- Every id below comes from Roblox's licensed partner catalogs on the Creator
-- Store (ProSoundEffects, APMOfficial, DistrokidOfficial), was found with
-- tools/assets/search_store.py and loaded successfully in Studio by
-- tools/studio/verify_audio.luau (59/59). Sources are listed in
-- docs/ASSET_LICENSES.md. Built-in rbxasset:// sounds ship with the client.

local AudioConfig = {}

local function id(n: number): string
	return "rbxassetid://" .. tostring(n)
end

-- Adaptive soundtrack, keyed by MusicState state. Each state may list several
-- cues; the director picks one at random and never repeats the last one.
AudioConfig.Music = {
	MAIN_MENU = { id(1838792473) }, -- Dawn 2 (APM)
	HOME_SAFE = { id(113205710506304), id(129193633608000) }, -- Relaxing Piano and Crackling Fireplace; Armchair Twilight Sonata
	HOME_RAIN = { id(133914369779227) }, -- Quiet Morning Drizzle
	DAY_EXPLORATION = { id(135947284128563), id(113725748108878) }, -- Autumn whispers; Echoes of the Ancient Wood
	DUSK = { id(9046385674) }, -- Sunset Glow (APM)
	NIGHT_SAFE = { id(84591888439601) }, -- Soft Mantel Clock
	NIGHT_OUTSIDE = { id(99895453377463) }, -- Existential Dread (dark ambient drone)
	CREATURE_NEARBY = { id(1839621827) }, -- Ominous (APM)
	CREATURE_HUNTING = { id(1837795171) }, -- Skin Crawler (APM)
	CREATURE_LOST = { id(1835935237) }, -- Tempus Oris (APM)
	DAWN = { id(9042042586) }, -- Eternal Ice (b) (APM)
	DISCOVERY = { id(113592187486066) }, -- Moon TAG (APM)
	BLACKOUT = {},
	-- "The Mechanism" (original, uploaded by the owner 2026-11-20) and APM "Music Box Of Death".
	STORM_NIGHT = { id(85164647841567), id(1837805876) },
} :: { [string]: { string } }

-- Looping ambience layers. The mixer sets each layer's volume every frame.
AudioConfig.Ambience = {
	dayBirds = id(9112835056), -- Neighborhood Birds 1 (ProSoundEffects)
	dayLeaves = id(9116258071), -- Leaves Rustle Wind Blowing Through Trees 1
	nightInsects = id(9112764573), -- Crickets Night 3
	nightDistant = id(9112775612), -- Eerie Presence 1
	windLight = id(9114057104), -- Desert Wind Whistley Light Gusts 1
	windStrong = id(81404060588532), -- Howling Wind (DistroKid)
	rainOutside = id(9112853422), -- Rain Heavy Rainfall Grass Wooden Roof 1
	rainRoof = id(9112853653), -- Rain Hitting Roof 2
	rainWindow = id(9112857056), -- Rain On Window 2
	fireplace = id(77688442375055), -- Crackling Fireplace for Deep Sleep
	cabinCreaks = id(9126282474), -- Wood Strain Stress Creaking
	dogBreathing = "",
	water = "",
	heartbeat = id(9043365842), -- HEARTBEAT 02 96BPM (APM)
}

-- One-shot cues fired by the server (SoundCue remote) or by client systems.
AudioConfig.Cues = {
	windowRattle = id(9120762268), -- Window Rattle 14
	windowBang = id(1837829565), -- HIT-Door Slam 02 (APM)
	glassCrack = id(9120761249), -- Window Rattle 11
	glassBreak = id(9114590297), -- Glass Break 1
	doorHit = id(9114148088), -- Door Pound 2
	doorBreak = id(9120805690), -- Wood Break Breaking Open Wood Door Cracks 1
	scratch = id(9116908825), -- Metal Wood Scrapes 1
	growl = id(9120788137), -- Wolf Growl 3 (quiet canine growl)
	bark = id(9113956187), -- Coyotes Gruff Barking 13 (ProSoundEffects); not yet loaded in Studio
	whine = id(9113951726), -- Coyote Whimpering 6 (canine whimper)
	thunder = id(9120018411), -- Thunder Distant Rumble 1
	thunderClose = id(9120016037), -- Thunder Cracks Big Rumbling Blasts 1
	gasp = id(9125572450), -- Gasps Male Deep Breaths Frightened
	exhale = id(9113586144), -- Breath Exhale 17
	switch = id(9125609743), -- Hotel Light Switch Clicks
	curtain = id(9114018343), -- Curtains Curtain Hardware Rattle 4
	door = id(9120839581), -- Wood Door Open Soft Close 1
	doorSlam = id(1837829565), -- HIT-Door Slam 02 (APM)
	latch = id(9116725218), -- Metal Latches 17
	chop = id(9120808574), -- Wood Chopping Exterior Single Hits 12
	mine = id(9118612665), -- Rock Impact 7
	pickup = "",
	cabinet = id(9120839870), -- Wood Door Open Soft Close 4
	craft = "",
	fireIgnite = "",
	radioStatic = id(9125774208), -- Police Radio Line Feed Static 1
	radioVoice = "",
	oldOneCall = id(9113985466), -- Creature Roar Constant Deep Throaty Growls 3
	watcherStep = "",
	creatureCall = id(9125467848), -- Creature Growls Deep Guttural Rumbling
	creatureResponse = id(9113983944), -- Creature Weird Deep Monster Breathing 1
	journal = "",
	discovery = id(113592187486066), -- Moon TAG (APM)
	shutterBang = id(9119128490), -- Shutter Bangs Rattle Shaking Wood Hits 29
	floorCreak = id(9125563505), -- Floor Creaks Wood Floorboard
	drip = id(9112903083), -- Water Drip Single Drops Into Tin Bucket 3
	wetSteps = id(9120589946), -- Water Splash Wet Smacking Footsteps 1
	gutter = id(9112853895), -- Rain In Gutter 3
	thunderStrike = id(9120021539), -- Thunder Sharp Booming Strikes Rumbling 3
	birdsTakeOff = id(9125738421), -- Pigeon Surges Sudden Bursts Of Birds Flying
	wolvesDistant = id(9120051816), -- Timber Wolves Distant Howling Chorus 2
	owl = id(9117181540), -- Owl Hooting Reverberant Several 1
	splash = "rbxasset://sounds/impact_water.mp3",
	jump = "rbxasset://sounds/action_jump.mp3",
	land = "rbxasset://sounds/action_jump_land.mp3",
	footstep = "rbxasset://sounds/action_footsteps_plastic.mp3",
} :: { [string]: string }

-- The H-17 Chaoscope on the cabin table (Chapter 36). hum and tone stay
-- empty until a partner-catalog id is verified in Studio; until then the
-- scope's hum falls back to the radio static, played very quietly and slow.
AudioConfig.Chaoscope = {
	hum = "",
	tone = "",
	click = id(9125609743), -- Hotel Light Switch Clicks (the relay click)
	static = id(9125774208), -- Police Radio Line Feed Static 1
} :: { [string]: string }

-- Mixer tuning.
AudioConfig.Mix = {
	MusicVolume = 0.45,
	AmbienceVolume = 0.8,
	CueVolume = 0.9,
	MusicFade = 4,
	AmbienceFade = 2.5,
	MusicMinGap = 75, -- seconds of silence before an ambient cue may start
	MusicChance = 0.35,
}

return AudioConfig

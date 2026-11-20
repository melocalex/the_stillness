--!strict
-- Tunables for Chapter 36, the Dissonance: the chaotic energy field, the
-- H-17 Chaoscope's modes and warning levels, the three signal families, the
-- active-scan signature, and the event director's rules and cooldowns.
--
-- CEU (chaotic energy units) is an in-world unit. Energy is not a creature
-- count: it drifts on peaceful nights, follows the weather a little, and a
-- reading never reliably predicts an encounter.

local DissonanceConfig = {}

DissonanceConfig.Field = {
	sectorSize = 200, -- studs per grid sector
	-- The field covers -halfSize..halfSize on X and Z (the map is +-1000).
	-- 11 sectors a side put the cabin (0, 0) in the middle of one sector.
	halfSize = 1100,
	tickSeconds = 1,
	baseline = 7, -- CEU on a quiet afternoon
	nightLift = 3, -- extra background CEU at full night
	driftPull = 0.02, -- mean reversion of the slow drift, per second
	driftSigma = 0.45, -- random walk step, CEU per sqrt(second)
	driftLimit = 6,
	rainPerUnit = 1.5, -- CEU per unit of RainIntensity (0..5)
	stormFrom = 3.4, -- rain above this adds interference, not energy
	stormInterference = 2.5, -- noise CEU per unit of rain above stormFrom
	creatureEnergy = 9, -- CEU from one creature at FearEnergy 1
	creatureHunger = 5, -- CEU from one creature at Hunger 1
	creatureRange = 260, -- studs a creature contributes over
	collectivePerLevel = 0.8, -- CEU per CollectiveService level, field-wide
	creatureLag = 25, -- seconds: the creature term is a slow average
	smoothing = 6, -- seconds for current energy to approach its target
	voidSmoothing = 1.2, -- seconds to fall to zero inside an Absence
	trendWindow = 10, -- seconds for the trend average
	anomalyFalloff = 160, -- studs: an anomaly's pull halves at this distance
}

-- Instrument modes. range in studs, noise in CEU (one sigma at sensitivity
-- 3), update in seconds, quantize rounds the display, flat averages every
-- sector in range equally (an approximate regional picture), blend is how
-- far the needle moves toward each new sample (the meter's damping),
-- signature is the strongest scan signature this mode can emit (at full
-- sensitivity).
export type Mode = {
	range: number,
	noise: number,
	update: number,
	quantize: number,
	flat: boolean,
	blend: number,
	signature: number,
}
DissonanceConfig.Modes = {
	PASSIVE = { range = 90, noise = 3, update = 3, quantize = 1, flat = false, blend = 0.25, signature = 0 },
	LOCAL = {
		range = 180,
		noise = 2,
		update = 1,
		quantize = 0.5,
		flat = false,
		blend = 0.5,
		signature = 0.35,
	},
	REGIONAL = {
		range = 1400,
		noise = 6,
		update = 4,
		quantize = 5,
		flat = true,
		blend = 0.4,
		signature = 0.7,
	},
} :: { [string]: Mode }
DissonanceConfig.ModeOrder = { "PASSIVE", "LOCAL", "REGIONAL" }
DissonanceConfig.Sensitivity = { min = 1, max = 5, default = 2 }

-- Warning levels by displayed CEU, lowest first. A reading near zero, or
-- one whose uncertainty is too high, is UNKNOWN.
DissonanceConfig.Levels = {
	{ name = "STABLE", from = 0 },
	{ name = "DRIFT", from = 18 },
	{ name = "DISTURBANCE", from = 36 },
	{ name = "CONVERGENCE", from = 58 },
	{ name = "THRESHOLD", from = 80 },
}
DissonanceConfig.LevelRules = {
	hysteresis = 4, -- CEU below a border before the level drops
	unknownUncertainty = 9, -- noise sigma at or above which the level is UNKNOWN
	zeroBelow = 0.75, -- a reading this close to zero is no reading at all
}

-- Anomaly sources: the signal families.
DissonanceConfig.Anomaly = {
	-- Chance per minute that an anomaly starts, by NightType ("Day" by day).
	chancePerMinute = { Day = 0.01, Peaceful = 0.05, Uneasy = 0.08, Bad = 0.1, Black = 0.12 } :: { [string]: number },
	rainBonus = 0.015, -- extra chance per minute while it rains (weather correlation)
	gapAfter = 120, -- seconds with no new anomaly after one ends
	firstDay = 2, -- no natural anomalies on day 1 (the opening owns it)
	families = { Arrival = 0.45, Echo = 0.3, Absence = 0.25 } :: { [string]: number },
	nearHome = 0.7, -- chance an anomaly centres on the home sector
	-- Stage lengths in seconds, {min, max}.
	stages = {
		ONSET = { 25, 45 },
		ACTIVE = { 50, 90 },
		PEAK = { 20, 35 },
		FADE = { 20, 40 },
	} :: { [string]: { number } },
	-- CEU at the source at full envelope.
	strength = { Arrival = 34, Echo = 22, Absence = 26 } :: { [string]: number },
	feedRate = 0.03, -- strength gain per second per unit of scan signature
	feedMax = 0.35, -- scanning can add at most +35% strength
	coherencePerSecond = 0.006, -- Arrival coherence gained per second (ACTIVE, PEAK)
	coherenceScan = 0.03, -- extra coherence per second per unit of signature
	coherenceSteps = { 0.2, 0.45, 0.7, 0.92 }, -- one transmission at each
	coherentAt = 0.7, -- from here the line comes through whole
	echoSteps = { 0.5, 0.75 }, -- envelope steps where the Echo replays
	noOutsideCoherence = 0.9,
	noOutsideChance = 0.2,
	noOutsideMinDays = 5, -- days between two uses of the rare line
	ghostNeedleChance = 0.45, -- scope switched off after an Arrival peaked
}

-- Active-scan signature: high sensitivity in LOCAL or REGIONAL emits a
-- signature that some creatures can learn to notice. It charges up (the
-- EMIT lamp warms, then blinks), pulses, then cools down.
DissonanceConfig.Scan = {
	threshold = 0.25, -- signatures below this never pulse
	chargePerSecond = 0.1, -- at signature 1
	decayPerSecond = 0.05, -- charge lost per second below the threshold
	warnAt = 0.6, -- charge where the EMIT lamp starts blinking
	cooldown = 45, -- seconds after a pulse before the next can charge
	pulseHold = 8, -- seconds the ChaosSignal attribute stays up after a pulse
}

-- Event director: per-event cooldowns (seconds) and how long effects last.
DissonanceConfig.Director = {
	cooldowns = {
		transmission = 12,
		radio = 25,
		window = 35,
		flicker = 60,
		hush = 60,
		maya = 120,
		dogRouse = 20,
		dogWatch = 30,
		dogGrowl = 45,
		echo = 25,
		ghostNeedle = 300,
		relax = 0,
	} :: { [string]: number },
	hushSeconds = { 6, 10 },
	mayaDarkSeconds = { 2.5, 4 },
	ghostPause = { 3, 6 },
	-- StartleStrength handed to Caramelo's mood system (0..0.5). Inside the
	-- house with his person near, 0.22 lands at ALERT (head up) and 0.45 at
	-- SUSPICIOUS (low growl); barking needs PANICKED, far above either.
	startle = { dogRouse = 0.22, dogWatch = 0.3, dogGrowl = 0.45 } :: { [string]: number },
	homeShare = 4, -- CEU of anomaly at home before house events may fire
	hearRadius = 45, -- studs from the scope: who hears transmissions
	controlRadius = 12, -- studs from the scope: who may turn its knobs
}

-- The Echo only replays ordinary, harmless in-game sounds. Never creatures,
-- breaking glass or doors giving way, and never anything recorded.
DissonanceConfig.EchoCues = {
	door = true,
	latch = true,
	switch = true,
	curtain = true,
	cabinet = true,
	chop = true,
	floorCreak = true,
	drip = true,
	footstep = true,
	whine = true,
	radioStatic = true,
} :: { [string]: boolean }

return DissonanceConfig

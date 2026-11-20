--!strict
-- Configuration-driven creature archetypes. Adding a creature means adding an
-- entry here and (only if it behaves in a new way) a behavior module.
-- Pure data: loadable by tests.

local CreatureConfig = {}

export type Archetype = {
	displayName: string,
	behavior: string, -- module under ServerScriptService.Server.Creatures.Behaviors
	senses: {
		visionRange: number,
		fovDegrees: number,
		peripheralRange: number,
		lightSensitivity: number,
		hearingMultiplier: number,
		presenceRange: number,
		presenceSensitivity: number,
		coatResistance: number,
	},
	brain: {
		suspiciousThreshold: number,
		investigateThreshold: number,
		huntThreshold: number,
		awarenessDecay: number,
		hearingGain: number,
		suspiciousTime: number,
		searchDuration: number,
		lostTargetTime: number,
		memorySeconds: number,
	},
	speeds: { slow: number, walk: number, run: number },
	catchRange: number,
	respectsShelter: boolean,
	canBreach: boolean,
	nocturnal: boolean,
	collective: boolean,
	reactsToObservation: string, -- watcher | none | listener
	lightAttraction: number, -- 0..1 how strongly lit houses pull it
	threatLevel: number,
	tickRate: number, -- AI updates per second when near players
	journalSubject: string,
}

CreatureConfig.Archetypes = {
	Watcher = {
		displayName = "The Watcher",
		behavior = "Watcher",
		senses = {
			visionRange = 70,
			fovDegrees = 110,
			peripheralRange = 12,
			lightSensitivity = 0.6,
			hearingMultiplier = 0.8,
			presenceRange = 14,
			presenceSensitivity = 0.9,
			coatResistance = 0.1,
		},
		brain = {
			suspiciousThreshold = 0.2,
			investigateThreshold = 0.45,
			huntThreshold = 1.0,
			awarenessDecay = 0.25,
			hearingGain = 0.6,
			suspiciousTime = 3,
			searchDuration = 14,
			lostTargetTime = 6,
			memorySeconds = 20,
		},
		speeds = { slow = 5, walk = 9, run = 19 },
		catchRange = 4.5,
		respectsShelter = true,
		canBreach = false,
		nocturnal = true,
		collective = true,
		reactsToObservation = "watcher",
		lightAttraction = 1,
		threatLevel = 2,
		tickRate = 4,
		journalSubject = "Watcher",
	},
	Dweller = {
		displayName = "The Dweller",
		behavior = "Dweller",
		senses = {
			visionRange = 26,
			fovDegrees = 140,
			peripheralRange = 8,
			lightSensitivity = 0.2,
			hearingMultiplier = 1.9,
			presenceRange = 8,
			presenceSensitivity = 0.7,
			coatResistance = 0.25,
		},
		brain = {
			suspiciousThreshold = 0.15,
			investigateThreshold = 0.35,
			huntThreshold = 0.9,
			awarenessDecay = 0.2,
			hearingGain = 0.8,
			suspiciousTime = 2,
			searchDuration = 18,
			lostTargetTime = 5,
			memorySeconds = 25,
		},
		speeds = { slow = 6, walk = 10, run = 20 },
		catchRange = 4,
		respectsShelter = true,
		canBreach = false,
		nocturnal = false,
		collective = false,
		reactsToObservation = "none",
		lightAttraction = 0,
		threatLevel = 3,
		tickRate = 5,
		journalSubject = "Dweller",
	},
	Crawler = {
		displayName = "Crawler",
		behavior = "Crawler",
		senses = {
			visionRange = 40,
			fovDegrees = 120,
			peripheralRange = 10,
			lightSensitivity = 0.7,
			hearingMultiplier = 1.5,
			presenceRange = 12,
			presenceSensitivity = 1.0,
			coatResistance = 0.1,
		},
		brain = {
			suspiciousThreshold = 0.2,
			investigateThreshold = 0.4,
			huntThreshold = 1.0,
			awarenessDecay = 0.25,
			hearingGain = 0.7,
			suspiciousTime = 2,
			searchDuration = 16,
			lostTargetTime = 5,
			memorySeconds = 20,
		},
		speeds = { slow = 7, walk = 12, run = 21 },
		catchRange = 4,
		respectsShelter = true,
		canBreach = true,
		nocturnal = true,
		collective = true,
		reactsToObservation = "none",
		lightAttraction = 0.7,
		threatLevel = 3,
		tickRate = 4,
		journalSubject = "Crawler",
	},
} :: { [string]: Archetype }

-- The Old One is presentation only in this prototype: a silhouette, sounds,
-- and an effect on the others (Watchers withdraw from it).
CreatureConfig.OldOne = {
	ChancePerNight = { Peaceful = 0.25, Uneasy = 0.5, Bad = 0.6, Black = 1 } :: { [string]: number },
	MinDay = 2,
	VisibleSeconds = 70,
	WatcherFleeRadius = 220,
}

return CreatureConfig

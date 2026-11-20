--!strict
-- Specs for the pure gameplay logic in src/shared/Logic.

local process = require("@lune/process")
local t = require("./harness")
local describe, it, eq, near, truthy, falsy = t.describe, t.it, t.eq, t.near, t.truthy, t.falsy

local TimeCycle = require("../src/shared/Logic/TimeCycle")
local Perception = require("../src/shared/Logic/Perception")
local CreatureBrain = require("../src/shared/Logic/CreatureBrain")
local Shelter = require("../src/shared/Logic/Shelter")
local Noise = require("../src/shared/Logic/Noise")
local CollectiveMind = require("../src/shared/Logic/CollectiveMind")
local Inventory = require("../src/shared/Logic/Inventory")
local NightClass = require("../src/shared/Logic/NightClass")
local Comfort = require("../src/shared/Logic/Comfort")
local LightVisibility = require("../src/shared/Logic/LightVisibility")
local MusicState = require("../src/shared/Logic/MusicState")
local Journal = require("../src/shared/Logic/Journal")
local StoryProgress = require("../src/shared/Logic/StoryProgress")
local Mystery = require("../src/shared/Logic/Mystery")
local Breath = require("../src/shared/Logic/Breath")
local AudioConfig = require("../src/shared/Config/AudioConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local CreatureConfig = require("../src/shared/Config/CreatureConfig")
local StoryConfig = require("../src/shared/Config/StoryConfig")

local D = { Day = 720, Dusk = 180, Night = 480, Dawn = 120 }

describe("TimeCycle", function()
	it("starts on day 1 in the morning", function()
		local s = TimeCycle.snapshot(D, 0)
		eq(s.phase, "Day")
		eq(s.day, 1)
		near(s.clockTime, 6.5)
	end)
	it("walks the phases in order with configured durations", function()
		eq(TimeCycle.snapshot(D, 719).phase, "Day")
		eq(TimeCycle.snapshot(D, 720).phase, "Dusk")
		eq(TimeCycle.snapshot(D, 900).phase, "Night")
		eq(TimeCycle.snapshot(D, 1380).phase, "Dawn")
		local next = TimeCycle.snapshot(D, 1500)
		eq(next.phase, "Day")
		eq(next.day, 2)
	end)
	it("keeps clock time continuous across phase borders", function()
		local before = TimeCycle.snapshot(D, 899.99).clockTime
		local after = TimeCycle.snapshot(D, 900).clockTime
		near(before, after, 0.01)
		near(TimeCycle.snapshot(D, 1379.99).clockTime, 5, 0.01)
	end)
	it("wraps midnight inside the night", function()
		local s = TimeCycle.snapshot(D, 900 + 480 * (4 / 9))
		near(s.clockTime, 0, 0.01)
	end)
	it("computes phase starts", function()
		eq(TimeCycle.phaseStart(D, 1, "Night"), 900)
		eq(TimeCycle.phaseStart(D, 2, "Dusk"), 1500 + 720)
	end)
	it("night factor rises through dusk and falls through dawn", function()
		near(TimeCycle.nightFactor(TimeCycle.snapshot(D, 810)), 0.5)
		eq(TimeCycle.nightFactor(TimeCycle.snapshot(D, 1000)), 1)
		near(TimeCycle.nightFactor(TimeCycle.snapshot(D, 1440)), 0.5)
	end)
	it("samples keyframes across midnight", function()
		local frames = { { at = 6, values = { 0 } }, { at = 18, values = { 10 } } }
		near(TimeCycle.sampleKeyframes(frames, 12)[1], 5)
		near(TimeCycle.sampleKeyframes(frames, 0)[1], 5)
	end)
	it("uses the configured durations", function()
		local d = GameConfig.Time.Durations
		eq(d.Day, 720)
		eq(d.Dusk, 180)
		eq(d.Night, 480)
		eq(d.Dawn, 120)
	end)
end)

local watcher = CreatureConfig.Archetypes.Watcher.senses
local function vis(overrides: { [string]: any })
	local input = {
		distance = 10,
		angleDegrees = 0,
		hasLineOfSight = true,
		illumination = 1,
		movement = "walk",
		coatEquipped = false,
		weatherVisibility = 1,
		throughWindow = false,
	}
	for k, v in overrides do
		(input :: any)[k] = v
	end
	return Perception.visionScore(watcher, input :: any)
end

describe("Perception", function()
	it("sees nothing without line of sight", function()
		eq(vis({ hasLineOfSight = false }), 0)
	end)
	it("darkness shortens vision range", function()
		truthy(vis({ distance = 50, illumination = 1 }) > 0)
		eq(vis({ distance = 50, illumination = 0 }), 0)
	end)
	it("running is more visible than standing still", function()
		truthy(vis({ movement = "run" }) > vis({ movement = "still" }))
	end)
	it("coat reduces sight of a still player but is not invisibility", function()
		local plain = vis({ movement = "still" })
		local coat = vis({ movement = "still", coatEquipped = true })
		truthy(coat < plain)
		truthy(coat > 0, "coat must not be an invisibility flag")
	end)
	it("coat suppresses the presence sense", function()
		local plain = Perception.presenceScore(watcher, 3, false, true)
		local coat = Perception.presenceScore(watcher, 3, true, true)
		truthy(coat < plain * 0.3)
	end)
	it("dark, still, coated player beside a creature stays below awareness decay", function()
		local cfg = CreatureConfig.Archetypes.Watcher.brain
		local gain = vis({ distance = 3, illumination = 0.05, movement = "still", coatEquipped = true })
			+ Perception.presenceScore(watcher, 3, true, true)
		truthy(gain < cfg.awarenessDecay, "close encounter must be survivable")
	end)
	it("lit, uncoated player beside a creature is found", function()
		local cfg = CreatureConfig.Archetypes.Watcher.brain
		local gain = vis({ distance = 3, illumination = 0.9, movement = "still" })
			+ Perception.presenceScore(watcher, 3, false, true)
		truthy(gain > cfg.awarenessDecay * 2)
	end)
	it("classifies movement", function()
		eq(Perception.movementFromSpeed(0, false), "still")
		eq(Perception.movementFromSpeed(8, true), "sneak")
		eq(Perception.movementFromSpeed(14, false), "walk")
		eq(Perception.movementFromSpeed(24, false), "run")
	end)
end)

local brainCfg = CreatureConfig.Archetypes.Watcher.brain
local function tick(over: { [string]: any }?)
	local tk = { dt = 0.5, active = true, shouldRetreat = false, arrived = false, targetProtected = false }
	if over then
		for k, v in over do
			(tk :: any)[k] = v
		end
	end
	return tk :: any
end

describe("CreatureBrain", function()
	it("wakes from dormant only when active", function()
		local b = CreatureBrain.new(brainCfg)
		CreatureBrain.step(b, tick({ active = false }))
		eq(b.state, "DORMANT")
		CreatureBrain.step(b, tick())
		eq(b.state, "PATROL")
	end)
	it("investigates a heard noise at the reported spot, not the player", function()
		local b = CreatureBrain.new(brainCfg, "PATROL")
		local intent = CreatureBrain.step(b, tick({ heard = { strength = 1, position = "noise-spot" } }))
		truthy(b.state == "INVESTIGATE" or b.state == "SUSPICIOUS")
		for _ = 1, 10 do
			intent = CreatureBrain.step(b, tick())
		end
		eq(b.state, "INVESTIGATE")
		eq(intent.position, "noise-spot")
	end)
	it("searches after arriving, then gives up", function()
		local b = CreatureBrain.new(brainCfg, "INVESTIGATE")
		b.lastKnown = "spot"
		CreatureBrain.step(b, tick({ arrived = true, dt = 1 }))
		eq(b.state, "SEARCH")
		for _ = 1, math.ceil(brainCfg.searchDuration) + 1 do
			CreatureBrain.step(b, tick({ dt = 1 }))
		end
		eq(b.state, "LOST_TARGET")
		for _ = 1, math.ceil(brainCfg.lostTargetTime) + 1 do
			CreatureBrain.step(b, tick({ dt = 1 }))
		end
		eq(b.state, "PATROL")
		eq(b.lastKnown, nil)
	end)
	it("hunts a clearly seen player and chases their seen position", function()
		local b = CreatureBrain.new(brainCfg, "PATROL")
		local intent
		for _ = 1, 20 do
			intent = CreatureBrain.step(
				b,
				tick({ stimulus = { gainPerSecond = 1.5, position = "seen", visible = true, targetId = 7 } })
			)
		end
		eq(b.state, "HUNT")
		eq(intent.kind, "Chase")
		eq(intent.targetId, 7)
	end)
	it("goes to last known position when sight is lost, never the true one", function()
		local b = CreatureBrain.new(brainCfg, "PATROL")
		for _ = 1, 20 do
			CreatureBrain.step(
				b,
				tick({
					stimulus = { gainPerSecond = 1.5, position = "behind-tree", visible = true, targetId = 1 },
				})
			)
		end
		local intent = CreatureBrain.step(b, tick())
		eq(intent.kind, "MoveTo")
		eq(intent.position, "behind-tree")
	end)
	it("stops pursuit at a protected shelter", function()
		local b = CreatureBrain.new(brainCfg, "PATROL")
		for _ = 1, 20 do
			CreatureBrain.step(
				b,
				tick({ stimulus = { gainPerSecond = 1.5, position = "door", visible = true, targetId = 1 } })
			)
		end
		CreatureBrain.step(b, tick({ targetProtected = true }))
		eq(b.state, "LOST_TARGET")
	end)
	it("retreats at dawn and forgets", function()
		local b = CreatureBrain.new(brainCfg, "SEARCH")
		b.lastKnown = "x"
		local intent = CreatureBrain.step(b, tick({ shouldRetreat = true }))
		eq(b.state, "RETREAT")
		eq(intent.kind, "Retreat")
		eq(b.lastKnown, nil)
		CreatureBrain.step(b, tick({ shouldRetreat = true, arrived = true }))
		eq(b.state, "DORMANT")
	end)
	it("memory of a position expires", function()
		local b = CreatureBrain.new(brainCfg, "SUSPICIOUS")
		b.lastKnown = "old"
		b.awareness = 0.2
		for _ = 1, math.ceil(brainCfg.memorySeconds) + 2 do
			CreatureBrain.step(b, tick({ dt = 1 }))
		end
		eq(b.lastKnown, nil)
	end)
end)

local function entry(id: string, over: { [string]: any }?)
	local e = { id = id, kind = "door", installed = true, open = false, health = 100, maxHealth = 100 }
	if over then
		for k, v in over do
			(e :: any)[k] = v
		end
	end
	return e :: any
end

describe("Shelter", function()
	it("is secure when every entry is installed, shut and unbroken", function()
		local ev = Shelter.evaluate({ entry("door"), entry("window", { kind = "window", health = 40 }) })
		truthy(ev.secure)
		eq(ev.weakest, "CRACKED")
	end)
	it("an open door makes it insecure", function()
		local ev = Shelter.evaluate({ entry("door", { open = true }) })
		falsy(ev.secure)
		eq(ev.reasons[1], "door is open")
	end)
	it("a missing door makes it insecure", function()
		falsy(Shelter.evaluate({ entry("door", { installed = false }) }).secure)
	end)
	it("ordinary creatures cannot harm players in a secure shelter", function()
		local ev = Shelter.evaluate({ entry("door") })
		falsy(Shelter.canHarmInside(ev, true))
		falsy(Shelter.canEnter(ev))
		truthy(Shelter.canHarmInside(ev, false))
	end)
	it("maps health to integrity states", function()
		eq(Shelter.integrityFor(100, 100), "INTACT")
		eq(Shelter.integrityFor(90, 100), "SCRATCHED")
		eq(Shelter.integrityFor(60, 100), "DAMAGED")
		eq(Shelter.integrityFor(10, 100), "CRACKED")
		eq(Shelter.integrityFor(0, 100), "BREACHED")
	end)
	it("a lone creature can only scratch a door", function()
		local rules = { groupThreshold = 3, soloDamageFloor = 0.8 }
		local h = 100
		for _ = 1, 1000 do
			h = Shelter.applyAttack(h, 100, 1, 5, 1, 1, rules)
		end
		eq(h, 80)
		eq(Shelter.integrityFor(h, 100), "DAMAGED")
	end)
	it("a coordinated group breaks through, reinforced doors last longer", function()
		local rules = { groupThreshold = 3, soloDamageFloor = 0.8 }
		local function secondsToBreach(resistance: number)
			local h, s = 100, 0
			while h > 0 and s < 10000 do
				h = Shelter.applyAttack(h, 100, 3, 2, resistance, 1, rules)
				s += 1
			end
			return s
		end
		local weak, reinforced = secondsToBreach(1), secondsToBreach(3)
		truthy(weak < 30)
		truthy(reinforced > weak * 2)
	end)
end)

describe("Noise", function()
	it("walls and rain muffle sound", function()
		local open = Noise.attenuation(true, false, false, "Clear")
		local sealed = Noise.attenuation(true, false, true, "Clear")
		local rain = Noise.attenuation(true, false, true, "Rain")
		truthy(sealed < open and rain < sealed)
		eq(Noise.attenuation(false, false, true, "Clear"), 1)
	end)
	it("quiet actions stay quiet, loud ones carry", function()
		eq(Noise.perceivedStrength(Noise.Loudness.crouch, 15, 1, 1), 0)
		truthy(Noise.perceivedStrength(Noise.Loudness.drop, 15, 1, 1) > 0)
		eq(Noise.perceivedStrength(Noise.Loudness.still, 0, 1, 1), 0)
	end)
	it("estimate error grows with distance", function()
		truthy(Noise.positionError(40, 0.2) > Noise.positionError(5, 0.2))
	end)
end)

local mindCfg = GameConfig.Collective
describe("CollectiveMind", function()
	it("one report makes the network aware but not converge", function()
		local m = CollectiveMind.new(mindCfg)
		CollectiveMind.report(
			m,
			{ sector = "cabin", strength = 0.3, position = "p", sourceId = "a", time = 0 }
		)
		CollectiveMind.update(m, 0.1, true)
		eq(CollectiveMind.highestLevel(m), CollectiveMind.Levels.AWARE)
	end)
	it("several creatures with strong evidence converge, then breach on bad nights only", function()
		local function build(allow: boolean)
			local m = CollectiveMind.new(mindCfg)
			for i, id in { "a", "b", "c" } do
				CollectiveMind.report(m, {
					sector = "cabin",
					strength = 0.8,
					position = "p",
					sourceId = id,
					time = i,
					breachable = true,
				})
			end
			CollectiveMind.update(m, 3.1, allow)
			return m
		end
		eq(CollectiveMind.highestLevel(build(true)), CollectiveMind.Levels.BREACHING)
		eq(CollectiveMind.highestLevel(build(false)), CollectiveMind.Levels.CONVERGING)
	end)
	it("evidence fades, the network disperses, then forgets", function()
		local m = CollectiveMind.new(mindCfg)
		CollectiveMind.report(m, { sector = "cabin", strength = 1, position = "p", sourceId = "a", time = 0 })
		CollectiveMind.update(m, 0, true)
		CollectiveMind.update(m, mindCfg.halfLife * 2.2, true)
		eq(CollectiveMind.highestLevel(m), CollectiveMind.Levels.DISPERSING)
		CollectiveMind.update(m, mindCfg.halfLife * 10, true)
		eq(CollectiveMind.highestLevel(m), CollectiveMind.Levels.DORMANT)
	end)
	it("shared position grows less reliable with age", function()
		local m = CollectiveMind.new(mindCfg)
		CollectiveMind.report(m, { sector = "s", strength = 1, position = "p", sourceId = "a", time = 0 })
		CollectiveMind.update(m, 0, true)
		local s = CollectiveMind.strongest(m) :: any
		local fresh = CollectiveMind.uncertainty(m, s)
		CollectiveMind.update(m, 10, true)
		truthy(CollectiveMind.uncertainty(m, s) > fresh)
	end)
	it("a breached house moves to searching", function()
		local m = CollectiveMind.new(mindCfg)
		CollectiveMind.report(
			m,
			{ sector = "cabin", strength = 1.2, position = "p", sourceId = "a", time = 0 }
		)
		CollectiveMind.setBreached(m, "cabin", true)
		CollectiveMind.update(m, 0.1, true)
		eq(CollectiveMind.highestLevel(m), CollectiveMind.Levels.SEARCHING)
	end)
end)

describe("Inventory", function()
	it("adds within caps and spends atomically", function()
		local inv = Inventory.new({ Wood = 10 })
		eq(Inventory.add(inv, "Wood", 15), 10)
		eq(Inventory.add(inv, "Stone", 3), 3)
		falsy(Inventory.spend(inv, { Wood = 5, Stone = 4 }))
		eq(Inventory.count(inv, "Wood"), 10, "failed spend must not change anything")
		truthy(Inventory.spend(inv, { Wood = 5, Stone = 3 }))
		eq(Inventory.count(inv, "Wood"), 5)
		eq(Inventory.count(inv, "Stone"), 0)
	end)
	it("rejects negative, fractional and NaN amounts", function()
		local inv = Inventory.new()
		eq(Inventory.add(inv, "Wood", -5), 0)
		eq(Inventory.add(inv, "Wood", 1.5), 0)
		eq(Inventory.add(inv, "Wood", 0 / 0), 0)
		falsy(Inventory.canAfford(inv, { Wood = -1 }))
	end)
	it("restores only known items with valid amounts", function()
		local inv = Inventory.new({ Wood = 50 })
		Inventory.restore(
			inv,
			{ Wood = 999, Hack = 5, Stone = -3, Fiber = "x" },
			{ Wood = true, Stone = true, Fiber = true }
		)
		eq(Inventory.count(inv, "Wood"), 50)
		eq(Inventory.count(inv, "Hack"), 0)
		eq(Inventory.count(inv, "Stone"), 0)
	end)
	it("losing on capture only takes a fraction", function()
		local inv = Inventory.new()
		Inventory.add(inv, "Wood", 9)
		local lost = Inventory.loseFraction(inv, 0.5, { "Wood" })
		eq(lost.Wood, 4)
		eq(Inventory.count(inv, "Wood"), 5)
	end)
end)

describe("NightClass", function()
	it("scripts the first three nights", function()
		eq(NightClass.classify(1, 0.99, GameConfig.Nights), "Peaceful")
		eq(NightClass.classify(2, 0.99, GameConfig.Nights), "Uneasy")
		eq(NightClass.classify(3, 0.0, GameConfig.Nights), "Bad")
	end)
	it("never rolls a black night before the configured day", function()
		for i = 0, 99 do
			local n = NightClass.classify(4, i / 100, GameConfig.Nights)
			truthy(n ~= "Black")
		end
	end)
	it("matches the configured distribution later", function()
		local counts = { Peaceful = 0, Uneasy = 0, Bad = 0, Black = 0 }
		for i = 0, 999 do
			local n = NightClass.classify(20, (i + 0.5) / 1000, GameConfig.Nights)
			counts[n] += 1
		end
		eq(counts.Peaceful, 450)
		eq(counts.Uneasy, 300)
		eq(counts.Bad, 200)
		eq(counts.Black, 50)
	end)
end)

describe("Comfort", function()
	local base = {
		inside = false,
		shelterSecure = false,
		nearFire = false,
		warmLight = false,
		seated = false,
		dogNear = false,
		pettedRecently = false,
		homeComing = false,
		weatherOutside = "Clear",
		observingSafely = false,
		routineDone = 0,
		upgradesBuilt = 0,
		chasedRecently = false,
		night = true,
	}
	local function with(over: { [string]: any })
		local i = table.clone(base)
		for k, v in over do
			(i :: any)[k] = v
		end
		return Comfort.target(i :: any)
	end
	it("a fire, a dog and rain on the roof beat standing in the dark forest", function()
		local cozy = with({
			inside = true,
			shelterSecure = true,
			nearFire = true,
			dogNear = true,
			weatherOutside = "Rain",
			seated = true,
		})
		local outside = with({})
		truthy(cozy.total > 85, "cozy total " .. cozy.total)
		truthy(outside.total < 20)
		truthy(cozy.weather > 0, "rain outside a secure home is weather coziness")
	end)
	it("rain while outside lowers comfort", function()
		truthy(with({ weatherOutside = "Rain" }).total < with({}).total)
	end)
	it("steps toward target without overshoot", function()
		eq(Comfort.step(10, 20, 1, 5), 15)
		eq(Comfort.step(10, 12, 1, 5), 12)
		eq(Comfort.step(50, 40, 1, 5), 45)
	end)
	it("exposure drops with the coat and stillness", function()
		local run = Comfort.exposure({
			outdoors = true,
			illumination = 0.8,
			movement = "run",
			coatEquipped = false,
			weatherVisibility = 1,
		})
		local hide = Comfort.exposure({
			outdoors = false,
			illumination = 0.05,
			movement = "still",
			coatEquipped = true,
			weatherVisibility = 1,
		})
		truthy(run > 80 and hide < 15)
	end)
end)

describe("LightVisibility", function()
	local function beacon(lights: number, curtains: number, fire: boolean)
		return LightVisibility.houseBeacon({
			electricLightsOn = lights,
			fireLit = fire,
			curtainsOpenFraction = curtains,
			nightFactor = 1,
			weatherVisibility = 1,
		})
	end
	it("orders the lights-off table from the design", function()
		local onOpen = beacon(2, 1, false)
		local onClosed = beacon(2, 0, false)
		local offOpen = beacon(0, 1, true)
		local offClosed = beacon(0, 0, true)
		truthy(onOpen > onClosed and onOpen > offOpen)
		truthy(offClosed < onClosed and offClosed < offOpen)
		truthy(offClosed < 0.05)
		eq(beacon(0, 0, false), 0)
	end)
	it("daylight hides house lights", function()
		eq(
			LightVisibility.houseBeacon({
				electricLightsOn = 3,
				fireLit = true,
				curtainsOpenFraction = 1,
				nightFactor = 0,
				weatherVisibility = 1,
			}),
			0
		)
	end)
	it("illumination combines sky and nearby lights", function()
		near(LightVisibility.illumination(0.1, {}, false), 0.1)
		truthy(
			LightVisibility.illumination(0.1, { { brightness = 1, range = 20, distance = 2 } }, false) > 0.5
		)
	end)
end)

describe("MusicState", function()
	local ctx = {
		menu = false,
		phase = "Day",
		sheltered = false,
		raining = false,
		threat = 0,
		secondsSinceThreat = 999,
		discovery = false,
		lightsOff = false,
		badNight = false,
	}
	local function pick(over: { [string]: any })
		local c = table.clone(ctx)
		for k, v in over do
			(c :: any)[k] = v
		end
		return MusicState.choose(c :: any)
	end
	it("chooses context states", function()
		eq(pick({}), "DAY_EXPLORATION")
		eq(pick({ sheltered = true, raining = true, phase = "Night" }), "HOME_RAIN")
		eq(pick({ sheltered = true, phase = "Night" }), "NIGHT_SAFE")
		eq(pick({ phase = "Night" }), "NIGHT_OUTSIDE")
		eq(pick({ threat = 3 }), "CREATURE_HUNTING")
		eq(pick({ secondsSinceThreat = 5 }), "CREATURE_LOST")
		eq(pick({ phase = "Dawn" }), "DAWN")
		eq(pick({ menu = true, threat = 3 }), "MAIN_MENU")
		eq(pick({ storm = true, phase = "Night", sheltered = true, raining = true }), "STORM_NIGHT")
		eq(pick({ storm = true, phase = "Day", sheltered = true, raining = true }), "HOME_RAIN")
		eq(pick({ storm = true, phase = "Night", threat = 3 }), "CREATURE_HUNTING")
	end)
	it("silence: ambient cues wait for a gap, blackout stays silent", function()
		falsy(MusicState.shouldStartCue("HOME_SAFE", 10, 60, 1, 0))
		truthy(MusicState.shouldStartCue("HOME_SAFE", 90, 60, 0.5, 0.2))
		falsy(MusicState.shouldStartCue("HOME_SAFE", 90, 60, 0.5, 0.8))
		falsy(MusicState.shouldStartCue("BLACKOUT", 999, 0, 1, 0))
		truthy(MusicState.shouldStartCue("CREATURE_HUNTING", 0, 60, 0, 0.9))
	end)
end)

describe("Journal", function()
	it("numbers observations per subject and ignores repeats", function()
		local j = Journal.new()
		local e1 = Journal.record(
			j,
			{ id = "w1", subject = "Watcher", text = "a", day = 1, clock = "21:00", weather = "Rain" }
		)
		eq((e1 :: any).title, "Watcher - Observation #1")
		eq(
			Journal.record(
				j,
				{ id = "w1", subject = "Watcher", text = "a", day = 1, clock = "21:00", weather = "Rain" }
			),
			nil
		)
		local e2 = Journal.record(j, {
			id = "w2",
			subject = "Watcher",
			text = "b",
			day = 2,
			clock = "22:00",
			weather = "Fog",
			certainty = "theory",
		})
		eq((e2 :: any).number, 2)
		eq((e2 :: any).certainty, "theory")
		eq(Journal.count(j), 2)
	end)
	it("formats clock time", function()
		eq(Journal.formatClock(21.5), "21:30")
		eq(Journal.formatClock(0.25), "00:15")
	end)
end)

describe("StoryProgress", function()
	local steps = {
		{ id = "a", text = "Find the cabin", fact = "foundCabin" },
		{ id = "b", text = "Collect wood", fact = "woodGathered", target = 8 },
		{ id = "c", text = "Repair door", fact = "doorRepaired" },
	}
	it("advances in order and labels progress", function()
		local p = StoryProgress.new()
		local facts: { [string]: any } = { woodGathered = 3, doorRepaired = true }
		eq(#StoryProgress.advance(p, steps, facts), 0, "must not skip the first step")
		facts.foundCabin = true
		eq(#StoryProgress.advance(p, steps, facts), 1)
		eq(StoryProgress.label(steps[2], facts), "Collect wood (3/8)")
		facts.woodGathered = 9
		eq(#StoryProgress.advance(p, steps, facts), 2)
		eq(StoryProgress.current(p, steps), nil)
	end)
	it("the shipped story has unique ids and known facts", function()
		local seen = {}
		for _, s in StoryConfig.Steps do
			falsy(seen[s.id], "duplicate step " .. s.id)
			seen[s.id] = true
			truthy(StoryConfig.KnownFacts[s.fact], "unknown fact " .. s.fact)
		end
	end)
end)

describe("Mystery", function()
	it("returns due events in order and swaps in the bad-night script", function()
		local script = GameConfig.LakeHouse
		local events = Mystery.eventsFor(script, 1, "Peaceful")
		local due = Mystery.due(events, 0, 1)
		truthy(#due >= 2)
		for i = 2, #due do
			truthy(due[i - 1].at <= due[i].at)
		end
		local bad = Mystery.eventsFor(script, 3, "Bad")
		eq(bad, script.badNight)
	end)
end)

describe("Breath", function()
	local cfg = Breath.Default
	it("holding drains, running out gasps and forces a cooldown", function()
		local s = Breath.new()
		local ev
		for _ = 1, math.ceil(cfg.capacitySeconds / 0.5) do
			ev = Breath.step(s, true, 0.5, cfg)
			if ev then
				break
			end
		end
		eq(ev, "gasp")
		eq(s.breath, 0)
		falsy(s.holding)
		Breath.step(s, true, 0.5, cfg)
		falsy(s.holding, "cannot hold again during the cooldown")
	end)
	it("an early release is silent, a late one is a soft exhale", function()
		local s = Breath.new()
		Breath.step(s, true, 1, cfg)
		eq(Breath.step(s, false, 0.1, cfg), "release")
		local late = Breath.new()
		for _ = 1, 7 do
			Breath.step(late, true, 1, cfg)
		end
		truthy(Breath.straining(late, cfg) or late.breath < cfg.exhaleBelow)
		eq(Breath.step(late, false, 0.1, cfg), "exhale")
	end)
	it("breath recovers when not holding", function()
		local s = Breath.new()
		s.breath = 0.2
		Breath.step(s, false, 2, cfg)
		truthy(s.breath > 0.2)
		for _ = 1, 20 do
			Breath.step(s, false, 1, cfg)
		end
		eq(s.breath, 1)
	end)
end)

describe("AudioConfig", function()
	it("only uses ids that are empty or built-in content", function()
		local function check(id: string)
			truthy(
				id == ""
					or string.sub(id, 1, 11) == "rbxasset://"
					or string.match(id, "^rbxassetid://%d+$") ~= nil,
				"bad id " .. id
			)
		end
		for _, list in AudioConfig.Music do
			for _, id in list do
				check(id)
			end
		end
		for _, id in AudioConfig.Ambience do
			check(id)
		end
		for _, id in AudioConfig.Cues do
			check(id)
		end
	end)
end)

if not t.report() then
	process.exit(1)
end

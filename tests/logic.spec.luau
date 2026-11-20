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
local FearEcology = require("../src/shared/Logic/FearEcology")
local DogMind = require("../src/shared/Logic/DogMind")
local ChaosField = require("../src/shared/Logic/ChaosField")
local Dissonance = require("../src/shared/Logic/Dissonance")
local DissonanceConfig = require("../src/shared/Config/DissonanceConfig")
local AudioConfig = require("../src/shared/Config/AudioConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local CreatureConfig = require("../src/shared/Config/CreatureConfig")
local StoryConfig = require("../src/shared/Config/StoryConfig")
local RadioConfig = require("../src/shared/Config/RadioConfig")

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
		eq(NightClass.classify(2, 0.99, GameConfig.Nights), "Peaceful")
		eq(NightClass.classify(3, 0.0, GameConfig.Nights), "Uneasy")
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
		eq(counts.Peaceful, 650, "mostly safe nights")
		eq(counts.Uneasy, 250)
		eq(counts.Bad, 90)
		eq(counts.Black, 10)
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

-- Seeded standard normal samples for the field specs.
local function gaussFrom(seed: number): () -> number
	local state = seed
	local function uniform(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	return function(): number
		local u1 = math.max(uniform(), 1e-9)
		local u2 = uniform()
		return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	end
end

local FC = DissonanceConfig.Field
local MODES = DissonanceConfig.Modes
local LEVELS = DissonanceConfig.Levels
local RULES = DissonanceConfig.LevelRules
local SENS = DissonanceConfig.Sensitivity
local HOME = { x = 0, z = 0 }

local function quietEnv(over: { [string]: any }?): ChaosField.Env
	local env: { [string]: any } = { rain = 0, night = 1, collective = 0, creatures = {}, sources = {} }
	for k, v in over or {} do
		env[k] = v
	end
	return env :: any
end

local function run(field: ChaosField.Field, seconds: number, env: ChaosField.Env, seed: number)
	local g = gaussFrom(seed)
	for _ = 1, seconds do
		ChaosField.step(field, 1, env, g)
	end
end

local function levelAt(
	field: ChaosField.Field,
	mode: string,
	sens: number,
	noise: number
): (string, ChaosField.Reading)
	local r = ChaosField.read(field, HOME.x, HOME.z, MODES[mode], sens, SENS.min, SENS.max, noise)
	return ChaosField.level(LEVELS, RULES, r.ceu, r.uncertainty, nil), r
end

local function idx(name: string): number
	return ChaosField.levelIndex(LEVELS, name)
end

describe("ChaosField", function()
	it("covers the map with sectors and maps positions to them", function()
		local f = ChaosField.new(FC)
		eq(#f.list, f.cols * f.cols)
		local s = ChaosField.sectorAt(f, 5, -5)
		truthy(math.abs(s.x - 5) <= FC.sectorSize / 2 and math.abs(s.z + 5) <= FC.sectorSize / 2)
		eq(ChaosField.keyFor(f, -5000, 5000), "0_" .. (f.cols - 1))
	end)
	it("drifts on a peaceful night with no creatures and no anomalies", function()
		local f = ChaosField.new(FC)
		local s = ChaosField.sectorAt(f, 0, 0)
		local g = gaussFrom(11)
		local lo, hi = math.huge, -math.huge
		for _ = 1, 900 do
			ChaosField.step(f, 1, quietEnv(), g)
			lo, hi = math.min(lo, s.current), math.max(hi, s.current)
		end
		truthy(hi - lo > 1.5, "the field should wander a little")
		truthy(hi < LEVELS[3].from, "a quiet night never reaches DISTURBANCE")
	end)
	it("calm rain alone stays at or below DRIFT", function()
		for seed = 1, 6 do
			local f = ChaosField.new(FC)
			local g = gaussFrom(seed * 97)
			for _ = 1, 1500 do
				ChaosField.step(f, 1, quietEnv({ rain = 2.4 }), g)
				for _, s in f.list do
					truthy(s.current < LEVELS[3].from, "rain made sector " .. s.key .. " read " .. s.current)
				end
			end
		end
	end)
	it("a storm alone stays below CONVERGENCE and only makes readings less certain", function()
		local calm = ChaosField.new(FC)
		local storm = ChaosField.new(FC)
		run(calm, 1200, quietEnv({ rain = 1.5 }), 5)
		run(storm, 1200, quietEnv({ rain = 4.8 }), 5)
		for _, s in storm.list do
			truthy(s.current < LEVELS[4].from, "storm sector " .. s.current)
		end
		local _, rc = levelAt(calm, "LOCAL", 3, 0)
		local _, rs = levelAt(storm, "LOCAL", 3, 0)
		truthy(rs.uncertainty > rc.uncertainty)
		eq((levelAt(storm, "REGIONAL", 2, 0)), "UNKNOWN")
	end)
	it("a creature-heavy field can read STABLE: energy is not a monster count", function()
		local f = ChaosField.new(FC)
		local calm = {}
		for i = 1, 6 do
			table.insert(calm, { x = i * 10, z = 0, energy = 0, hunger = 0 })
		end
		run(f, 600, quietEnv({ night = 0, creatures = calm }), 3)
		eq((levelAt(f, "LOCAL", 3, 0)), "STABLE")
	end)
	it("fed, hungry creatures raise the field slowly, never at once", function()
		local f = ChaosField.new(FC)
		local s = ChaosField.sectorAt(f, 0, 0)
		local fed = { { x = s.x, z = s.z, energy = 1, hunger = 1 } }
		local steady = FC.creatureEnergy + FC.creatureHunger
		ChaosField.step(f, 1, quietEnv({ creatures = fed }), function()
			return 0
		end)
		truthy(s.creature < steady * 0.1, "the creature term is lagged")
		run(f, 300, quietEnv({ creatures = fed }), 4)
		near(s.creature, steady, steady * 0.05)
	end)
	it("a zero-creature field still produces anomalies", function()
		local f = ChaosField.new(FC)
		local home = ChaosField.sectorAt(f, 0, 0)
		local src = { { x = home.x, z = home.z, strength = 30, void = false } }
		run(f, 120, quietEnv({ rain = 2, sources = src }), 8)
		local level, r = levelAt(f, "LOCAL", 3, 0)
		truthy(idx(level) >= idx("DISTURBANCE"), "local read " .. r.ceu)
		truthy(r.irregularity > 0.4, "an anomaly makes the trace irregular")
	end)
	it("regional is approximate: a local anomaly barely moves it", function()
		local f = ChaosField.new(FC)
		local home = ChaosField.sectorAt(f, 0, 0)
		run(
			f,
			120,
			quietEnv({ rain = 2, sources = { { x = home.x, z = home.z, strength = 30, void = false } } }),
			8
		)
		local _, rl = levelAt(f, "LOCAL", 3, 0)
		local regional, rr = levelAt(f, "REGIONAL", 3, 0)
		truthy(rr.ceu < rl.ceu - 15, "regional " .. rr.ceu .. " vs local " .. rl.ceu)
		truthy(idx(regional) <= idx("DRIFT"), "regional reads " .. regional)
		eq(rr.ceu % 5, 0)
	end)
	it("a void drops the reading to exactly zero and the level to UNKNOWN", function()
		local f = ChaosField.new(FC)
		local home = ChaosField.sectorAt(f, 0, 0)
		run(f, 60, quietEnv({ rain = 2 }), 2)
		run(
			f,
			12,
			quietEnv({ rain = 2, sources = { { x = home.x, z = home.z, strength = 0, void = true } } }),
			2
		)
		local level, r = levelAt(f, "LOCAL", 3, 1.5)
		eq(r.ceu, 0)
		eq(level, "UNKNOWN")
	end)
	it("higher sensitivity lowers measurement noise", function()
		local f = ChaosField.new(FC)
		local lo = ChaosField.read(f, 0, 0, MODES.LOCAL, SENS.min, SENS.min, SENS.max, 0)
		local hi = ChaosField.read(f, 0, 0, MODES.LOCAL, SENS.max, SENS.min, SENS.max, 0)
		truthy(hi.uncertainty < lo.uncertainty)
	end)
	it("levels have hysteresis and an UNKNOWN state", function()
		eq(ChaosField.level(LEVELS, RULES, 37, 1, nil), "DISTURBANCE")
		eq(ChaosField.level(LEVELS, RULES, 34, 1, "DISTURBANCE"), "DISTURBANCE")
		eq(ChaosField.level(LEVELS, RULES, 31, 1, "DISTURBANCE"), "DRIFT")
		eq(ChaosField.level(LEVELS, RULES, 85, 1, nil), "THRESHOLD")
		eq(ChaosField.level(LEVELS, RULES, 40, RULES.unknownUncertainty, nil), "UNKNOWN")
		eq(ChaosField.level(LEVELS, RULES, 0, 1, "STABLE"), "UNKNOWN")
	end)
end)

local AC = DissonanceConfig.Anomaly
local SC = DissonanceConfig.Scan

local function runAnomaly(a: Dissonance.Anomaly, signature: number): { string }
	local all = {}
	for _ = 1, 600 do
		for _, b in Dissonance.step(a, 1, signature, AC) do
			table.insert(all, b)
		end
		if a.stage == "DONE" then
			break
		end
	end
	return all
end

local function position(list: { string }, value: string): number
	for i, v in list do
		if v == value then
			return i
		end
	end
	return 0
end

local function ctx(over: { [string]: any }?): Dissonance.Context
	local c: { [string]: any } = {
		family = "Arrival",
		atHome = true,
		scopeOn = true,
		night = true,
		dogNear = true,
		mayaLit = true,
		electric = true,
		flickered = false,
		peaked = true,
		ghostDone = false,
	}
	for k, v in over or {} do
		c[k] = v
	end
	return c :: any
end

describe("Dissonance", function()
	it("an Arrival walks its stages in order, transmits, and ends", function()
		local a = Dissonance.newAnomaly(1, "Arrival", 0, 0, AC, { 0.5, 0.5, 0.5, 0.5 })
		local beats = runAnomaly(a, 0)
		eq(a.stage, "DONE")
		local pa, pp, pf, pd =
			position(beats, "active"),
			position(beats, "peak"),
			position(beats, "fade"),
			position(beats, "done")
		truthy(pa > 0 and pa < pp and pp < pf and pf < pd, table.concat(beats, ","))
		truthy(position(beats, "transmit") > 0)
		truthy(a.peaked)
	end)
	it("stage lengths differ from one anomaly to the next", function()
		local a = Dissonance.newAnomaly(1, "Arrival", 0, 0, AC, { 0.1, 0.9, 0.3, 0.7 })
		local b = Dissonance.newAnomaly(2, "Arrival", 0, 0, AC, { 0.8, 0.2, 0.6, 0.1 })
		truthy(a.durations.ONSET ~= b.durations.ONSET and a.durations.ACTIVE ~= b.durations.ACTIVE)
		truthy(a.durations.ONSET >= AC.stages.ONSET[1] and a.durations.ONSET <= AC.stages.ONSET[2])
	end)
	it("scanning hard feeds the anomaly and makes it coherent sooner", function()
		local quiet = Dissonance.newAnomaly(1, "Arrival", 0, 0, AC, { 0.5, 0.5, 0.5, 0.5 })
		local loud = Dissonance.newAnomaly(2, "Arrival", 0, 0, AC, { 0.5, 0.5, 0.5, 0.5 })
		for _ = 1, math.floor(quiet.durations.ONSET + 30) do
			Dissonance.step(quiet, 1, 0, AC)
			Dissonance.step(loud, 1, 0.35, AC)
		end
		truthy(loud.strength > quiet.strength)
		truthy(loud.coherence > quiet.coherence)
		truthy(loud.feed <= AC.feedMax)
	end)
	it("the Absence rises, drops to a void, then goes silent", function()
		local a = Dissonance.newAnomaly(1, "Absence", 0, 0, AC, { 0.5, 0.5, 0.5, 0.5 })
		local rose, sawVoid = 0, false
		local beats = {}
		for _ = 1, 600 do
			for _, b in Dissonance.step(a, 1, 0, AC) do
				table.insert(beats, b)
			end
			rose = math.max(rose, a.envelope)
			if a.stage == "PEAK" then
				sawVoid = a.void and Dissonance.source(a).void and a.envelope == 0
			end
			if a.stage == "DONE" then
				break
			end
		end
		truthy(rose > 0.8)
		truthy(sawVoid)
		truthy(position(beats, "drop") > 0 and position(beats, "drop") < position(beats, "silence"))
		eq(position(beats, "transmit"), 0)
	end)
	it("the Echo replays at envelope steps", function()
		local a = Dissonance.newAnomaly(1, "Echo", 0, 0, AC, { 0.5, 0.5, 0.5, 0.5 })
		local n = 0
		for _, b in runAnomaly(a, 0) do
			if b == "echo" then
				n += 1
			end
		end
		eq(n, #AC.echoSteps)
	end)
	it("the Arrival's line gets clearer; the rare line is rare and gated", function()
		local low = Dissonance.arrivalLine(0.1, 0.99, 42, false, AC)
		truthy(low ~= Dissonance.ARRIVAL and string.find(low, "-", 1, true) ~= nil)
		eq(#low, #Dissonance.ARRIVAL)
		eq((Dissonance.arrivalLine(0.9, 0.99, 42, false, AC)), Dissonance.ARRIVAL)
		local line, rare = Dissonance.arrivalLine(1, 0, 42, false, AC)
		eq(line, Dissonance.ARRIVAL)
		falsy(rare)
		line, rare = Dissonance.arrivalLine(0.95, 0.1, 42, true, AC)
		eq(line, Dissonance.NO_OUTSIDE)
		truthy(rare)
		eq((Dissonance.arrivalLine(0.95, 0.5, 42, true, AC)), Dissonance.ARRIVAL)
		eq((Dissonance.arrivalLine(0.6, 0, 42, true, AC)) == Dissonance.NO_OUTSIDE, false)
	end)
	it("the Echo never keeps the original timing", function()
		local times = { 0, 1, 2.5, 3.1 }
		for seed = 1, 40 do
			local plan = Dissonance.echoPlan(times, seed, 3)
			eq(#plan, 3)
			for k = 2, #plan do
				local original = math.abs(times[plan[k].index] - times[plan[k - 1].index])
				local replay = plan[k].delay - plan[k - 1].delay
				local ratio = replay / math.max(original, 0.2)
				truthy(ratio < 0.8 or ratio > 1.25, "seed " .. seed .. " kept a gap: " .. ratio)
			end
			for _, s in plan do
				truthy(s.speed < 1 and s.index >= 2)
			end
		end
		eq(#Dissonance.echoPlan({}, 1, 3), 0)
	end)
	it("the scan signature is zero when off or passive and grows with sensitivity", function()
		eq(Dissonance.signature(false, MODES.LOCAL.signature, 5, SENS.min, SENS.max), 0)
		eq(Dissonance.signature(true, MODES.PASSIVE.signature, 5, SENS.min, SENS.max), 0)
		local s2 = Dissonance.signature(true, MODES.LOCAL.signature, 2, SENS.min, SENS.max)
		local s5 = Dissonance.signature(true, MODES.LOCAL.signature, 5, SENS.min, SENS.max)
		truthy(s2 < SC.threshold and s5 >= SC.threshold)
		truthy(Dissonance.signature(true, MODES.REGIONAL.signature, 5, SENS.min, SENS.max) > s5)
	end)
	it("the emitter warms, blinks, pulses once, then cools down", function()
		local e = Dissonance.newEmitter()
		local sig = Dissonance.signature(true, MODES.LOCAL.signature, 5, SENS.min, SENS.max)
		eq(Dissonance.emitterLamp(e, sig, SC), "warm")
		local pulses, blinked, firstPulse = 0, false, 0
		for t = 1, 120 do
			if Dissonance.stepEmitter(e, 1, sig, SC) then
				pulses += 1
				firstPulse = if firstPulse == 0 then t else firstPulse
				eq(Dissonance.emitterLamp(e, sig, SC), "pulse")
			elseif pulses == 0 and Dissonance.emitterLamp(e, sig, SC) == "blink" then
				blinked = true
			end
		end
		truthy(blinked, "the lamp blinks before the pulse")
		truthy(firstPulse > 10, "a pulse is never instant")
		eq(pulses, 2) -- the second only after the full cooldown
		local low = Dissonance.newEmitter()
		for _ = 1, 600 do
			falsy(Dissonance.stepEmitter(low, 1, SC.threshold * 0.9, SC))
		end
	end)
	it("the director answers beats within its gates and cooldowns", function()
		local cd = DissonanceConfig.Director.cooldowns
		local last = {}
		eq(Dissonance.choose("transmit", ctx(), last, 0, 0, cd, 0.5), "transmission")
		eq(Dissonance.choose("transmit", ctx(), last, 1, 0, cd, 0.5), nil) -- cooling down
		eq(Dissonance.choose("transmit", ctx({ scopeOn = false }), {}, 0, 0, cd, 0.5), nil)
		eq(Dissonance.choose("peak", ctx(), {}, 0, 0, cd, 0.5), "flicker")
		truthy(Dissonance.choose("peak", ctx({ flickered = true }), {}, 0, 0, cd, 0.5) ~= "flicker")
		truthy(Dissonance.choose("peak", ctx({ electric = false }), {}, 0, 0, cd, 0.5) ~= "flicker")
		eq(Dissonance.choose("level_DRIFT", ctx(), {}, 0, 0.99, cd, 0.5), nil) -- "none" can win
		eq(Dissonance.choose("level_DISTURBANCE", ctx({ atHome = false }), {}, 0, 0, cd, 0.5), nil)
		eq(Dissonance.choose("scopeOff", ctx({ scopeOn = false }), {}, 0, 0.1, cd, 0.5), "ghostNeedle")
		eq(Dissonance.choose("scopeOff", ctx({ scopeOn = false, peaked = false }), {}, 0, 0.1, cd, 0.5), nil)
		eq(
			Dissonance.choose("scopeOff", ctx({ scopeOn = false, ghostDone = true }), {}, 0, 0.1, cd, 0.5),
			nil
		)
		eq(Dissonance.choose("peak", ctx({ family = "Echo" }), {}, 0, 0, cd, 0.5), "echo")
	end)
	it("every director event is nonviolent and has a cooldown", function()
		local safe = {
			none = true,
			transmission = true,
			radio = true,
			window = true,
			flicker = true,
			hush = true,
			maya = true,
			dogRouse = true,
			dogWatch = true,
			dogGrowl = true,
			echo = true,
			ghostNeedle = true,
			relax = true,
		}
		local beats = { "level_DRIFT", "level_DISTURBANCE", "level_HIGH", "transmit", "peak", "echo" }
		for _, b in { "drop", "silence", "fade", "done", "scopeOff" } do
			table.insert(beats, b)
		end
		for _, family in Dissonance.Families do
			for _, b in beats do
				for _, rule in Dissonance.rulesFor(b, family, 0.5) or {} do
					local event = rule.event
					truthy(safe[event], event)
					truthy(event == "none" or DissonanceConfig.Director.cooldowns[event] ~= nil, event)
				end
			end
		end
	end)
	it("config is ordered and the passive mode is silent", function()
		for i = 2, #LEVELS do
			truthy(LEVELS[i].from > LEVELS[i - 1].from)
		end
		eq(MODES.PASSIVE.signature, 0)
		truthy(MODES.PASSIVE.range < MODES.LOCAL.range and MODES.LOCAL.range < MODES.REGIONAL.range)
		for _, id in AudioConfig.Chaoscope do
			truthy(id == "" or string.match(id, "^rbxassetid://%d+$") ~= nil, id)
		end
	end)
end)

describe("FearEcology", function()
	local cfg = CreatureConfig.Fear
	local quiet = {
		threat = 0,
		chased = false,
		sawCreature = false,
		exposedDark = false,
		unexplainedSound = false,
		secureShelter = false,
		nearDog = false,
		nearFire = false,
		nearMaya = false,
	}
	local function with(changes: { [string]: any }): any
		local i = table.clone(quiet) :: any
		for k, v in changes do
			i[k] = v
		end
		return i
	end
	it("fear comes from fictional danger signals and stays within 0..1", function()
		eq(FearEcology.target(quiet), 0)
		truthy(FearEcology.target(with({ threat = 2 })) > FearEcology.target(with({ threat = 1 })))
		local worst = with({
			threat = 3,
			chased = true,
			sawCreature = true,
			exposedDark = true,
			unexplainedSound = true,
		})
		eq(FearEcology.target(worst), 1)
	end)
	it("home, the dog, the fire and Maya calm a character", function()
		local scared = with({ threat = 2, sawCreature = true })
		local held =
			with({ threat = 2, sawCreature = true, secureShelter = true, nearDog = true, nearFire = true })
		truthy(FearEcology.target(held) < FearEcology.target(scared))
		eq(FearEcology.target(with({ secureShelter = true, nearMaya = true })), 0)
	end)
	it("fear rises fast and fades slowly", function()
		local up = FearEcology.step(0, 1, 1, cfg)
		local down = 1 - FearEcology.step(1, 0, 1, cfg)
		truthy(up > down)
		eq(FearEcology.step(0.5, 0.5, 1, cfg), 0.5)
	end)
	it("names the fear states, with recovery while it fades", function()
		eq(FearEcology.state(0.05, false), "CALM")
		eq(FearEcology.state(0.25, false), "UNEASY")
		eq(FearEcology.state(0.5, false), "ALARMED")
		eq(FearEcology.state(0.7, false), "TERRIFIED")
		eq(FearEcology.state(0.9, false), "PANICKED")
		eq(FearEcology.state(0.4, true), "RECOVERING")
	end)
	it("only nearby fear feeds a creature, closer is richer", function()
		eq(FearEcology.intake(1, cfg.feedRange + 1, cfg), 0)
		truthy(FearEcology.intake(1, 10, cfg) > FearEcology.intake(1, 60, cfg))
	end)
	it("calm people starve a creature back to nothing", function()
		local e, h = 0.8, 0.8
		for _ = 1, 400 do
			e, h = FearEcology.feed(e, h, 0, 0.5, cfg)
		end
		eq(e, 0)
		eq(h, 0)
	end)
	it("feeding has diminishing returns and a crowd is capped", function()
		local lowE = FearEcology.feed(0.1, 0, 1, 1, cfg) - 0.1
		local highE = FearEcology.feed(0.8, 0, 1, 1, cfg) - 0.8
		truthy(lowE > highE)
		local one = FearEcology.feed(0, 0, 1, 1, cfg)
		local crowd = FearEcology.feed(0, 0, 5, 1, cfg)
		eq(one, crowd)
		local e = 0
		for _ = 1, 2000 do
			e = FearEcology.feed(e, 0, 1, 0.5, cfg)
		end
		truthy(e < 1, "constant terror never reaches full power")
	end)
	it("energy makes it bolder, within bounds, for every temperament", function()
		for name, p in CreatureConfig.Temperaments do
			local calm = FearEcology.mods(0, 0, p)
			local fed = FearEcology.mods(1, 1, p)
			truthy(fed.dashChance >= calm.dashChance, name)
			truthy(fed.noiseInterval <= calm.noiseInterval, name)
			truthy(fed.dashChance <= 0.9 and fed.displaceChance <= 0.2, name)
			truthy(fed.stareSeconds <= 40 and calm.stareSeconds >= 6, name)
			truthy(fed.seeksPeople and not calm.seeksPeople, name)
		end
	end)
	it("every species' temperament odds name real temperaments", function()
		for kind, odds in CreatureConfig.TemperamentOdds do
			truthy(CreatureConfig.Archetypes[kind] ~= nil, kind)
			for name in odds do
				truthy(CreatureConfig.Temperaments[name] ~= nil, kind .. "." .. name)
			end
		end
	end)
end)

describe("DogMind", function()
	local cfg = DogMind.Default
	local all = { heard = true, seen = true, presence = true }
	local none = { heard = false, seen = false, presence = false }
	local alone = {
		ownerNear = false,
		concealed = false,
		mayaNear = false,
		inShelter = false,
		thunder = false,
		startle = 0,
	}
	it("senses closer things more strongly, and nothing he cannot sense", function()
		local m = DogMind.new()
		truthy(DogMind.signal(m, "Watcher", 10, all) > DogMind.signal(m, "Watcher", 60, all))
		eq(DogMind.signal(m, "Watcher", 10, none), 0)
		eq(DogMind.signal(m, "Watcher", 40, { heard = false, seen = false, presence = true }), 0)
		truthy(DogMind.signal(m, "Wildlife", 10, all) < DogMind.signal(m, "Crawler", 10, all))
	end)
	it("familiarity softens a kind but never makes him fearless", function()
		local m = DogMind.new()
		local fresh = DogMind.signal(m, "Watcher", 20, all)
		for _ = 1, 20 do
			DogMind.learn(m, "Watcher")
		end
		local known = DogMind.signal(m, "Watcher", 20, all)
		truthy(known < fresh and known > 0)
		eq(DogMind.signal(m, "Dweller", 20, all), DogMind.signal(DogMind.new(), "Dweller", 20, all))
	end)
	it("rises quickly, settles slowly, and holds its level in the band", function()
		local m = DogMind.new()
		DogMind.step(m, 1, 1, cfg)
		local up = m.agitation
		local m2 = DogMind.new()
		m2.agitation = 1
		DogMind.step(m2, 0, 1, cfg)
		truthy(up > 1 - m2.agitation)
		local h = DogMind.new()
		h.agitation = 0.45
		DogMind.step(h, 0.45, 0.1, cfg)
		eq(h.level, 2)
		h.agitation = 0.33 -- below up[2] but above down[2]: still suspicious
		DogMind.step(h, 0.33, 0.01, cfg)
		eq(h.level, 2)
		h.agitation = 0.2
		DogMind.step(h, 0.2, 0.01, cfg)
		eq(h.level, 1)
	end)
	it("barks only when panicked; training and the coat make it rare, not impossible", function()
		local m = DogMind.new()
		m.level = 3
		eq(DogMind.barkChance(m, false, 1, cfg), 0)
		m.level = 4
		local raw = DogMind.barkChance(m, false, 1, cfg)
		local hidden = DogMind.barkChance(m, true, 1, cfg)
		truthy(hidden > 0 and hidden < raw * 0.2)
		DogMind.train(m, "quietness", 1)
		truthy(DogMind.barkChance(m, false, 1, cfg) < raw)
	end)
	it("a Watcher tapping at the glass can make an untrained dog bark", function()
		local m = DogMind.new()
		local signal = DogMind.signal(m, "Watcher", 6, all)
		local indoors = table.clone(alone)
		indoors.inShelter = true
		eq(DogMind.target(m, signal, indoors) < cfg.up[4], true, "without a sudden sound he only growls")
		indoors.startle = 0.35
		for _ = 1, 20 do
			DogMind.step(m, DogMind.target(m, signal, indoors), 0.5, cfg)
		end
		eq(m.level, 4)
		truthy(DogMind.barkChance(m, false, 1, cfg) > 0)
	end)
	it("calming helps step by step, less with a threat close", function()
		local m = DogMind.new()
		m.agitation = 1
		local far = DogMind.calm(m, false, cfg)
		truthy(far > 0 and far <= cfg.calmStep)
		truthy(m.agitation > 0.5, "one calm never erases panic")
		local m2 = DogMind.new()
		m2.agitation = 1
		truthy(DogMind.calm(m2, true, cfg) < far)
	end)
	it("his person, the coat and Maya soothe him; thunder unsettles him", function()
		local m = DogMind.new()
		local base = DogMind.target(m, 0.8, alone)
		local held = DogMind.target(m, 0.8, {
			ownerNear = true,
			concealed = true,
			mayaNear = false,
			inShelter = true,
			thunder = false,
			startle = 0,
		})
		truthy(held < base * 0.5)
		truthy(DogMind.target(m, 0, {
			ownerNear = false,
			concealed = false,
			mayaNear = false,
			inShelter = false,
			thunder = true,
			startle = 0,
		}) > 0)
		eq(DogMind.state(m, true), "CONCEALED")
		eq(DogMind.state(m, false), "RELAXED")
	end)
end)

describe("NightStories", function()
	local KNOWN =
		{ quiet = true, stays = true, visit = true, distant = true, passerby = true, mayaSilent = true }
	it("only names stories the director can tell, and only for ordinary nights", function()
		for nightType, weights in GameConfig.NightStories do
			truthy(nightType == "Peaceful" or nightType == "Uneasy", nightType)
			for name, w in weights do
				truthy(KNOWN[name], "unknown story " .. name)
				truthy(w > 0, name)
			end
		end
	end)
	it("peaceful nights are mostly quiet or harmless", function()
		local w = GameConfig.NightStories.Peaceful
		truthy(w.visit == nil, "no house visits on a peaceful night")
		truthy(w.quiet >= 40)
	end)
end)

describe("RadioConfig", function()
	local CONDITIONS = {
		morning = true,
		day = true,
		evening = true,
		night = true,
		dawn = true,
		clear = true,
		fog = true,
		rain = true,
		storm = true,
		badNight = true,
		uneasy = true,
		peaceful = true,
		creatureNear = true,
		watcherNear = true,
		crawlerNear = true,
		creatureFed = true,
		oldOne = true,
		cabinLit = true,
		cabinDark = true,
		dogAlert = true,
		scared = true,
		mayaKnown = true,
		mayaLit = true,
	}
	it("every line needs only real conditions or known story facts", function()
		for _, line in RadioConfig.Lines do
			truthy(#line.text > 0 and #line.need > 0, line.text)
			for _, need in line.need do
				local key = if string.sub(need, 1, 1) == "!" then string.sub(need, 2) else need
				if string.sub(key, 1, 5) == "fact:" then
					truthy(StoryConfig.KnownFacts[string.sub(key, 6)] ~= nil, "unknown fact " .. key)
				else
					truthy(CONDITIONS[key], "unknown condition " .. key)
				end
			end
		end
	end)
	it("has a report and a forecast word for every weather", function()
		for label in GameConfig.Weather.Visibility do
			truthy(RadioConfig.Weather[label] ~= nil, label)
			truthy(RadioConfig.Forecast[label] ~= nil, label)
		end
		truthy(RadioConfig.Forecast.Unknown ~= nil)
	end)
end)

if not t.report() then
	process.exit(1)
end

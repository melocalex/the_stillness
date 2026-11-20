--!strict
-- Caramelo's inner state (Chapter 38). Pure: no requires, no Roblox APIs.
--
-- Agitation (0..1) drifts toward a target built from what he senses. It
-- rises quickly and settles slowly. Warning levels use hysteresis, so he
-- never flickers between calm and panic:
--   0 relaxed  1 attentive (head up)  2 suspicious (growls, watches)
--   3 frightened (whimpers, seeks you or a hiding place)  4 panicked (barks)
-- Training and familiarity soften his reactions without making him
-- fearless; hiding under your coat calms him and quiets him, but a bark
-- under the coat is still a bark.

local DogMind = {}

export type Mind = {
	agitation: number,
	level: number,
	peak: number, -- highest level since he was last relaxed
	familiarity: { [string]: number }, -- per creature kind, 0..0.8
	quietness: number, -- training, 0..1
	sharedHiding: number, -- training, 0..1
	awareness: number, -- training, 0..1
	bond: number, -- 0..1
}

export type Senses = { heard: boolean, seen: boolean, presence: boolean }

export type Context = {
	ownerNear: boolean,
	concealed: boolean,
	mayaNear: boolean,
	inShelter: boolean,
	thunder: boolean,
}

export type Config = {
	riseRate: number,
	fallRate: number,
	up: { number }, -- agitation needed to climb to levels 1..4
	down: { number }, -- agitation below which he drops from levels 1..4
	barkPerSecond: number, -- at level 4, untrained, not concealed
	calmStep: number,
}

DogMind.Default = {
	riseRate = 0.35,
	fallRate = 0.06,
	up = { 0.18, 0.38, 0.6, 0.82 },
	down = { 0.1, 0.28, 0.48, 0.7 },
	barkPerSecond = 0.35,
	calmStep = 0.22,
} :: Config

-- How much each kind unsettles him at close range.
DogMind.KindWeight =
	{ Watcher = 0.8, Dweller = 0.9, Crawler = 1.0, Wildlife = 0.25, Wind = 0.2 } :: { [string]: number }

function DogMind.new(): Mind
	return {
		agitation = 0,
		level = 0,
		peak = 0,
		familiarity = {},
		quietness = 0,
		sharedHiding = 0,
		awareness = 0,
		bond = 0.5,
	}
end

-- One source's pull on him, 0..1. He hears and sees much further than he
-- senses presence; awareness training stretches his range a little.
function DogMind.signal(mind: Mind, kind: string, distance: number, s: Senses): number
	local range = 0
	if s.presence then
		range = math.max(range, 30)
	end
	if s.heard then
		range = math.max(range, 70)
	end
	if s.seen then
		range = math.max(range, 90)
	end
	range *= 1 + 0.3 * mind.awareness
	if range <= 0 or distance >= range then
		return 0
	end
	local closeness = 1 - distance / range
	local familiar = 1 - (mind.familiarity[kind] or 0)
	return math.clamp((DogMind.KindWeight[kind] or 0.5) * closeness * familiar, 0, 1)
end

-- Where his agitation is heading, given the strongest signal and context.
function DogMind.target(mind: Mind, signal: number, c: Context): number
	local t = signal
	if c.thunder then
		t = math.max(t, 0.3)
	end
	local soothe = 1
	if c.ownerNear then
		soothe *= 0.85 - 0.15 * mind.bond
	end
	if c.concealed then
		soothe *= 0.45 - 0.2 * mind.sharedHiding
	end
	if c.mayaNear then
		soothe *= 0.8
	end
	if c.inShelter then
		soothe *= 0.9
	end
	return math.clamp(t * soothe, 0, 1)
end

-- Moves agitation toward the target, then the level with hysteresis.
function DogMind.step(mind: Mind, target: number, dt: number, cfg: Config)
	local a = mind.agitation
	if target > a then
		a = math.min(target, a + cfg.riseRate * dt)
	else
		a = math.max(target, a - cfg.fallRate * dt)
	end
	mind.agitation = a
	local level = mind.level
	while level < 4 and a >= cfg.up[level + 1] do
		level += 1
	end
	while level > 0 and a < cfg.down[level] do
		level -= 1
	end
	mind.level = level
	if level == 0 then
		mind.peak = 0
	else
		mind.peak = math.max(mind.peak, level)
	end
end

-- Chance he barks during dt. Only when panicked; training and the coat make
-- it much rarer, never impossible.
function DogMind.barkChance(mind: Mind, concealed: boolean, dt: number, cfg: Config): number
	if mind.level < 4 then
		return 0
	end
	local p = cfg.barkPerSecond * (1 - 0.7 * mind.quietness)
	if concealed then
		p *= 0.15
	end
	return math.clamp(p * dt, 0, 1)
end

-- One calming moment from his person. Never erases panic in one go; a near
-- threat halves it. Returns how much it helped.
function DogMind.calm(mind: Mind, threatNear: boolean, cfg: Config): number
	local amount = cfg.calmStep * (0.6 + 0.4 * mind.bond) * (if threatNear then 0.5 else 1)
	local before = mind.agitation
	mind.agitation = math.max(0, before - amount)
	return before - mind.agitation
end

-- After a creature of this kind came close and left without harm, he takes
-- it a little less hard next time. Never fearless.
function DogMind.learn(mind: Mind, kind: string)
	mind.familiarity[kind] = math.min(0.8, (mind.familiarity[kind] or 0) + 0.1)
end

function DogMind.train(mind: Mind, skill: string, amount: number)
	if skill == "quietness" then
		mind.quietness = math.min(1, mind.quietness + amount)
	elseif skill == "sharedHiding" then
		mind.sharedHiding = math.min(1, mind.sharedHiding + amount)
	elseif skill == "awareness" then
		mind.awareness = math.min(1, mind.awareness + amount)
	end
end

local NAMES = { "RELAXED", "ALERT", "SUSPICIOUS", "AFRAID", "PANICKED" }

function DogMind.state(mind: Mind, concealed: boolean): string
	if concealed then
		return "CONCEALED"
	end
	if mind.level == 0 and mind.peak == 0 and mind.agitation > 0.05 then
		return "RECOVERING"
	end
	return NAMES[mind.level + 1]
end

return DogMind

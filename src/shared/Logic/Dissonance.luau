--!strict
-- Pure rules of the Dissonance (Chapter 36): anomaly lifecycles for the three
-- signal families, the Arrival's transmission lines, the Echo's wrong timing,
-- the active-scan signature, and which nonvisual event (if any) answers each
-- anomaly beat. No requires, no Roblox APIs: randomness comes in as numbers.
--
-- Families:
--   Arrival  an intermittent transmission that slowly becomes coherent.
--   Echo     recent in-game sounds replayed with the wrong timing.
--   Absence  energy rises, drops to zero, then an unusual silence.
--
-- Every anomaly runs ONSET -> ACTIVE -> PEAK -> FADE -> DONE with stage
-- lengths drawn per anomaly. The director reacts to beats (stage changes,
-- coherence steps, level crossings), never to a clock, and each beat may
-- also produce nothing, so no two anomalies play out the same way.

local Dissonance = {}

export type Anomaly = {
	id: number,
	family: string,
	x: number,
	z: number,
	stage: string,
	stageAge: number,
	age: number,
	durations: { [string]: number },
	base: number,
	strength: number,
	envelope: number,
	feed: number,
	coherence: number,
	coherenceStep: number,
	echoStep: number,
	void: boolean,
	peaked: boolean,
}

export type AnomalyConfig = {
	stages: { [string]: { number } },
	strength: { [string]: number },
	feedRate: number,
	feedMax: number,
	coherencePerSecond: number,
	coherenceScan: number,
	coherenceSteps: { number },
	echoSteps: { number },
	noOutsideCoherence: number,
	noOutsideChance: number,
}

export type ScanConfig = {
	threshold: number,
	chargePerSecond: number,
	decayPerSecond: number,
	warnAt: number,
	cooldown: number,
	pulseHold: number,
}

export type Emitter = { charge: number, cooldown: number, signal: number, hold: number }

export type EchoStep = { index: number, delay: number, speed: number }

-- What the director knows when a beat arrives.
export type Context = {
	family: string,
	atHome: boolean, -- the anomaly is strong at the house
	scopeOn: boolean,
	night: boolean,
	dogNear: boolean,
	mayaLit: boolean,
	electric: boolean, -- an electric light is lit in the house
	flickered: boolean, -- this anomaly already flickered the lights
	peaked: boolean,
	ghostDone: boolean,
}

Dissonance.ARRIVAL = "The quiet is ending."
Dissonance.NO_OUTSIDE = "THERE IS NO OUTSIDE."
Dissonance.Families = { "Arrival", "Echo", "Absence" }

local ORDER = { "ONSET", "ACTIVE", "PEAK", "FADE", "DONE" }
local NEXT: { [string]: string } = { ONSET = "ACTIVE", ACTIVE = "PEAK", PEAK = "FADE", FADE = "DONE" }
local STAGE_BEAT: { [string]: { [string]: string } } = {
	Arrival = { ACTIVE = "active", PEAK = "peak", FADE = "fade", DONE = "done" },
	Echo = { ACTIVE = "active", PEAK = "peak", FADE = "fade", DONE = "done" },
	Absence = { ACTIVE = "active", PEAK = "drop", FADE = "silence", DONE = "done" },
}

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, v))
end

-- Small deterministic generator for text and timing variation.
local function lcg(seed: number): () -> number
	local state = math.floor(math.abs(seed) * 2147483) % 2147483647 + 1
	return function(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

-- rolls: four numbers in [0, 1) choosing each stage's length.
function Dissonance.newAnomaly(
	id: number,
	family: string,
	x: number,
	z: number,
	cfg: AnomalyConfig,
	rolls: { number }
): Anomaly
	local durations: { [string]: number } = {}
	for i = 1, 4 do
		local name = ORDER[i]
		local range = cfg.stages[name]
		durations[name] = range[1] + (range[2] - range[1]) * clamp(rolls[i] or 0.5, 0, 1)
	end
	local base = cfg.strength[family] or 20
	return {
		id = id,
		family = family,
		x = x,
		z = z,
		stage = "ONSET",
		stageAge = 0,
		age = 0,
		durations = durations,
		base = base,
		strength = base,
		envelope = 0,
		feed = 0,
		coherence = 0,
		coherenceStep = 0,
		echoStep = 0,
		void = false,
		peaked = false,
	}
end

-- 0..1 strength envelope through the stages (p is stage progress 0..1).
function Dissonance.envelope(family: string, stage: string, p: number): number
	p = clamp(p, 0, 1)
	if stage == "ONSET" then
		return 0.3 * p
	elseif stage == "ACTIVE" then
		return 0.3 + 0.55 * p
	elseif stage == "PEAK" then
		return if family == "Absence" then 0 else 0.85 + 0.15 * math.min(p * 3, 1)
	elseif stage == "FADE" then
		return if family == "Absence" then 0 else 1 - p
	end
	return 0
end

-- Advance an anomaly. signature is the scope's scan signature (0..1):
-- measuring an anomaly hard feeds it. Returns the beats that happened.
function Dissonance.step(a: Anomaly, dt: number, signature: number, cfg: AnomalyConfig): { string }
	local beats: { string } = {}
	if a.stage == "DONE" then
		return beats
	end
	a.age += dt
	a.stageAge += dt
	if a.stage ~= "FADE" then
		a.feed = math.min(a.feed + signature * cfg.feedRate * dt, cfg.feedMax)
	end
	if a.family == "Arrival" and (a.stage == "ACTIVE" or a.stage == "PEAK") then
		a.coherence = math.min(1, a.coherence + (cfg.coherencePerSecond + signature * cfg.coherenceScan) * dt)
		local steps = cfg.coherenceSteps
		while a.coherenceStep < #steps and a.coherence >= steps[a.coherenceStep + 1] do
			a.coherenceStep += 1
			table.insert(beats, "transmit")
		end
	end
	local dur = a.durations[a.stage]
	while dur and a.stageAge >= dur do
		a.stageAge -= dur
		a.stage = NEXT[a.stage]
		if a.stage == "PEAK" then
			a.peaked = true
		end
		table.insert(beats, STAGE_BEAT[a.family][a.stage])
		dur = a.durations[a.stage]
	end
	local p = if dur then a.stageAge / dur else 1
	a.envelope = Dissonance.envelope(a.family, a.stage, p)
	a.void = a.family == "Absence" and a.stage == "PEAK"
	if a.family == "Echo" and (a.stage == "ACTIVE" or a.stage == "PEAK") then
		local steps = cfg.echoSteps
		while a.echoStep < #steps and a.envelope >= steps[a.echoStep + 1] do
			a.echoStep += 1
			table.insert(beats, "echo")
		end
	end
	a.strength = a.base * (1 + a.feed)
	return beats
end

-- The anomaly as a field source.
function Dissonance.source(a: Anomaly): { x: number, z: number, strength: number, void: boolean }
	return { x = a.x, z = a.z, strength = a.strength * a.envelope, void = a.void }
end

-- Drop letters from text: each survives with probability clarity. Spaces
-- and punctuation stay, so the shape of the sentence is always there.
function Dissonance.corrupt(text: string, clarity: number, seed: number): string
	local rand = lcg(seed)
	local out = table.create(#text)
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		if string.match(ch, "%a") and rand() >= clarity then
			table.insert(out, "-")
		else
			table.insert(out, ch)
		end
	end
	return table.concat(out)
end

-- The Arrival's line at this coherence. The rare line is only possible when
-- the caller allows it (days since its last use) and the signal is nearly
-- whole. Returns the text and whether the rare line was used.
function Dissonance.arrivalLine(
	coherence: number,
	roll: number,
	seed: number,
	rareAllowed: boolean,
	cfg: AnomalyConfig
): (string, boolean)
	if rareAllowed and coherence >= cfg.noOutsideCoherence and roll < cfg.noOutsideChance then
		return Dissonance.NO_OUTSIDE, true
	end
	if coherence >= 0.85 then
		return Dissonance.ARRIVAL, false
	end
	return Dissonance.corrupt(Dissonance.ARRIVAL, clamp(0.15 + coherence, 0, 1), seed), false
end

-- Replay plan for the Echo. times are when recent sounds played, oldest
-- first. The last few come back with every gap stretched or squeezed by a
-- different wrong factor, sometimes in reverse order, a little slow.
function Dissonance.echoPlan(times: { number }, seed: number, maxCount: number): { EchoStep }
	local plan: { EchoStep } = {}
	local n = math.min(#times, maxCount)
	if n == 0 then
		return plan
	end
	local rand = lcg(seed)
	local first = #times - n + 1
	local order: { number } = {}
	for i = first, #times do
		table.insert(order, i)
	end
	if n > 1 and rand() < 0.4 then
		local reversed: { number } = {}
		for i = #order, 1, -1 do
			table.insert(reversed, order[i])
		end
		order = reversed
	end
	local delay = 0.4 + rand() * 1.2
	for k, idx in order do
		if k > 1 then
			local gap = clamp(math.abs(times[idx] - times[order[k - 1]]), 0.2, 6)
			local warp = if rand() < 0.5 then 0.35 + rand() * 0.35 else 1.6 + rand() * 1.0
			delay += math.max(0.15, gap * warp)
		end
		table.insert(plan, { index = idx, delay = delay, speed = 0.82 + rand() * 0.12 })
	end
	return plan
end

-- Scan signature: 0 when off or in PASSIVE, rising steeply with sensitivity.
function Dissonance.signature(
	powered: boolean,
	modeSignature: number,
	sensitivity: number,
	sMin: number,
	sMax: number
): number
	if not powered then
		return 0
	end
	local t = clamp((sensitivity - sMin) / math.max(sMax - sMin, 1), 0, 1)
	return modeSignature * t ^ 1.3
end

function Dissonance.newEmitter(): Emitter
	return { charge = 0, cooldown = 0, signal = 0, hold = 0 }
end

-- Charge, pulse, cool down. Returns true on the step that pulses.
function Dissonance.stepEmitter(e: Emitter, dt: number, signature: number, cfg: ScanConfig): boolean
	if e.hold > 0 then
		e.hold = math.max(0, e.hold - dt)
		if e.hold == 0 then
			e.signal = 0
		end
	end
	if e.cooldown > 0 then
		e.cooldown = math.max(0, e.cooldown - dt)
		e.charge = math.max(0, e.charge - cfg.decayPerSecond * dt)
		return false
	end
	if signature >= cfg.threshold then
		e.charge += cfg.chargePerSecond * signature * dt
	else
		e.charge = math.max(0, e.charge - cfg.decayPerSecond * dt)
	end
	if e.charge >= 1 then
		e.charge = 0
		e.cooldown = cfg.cooldown
		e.signal = signature
		e.hold = cfg.pulseHold
		return true
	end
	return false
end

-- The EMIT lamp: the telegraph a player learns to read.
function Dissonance.emitterLamp(e: Emitter, signature: number, cfg: ScanConfig): string
	if e.hold > 0 then
		return "pulse"
	elseif e.cooldown > 0 then
		return "cool"
	elseif e.charge >= cfg.warnAt then
		return "blink"
	elseif signature >= cfg.threshold then
		return "warm"
	end
	return "off"
end

export type Rule = { event: string, weight: number }

local function r(event: string, weight: number): Rule
	return { event = event, weight = weight }
end

-- Candidate events per beat, with weights. "none" is a real answer.
local RULES: { [string]: { Rule } } = {
	level_DRIFT = { r("dogRouse", 0.35), r("radio", 0.25), r("none", 0.4) },
	level_DISTURBANCE = { r("dogRouse", 0.6), r("window", 0.2), r("radio", 0.1), r("none", 0.1) },
	level_HIGH = { r("dogWatch", 0.5), r("dogGrowl", 0.3), r("window", 0.2) },
	transmit = { r("transmission", 1) },
	["Arrival:peak"] = { r("flicker", 0.6), r("dogWatch", 0.25), r("maya", 0.15) },
	["Echo:peak"] = { r("echo", 0.7), r("window", 0.3) },
	echo = { r("echo", 1) },
	drop = { r("dogWatch", 0.5), r("dogRouse", 0.3), r("none", 0.2) },
	silence = { r("hush", 1) },
	["Arrival:fade"] = { r("hush", 0.6), r("maya", 0.15), r("none", 0.25) },
	["Echo:fade"] = { r("radio", 0.3), r("none", 0.7) },
	done = { r("relax", 1) },
}

function Dissonance.rulesFor(beat: string, family: string, ghostChance: number): { Rule }?
	if beat == "scopeOff" then
		return { r("ghostNeedle", ghostChance), r("none", 1 - ghostChance) }
	end
	return RULES[family .. ":" .. beat] or RULES[beat]
end

function Dissonance.allowed(event: string, ctx: Context): boolean
	if event == "none" or event == "relax" then
		return true
	elseif event == "transmission" then
		return ctx.scopeOn
	elseif event == "echo" then
		return ctx.atHome or ctx.scopeOn
	elseif event == "ghostNeedle" then
		return ctx.atHome and not ctx.scopeOn and ctx.peaked and not ctx.ghostDone
	elseif not ctx.atHome then
		return false
	elseif event == "flicker" then
		return ctx.electric and not ctx.flickered
	elseif event == "maya" then
		return ctx.night and ctx.mayaLit
	elseif event == "dogRouse" or event == "dogWatch" or event == "dogGrowl" then
		return ctx.dogNear
	end
	return true
end

-- Pick the event that answers a beat, or nil. Events still cooling down or
-- not allowed here drop out; "none" can win. Records the pick in lastAt.
function Dissonance.choose(
	beat: string,
	ctx: Context,
	lastAt: { [string]: number },
	now: number,
	roll: number,
	cooldowns: { [string]: number },
	ghostChance: number
): string?
	local rules = Dissonance.rulesFor(beat, ctx.family, ghostChance)
	if not rules then
		return nil
	end
	local pool: { Rule } = {}
	local total = 0
	local real = 0
	for _, rule in rules do
		local event = rule.event
		local ready = now - (lastAt[event] or -math.huge) >= (cooldowns[event] or 0)
		if rule.weight > 0 and (event == "none" or (ready and Dissonance.allowed(event, ctx))) then
			table.insert(pool, rule)
			total += rule.weight
			if event ~= "none" then
				real += 1
			end
		end
	end
	if real == 0 then
		return nil
	end
	local pick = clamp(roll, 0, 0.999999) * total
	for _, rule in pool do
		if pick < rule.weight then
			if rule.event == "none" then
				return nil
			end
			lastAt[rule.event] = now
			return rule.event
		end
		pick -= rule.weight
	end
	return nil
end

return Dissonance

--!strict
-- Pure model of the chaotic energy field (Chapter 36). No requires, no
-- Roblox APIs: every random number comes in as an argument.
--
-- The map is cut into square sectors. Each sector's energy is a background
-- (a baseline, a little more at night, and a slow mean-reverting drift),
-- plus a weather term (rain adds a little energy; storms add interference,
-- not energy), plus a slow, lagged creature term (their fear energy and
-- hunger, and the collective's alert level), plus anomaly sources. Energy
-- is not a creature count: calm creatures add nothing, and anomalies happen
-- with no creatures at all.
--
-- A reading is what an instrument would show: a weighted average of nearby
-- sectors plus measurement noise. The true value never leaves this module
-- except through a noisy, quantized reading.

local ChaosField = {}

export type Config = {
	sectorSize: number,
	halfSize: number,
	baseline: number,
	nightLift: number,
	driftPull: number,
	driftSigma: number,
	driftLimit: number,
	rainPerUnit: number,
	stormFrom: number,
	stormInterference: number,
	creatureEnergy: number,
	creatureHunger: number,
	creatureRange: number,
	collectivePerLevel: number,
	creatureLag: number,
	smoothing: number,
	voidSmoothing: number,
	trendWindow: number,
	anomalyFalloff: number,
}

export type Sector = {
	key: string,
	x: number,
	z: number,
	drift: number,
	creature: number,
	anomaly: number,
	current: number,
	trend: number,
	interference: number,
}

export type Field = {
	config: Config,
	sectors: { [string]: Sector },
	list: { Sector },
	cols: number,
}

export type Creature = { x: number, z: number, energy: number, hunger: number }

-- An anomaly as the field sees it. A void source (the Absence) pulls the
-- energy around it down to zero instead of adding to it.
export type Source = { x: number, z: number, strength: number, void: boolean }

export type Env = {
	rain: number, -- RainIntensity, 0..5
	night: number, -- NightFactor, 0..1
	collective: number, -- collective alert level, 0..5
	creatures: { Creature },
	sources: { Source },
}

export type Mode = {
	range: number,
	noise: number,
	quantize: number,
	flat: boolean,
}

export type Reading = {
	ceu: number, -- what the needle shows
	uncertainty: number, -- one sigma of measurement noise
	irregularity: number, -- 0 smooth trace .. 1 jagged trace
}

export type LevelDef = { name: string, from: number }
export type LevelRules = { hysteresis: number, unknownUncertainty: number, zeroBelow: number }

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, v))
end

local function index(field: Field, v: number): number
	local c = field.config
	return clamp(math.floor((v + c.halfSize) / c.sectorSize), 0, field.cols - 1)
end

function ChaosField.new(config: Config): Field
	local cols = math.ceil(2 * config.halfSize / config.sectorSize)
	local field: Field = { config = config, sectors = {}, list = {}, cols = cols }
	for i = 0, cols - 1 do
		for j = 0, cols - 1 do
			local key = i .. "_" .. j
			local s: Sector = {
				key = key,
				x = -config.halfSize + (i + 0.5) * config.sectorSize,
				z = -config.halfSize + (j + 0.5) * config.sectorSize,
				drift = 0,
				creature = 0,
				anomaly = 0,
				current = config.baseline,
				trend = 0,
				interference = 0,
			}
			field.sectors[key] = s
			table.insert(field.list, s)
		end
	end
	return field
end

function ChaosField.keyFor(field: Field, x: number, z: number): string
	return index(field, x) .. "_" .. index(field, z)
end

function ChaosField.sectorAt(field: Field, x: number, z: number): Sector
	return field.sectors[ChaosField.keyFor(field, x, z)]
end

-- How strongly an anomaly at distance d pulls a sector (1 at the source).
function ChaosField.falloff(d: number, half: number): number
	return 1 / (1 + (d / half) ^ 2)
end

-- How much of a void reaches a sector: full inside half a sector, none
-- past one and a half.
local function voidReach(d: number, size: number): number
	return clamp(1.5 - d / size, 0, 1)
end

-- Advance the field by dt seconds. gauss() returns a standard normal sample.
function ChaosField.step(field: Field, dt: number, env: Env, gauss: () -> number)
	if dt <= 0 then
		return
	end
	local c = field.config
	local rain = clamp(env.rain, 0, 5)
	local weather = rain * c.rainPerUnit
	local interference = math.max(0, rain - c.stormFrom) * c.stormInterference
	local collective = clamp(env.collective, 0, 5) * c.collectivePerLevel
	local background = c.baseline + c.nightLift * clamp(env.night, 0, 1)
	for _, s in field.list do
		-- Slow drift: a mean-reverting random walk, so peaceful nights still move.
		s.drift += -c.driftPull * s.drift * dt + c.driftSigma * math.sqrt(dt) * gauss()
		s.drift = clamp(s.drift, -c.driftLimit, c.driftLimit)

		-- Creatures: only their fear energy and hunger count, lagged.
		local raw = collective
		for _, cr in env.creatures do
			local d = math.sqrt((cr.x - s.x) ^ 2 + (cr.z - s.z) ^ 2)
			if d < c.creatureRange then
				local e = clamp(cr.energy, 0, 1) * c.creatureEnergy
					+ clamp(cr.hunger, 0, 1) * c.creatureHunger
				raw += e * (1 - d / c.creatureRange)
			end
		end
		s.creature += (raw - s.creature) * math.min(dt / c.creatureLag, 1)

		-- Anomalies add; voids subtract everything.
		local anomaly, void = 0, 0
		for _, src in env.sources do
			local d = math.sqrt((src.x - s.x) ^ 2 + (src.z - s.z) ^ 2)
			if src.void then
				void = math.max(void, voidReach(d, c.sectorSize))
			else
				anomaly += math.max(src.strength, 0) * ChaosField.falloff(d, c.anomalyFalloff)
			end
		end
		s.anomaly = anomaly * (1 - void)
		s.interference = interference

		local target = math.max(0, background + s.drift + weather + s.creature + anomaly) * (1 - void)
		local tau = if void > 0.5 then c.voidSmoothing else c.smoothing
		local before = s.current
		s.current += (target - s.current) * math.min(dt / tau, 1)
		s.trend += ((s.current - before) / dt - s.trend) * math.min(dt / c.trendWindow, 1)
	end
end

-- What an instrument at (x, z) shows. noise is a standard normal sample;
-- sensitivity runs from sMin to sMax and lowers the noise.
function ChaosField.read(
	field: Field,
	x: number,
	z: number,
	mode: Mode,
	sensitivity: number,
	sMin: number,
	sMax: number,
	noise: number
): Reading
	local size = field.config.sectorSize
	local nearest = ChaosField.sectorAt(field, x, z)
	local num, den, anomaly, trend, interference = 0, 0, 0, 0, 0
	for _, s in field.list do
		local d = math.sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2)
		if s == nearest or d <= mode.range then
			local w = if mode.flat then 1 else 1 / (1 + (d / size) ^ 2)
			num += s.current * w
			anomaly += s.anomaly * w
			trend += s.trend * w
			interference += s.interference * w
			den += w
		end
	end
	local truth = num / den
	anomaly /= den
	trend /= den
	interference /= den
	local t = clamp((sensitivity - sMin) / math.max(sMax - sMin, 1), 0, 1)
	local sigma = mode.noise * (1.3 - 0.6 * t) + interference
	-- A dead field reads dead: no noise floor to hide it.
	local shown = if truth < 1 then truth else math.max(0, truth + sigma * noise)
	shown = ChaosField.quantize(shown, mode.quantize)
	local irregularity =
		clamp(math.abs(trend) / 3 + anomaly / math.max(truth, 1) * 0.9 + interference * 0.05, 0, 1)
	return { ceu = shown, uncertainty = sigma, irregularity = irregularity }
end

-- The meter's damping: the needle moves part of the way toward each new
-- sample. A dead field (exactly zero) drops the needle at once.
function ChaosField.blend(prev: number?, ceu: number, blend: number): number
	if prev == nil or ceu == 0 then
		return ceu
	end
	return prev + (ceu - prev) * clamp(blend, 0, 1)
end

function ChaosField.quantize(ceu: number, step: number): number
	if step <= 0 then
		return ceu
	end
	return math.floor(ceu / step + 0.5) * step
end

-- Warning level for a displayed reading, with hysteresis against the
-- previous level so a needle hovering on a border does not flap.
function ChaosField.level(
	levels: { LevelDef },
	rules: LevelRules,
	ceu: number,
	uncertainty: number,
	prev: string?
): string
	if uncertainty >= rules.unknownUncertainty or ceu < rules.zeroBelow then
		return "UNKNOWN"
	end
	local idx = 1
	for i, l in levels do
		if ceu >= l.from then
			idx = i
		end
	end
	if prev then
		for i, l in levels do
			if l.name == prev and i > idx and ceu >= l.from - rules.hysteresis then
				return prev
			end
		end
	end
	return levels[idx].name
end

-- Position of a level in the list (STABLE 1 .. THRESHOLD 5); UNKNOWN is 0.
function ChaosField.levelIndex(levels: { LevelDef }, name: string): number
	for i, l in levels do
		if l.name == name then
			return i
		end
	end
	return 0
end

return ChaosField

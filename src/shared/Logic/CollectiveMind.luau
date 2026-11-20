--!strict
-- Pure model of the creatures' shared mental network.
--
-- Creatures report evidence about a sector (an area or a building). Evidence
-- fades with a half-life, so shared knowledge grows stale. The network never
-- stores a player's true position: only the position the reporter believed,
-- plus an uncertainty that grows with age. A coordinated break-in needs strong,
-- recent evidence from several distinct creatures, and only on nights that
-- allow it.

local CollectiveMind = {}

export type Level = number
CollectiveMind.Levels = {
	DORMANT = 0,
	AWARE = 1,
	INVESTIGATING = 2,
	CONVERGING = 3,
	BREACHING = 4,
	SEARCHING = 5,
	DISPERSING = 6,
}
CollectiveMind.LevelNames = {
	[0] = "DORMANT",
	[1] = "AWARE",
	[2] = "INVESTIGATING",
	[3] = "CONVERGING",
	[4] = "BREACHING",
	[5] = "SEARCHING",
	[6] = "DISPERSING",
} :: { [number]: string }

export type Config = {
	halfLife: number,
	reporterWindow: number,
	investigateStrength: number,
	convergeStrength: number,
	convergeReporters: number,
	breachStrength: number,
	breachReporters: number,
	disperseStrength: number,
	forgetStrength: number,
	baseError: number,
	errorPerSecond: number,
}

export type Sector = {
	key: string,
	strength: number,
	lastTime: number,
	position: any,
	reporters: { [string]: number },
	breached: boolean,
	breachable: boolean,
	level: Level,
	peak: Level,
}

export type Mind = {
	config: Config,
	sectors: { [string]: Sector },
	now: number,
}

export type Report = {
	sector: string,
	strength: number,
	position: any,
	sourceId: string,
	time: number,
	breachable: boolean?,
}

function CollectiveMind.new(config: Config): Mind
	return { config = config, sectors = {}, now = 0 }
end

local function reporterCount(mind: Mind, s: Sector): number
	local n = 0
	for _, t in s.reporters do
		if mind.now - t <= mind.config.reporterWindow then
			n += 1
		end
	end
	return n
end

local function computeLevel(mind: Mind, s: Sector, allowBreach: boolean): Level
	local c = mind.config
	local L = CollectiveMind.Levels
	local reporters = reporterCount(mind, s)
	if s.strength < c.disperseStrength then
		if s.peak >= L.INVESTIGATING and s.strength >= c.forgetStrength then
			return L.DISPERSING
		end
		return if s.strength >= c.forgetStrength then L.AWARE else L.DORMANT
	end
	if s.breached then
		return L.SEARCHING
	end
	if allowBreach and s.breachable and s.strength >= c.breachStrength and reporters >= c.breachReporters then
		return L.BREACHING
	end
	if s.strength >= c.convergeStrength and reporters >= c.convergeReporters then
		return L.CONVERGING
	end
	if s.strength >= c.investigateStrength then
		return L.INVESTIGATING
	end
	return L.AWARE
end

function CollectiveMind.report(mind: Mind, r: Report)
	local s = mind.sectors[r.sector]
	if not s then
		s = {
			key = r.sector,
			strength = 0,
			lastTime = r.time,
			position = r.position,
			reporters = {},
			breached = false,
			breachable = r.breachable == true,
			level = 0,
			peak = 0,
		}
		mind.sectors[r.sector] = s
	end
	s.strength = math.min(s.strength + math.max(r.strength, 0), 3)
	s.lastTime = r.time
	s.position = r.position
	s.reporters[r.sourceId] = r.time
	if r.breachable then
		s.breachable = true
	end
end

function CollectiveMind.setBreached(mind: Mind, sector: string, breached: boolean)
	local s = mind.sectors[sector]
	if s then
		s.breached = breached
	end
end

-- Advance time: decay evidence and recompute every sector's level.
function CollectiveMind.update(mind: Mind, now: number, allowBreach: boolean)
	local dt = math.max(now - mind.now, 0)
	mind.now = now
	local decay = if mind.config.halfLife > 0 then 0.5 ^ (dt / mind.config.halfLife) else 0
	for key, s in mind.sectors do
		s.strength *= decay
		s.level = computeLevel(mind, s, allowBreach)
		if s.level > s.peak and s.level ~= CollectiveMind.Levels.DISPERSING then
			s.peak = s.level
		end
		if s.level == CollectiveMind.Levels.DORMANT then
			mind.sectors[key] = nil
		end
	end
end

-- How unreliable the shared position is, in studs.
function CollectiveMind.uncertainty(mind: Mind, s: Sector): number
	local age = math.max(mind.now - s.lastTime, 0)
	return mind.config.baseError + age * mind.config.errorPerSecond
end

function CollectiveMind.strongest(mind: Mind): Sector?
	local best: Sector? = nil
	for _, s in mind.sectors do
		if best == nil or s.level > best.level or (s.level == best.level and s.strength > best.strength) then
			best = s
		end
	end
	return best
end

function CollectiveMind.highestLevel(mind: Mind): Level
	local s = CollectiveMind.strongest(mind)
	return if s then s.level else 0
end

return CollectiveMind

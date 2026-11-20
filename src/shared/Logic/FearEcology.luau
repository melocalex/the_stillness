--!strict
-- Fear as food (Chapter 35). Pure: no requires, no Roblox APIs.
--
-- Characters gather fear from fictional gameplay signals (never from the
-- real player). Creatures near a frightened character feed on it: energy
-- that rises with diminishing returns and decays, and an appetite (hunger)
-- that grows while they feed and fades when the people near them are calm.
-- Energy and hunger change how bold a creature is (stares, dashes,
-- displacement, noises), never the rules of shelter, breaching or capture.

local FearEcology = {}

export type FearInput = {
	threat: number, -- 0..3, creature threat level around the character
	chased: boolean, -- pursued in the last few seconds
	sawCreature: boolean, -- looking straight at a creature
	exposedDark: boolean, -- outdoors, at night, unlit
	unexplainedSound: boolean, -- a creature noise nearby, recently
	secureShelter: boolean,
	nearDog: boolean,
	nearFire: boolean,
	nearMaya: boolean,
}

export type Config = {
	riseRate: number,
	fallRate: number,
	feedRange: number,
	feedGain: number,
	energyDecay: number,
	appetite: number,
	hungerDecay: number,
}

export type Profile = { dash: number, displace: number, stare: number, noise: number, pause: number }

export type Mods = {
	dashChance: number, -- chance a long stare ends in a dash
	displaceChance: number, -- per second while nobody is watching
	stareSeconds: number, -- how long it holds still under a gaze
	noiseInterval: number, -- seconds between its noises
	seeksPeople: boolean, -- hunger pulls it toward inhabited places
}

-- The fear a character is drifting toward, 0..1.
function FearEcology.target(i: FearInput): number
	local f = 0.14 * math.clamp(i.threat, 0, 3)
	if i.chased then
		f += 0.3
	end
	if i.sawCreature then
		f += 0.22
	end
	if i.exposedDark then
		f += 0.12
	end
	if i.unexplainedSound then
		f += 0.1
	end
	local calm = 0
	if i.secureShelter then
		calm += 0.15
	end
	if i.nearDog then
		calm += 0.08
	end
	if i.nearFire then
		calm += 0.06
	end
	if i.nearMaya then
		calm += 0.1
	end
	return math.clamp(f - calm, 0, 1)
end

-- Fear moves toward its target: quickly up, slowly down.
function FearEcology.step(fear: number, target: number, dt: number, cfg: Config): number
	if target > fear then
		return math.min(target, fear + cfg.riseRate * dt)
	end
	return math.max(target, fear - cfg.fallRate * dt)
end

function FearEcology.state(fear: number, falling: boolean): string
	if falling and fear >= 0.15 and fear < 0.6 then
		return "RECOVERING"
	elseif fear < 0.15 then
		return "CALM"
	elseif fear < 0.35 then
		return "UNEASY"
	elseif fear < 0.6 then
		return "ALARMED"
	elseif fear < 0.85 then
		return "TERRIFIED"
	end
	return "PANICKED"
end

-- How much of one character's fear reaches a creature at a distance.
function FearEcology.intake(fear: number, distance: number, cfg: Config): number
	if distance >= cfg.feedRange then
		return 0
	end
	return fear * (1 - distance / cfg.feedRange)
end

-- A creature's energy and hunger after dt. Intake is the sum over nearby
-- characters, capped at 1 so a crowd is not a feast. Gains shrink as the
-- value grows (diminishing returns); both decay when nobody is afraid.
function FearEcology.feed(
	energy: number,
	hunger: number,
	intake: number,
	dt: number,
	cfg: Config
): (number, number)
	local food = math.clamp(intake, 0, 1)
	local e = energy + (food * cfg.feedGain * (1 - energy) - cfg.energyDecay) * dt
	local h = hunger + (food * cfg.appetite * (1 - hunger) - cfg.hungerDecay) * dt
	return math.clamp(e, 0, 1), math.clamp(h, 0, 1)
end

-- What energy and hunger change, shaped by temperament. Every value has a
-- floor and a ceiling, so no amount of fear makes a creature unstoppable.
function FearEcology.mods(energy: number, hunger: number, p: Profile): Mods
	return {
		dashChance = math.clamp((0.15 + 0.6 * energy) * p.dash, 0, 0.9),
		displaceChance = math.clamp((0.02 + 0.12 * energy) * p.displace, 0, 0.2),
		stareSeconds = math.clamp((10 + 14 * energy + 6 * hunger) * p.stare, 6, 40),
		noiseInterval = math.clamp((45 - 30 * energy - 8 * hunger) * p.noise, 10, 90),
		seeksPeople = hunger >= 0.5,
	}
end

return FearEcology

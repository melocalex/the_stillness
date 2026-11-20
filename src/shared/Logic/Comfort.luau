--!strict
-- Pure comfort and exposure model.
--
-- Comfort is how safe and well the player feels. It is broken into the kinds
-- of coziness the design names (physical, emotional, weather, observational,
-- routine, achieved) so the UI can say *why* the player feels at home.
--
-- Exposure is a readout of the same inputs the creature perception uses
-- (light on the player, movement, coat, being outdoors). It never rolls dice
-- of its own; creatures detect through Perception, not through this number.

local Comfort = {}

export type ComfortInput = {
	inside: boolean,
	shelterSecure: boolean,
	nearFire: boolean,
	warmLight: boolean,
	seated: boolean,
	dogNear: boolean,
	pettedRecently: boolean,
	homeComing: boolean, -- recently returned home after time outside
	weatherOutside: string, -- Clear | Fog | Rain | Storm
	observingSafely: boolean,
	routineDone: number, -- rituals done today (fire lit, curtains at dusk, fed dog)
	upgradesBuilt: number,
	chasedRecently: boolean,
	night: boolean,
}

export type Breakdown = {
	physical: number,
	emotional: number,
	weather: number,
	observational: number,
	routine: number,
	achieved: number,
	stress: number,
	total: number,
}

function Comfort.target(i: ComfortInput): Breakdown
	local physical = 0
	if i.inside then
		physical += 15
		if i.shelterSecure then
			physical += 10
		end
		if i.nearFire then
			physical += 15
		end
		if i.warmLight then
			physical += 5
		end
		if i.seated then
			physical += 5
		end
	end

	local emotional = 0
	if i.dogNear then
		emotional += 12
	end
	if i.pettedRecently then
		emotional += 6
	end
	if i.inside and i.homeComing then
		emotional += 8
	end

	local weather = 0
	if i.inside and i.shelterSecure then
		if i.weatherOutside == "Rain" then
			weather = 10
		elseif i.weatherOutside == "Storm" then
			weather = 12
		elseif i.weatherOutside == "Fog" then
			weather = 5
		end
	elseif not i.inside and (i.weatherOutside == "Rain" or i.weatherOutside == "Storm") then
		weather = -10
	end

	local observational = if i.observingSafely and i.inside and i.shelterSecure then 6 else 0
	local routine = math.min(i.routineDone, 3) * 3
	local achieved = math.min(i.upgradesBuilt, 4) * 2

	local stress = 0
	if i.chasedRecently then
		stress -= 25
	end
	if not i.inside and i.night then
		stress -= 15
	end

	local total =
		math.clamp(25 + physical + emotional + weather + observational + routine + achieved + stress, 0, 100)
	return {
		physical = physical,
		emotional = emotional,
		weather = weather,
		observational = observational,
		routine = routine,
		achieved = achieved,
		stress = stress,
		total = total,
	}
end

-- Moves current toward target at `rate` points per second.
function Comfort.step(current: number, target: number, dt: number, rate: number): number
	local delta = target - current
	local maxStep = rate * dt
	if math.abs(delta) <= maxStep then
		return target
	end
	return current + math.sign(delta) * maxStep
end

-- Multiplier on stamina recovery from comfort 0..100 (0.6x .. 1.8x).
function Comfort.staminaMultiplier(comfort: number): number
	return 0.6 + 1.2 * math.clamp(comfort, 0, 100) / 100
end

export type ExposureInput = {
	outdoors: boolean,
	illumination: number,
	movement: string, -- still | sneak | walk | run
	coatEquipped: boolean,
	weatherVisibility: number,
}

local MOVE: { [string]: number } = { still = 0.1, sneak = 0.35, walk = 0.6, run = 1 }

function Comfort.exposure(i: ExposureInput): number
	local base = if i.outdoors then 40 else 10
	local light = math.clamp(i.illumination, 0, 1) * 30
	local move = (MOVE[i.movement] or 0.6) * 30
	local total = (base + light + move) * math.clamp(i.weatherVisibility, 0.3, 1)
	if i.coatEquipped then
		total *= 0.6
	end
	return math.clamp(math.floor(total + 0.5), 0, 100)
end

return Comfort

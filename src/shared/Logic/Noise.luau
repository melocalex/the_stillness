--!strict
-- Pure noise model. Loudness is the radius (studs) at which an average
-- listener hears the sound in open air. Walls, weather and the listener's
-- hearing scale that radius. The coat never changes noise.

local Noise = {}

Noise.Loudness = {
	still = 0,
	crouch = 6,
	curtain = 4,
	cabinet = 9,
	switch = 7,
	walk = 18,
	door = 14,
	jump = 22,
	drop = 30,
	chop = 32,
	mine = 32,
	doorSlam = 36,
	run = 40,
	bark = 45,
	radio = 20,
	windowBreak = 70,
	doorBreak = 70,
} :: { [string]: number }

local WEATHER_MASK: { [string]: number } = {
	Clear = 1,
	Fog = 0.95,
	Rain = 0.7,
	Storm = 0.55,
}

-- Multiplier on loudness between a source and a listener.
function Noise.attenuation(
	sourceInside: boolean,
	listenerInside: boolean,
	shelterSealed: boolean,
	weather: string
): number
	local m = WEATHER_MASK[weather] or 1
	if sourceInside ~= listenerInside then
		m *= if shelterSealed then 0.35 else 0.75
	end
	return m
end

-- 0 when inaudible, up to 1 right next to the source.
function Noise.perceivedStrength(
	loudness: number,
	distance: number,
	attenuation: number,
	hearingMultiplier: number
): number
	local radius = loudness * attenuation * hearingMultiplier
	if radius <= 0 or distance >= radius then
		return 0
	end
	return 1 - distance / radius
end

-- How far off the listener's estimate of the source may be (studs).
function Noise.positionError(distance: number, strength: number): number
	return distance * 0.2 * (1 - math.clamp(strength, 0, 1)) + 1
end

return Noise

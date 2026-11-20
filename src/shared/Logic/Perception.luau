--!strict
-- Pure creature perception scoring. Callers measure geometry (distance, angle,
-- line of sight) and pass plain numbers; this module only weighs them.
--
-- Three independent channels, never one invisibility flag:
--   vision   - sight, light, movement, coat while still
--   presence - the creatures' unnatural sense; the coat suppresses it
--   hearing  - handled by Noise; the coat never cancels sound

local Perception = {}

export type SenseProfile = {
	visionRange: number,
	fovDegrees: number,
	peripheralRange: number,
	lightSensitivity: number, -- 0: sees equally in the dark, 1: needs light
	hearingMultiplier: number,
	presenceRange: number,
	presenceSensitivity: number,
	coatResistance: number, -- 0: coat fully effective, 1: coat ignored
}

export type Movement = "still" | "sneak" | "walk" | "run"

export type VisionInput = {
	distance: number,
	angleDegrees: number,
	hasLineOfSight: boolean,
	illumination: number, -- 0..1 light falling on the player
	movement: Movement,
	coatEquipped: boolean,
	weatherVisibility: number, -- 0..1
	throughWindow: boolean,
}

local MOVEMENT_FACTOR: { [Movement]: number } = {
	still = 0.45,
	sneak = 0.7,
	walk = 1.0,
	run = 1.3,
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Effective light the creature can use, after its light sensitivity.
function Perception.effectiveLight(profile: SenseProfile, illumination: number): number
	return lerp(1, math.clamp(illumination, 0, 1), profile.lightSensitivity)
end

-- Awareness gained per second from sight. 0 when the player cannot be seen.
function Perception.visionScore(profile: SenseProfile, input: VisionInput): number
	if not input.hasLineOfSight then
		return 0
	end
	local light = Perception.effectiveLight(profile, input.illumination)
	local range = profile.visionRange * math.clamp(input.weatherVisibility, 0, 1) * (0.35 + 0.65 * light)
	if range <= 0 or input.distance > range then
		return 0
	end
	local inFov = input.angleDegrees <= profile.fovDegrees / 2
	if not inFov and input.distance > profile.peripheralRange then
		return 0
	end
	local distFactor = 1 - input.distance / range
	local score = distFactor * MOVEMENT_FACTOR[input.movement] * (0.25 + 0.75 * light)
	if input.coatEquipped then
		local still = input.movement == "still" or input.movement == "sneak"
		local coatFactor = if still then 0.35 else 0.85
		score *= lerp(coatFactor, 1, profile.coatResistance)
	end
	if not inFov then
		score *= 0.5
	end
	if input.throughWindow then
		score *= 0.8
	end
	return math.clamp(score, 0, 1.5)
end

-- Awareness gained per second from the supernatural presence sense.
function Perception.presenceScore(
	profile: SenseProfile,
	distance: number,
	coatEquipped: boolean,
	still: boolean
): number
	if profile.presenceRange <= 0 or distance > profile.presenceRange then
		return 0
	end
	local score = (1 - distance / profile.presenceRange) * profile.presenceSensitivity
	if coatEquipped then
		score *= lerp(0.08, 1, profile.coatResistance)
	end
	if still then
		score *= 0.8
	end
	return math.clamp(score, 0, 1.5)
end

-- Integrates awareness over one tick. Awareness is bounded so a creature that
-- loses the player forgets in a predictable time.
function Perception.updateAwareness(
	current: number,
	gainPerSecond: number,
	dt: number,
	decayPerSecond: number
): number
	local value = current + gainPerSecond * dt - decayPerSecond * dt
	return math.clamp(value, 0, 1.5)
end

function Perception.movementFromSpeed(speed: number, crouching: boolean): Movement
	if speed < 0.5 then
		return "still"
	elseif crouching or speed < 10 then
		return "sneak"
	elseif speed < 19 then
		return "walk"
	end
	return "run"
end

return Perception

--!strict
-- Pure light model: how lit a player is, and how much a house advertises
-- that someone is home. Relative values, not guarantees; creature perception
-- consumes them.

local LightVisibility = {}

export type LightSample = { brightness: number, range: number, distance: number }

-- Illumination on a point: ambient sky plus the strongest nearby lights.
function LightVisibility.illumination(sky: number, lights: { LightSample }, flashlight: boolean): number
	local sum = math.clamp(sky, 0, 1)
	for _, l in lights do
		if l.range > 0 and l.distance < l.range then
			sum += math.clamp(l.brightness, 0, 2) * 0.5 * (1 - l.distance / l.range)
		end
	end
	if flashlight then
		sum += 0.35
	end
	return math.clamp(sum, 0, 1)
end

export type HouseInput = {
	electricLightsOn: number,
	fireLit: boolean,
	curtainsOpenFraction: number,
	nightFactor: number,
	weatherVisibility: number,
}

-- 0..1 how strongly a lit house draws attention from outside at night.
-- lights on + curtains open  -> very high
-- lights on + curtains closed -> low to moderate
-- lights off + curtains open  -> low
-- lights off + curtains closed -> very low
function LightVisibility.houseBeacon(i: HouseInput): number
	local glow = math.min(i.electricLightsOn * 0.35, 0.85) + (if i.fireLit then 0.15 else 0)
	local leak = 0.12 + 0.88 * math.clamp(i.curtainsOpenFraction, 0, 1)
	local v = glow * leak * math.clamp(i.nightFactor, 0, 1) * math.clamp(i.weatherVisibility, 0.2, 1)
	return math.clamp(v, 0, 1)
end

return LightVisibility

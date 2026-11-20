--!strict
-- Pure adaptive-music decisions. The client MusicDirector feeds it context
-- built from server-replicated state; it returns the state to play and
-- whether this moment should be silence.

local MusicState = {}

export type State =
	"MAIN_MENU"
	| "HOME_SAFE"
	| "HOME_RAIN"
	| "DAY_EXPLORATION"
	| "DUSK"
	| "NIGHT_SAFE"
	| "NIGHT_OUTSIDE"
	| "CREATURE_NEARBY"
	| "CREATURE_HUNTING"
	| "CREATURE_LOST"
	| "DAWN"
	| "DISCOVERY"
	| "BLACKOUT"
	| "STORM_NIGHT"

export type Context = {
	menu: boolean,
	phase: string,
	sheltered: boolean,
	raining: boolean,
	threat: number, -- 0 none, 1 present, 2 investigating, 3 hunting
	secondsSinceThreat: number,
	discovery: boolean,
	lightsOff: boolean,
	badNight: boolean,
	storm: boolean?, -- heavy rain (intensity >= 3.4)
}

function MusicState.choose(c: Context): State
	if c.menu then
		return "MAIN_MENU"
	end
	if c.discovery then
		return "DISCOVERY"
	end
	if c.threat >= 3 then
		return "CREATURE_HUNTING"
	end
	if c.threat >= 1 then
		return "CREATURE_NEARBY"
	end
	if c.secondsSinceThreat < 25 then
		return "CREATURE_LOST"
	end
	if c.badNight and c.sheltered and c.lightsOff then
		return "BLACKOUT"
	end
	-- Storm nights get the music-box motif: slow, high, slightly wrong.
	if c.storm and c.phase == "Night" then
		return "STORM_NIGHT"
	end
	if c.phase == "Dawn" then
		return "DAWN"
	end
	if c.sheltered then
		if c.raining then
			return "HOME_RAIN"
		end
		if c.phase == "Night" then
			return "NIGHT_SAFE"
		end
		return "HOME_SAFE"
	end
	if c.phase == "Night" then
		return "NIGHT_OUTSIDE"
	elseif c.phase == "Dusk" then
		return "DUSK"
	end
	return "DAY_EXPLORATION"
end

-- States that must keep playing as long as they hold (tension needs continuity).
local ALWAYS_ON: { [State]: boolean } = {
	CREATURE_NEARBY = true,
	CREATURE_HUNTING = true,
	CREATURE_LOST = true,
	DISCOVERY = true,
	MAIN_MENU = true,
}

-- Silence is a feature: ambient states only get a cue after a quiet gap,
-- and only sometimes. roll is uniform in [0, 1).
function MusicState.shouldStartCue(
	state: State,
	secondsSinceLastCue: number,
	minGap: number,
	chance: number,
	roll: number
): boolean
	if ALWAYS_ON[state] then
		return true
	end
	if state == "BLACKOUT" then
		return false
	end
	return secondsSinceLastCue >= minGap and roll < chance
end

function MusicState.isAlwaysOn(state: State): boolean
	return ALWAYS_ON[state] == true
end

return MusicState

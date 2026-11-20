--!strict
-- Pure neighborhood-mystery progression for a watched house. Each night has a
-- small timeline of house events keyed by fraction of the night. Missed
-- observations are fine: the house keeps physical clues the player can find
-- by day.

local Mystery = {}

export type Event = {
	at: number, -- 0..1 fraction of the Night phase
	action: string,
	note: string?,
}

export type Script = {
	nights: { [number]: { Event } },
	fallback: { Event },
	badNight: { Event },
}

function Mystery.eventsFor(script: Script, nightIndex: number, nightType: string): { Event }
	if nightType == "Bad" or nightType == "Black" then
		return script.badNight
	end
	return script.nights[nightIndex] or script.fallback
end

-- Events whose time falls in (fromFraction, toFraction].
function Mystery.due(events: { Event }, fromFraction: number, toFraction: number): { Event }
	local out = {}
	for _, e in events do
		if e.at > fromFraction and e.at <= toFraction then
			table.insert(out, e)
		end
	end
	table.sort(out, function(a, b)
		return a.at < b.at
	end)
	return out
end

return Mystery

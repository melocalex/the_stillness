--!strict
-- Pure observation journal. Entries are deduplicated by event id, numbered per
-- subject, and labeled with how certain the knowledge is.

local Journal = {}

export type Certainty = "observed" | "theory" | "verified"

export type Entry = {
	id: string,
	subject: string,
	title: string,
	text: string,
	day: number,
	clock: string,
	weather: string,
	certainty: Certainty,
	number: number,
}

export type Journal = {
	entries: { Entry },
	seen: { [string]: boolean },
	perSubject: { [string]: number },
	maxEntries: number,
}

function Journal.new(maxEntries: number?): Journal
	return { entries = {}, seen = {}, perSubject = {}, maxEntries = maxEntries or 200 }
end

export type NewEntry = {
	id: string,
	subject: string,
	text: string,
	day: number,
	clock: string,
	weather: string,
	certainty: Certainty?,
}

-- Returns the stored entry, or nil if this event was already recorded.
function Journal.record(j: Journal, e: NewEntry): Entry?
	if j.seen[e.id] or #j.entries >= j.maxEntries then
		return nil
	end
	local n = (j.perSubject[e.subject] or 0) + 1
	j.perSubject[e.subject] = n
	j.seen[e.id] = true
	local entry: Entry = {
		id = e.id,
		subject = e.subject,
		title = string.format("%s - Observation #%d", e.subject, n),
		text = e.text,
		day = e.day,
		clock = e.clock,
		weather = e.weather,
		certainty = e.certainty or "observed",
		number = n,
	}
	table.insert(j.entries, entry)
	return entry
end

function Journal.has(j: Journal, id: string): boolean
	return j.seen[id] == true
end

function Journal.count(j: Journal, subject: string?): number
	if subject then
		return j.perSubject[subject] or 0
	end
	return #j.entries
end

function Journal.formatClock(clockTime: number): string
	local h = math.floor(clockTime) % 24
	local m = math.floor((clockTime - math.floor(clockTime)) * 60)
	return string.format("%02d:%02d", h, m)
end

return Journal

--!strict
-- Picks what an NPC says from ordered, conditional lines. The first entry
-- whose conditions all hold wins, so put the most specific first and an
-- unconditional default last. Pure.

local Dialogue = {}

export type Entry = {
	lines: { string },
	quest: string?, -- with status: the quest must be in that status
	status: string?, -- "locked" | "available" | "active" | "done"
	flag: string?, -- this quest flag must be set
	notFlag: string?, -- this quest flag must not be set
	trust: number?, -- at least this much trust with the speaker
}

export type Facts = {
	quests: { [string]: string },
	flags: { [string]: boolean },
	trust: number,
}

function Dialogue.matches(e: Entry, f: Facts): boolean
	if e.quest and (f.quests[e.quest] or "locked") ~= (e.status or "done") then
		return false
	end
	if e.flag and not f.flags[e.flag] then
		return false
	end
	if e.notFlag and f.flags[e.notFlag] then
		return false
	end
	if e.trust and f.trust < e.trust then
		return false
	end
	return true
end

function Dialogue.pick(entries: { Entry }, f: Facts): { string }?
	for _, e in entries do
		if Dialogue.matches(e, f) then
			return e.lines
		end
	end
	return nil
end

return Dialogue

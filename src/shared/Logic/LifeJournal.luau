--!strict
-- Builds the Life Journal's four tabs (HOME, TOWN, PEOPLE, MYSTERIES) and the
-- on-screen tracker from plain progress data. The server fills the input from
-- the player's saved state; the client only renders sections and rows. Pure.

local LifeJournal = {}

export type QuestRow = {
	id: string,
	title: string,
	giverName: string,
	place: string,
	status: string, -- "available" | "active" | "done"
	category: string, -- "town" | "maya" | "dog" | "mystery"
	optional: boolean,
	context: string,
	objective: string?,
	progress: string?,
	fraction: number?,
	opens: { string }?, -- titles of quests this one unlocked
}

export type Person = {
	id: string,
	name: string,
	role: string,
	trust: number,
	maxTrust: number,
	note: string,
}

export type Project = {
	name: string,
	stage: string,
	fraction: number,
	benefit: string,
	done: boolean,
}

export type Input = {
	quests: { QuestRow },
	tracked: string?,
	credits: number,
	reputation: number,
	tier: string,
	nextTier: string?,
	tierFraction: number,
	people: { Person },
	projects: { Project },
	skills: { { name: string, level: number, max: number } },
	forecast: string?,
	incident: string?,
	milestones: { { name: string, done: boolean } },
	changes: { string },
	observations: number,
}

export type Row = {
	title: string,
	detail: string?,
	right: string?,
	bar: number?,
	tone: string?, -- "good" | "warn" | "muted" | nil
}

export type Section = { heading: string, rows: { Row }, empty: string? }
export type Tab = { id: string, sections: { Section } }
export type Tracker = { id: string, title: string, objective: string, progress: string?, available: boolean? }
export type View = { tabs: { Tab }, tracker: Tracker?, credits: number, tier: string }

local function questRow(q: QuestRow): Row
	if q.status == "active" then
		return {
			title = q.title,
			detail = (q.objective or "")
				.. (if q.progress and q.progress ~= "" then "  ·  " .. q.progress else ""),
			right = q.giverName,
			bar = q.fraction,
		}
	elseif q.status == "available" then
		return {
			title = q.title,
			detail = string.format("%s, %s. %s", q.giverName, q.place, q.context),
			right = "New",
			tone = "warn",
		}
	end
	local opens = if q.opens and #q.opens > 0 then "  ·  Opened: " .. table.concat(q.opens, ", ") else ""
	return { title = q.title, detail = "Done" .. opens, right = q.giverName, tone = "good" }
end

local function filter(quests: { QuestRow }, keep: (QuestRow) -> boolean): { Row }
	local rows = {}
	for _, q in quests do
		if keep(q) then
			table.insert(rows, questRow(q))
		end
	end
	return rows
end

local function home(input: Input): Tab
	local today: { Row } = {}
	if input.forecast then
		table.insert(today, { title = "Forecast", detail = input.forecast, tone = "good" })
	end
	if input.incident then
		table.insert(today, { title = "Happening today", detail = input.incident, tone = "warn" })
	end
	local caramelo: { Row } = {}
	for _, s in input.skills do
		table.insert(caramelo, {
			title = s.name,
			right = string.format("%d/%d", s.level, s.max),
			bar = s.level / math.max(s.max, 1),
		})
	end
	return {
		id = "HOME",
		sections = {
			{
				heading = "Today",
				rows = today,
				empty = "A quiet day. Good for chores, a walk, or the porch.",
			},
			{
				heading = "Errands",
				rows = filter(input.quests, function(q)
					return q.status == "active" and not q.optional
				end),
				empty = "Nothing in hand. People in Pinehaven could use help.",
			},
			{
				heading = "Could do",
				rows = filter(input.quests, function(q)
					return q.status == "available" and not q.optional
				end),
				empty = "Nobody is asking right now.",
			},
			{ heading = "Caramelo", rows = caramelo },
		},
	}
end

local function town(input: Input): Tab
	local standing: { Row } = {
		{
			title = input.tier,
			detail = if input.nextTier
				then "Next: " .. input.nextTier
				else "Pinehaven counts you as one of its own.",
			right = string.format("%d rep", input.reputation),
			bar = input.tierFraction,
		},
		{ title = "Pinehaven Credits", right = tostring(input.credits) },
	}
	local projects: { Row } = {}
	for _, p in input.projects do
		table.insert(projects, {
			title = p.name,
			detail = p.stage .. "  ·  " .. p.benefit,
			bar = p.fraction,
			tone = if p.done then "good" else nil,
		})
	end
	local changes: { Row } = {}
	for _, c in input.changes do
		table.insert(changes, { title = c, tone = "good" })
	end
	return {
		id = "TOWN",
		sections = {
			{ heading = "Standing", rows = standing },
			{ heading = "Restoration", rows = projects, empty = "No repairs started." },
			{ heading = "Because of you", rows = changes, empty = "The town hasn't changed yet." },
			{
				heading = "Finished",
				rows = filter(input.quests, function(q)
					return q.status == "done" and not q.optional
				end),
				empty = "Nothing finished yet.",
			},
		},
	}
end

local function people(input: Input): Tab
	local rows: { Row } = {}
	for _, p in input.people do
		table.insert(rows, {
			title = p.name .. "  ·  " .. p.role,
			detail = p.note,
			right = string.format("trust %d/%d", p.trust, p.maxTrust),
			bar = p.trust / math.max(p.maxTrust, 1),
		})
	end
	local maya: { Row } = {}
	for _, m in input.milestones do
		table.insert(maya, {
			title = m.name,
			right = if m.done then "Done" else "Not yet",
			tone = if m.done then "good" else "muted",
		})
	end
	return {
		id = "PEOPLE",
		sections = {
			{ heading = "Maya", rows = maya },
			{ heading = "Pinehaven", rows = rows },
		},
	}
end

local function mysteries(input: Input): Tab
	return {
		id = "MYSTERIES",
		sections = {
			{
				heading = "Research (optional)",
				rows = filter(input.quests, function(q)
					return q.optional
				end),
				empty = "Nothing here needs doing. Watching the dark is a choice, never a chore.",
			},
			{
				heading = "Observations",
				rows = {
					{
						title = string.format("%d entries in the observation journal", input.observations),
						detail = "Sightings from your windows are listed below.",
						tone = "muted",
					},
				},
			},
		},
	}
end

local function tracker(input: Input): Tracker?
	local pick: QuestRow? = nil
	for _, q in input.quests do
		if q.status == "active" then
			if q.id == input.tracked then
				pick = q
				break
			elseif not pick and not q.optional then
				pick = q
			end
		end
	end
	if not pick then
		-- Nothing in hand: point at someone who could use help.
		for _, q in input.quests do
			if q.status == "available" and not q.optional then
				return {
					id = q.id,
					title = "New: " .. q.title,
					objective = string.format("Talk to %s, %s", q.giverName, q.place),
					available = true,
				}
			end
		end
		return nil
	end
	return {
		id = pick.id,
		title = pick.title,
		objective = pick.objective or "",
		progress = if pick.progress ~= "" then pick.progress else nil,
	}
end

function LifeJournal.build(input: Input): View
	return {
		tabs = { home(input), town(input), people(input), mysteries(input) },
		tracker = tracker(input),
		credits = input.credits,
		tier = input.tier,
	}
end

return LifeJournal

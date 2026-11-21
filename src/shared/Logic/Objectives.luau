--!strict
-- Reusable quest objective components. Every quest objective names one kind;
-- the kind decides which server event moves it and how far. Pure: no
-- requires, no Roblox services.
--
--   collect      have items in the pack (re-checked, can go back down)
--   deliver      hand items to an NPC (the server spends them first)
--   repair       actions done on a restoration project
--   reach        arrive at a site
--   talk         speak to an NPC
--   interact     use a world object (count times)
--   observe      record a creature from a safe window (count times)
--   weather      sheltered seconds in a weather type
--   investigate  search a site
--   locate       find a missing NPC or animal
--   inspect      look closely at a thing (a shutter, a circuit, a radio)
--   escort       bring someone to a place (count people)
--   track        follow a trail to its end (Caramelo)
--   communicate  reach someone by radio
--   activate     switch on a device (count devices)
--   coordinate   get enough participants ready (the event carries how many)
--   survive      come through a night or event of a given kind
--
-- An event may carry `evidence`, a unique id for what was seen or done;
-- Quests counts each id once per quest, so the same sighting or the same
-- switch never counts twice. An objective may list `anyOf` alternatives:
-- any one of them completes it (repair the truck, or lead them to the
-- shelter), and the chosen one's `flag` records which.

local Objectives = {}

export type Objective = {
	kind: string,
	text: string,
	target: string?,
	items: { [string]: number }?,
	count: number?,
	phases: { string }?,
	hint: string?,
	say: { string }?,
	anyOf: { Objective }?,
	flag: string?,
}

export type Event = {
	kind: string,
	target: string?,
	amount: number?,
	inventory: { [string]: number }?,
	phase: string?,
	evidence: string?,
}

type Step = (obj: Objective, progress: number, ev: Event, goal: number) -> number

export type Component = {
	event: string,
	targeted: boolean,
	unit: string?,
	step: Step,
}

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

local function sortedKeys(items: { [string]: number }): { string }
	local keys = {}
	for k in items do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

local function haveItems(obj: Objective, _progress: number, ev: Event, _goal: number): number
	local inv = ev.inventory or {}
	local total = 0
	local items: { [string]: number } = obj.items or {}
	for item, need in items do
		local have = inv[item] or 0
		total += math.min(if finite(have) then have else 0, need)
	end
	return total
end

local function finish(_obj: Objective, _progress: number, _ev: Event, goal: number): number
	return goal
end

local function count(_obj: Objective, progress: number, ev: Event, _goal: number): number
	local n = ev.amount or 1
	return progress + (if finite(n) and n > 0 then n else 0)
end

local function atLeast(_obj: Objective, progress: number, ev: Event, _goal: number): number
	local n = ev.amount or 0
	return if finite(n) then math.max(progress, n) else progress
end

Objectives.Kinds = {
	collect = { event = "inventory", targeted = false, step = haveItems },
	deliver = { event = "deliver", targeted = true, step = finish },
	repair = { event = "repair", targeted = true, step = atLeast },
	reach = { event = "reach", targeted = true, step = finish },
	talk = { event = "talk", targeted = true, step = finish },
	interact = { event = "interact", targeted = true, step = count },
	observe = { event = "observe", targeted = true, step = count },
	weather = { event = "weather", targeted = true, unit = "s", step = count },
	investigate = { event = "investigate", targeted = true, step = finish },
	locate = { event = "locate", targeted = true, step = finish },
	inspect = { event = "inspect", targeted = true, step = finish },
	escort = { event = "escort", targeted = true, step = count },
	track = { event = "track", targeted = true, step = finish },
	communicate = { event = "communicate", targeted = true, step = finish },
	activate = { event = "activate", targeted = true, step = count },
	coordinate = { event = "coordinate", targeted = true, step = atLeast },
	survive = { event = "survive", targeted = true, step = count },
} :: { [string]: Component }

function Objectives.known(kind: string): boolean
	return Objectives.Kinds[kind] ~= nil
end

function Objectives.goal(obj: Objective): number
	if obj.items then
		local total = 0
		for _, n in obj.items do
			total += n
		end
		return math.max(1, total)
	end
	return math.max(1, obj.count or 1)
end

local function phaseOk(obj: Objective, ev: Event): boolean
	local phases = obj.phases
	if not phases then
		return true
	end
	for _, p in phases do
		if p == ev.phase then
			return true
		end
	end
	return false
end

-- Feeds one event to one objective. Returns the new progress (0..goal) and
-- whether the objective is now complete. Unrelated events change nothing.
function Objectives.apply(obj: Objective, progress: number, ev: Event): (number, boolean)
	local c = Objectives.Kinds[obj.kind]
	local goal = Objectives.goal(obj)
	if not c or ev.kind ~= c.event then
		return progress, progress >= goal
	end
	if c.targeted and ev.target ~= obj.target then
		return progress, progress >= goal
	end
	if not phaseOk(obj, ev) then
		return progress, progress >= goal
	end
	local p = math.clamp(c.step(obj, progress, ev, goal), 0, goal)
	return p, p >= goal
end

-- "3/8", "Wood 3/8 · Fiber 0/2", "40/60 s", or "" for one-shot objectives.
function Objectives.progressText(obj: Objective, progress: number, inventory: { [string]: number }?): string
	local items = obj.items
	if items then
		local parts = {}
		local inv = inventory or {}
		for _, item in sortedKeys(items) do
			local need = items[item]
			table.insert(parts, string.format("%s %d/%d", item, math.min(inv[item] or 0, need), need))
		end
		return table.concat(parts, " · ")
	end
	local goal = Objectives.goal(obj)
	if goal <= 1 then
		return ""
	end
	local c = Objectives.Kinds[obj.kind]
	local unit = if c and c.unit then " " .. c.unit else ""
	return string.format("%d/%d%s", math.floor(progress), goal, unit)
end

return Objectives

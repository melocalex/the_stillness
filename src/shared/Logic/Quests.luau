--!strict
-- Data-driven quests. Definitions live in QuestConfig; this module keeps one
-- player's quest log: prerequisites, start, routing events to the current
-- objective (objectives run in order), completion, expiry and persistent
-- flags (world consequences and milestones). Rewards are paid by the caller
-- through Town's one-time ledger. Pure: the objective components are passed
-- in (the Objectives module), nothing is required.

local Quests = {}

export type Objective = {
	kind: string,
	text: string,
	target: string?,
	items: { [string]: number }?,
	count: number?,
	phases: { string }?,
	hint: string?,
	say: { string }?,
}

export type Rewards = {
	credits: number?,
	reputation: number?,
	trust: { [string]: number }?,
	items: { [string]: number }?,
	dogSkill: { [string]: number }?,
	comfort: number?,
}

export type Requires = {
	quests: { string }?,
	flags: { string }?,
	reputation: number?,
	trust: { [string]: number }?,
}

export type Def = {
	id: string,
	giver: string,
	title: string,
	context: string,
	category: string,
	optional: boolean?,
	requires: Requires?,
	objectives: { Objective },
	rewards: Rewards,
	expiresAfter: number?,
	consequences: { string }?,
	followUps: { string }?,
	intro: { string }?,
	outro: { string }?,
	reminder: string?,
}

export type Entry = {
	status: string, -- "active" | "done" | "expired"
	step: number,
	progress: number,
	startedAt: number,
	doneAt: number?,
	expiresAt: number?,
}

export type Log = {
	entries: { [string]: Entry },
	flags: { [string]: boolean },
}

export type Context = {
	reputation: number,
	trust: { [string]: number },
	now: number,
}

export type Change = {
	id: string,
	step: number,
	progress: number,
	objectiveDone: boolean,
	completed: boolean,
}

export type Components = {
	apply: (obj: any, progress: number, ev: any) -> (number, boolean),
}

local STATUSES = { active = true, done = true, expired = true }
local MAX_FLAGS = 256

function Quests.new(): Log
	return { entries = {}, flags = {} }
end

function Quests.byId(defs: { Def }): { [string]: Def }
	local map = {}
	for _, d in defs do
		map[d.id] = d
	end
	return map
end

function Quests.isDone(log: Log, id: string): boolean
	local e = log.entries[id]
	return e ~= nil and e.status == "done"
end

function Quests.setFlag(log: Log, name: string)
	log.flags[name] = true
end

function Quests.hasFlag(log: Log, name: string): boolean
	return log.flags[name] == true
end

-- Returns whether the quest may be offered, and why not.
function Quests.requirementsMet(log: Log, def: Def, ctx: Context): (boolean, string?)
	local r = def.requires
	if not r then
		return true, nil
	end
	local quests: { string } = r.quests or {}
	for _, q in quests do
		if not Quests.isDone(log, q) then
			return false, "quest:" .. q
		end
	end
	local flags: { string } = r.flags or {}
	for _, f in flags do
		if not Quests.hasFlag(log, f) then
			return false, "flag:" .. f
		end
	end
	if r.reputation and ctx.reputation < r.reputation then
		return false, "reputation"
	end
	local trust: { [string]: number } = r.trust or {}
	for npc, n in trust do
		if (ctx.trust[npc] or 0) < n then
			return false, "trust:" .. npc
		end
	end
	return true, nil
end

-- "locked" | "available" | "active" | "done". An expired quest is offered again.
function Quests.status(log: Log, def: Def, ctx: Context): string
	local e = log.entries[def.id]
	if e and (e.status == "active" or e.status == "done") then
		return e.status
	end
	return if Quests.requirementsMet(log, def, ctx) then "available" else "locked"
end

function Quests.available(log: Log, defs: { Def }, ctx: Context): { Def }
	local out = {}
	for _, d in defs do
		if Quests.status(log, d, ctx) == "available" then
			table.insert(out, d)
		end
	end
	return out
end

function Quests.start(log: Log, def: Def, ctx: Context): (boolean, string?)
	local status = Quests.status(log, def, ctx)
	if status ~= "available" then
		return false, status
	end
	log.entries[def.id] = {
		status = "active",
		step = 1,
		progress = 0,
		startedAt = ctx.now,
		expiresAt = if def.expiresAfter then ctx.now + def.expiresAfter else nil,
	}
	return true, nil
end

function Quests.current(log: Log, def: Def): (Objective?, number)
	local e = log.entries[def.id]
	if not e or e.status ~= "active" then
		return nil, 0
	end
	return def.objectives[e.step], e.progress
end

local function complete(log: Log, def: Def, e: Entry, now: number)
	e.status = "done"
	e.step = #def.objectives + 1
	e.progress = 0
	e.doneAt = now
	e.expiresAt = nil
	local consequences: { string } = def.consequences or {}
	for _, flag in consequences do
		log.flags[flag] = true
	end
end

-- Routes one event to every active quest's current objective, in definition
-- order. An objective that completes moves its quest to the next one; the
-- last one completes the quest. Returns what changed.
function Quests.apply(log: Log, defs: { Def }, ev: any, components: Components, now: number): { Change }
	local changes: { Change } = {}
	for _, def in defs do
		local e = log.entries[def.id]
		local obj = if e and e.status == "active" then def.objectives[e.step] else nil
		if e and obj then
			local p, done = components.apply(obj, e.progress, ev)
			if p ~= e.progress or done then
				local step = e.step
				e.progress = p
				local completed = false
				if done then
					e.step += 1
					e.progress = 0
					if e.step > #def.objectives then
						complete(log, def, e, now)
						completed = true
					end
				end
				table.insert(changes, {
					id = def.id,
					step = step,
					progress = p,
					objectiveDone = done,
					completed = completed,
				})
			end
		end
	end
	return changes
end

-- Active quests past their deadline become "expired" (offered again later).
function Quests.expire(log: Log, defs: { Def }, now: number): { string }
	local out = {}
	for _, def in defs do
		local e = log.entries[def.id]
		if e and e.status == "active" and e.expiresAt and now >= e.expiresAt then
			e.status = "expired"
			table.insert(out, def.id)
		end
	end
	return out
end

function Quests.snapshot(log: Log): { [string]: any }
	local entries = {}
	for id, e in log.entries do
		entries[id] = {
			status = e.status,
			step = e.step,
			progress = e.progress,
			startedAt = e.startedAt,
			doneAt = e.doneAt,
			expiresAt = e.expiresAt,
		}
	end
	return { entries = entries, flags = table.clone(log.flags) }
end

local function num(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v or v < lo or v > hi then
		return nil
	end
	return v
end

-- Rebuilds a log from untrusted saved data: unknown quests, bad statuses and
-- out-of-range steps are dropped, never trusted.
function Quests.restore(data: any, defs: { Def }): Log
	local log = Quests.new()
	if type(data) ~= "table" then
		return log
	end
	local map = Quests.byId(defs)
	if type(data.entries) == "table" then
		for id, raw in data.entries do
			local def = if type(id) == "string" then map[id] else nil
			if def and type(raw) == "table" and type(raw.status) == "string" and STATUSES[raw.status] then
				local n = #def.objectives
				-- A step past the end (the quest lost an objective) clamps to the last.
				local step = num(raw.step, 1, 1e6)
				local progress = num(raw.progress, 0, 1e6)
				local startedAt = num(raw.startedAt, 0, 1e12)
				if step and progress and startedAt and math.floor(step) == step then
					local status: string = raw.status
					if status == "done" then
						step, progress = n + 1, 0
					elseif step > n then
						step = n
					end
					log.entries[id] = {
						status = status,
						step = step,
						progress = progress,
						startedAt = startedAt,
						doneAt = num(raw.doneAt, 0, 1e12),
						expiresAt = if status == "active" then num(raw.expiresAt, 0, 1e12) else nil,
					}
				end
			end
		end
	end
	if type(data.flags) == "table" then
		local count = 0
		for k, v in data.flags do
			if type(k) == "string" and #k <= 64 and v == true and count < MAX_FLAGS then
				log.flags[k] = true
				count += 1
			end
		end
	end
	return log
end

return Quests

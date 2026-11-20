--!strict
-- Restoration projects: a building or structure repaired in ordered actions,
-- each with a resource cost. The number of actions done is the visual stage
-- (0 = broken, #actions = restored). The caller spends the cost, then calls
-- advance. Pure: no requires.

local Restoration = {}

export type Action = { id: string, text: string, cost: { [string]: number } }

export type Project = {
	id: string,
	name: string,
	site: string,
	quest: string?, -- repairs open once this quest is active
	actions: { Action },
	stages: { string }, -- one name per stage, #actions + 1 entries
	benefit: string,
	ack: { npc: string, line: string }?,
}

export type State = { [string]: number }

function Restoration.new(): State
	return {}
end

function Restoration.stage(st: State, p: Project): number
	return math.clamp(st[p.id] or 0, 0, #p.actions)
end

function Restoration.complete(st: State, p: Project): boolean
	return Restoration.stage(st, p) >= #p.actions
end

function Restoration.nextAction(st: State, p: Project): Action?
	return p.actions[Restoration.stage(st, p) + 1]
end

function Restoration.stageName(st: State, p: Project): string
	return p.stages[Restoration.stage(st, p) + 1] or ""
end

function Restoration.fraction(st: State, p: Project): number
	return Restoration.stage(st, p) / math.max(#p.actions, 1)
end

-- One paid action. Returns the new stage and whether this finished it.
-- A finished project never advances again.
function Restoration.advance(st: State, p: Project): (number, boolean)
	local s = Restoration.stage(st, p)
	if s >= #p.actions then
		return s, false
	end
	s += 1
	st[p.id] = s
	return s, s >= #p.actions
end

-- The world shows the furthest stage among the players present.
function Restoration.union(states: { State }, p: Project): number
	local best = 0
	for _, st in states do
		best = math.max(best, Restoration.stage(st, p))
	end
	return best
end

function Restoration.restore(data: any, projects: { Project }): State
	local st = Restoration.new()
	if type(data) ~= "table" then
		return st
	end
	for _, p in projects do
		local v = data[p.id]
		if type(v) == "number" and v == v and v >= 0 and math.floor(v) == v then
			st[p.id] = math.min(v, #p.actions)
		end
	end
	return st
end

return Restoration

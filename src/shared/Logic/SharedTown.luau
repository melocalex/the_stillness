--!strict
-- Pinehaven's shared state: what the town has become, for everyone, kept
-- apart from any one player's save. Repaired community buildings (stages),
-- opened routes and town-wide flags. Every change only moves forward, so
-- states saved by different servers merge without losing anything (max of
-- each stage, union of routes and flags). Readiness is only a summary of
-- the real pieces. Pure: no requires.
--
-- Per-player state (Quests, Town standing, personal projects) stays in the
-- player's save. Town-scope restoration projects use `buildings` here with
-- the same Restoration functions.

local SharedTown = {}

export type State = {
	buildings: { [string]: number },
	routes: { [string]: boolean },
	flags: { [string]: boolean },
}

local MAX_KEYS = 256

function SharedTown.new(): State
	return { buildings = {}, routes = {}, flags = {} }
end

-- Raises a building's stage; never lowers it. Returns whether it changed.
function SharedTown.raiseBuilding(st: State, id: string, stage: number): boolean
	if stage ~= stage or stage <= (st.buildings[id] or 0) then
		return false
	end
	st.buildings[id] = math.floor(stage)
	return true
end

function SharedTown.openRoute(st: State, id: string): boolean
	if st.routes[id] then
		return false
	end
	st.routes[id] = true
	return true
end

function SharedTown.setFlag(st: State, id: string): boolean
	if st.flags[id] then
		return false
	end
	st.flags[id] = true
	return true
end

-- Combines two states (this server's and the saved one) without losing
-- either side's progress.
function SharedTown.merge(a: State, b: State): State
	local out = SharedTown.new()
	for _, s in { a, b } do
		for id, stage in s.buildings do
			out.buildings[id] = math.max(out.buildings[id] or 0, stage)
		end
		for id in s.routes do
			out.routes[id] = true
		end
		for id in s.flags do
			out.flags[id] = true
		end
	end
	return out
end

-- A summary for the journal: finished town projects and open routes.
-- `goals` maps a building id to the stage that counts as finished.
function SharedTown.readiness(st: State, goals: { [string]: number }): (number, number)
	local done, total = 0, 0
	for id, goal in goals do
		total += 1
		if (st.buildings[id] or 0) >= goal then
			done += 1
		end
	end
	return done, total
end

function SharedTown.snapshot(st: State): { [string]: any }
	local routes, flags = {}, {}
	for id in st.routes do
		table.insert(routes, id)
	end
	for id in st.flags do
		table.insert(flags, id)
	end
	table.sort(routes)
	table.sort(flags)
	return { buildings = table.clone(st.buildings), routes = routes, flags = flags }
end

local function names(list: any, into: { [string]: boolean })
	if type(list) ~= "table" then
		return
	end
	local n = 0
	for _, id in list do
		if type(id) == "string" and #id <= 64 and n < MAX_KEYS then
			into[id] = true
			n += 1
		end
	end
end

-- Rebuilds from untrusted saved data.
function SharedTown.restore(data: any): State
	local st = SharedTown.new()
	if type(data) ~= "table" then
		return st
	end
	if type(data.buildings) == "table" then
		local n = 0
		for id, stage in data.buildings do
			if
				type(id) == "string"
				and #id <= 64
				and type(stage) == "number"
				and stage == stage
				and stage >= 0
				and stage < 1000
				and n < MAX_KEYS
			then
				st.buildings[id] = math.floor(stage)
				n += 1
			end
		end
	end
	names(data.routes, st.routes)
	names(data.flags, st.flags)
	return st
end

return SharedTown

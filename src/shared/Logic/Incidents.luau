--!strict
-- The small incident director: which incidents may happen now, a weighted
-- pick among them, and cooldowns. Incidents are world events for everyone on
-- the server; rewards are capped per player elsewhere (Town.earn). Most are
-- peaceful errands. Pure: no requires.

local Incidents = {}

export type Def = {
	id: string,
	title: string,
	weight: number,
	peaceful: boolean,
	cooldownDays: number,
	phases: { string }?,
	weather: { string }?,
	afterNights: { string }?, -- only after one of these night types
	flags: { string }?, -- someone present must have these quest flags
	minDay: number?,
}

export type Context = {
	day: number,
	phase: string,
	weather: string,
	lastNight: string?,
	flags: { [string]: boolean },
}

export type State = {
	last: { [string]: number },
	perDay: { [number]: number },
}

function Incidents.new(): State
	return { last = {}, perDay = {} }
end

local function contains(list: { string }?, v: string?): boolean
	if not list then
		return true
	end
	for _, x in list do
		if x == v then
			return true
		end
	end
	return false
end

function Incidents.isEligible(def: Def, st: State, ctx: Context): boolean
	if def.minDay and ctx.day < def.minDay then
		return false
	end
	local last = st.last[def.id]
	if last and ctx.day - last < def.cooldownDays then
		return false
	end
	if not contains(def.phases, ctx.phase) or not contains(def.weather, ctx.weather) then
		return false
	end
	if def.afterNights and not contains(def.afterNights, ctx.lastNight) then
		return false
	end
	local flags: { string } = def.flags or {}
	for _, f in flags do
		if not ctx.flags[f] then
			return false
		end
	end
	return true
end

-- Eligible incidents, or none once today's budget is used.
function Incidents.eligible(defs: { Def }, st: State, ctx: Context, perDay: number): { Def }
	local out = {}
	if (st.perDay[ctx.day] or 0) >= perDay then
		return out
	end
	for _, d in defs do
		if d.weight > 0 and Incidents.isEligible(d, st, ctx) then
			table.insert(out, d)
		end
	end
	return out
end

-- Weighted choice; roll is a uniform number in [0, 1).
function Incidents.choose(list: { Def }, roll: number): Def?
	local total = 0
	for _, d in list do
		total += d.weight
	end
	if total <= 0 then
		return nil
	end
	local pick = math.clamp(roll, 0, 0.999999) * total
	for _, d in list do
		pick -= d.weight
		if pick < 0 then
			return d
		end
	end
	return list[#list]
end

function Incidents.fire(st: State, def: Def, day: number)
	st.last[def.id] = day
	st.perDay[day] = (st.perDay[day] or 0) + 1
end

return Incidents

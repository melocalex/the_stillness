--!strict
-- Pure shelter rules. A shelter is an explicit, registered volume with a list
-- of entry points (doors, windows, roof). We never infer enclosure from
-- geometry: the cabin is built from known modules, and each module reports
-- its own state. These rules are what "safe" means everywhere in the game.

local Shelter = {}

export type Integrity = "INTACT" | "SCRATCHED" | "DAMAGED" | "CRACKED" | "BREACHED"
export type EntryKind = "door" | "window" | "roof"

export type EntryPoint = {
	id: string,
	kind: EntryKind,
	installed: boolean, -- false: missing or broken off, a hole
	open: boolean,
	health: number,
	maxHealth: number,
	shuttered: boolean?,
}

export type Evaluation = {
	secure: boolean,
	reasons: { string },
	weakest: Integrity,
	weakestId: string?,
}

local ORDER: { Integrity } = { "INTACT", "SCRATCHED", "DAMAGED", "CRACKED", "BREACHED" }
local RANK: { [Integrity]: number } = { INTACT = 1, SCRATCHED = 2, DAMAGED = 3, CRACKED = 4, BREACHED = 5 }

function Shelter.integrityFor(health: number, maxHealth: number): Integrity
	if maxHealth <= 0 or health <= 0 then
		return "BREACHED"
	end
	local f = health / maxHealth
	if f >= 0.999 then
		return "INTACT"
	elseif f > 0.8 then
		return "SCRATCHED"
	elseif f > 0.5 then
		return "DAMAGED"
	end
	return "CRACKED"
end

function Shelter.rank(i: Integrity): number
	return RANK[i]
end

function Shelter.order(): { Integrity }
	return table.clone(ORDER)
end

-- Secure means: every entry point exists, is shut, and is not breached.
-- Damage short of a breach does not make a shelter insecure.
function Shelter.evaluate(entries: { EntryPoint }): Evaluation
	local reasons = {}
	local weakest: Integrity = "INTACT"
	local weakestId: string? = nil
	for _, e in entries do
		local integrity: Integrity = if e.installed
			then Shelter.integrityFor(e.health, e.maxHealth)
			else "BREACHED"
		if RANK[integrity] > RANK[weakest] then
			weakest = integrity
			weakestId = e.id
		end
		if not e.installed then
			table.insert(reasons, e.id .. " is missing")
		elseif integrity == "BREACHED" then
			table.insert(reasons, e.id .. " is broken through")
		elseif e.open then
			table.insert(reasons, e.id .. " is open")
		end
	end
	return { secure = #reasons == 0, reasons = reasons, weakest = weakest, weakestId = weakestId }
end

-- Can an ordinary creature that respects shelters physically come inside?
-- Only through an opening. It never teleports past intact walls.
function Shelter.canEnter(evaluation: Evaluation): boolean
	return not evaluation.secure
end

-- Can this creature harm a player standing inside?
function Shelter.canHarmInside(evaluation: Evaluation, respectsShelter: boolean): boolean
	if not respectsShelter then
		return true
	end
	return not evaluation.secure
end

export type BreachRules = {
	groupThreshold: number, -- attackers needed to do real damage
	soloDamageFloor: number, -- fraction of health a lone attacker cannot go below
}

-- Damage applied this tick to one entry point by the creatures attacking it.
-- A single ordinary creature can only scratch; a coordinated group breaks in.
-- Returns the new health.
function Shelter.applyAttack(
	health: number,
	maxHealth: number,
	attackers: number,
	damagePerAttacker: number,
	resistance: number,
	dt: number,
	rules: BreachRules
): number
	if attackers <= 0 or health <= 0 then
		return health
	end
	local raw = attackers * damagePerAttacker * dt / math.max(resistance, 0.01)
	local newHealth = health - raw
	if attackers < rules.groupThreshold then
		local floor = maxHealth * rules.soloDamageFloor
		newHealth = math.max(newHealth, math.min(health, floor))
	end
	return math.max(newHealth, 0)
end

return Shelter

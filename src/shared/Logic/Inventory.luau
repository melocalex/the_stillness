--!strict
-- Pure inventory ledger. The server owns one per player; clients only ever
-- receive copies. Every mutation is all-or-nothing.

local Inventory = {}

export type Cost = { [string]: number }
export type Inventory = {
	items: { [string]: number },
	caps: { [string]: number },
	defaultCap: number,
}

function Inventory.new(caps: { [string]: number }?, defaultCap: number?): Inventory
	return { items = {}, caps = caps or {}, defaultCap = defaultCap or 99 }
end

function Inventory.count(inv: Inventory, item: string): number
	return inv.items[item] or 0
end

function Inventory.capFor(inv: Inventory, item: string): number
	return inv.caps[item] or inv.defaultCap
end

local function validAmount(n: number): boolean
	return n == n and n >= 0 and n < math.huge and math.floor(n) == n
end

-- Adds up to `n`, respecting the cap. Returns how many were actually added.
function Inventory.add(inv: Inventory, item: string, n: number): number
	if not validAmount(n) or n == 0 then
		return 0
	end
	local have = Inventory.count(inv, item)
	local room = math.max(Inventory.capFor(inv, item) - have, 0)
	local added = math.min(n, room)
	if added > 0 then
		inv.items[item] = have + added
	end
	return added
end

function Inventory.canAfford(inv: Inventory, cost: Cost): boolean
	for item, n in cost do
		if not validAmount(n) or Inventory.count(inv, item) < n then
			return false
		end
	end
	return true
end

-- Atomically removes the whole cost. Returns false and changes nothing if any part is missing.
function Inventory.spend(inv: Inventory, cost: Cost): boolean
	if not Inventory.canAfford(inv, cost) then
		return false
	end
	for item, n in cost do
		local left = Inventory.count(inv, item) - n
		if left > 0 then
			inv.items[item] = left
		else
			inv.items[item] = nil
		end
	end
	return true
end

function Inventory.remove(inv: Inventory, item: string, n: number): number
	if not validAmount(n) then
		return 0
	end
	local have = Inventory.count(inv, item)
	local taken = math.min(have, n)
	local left = have - taken
	if left > 0 then
		inv.items[item] = left
	else
		inv.items[item] = nil
	end
	return taken
end

-- Lose a fraction of each listed item (rounded down). Returns what was lost.
function Inventory.loseFraction(inv: Inventory, fraction: number, affected: { string }): { [string]: number }
	local lost = {}
	for _, item in affected do
		local n = math.floor(Inventory.count(inv, item) * math.clamp(fraction, 0, 1))
		if n > 0 then
			lost[item] = Inventory.remove(inv, item, n)
		end
	end
	return lost
end

function Inventory.snapshot(inv: Inventory): { [string]: number }
	return table.clone(inv.items)
end

-- Rebuilds from untrusted saved data: unknown items and bad amounts are dropped.
function Inventory.restore(inv: Inventory, data: any, known: { [string]: any })
	if type(data) ~= "table" then
		return
	end
	for item, n in data do
		if type(item) == "string" and known[item] ~= nil and type(n) == "number" and validAmount(n) then
			inv.items[item] = math.min(n, Inventory.capFor(inv, item))
		end
	end
end

return Inventory

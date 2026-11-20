--!strict
-- Pinehaven standing for one player: reputation, Pinehaven Credits, trust per
-- NPC, a one-time payout ledger, capped small earnings and shop purchases.
--
-- Farming rules: a keyed payout (a quest, a finished project) is paid once,
-- ever. Small repeatable earnings (incidents) are capped per real-time
-- window, and shop limits use the same windows. Windows come from the
-- caller (os.time based), never from the per-server game day, so leaving and
-- rejoining resets nothing. Pure: no requires.

local Town = {}

export type Reward = {
	credits: number?,
	reputation: number?,
	trust: { [string]: number }?,
}

export type Limits = {
	maxCredits: number,
	maxReputation: number,
	maxTrust: number,
}

export type Tier = { name: string, min: number }

export type Offer = {
	id: string,
	vendor: string,
	item: string,
	amount: number,
	price: number,
	limit: number?, -- per window
	once: boolean?,
	minTier: number?, -- index into the tier list
	flag: string?, -- a quest flag that opens this offer
}

export type State = {
	credits: number,
	reputation: number,
	trust: { [string]: number },
	granted: { [string]: boolean },
	bought: { [string]: { window: number, n: number } },
	owned: { [string]: boolean },
	earned: { window: number, credits: number, reputation: number },
}

export type BuyContext = {
	window: number,
	tier: number,
	flags: { [string]: boolean },
}

function Town.new(): State
	return {
		credits = 0,
		reputation = 0,
		trust = {},
		granted = {},
		bought = {},
		owned = {},
		earned = { window = -1, credits = 0, reputation = 0 },
	}
end

local function whole(n: any): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.floor(n)
end

local function apply(st: State, reward: Reward, limits: Limits)
	st.credits = math.clamp(st.credits + whole(reward.credits), 0, limits.maxCredits)
	st.reputation = math.clamp(st.reputation + whole(reward.reputation), 0, limits.maxReputation)
	local trust: { [string]: number } = reward.trust or {}
	for npc, n in trust do
		st.trust[npc] = math.clamp((st.trust[npc] or 0) + whole(n), 0, limits.maxTrust)
	end
end

function Town.wasGranted(st: State, key: string): boolean
	return st.granted[key] == true
end

-- Pays a keyed reward exactly once. Returns false for a duplicate.
function Town.grant(st: State, key: string, reward: Reward, limits: Limits): boolean
	if st.granted[key] then
		return false
	end
	st.granted[key] = true
	apply(st, reward, limits)
	return true
end

-- Small repeatable earnings, capped per window. Returns what was paid.
function Town.earn(
	st: State,
	reward: Reward,
	window: number,
	cap: { credits: number, reputation: number },
	limits: Limits
): Reward
	if st.earned.window ~= window then
		st.earned = { window = window, credits = 0, reputation = 0 }
	end
	local c = math.clamp(whole(reward.credits), 0, math.max(cap.credits - st.earned.credits, 0))
	local r = math.clamp(whole(reward.reputation), 0, math.max(cap.reputation - st.earned.reputation, 0))
	st.earned.credits += c
	st.earned.reputation += r
	local paid: Reward = { credits = c, reputation = r }
	apply(st, paid, limits)
	return paid
end

-- Returns the tier index (1-based), the tier, the next tier (or nil) and the
-- fraction of the way to it.
function Town.tier(reputation: number, tiers: { Tier }): (number, Tier, Tier?, number)
	local index = 1
	for i, t in tiers do
		if reputation >= t.min then
			index = i
		end
	end
	local tier, nextTier = tiers[index], tiers[index + 1]
	local fraction = 1
	if nextTier then
		fraction = math.clamp((reputation - tier.min) / (nextTier.min - tier.min), 0, 1)
	end
	return index, tier, nextTier, fraction
end

function Town.canBuy(st: State, offer: Offer, ctx: BuyContext): (boolean, string?)
	if offer.flag and not ctx.flags[offer.flag] then
		return false, "closed"
	end
	if offer.minTier and ctx.tier < offer.minTier then
		return false, "reputation"
	end
	if offer.once and st.owned[offer.id] then
		return false, "owned"
	end
	local b = st.bought[offer.id]
	if offer.limit and b and b.window == ctx.window and b.n >= offer.limit then
		return false, "soldout"
	end
	if st.credits < offer.price then
		return false, "credits"
	end
	return true, nil
end

function Town.buy(st: State, offer: Offer, ctx: BuyContext): (boolean, string?)
	local ok, why = Town.canBuy(st, offer, ctx)
	if not ok then
		return false, why
	end
	st.credits -= offer.price
	local prev = st.bought[offer.id]
	local n = if prev and prev.window == ctx.window then prev.n else 0
	st.bought[offer.id] = { window = ctx.window, n = n + 1 }
	if offer.once then
		st.owned[offer.id] = true
	end
	return true, nil
end

-- Returns an unspent purchase (the pack was full).
function Town.refund(st: State, offer: Offer)
	st.credits += offer.price
	local b = st.bought[offer.id]
	if b and b.n > 0 then
		b.n -= 1
	end
	st.owned[offer.id] = nil
end

function Town.snapshot(st: State): { [string]: any }
	local bought = {}
	for id, b in st.bought do
		bought[id] = { window = b.window, n = b.n }
	end
	return {
		credits = st.credits,
		reputation = st.reputation,
		trust = table.clone(st.trust),
		granted = table.clone(st.granted),
		bought = bought,
		owned = table.clone(st.owned),
		earned = table.clone(st.earned),
	}
end

local function boolSet(v: any, max: number): { [string]: boolean }
	local out = {}
	local n = 0
	if type(v) == "table" then
		for k, x in v do
			if type(k) == "string" and #k <= 80 and x == true and n < max then
				out[k] = true
				n += 1
			end
		end
	end
	return out
end

-- Rebuilds from untrusted saved data, clamped to the limits.
function Town.restore(data: any, limits: Limits): State
	local st = Town.new()
	if type(data) ~= "table" then
		return st
	end
	st.credits = math.clamp(whole(data.credits), 0, limits.maxCredits)
	st.reputation = math.clamp(whole(data.reputation), 0, limits.maxReputation)
	if type(data.trust) == "table" then
		for npc, n in data.trust do
			if type(npc) == "string" and #npc <= 32 then
				st.trust[npc] = math.clamp(whole(n), 0, limits.maxTrust)
			end
		end
	end
	st.granted = boolSet(data.granted, 512)
	st.owned = boolSet(data.owned, 64)
	if type(data.bought) == "table" then
		for id, b in data.bought do
			if type(id) == "string" and #id <= 40 and type(b) == "table" then
				st.bought[id] = { window = whole(b.window), n = math.max(whole(b.n), 0) }
			end
		end
	end
	if type(data.earned) == "table" then
		st.earned = {
			window = whole(data.earned.window),
			credits = math.max(whole(data.earned.credits), 0),
			reputation = math.max(whole(data.earned.reputation), 0),
		}
	end
	return st
end

return Town

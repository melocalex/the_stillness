--!strict
-- Chapter 37 progression for each player: quests, Pinehaven standing,
-- restoration projects and Caramelo's training. Server-authoritative; all
-- rules live in shared/Logic and are tested there. Saved as the
-- "progression" section of the player's save (PlayerService), so it rides
-- the same DataStore write as the inventory.
--
-- Other services report what players do through ProgressBus or by calling
-- ProgressionService.event. TownService gives positions (setLocator) and
-- shows the world; this module never touches world geometry.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local LifeJournal = require(ReplicatedStorage.Shared.Logic.LifeJournal)
local Net = require(ReplicatedStorage.Shared.Net)
local Objectives = require(ReplicatedStorage.Shared.Logic.Objectives)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local Quests = require(ReplicatedStorage.Shared.Logic.Quests)
local Restoration = require(ReplicatedStorage.Shared.Logic.Restoration)
local Town = require(ReplicatedStorage.Shared.Logic.Town)
local TownConfig = require(ReplicatedStorage.Shared.Config.TownConfig)
local NightDirector = require(script.Parent.NightDirector)
local PlayerService = require(script.Parent.PlayerService)
local SharedTownService = require(script.Parent.SharedTownService)
local ProgressBus = require(script.Parent.ProgressBus)
local TimeService = require(script.Parent.TimeService)
local WeatherService = require(script.Parent.WeatherService)

local ProgressionService = {}

local DEFS: { Quests.Def } = QuestConfig.List :: any
local BY_ID = Quests.byId(DEFS)
local PROJECTS: { Restoration.Project } = TownConfig.Projects :: any
local TRACKING_MAX = TownConfig.DogSkills.tracking.max
local LIMITS: Town.Limits = TownConfig.Limits
local OFFERS: { Town.Offer } = TownConfig.Shop :: any

export type Progress = {
	player: Player,
	ready: boolean,
	log: Quests.Log,
	town: Town.State,
	projects: Restoration.State,
	tracking: number, -- Caramelo's Tracking skill, raised by Martha's mission
	gift: number, -- window of Maya's last garden gift
	tracked: string?,
	seconds: { [string]: number }, -- sub-second weather accumulation
}

local states: { [Player]: Progress } = {}
local changedListeners: { (Player) -> () } = {}
local completeListeners: { (Player, string) -> () } = {}
local projectListeners: { (Player, string, number, boolean) -> () } = {}
local locator: ((key: string, player: Player?) -> Vector3?)? = nil
local incidentText: string? = nil
local forecastText: string? = nil

local function now(): number
	return os.time()
end

local function list(t: { string }?): { string }
	return t or {}
end

local function bag(t: { [string]: number }?): { [string]: number }
	return t or {}
end

local function window(): number
	return math.floor(os.time() / TownConfig.WindowSeconds)
end

local function projectById(id: string): Restoration.Project?
	for _, p in PROJECTS do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- Where a project's stage lives: the player's own save, or the shared town.
local function projectState(p: { projects: Restoration.State }, proj: Restoration.Project): Restoration.State
	return if proj.scope == "town" then SharedTownService.get().buildings else p.projects
end

local function offerById(id: string): Town.Offer?
	for _, o in OFFERS do
		if o.id == id then
			return o
		end
	end
	return nil
end

local function npcName(id: string): string
	if id == "maya" then
		return TownConfig.MayaInfo.name
	end
	local n = TownConfig.Npcs[id]
	return if n then n.name else id
end

local function npcPlace(id: string): string
	if id == "maya" then
		return TownConfig.MayaInfo.place
	end
	local n = TownConfig.Npcs[id]
	return if n then n.place else ""
end

local function notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

local function ctxOf(p: Progress): Quests.Context
	return { reputation = p.town.reputation, trust = p.town.trust, now = now() }
end

local function inventoryOf(player: Player): { [string]: number }
	local s = PlayerService.get(player)
	return if s then table.clone(s.inventory.items) else {}
end

-- Public reads ---------------------------------------------------------------

function ProgressionService.get(player: Player): Progress?
	local p = states[player]
	return if p and p.ready then p else nil
end

function ProgressionService.all(): { Progress }
	local out = {}
	for _, p in states do
		if p.ready then
			table.insert(out, p)
		end
	end
	return out
end

function ProgressionService.status(player: Player, questId: string): string
	local p = ProgressionService.get(player)
	local def = BY_ID[questId]
	if not p or not def then
		return "locked"
	end
	return Quests.status(p.log, def, ctxOf(p))
end

function ProgressionService.hasFlag(player: Player, flag: string): boolean
	local p = ProgressionService.get(player)
	return p ~= nil and Quests.hasFlag(p.log, flag)
end

-- The quest (and objective) currently waiting on this kind and target.
function ProgressionService.waitingOn(
	player: Player,
	kind: string,
	target: string
): (Quests.Def?, Quests.Objective?)
	local p = ProgressionService.get(player)
	if not p then
		return nil, nil
	end
	for _, def in DEFS do
		for _, obj in Quests.currentOptions(p.log, def) do
			if obj.kind == kind and obj.target == target then
				return def, obj
			end
		end
	end
	return nil, nil
end

-- Statuses of every quest, flags and trust, for Dialogue.pick.
function ProgressionService.facts(
	player: Player,
	npc: string
): { quests: { [string]: string }, flags: { [string]: boolean }, trust: number }
	local p = ProgressionService.get(player)
	local quests = {}
	if not p then
		return { quests = quests, flags = {}, trust = 0 }
	end
	local c = ctxOf(p)
	for _, def in DEFS do
		quests[def.id] = Quests.status(p.log, def, c)
	end
	return { quests = quests, flags = p.log.flags, trust = p.town.trust[npc] or 0 }
end

function ProgressionService.available(player: Player, giver: string): { Quests.Def }
	local p = ProgressionService.get(player)
	local out = {}
	if not p then
		return out
	end
	for _, def in Quests.available(p.log, DEFS, ctxOf(p)) do
		if def.giver == giver then
			table.insert(out, def)
		end
	end
	return out
end

function ProgressionService.activeFrom(player: Player, giver: string): { Quests.Def }
	local p = ProgressionService.get(player)
	local out = {}
	if not p then
		return out
	end
	for _, def in DEFS do
		local e = p.log.entries[def.id]
		if def.giver == giver and e and e.status == "active" then
			table.insert(out, def)
		end
	end
	return out
end

function ProgressionService.projectStage(player: Player, projectId: string): number
	local p = ProgressionService.get(player)
	local proj = projectById(projectId)
	return if p and proj then Restoration.stage(projectState(p, proj), proj) else 0
end

-- Caramelo's saved Tracking skill (0 until Martha's mission is done).
function ProgressionService.trackingSkill(player: Player): number
	local p = ProgressionService.get(player)
	return if p then p.tracking else 0
end

function ProgressionService.def(id: string): Quests.Def?
	return BY_ID[id]
end

function ProgressionService.project(id: string): Restoration.Project?
	return projectById(id)
end

-- Hooks ------------------------------------------------------------------------

function ProgressionService.onChanged(fn: (Player) -> ())
	table.insert(changedListeners, fn)
end

function ProgressionService.onQuestCompleted(fn: (Player, string) -> ())
	table.insert(completeListeners, fn)
end

function ProgressionService.onProjectAdvanced(fn: (Player, string, number, boolean) -> ())
	table.insert(projectListeners, fn)
end

function ProgressionService.setLocator(fn: (key: string, player: Player?) -> Vector3?)
	locator = fn
end

function ProgressionService.setIncident(text: string?)
	incidentText = text
	for player in states do
		ProgressionService.push(player)
	end
end

-- View -------------------------------------------------------------------------

local function whereOf(obj: Quests.Objective?, player: Player): Vector3?
	if not obj or not locator then
		return nil
	end
	-- Alternatives: point at the first one that has a place.
	if obj.anyOf then
		for _, opt in obj.anyOf do
			local at = whereOf(opt, player)
			if at then
				return at
			end
		end
		return nil
	end
	local loc = locator :: (string, Player?) -> Vector3?
	local t = obj.target or ""
	if obj.kind == "talk" or obj.kind == "deliver" then
		return loc("npc:" .. t, player)
	elseif obj.kind == "repair" then
		return loc("project:" .. t, player)
	elseif obj.kind == "reach" or obj.kind == "investigate" then
		return loc("site:" .. t, player)
	elseif obj.kind == "interact" then
		return loc("interact:" .. t, player)
	end
	return nil
end

local function forecastPhrase(): string
	local night = NightDirector.forecast()
	local phrases: { [string]: string } = {
		Peaceful = "Tonight looks calm. A good night for the porch light.",
		Uneasy = "Tonight feels restless. Curtains drawn, I'd say.",
		Bad = "Tonight is a bad one. Lights off early and stay in.",
		Black = "The worst kind of night. Shut everything before dusk.",
	}
	return string.format(
		"%s Right now: %s.",
		phrases[night] or phrases.Peaceful,
		string.lower(WeatherService.label())
	)
end

local function buildView(p: Progress): any
	local player = p.player
	local c = ctxOf(p)
	local inv = inventoryOf(player)
	local rows: { LifeJournal.QuestRow } = {}
	local currentObj: { [string]: Quests.Objective } = {}
	for _, def in DEFS do
		local status = Quests.status(p.log, def, c)
		if status ~= "locked" then
			local obj, prog = Quests.current(p.log, def)
			local text, fraction = nil, nil
			if obj then
				currentObj[def.id] = obj
				local o: Objectives.Objective = obj :: any
				local progress = prog
				if o.kind == "collect" then
					progress = select(1, Objectives.apply(o, 0, { kind = "inventory", inventory = inv }))
				end
				text = Objectives.progressText(o, progress, inv)
				fraction = progress / Objectives.goal(o)
			end
			local opens = {}
			if status == "done" then
				for _, f in list(def.followUps) do
					local fd = BY_ID[f]
					if fd and Quests.status(p.log, fd, c) ~= "locked" then
						table.insert(opens, fd.title)
					end
				end
			end
			table.insert(rows, {
				id = def.id,
				title = def.title,
				giverName = npcName(def.giver),
				place = npcPlace(def.giver),
				status = status,
				category = def.category,
				optional = def.optional == true,
				context = def.context,
				objective = if obj then obj.text else nil,
				progress = text,
				fraction = fraction,
				opens = opens,
			})
		end
	end
	local tierIndex, tier, nextTier, tierFraction = Town.tier(p.town.reputation, TownConfig.Tiers)
	local _ = tierIndex
	local people = {}
	for _, id in TownConfig.Order do
		local npc = TownConfig.Npcs[id]
		local note = npc.role .. ", " .. npc.place .. "."
		for _, def in DEFS do
			if def.giver == id then
				local st = Quests.status(p.log, def, c)
				if st == "active" then
					local obj = currentObj[def.id]
					note = "Waiting on you: " .. (if obj then obj.text else def.title)
					break
				elseif st == "available" and not def.optional then
					note = "Has something to ask you."
				end
			end
		end
		table.insert(people, {
			id = id,
			name = npc.name,
			role = npc.role,
			trust = p.town.trust[id] or 0,
			maxTrust = LIMITS.maxTrust,
			note = note,
		})
	end
	local projects = {}
	for _, proj in PROJECTS do
		local st = projectState(p, proj)
		local stage = Restoration.stage(st, proj)
		local quest = if proj.quest then p.log.entries[proj.quest] else nil
		if stage > 0 or quest then
			table.insert(projects, {
				name = proj.name,
				stage = Restoration.stageName(st, proj),
				fraction = Restoration.fraction(st, proj),
				benefit = proj.benefit,
				done = Restoration.complete(st, proj),
			})
		end
	end
	local skills = {
		{ name = TownConfig.DogSkills.tracking.name, level = p.tracking, max = TRACKING_MAX },
	}
	local milestones = {}
	for _, m in TownConfig.MayaMilestones do
		table.insert(milestones, { name = m.name, done = Quests.hasFlag(p.log, m.flag) })
	end
	local changes = {}
	for _, ch in TownConfig.Changes do
		if Quests.hasFlag(p.log, ch.flag) then
			table.insert(changes, ch.text)
		end
	end
	local view: any = LifeJournal.build({
		quests = rows,
		tracked = p.tracked,
		credits = p.town.credits,
		reputation = p.town.reputation,
		tier = tier.name,
		nextTier = if nextTier then nextTier.name else nil,
		tierFraction = tierFraction,
		people = people,
		projects = projects,
		skills = skills,
		forecast = if Quests.hasFlag(p.log, "forecastUnlocked")
			then forecastText or forecastPhrase()
			else nil,
		incident = incidentText,
		milestones = milestones,
		changes = changes,
		observations = 0,
	})
	if view.tracker then
		local tracked = BY_ID[view.tracker.id]
		local obj = if tracked then currentObj[tracked.id] else nil
		if view.tracker.available and tracked and locator then
			view.tracker.where = (locator :: (string, Player?) -> Vector3?)("npc:" .. tracked.giver, player)
		else
			view.tracker.where = whereOf(obj, player)
		end
		view.tracker.hint = if obj then obj.hint else nil
	end
	return view
end

function ProgressionService.push(player: Player)
	local p = ProgressionService.get(player)
	if p then
		local ok, view = pcall(buildView, p)
		if ok then
			Net.event("Life"):FireClient(player, view)
		else
			warn("[Progression] view failed: " .. tostring(view))
		end
	end
end

local function changed(player: Player)
	ProgressionService.push(player)
	for _, fn in changedListeners do
		task.spawn(fn, player)
	end
end

-- Rewards ------------------------------------------------------------------------

local function rewardText(r: Quests.Rewards): string
	local parts = {}
	if r.credits and r.credits > 0 then
		table.insert(parts, string.format("+%d credits", r.credits))
	end
	if r.reputation and r.reputation > 0 then
		table.insert(parts, string.format("+%d reputation", r.reputation))
	end
	for item, n in bag(r.items) do
		local cfg = ItemConfig.Items[item]
		table.insert(parts, string.format("+%d %s", n, if cfg then cfg.name else item))
	end
	return table.concat(parts, "  ")
end

local function payQuest(p: Progress, def: Quests.Def)
	local player = p.player
	if not Town.grant(p.town, "quest:" .. def.id, def.rewards :: any, LIMITS) then
		return -- already paid, ever
	end
	local r = def.rewards
	for item, n in bag(r.items) do
		PlayerService.give(player, item, n)
	end
	-- A skill reward is an increment, paid once with the quest.
	for skill, n in bag(r.dogSkill) do
		if skill == "tracking" then
			p.tracking = math.clamp(p.tracking + n, 0, TRACKING_MAX)
			notify(player, string.format("Caramelo's Tracking: %d/%d", p.tracking, TRACKING_MAX), "good")
		end
	end
	if r.comfort then
		local s = PlayerService.get(player)
		if s then
			s.comfort = math.min(100, s.comfort + r.comfort)
			PlayerService.markRoutine(player, "meal")
		end
	end
	local text = rewardText(r)
	notify(player, "Done: " .. def.title .. (if text ~= "" then "   " .. text else ""), "good")
	Net.event("SoundCue"):FireClient(player, "journal")
end

-- Events -------------------------------------------------------------------------

local function applyEvent(p: Progress, ev: Objectives.Event): { Quests.Change }
	local player = p.player
	local changes = Quests.apply(p.log, DEFS, ev, Objectives, now())
	for _, ch in changes do
		local def = BY_ID[ch.id]
		if ch.objectiveDone then
			local done = def.objectives[ch.step]
			for _, line in list(done.say) do
				notify(player, line, "info")
			end
			if ch.completed then
				payQuest(p, def)
				for _, fn in completeListeners do
					task.spawn(fn, player, def.id)
				end
			else
				local nextObj = def.objectives[ch.step + 1]
				notify(player, "✓ " .. done.text, "good")
				if nextObj then
					notify(player, "Next: " .. nextObj.text, "info")
				end
			end
		end
	end
	return changes
end

-- Feeds an event to this player's quests. Ignored until the save has loaded.
function ProgressionService.event(
	player: Player,
	kind: string,
	target: string?,
	amount: number?,
	evidence: string?
): { Quests.Change }
	local p = ProgressionService.get(player)
	if not p then
		return {}
	end
	if kind == "met" and target then
		local flag = "met" .. string.upper(string.sub(target, 1, 1)) .. string.sub(target, 2)
		if not Quests.hasFlag(p.log, flag) then
			Quests.setFlag(p.log, flag)
			changed(player)
		end
		return {}
	end
	local ev: Objectives.Event = {
		kind = kind,
		target = target,
		amount = amount,
		phase = TimeService.snapshot().phase,
		inventory = inventoryOf(player),
		evidence = evidence,
	}
	local changes = applyEvent(p, ev)
	if #changes > 0 then
		-- A newly current "collect" may already be satisfied by the pack.
		applyEvent(p, { kind = "inventory", inventory = inventoryOf(player) })
		changed(player)
	end
	return changes
end

function ProgressionService.startQuest(player: Player, id: string): boolean
	local p = ProgressionService.get(player)
	local def = BY_ID[id]
	if not p or not def then
		return false
	end
	local ok = Quests.start(p.log, def, ctxOf(p))
	if ok then
		if not p.tracked or Quests.isDone(p.log, p.tracked) then
			p.tracked = id
		end
		notify(player, "New: " .. def.title, "warning")
		local first = def.objectives[1]
		if first then
			notify(player, first.text, "info")
		end
		applyEvent(p, { kind = "inventory", inventory = inventoryOf(player) })
		changed(player)
	end
	return ok
end

-- Restoration: pay the next action's cost and advance. Returns a message.
function ProgressionService.repair(player: Player, projectId: string): (boolean, string)
	local p = ProgressionService.get(player)
	local proj = projectById(projectId)
	if not p or not proj then
		return false, ""
	end
	local st = projectState(p, proj)
	if Restoration.complete(st, proj) then
		return false, proj.name .. " is already restored."
	end
	local questId = proj.quest
	if questId then
		local qdef = BY_ID[questId]
		if Quests.status(p.log, qdef, ctxOf(p)) ~= "active" then
			return false, string.format("Ask %s about this first.", npcName(qdef.giver))
		end
		-- Only on the repair step, so an early press never spends what the
		-- collect step still needs in the pack.
		local onStep = false
		for _, opt in Quests.currentOptions(p.log, qdef) do
			if opt.kind == "repair" and opt.target == projectId then
				onStep = true
			end
		end
		if not onStep then
			local current = Quests.current(p.log, qdef)
			return false, if current then "First: " .. current.text else ""
		end
	end
	local action = Restoration.nextAction(st, proj) :: Restoration.Action
	if not PlayerService.spend(player, action.cost) then
		return false, ""
	end
	local stage, finished = Restoration.advance(st, proj)
	if proj.scope == "town" then
		SharedTownService.touched()
	end
	for _, fn in projectListeners do
		task.spawn(fn, player, projectId, stage, finished)
	end
	ProgressionService.event(player, "repair", projectId, stage)
	if finished then
		Town.grant(p.town, "project:" .. projectId, { reputation = 2 }, LIMITS)
	end
	changed(player)
	return true, action.text .. (if finished then ". Restored!" else ".")
end

-- Small capped earnings for incidents.
function ProgressionService.earn(
	player: Player,
	reward: { credits: number, reputation: number },
	items: { [string]: number }?,
	why: string
)
	local p = ProgressionService.get(player)
	if not p then
		return
	end
	local paid = Town.earn(p.town, reward :: any, window(), TownConfig.EarnCap, LIMITS)
	local parts = {}
	if (paid.credits or 0) > 0 then
		table.insert(parts, string.format("+%d credits", paid.credits :: number))
	end
	if (paid.reputation or 0) > 0 then
		table.insert(parts, string.format("+%d reputation", paid.reputation :: number))
	end
	for item, n in bag(items) do
		local added = PlayerService.give(player, item, n)
		if added > 0 then
			table.insert(parts, string.format("+%d %s", added, ItemConfig.Items[item].name))
		end
	end
	notify(player, why .. (if #parts > 0 then "   " .. table.concat(parts, "  ") else ""), "good")
	changed(player)
end

-- Maya's garden gives berries once per window after the trellis is done.
function ProgressionService.gardenGift(player: Player): boolean
	local p = ProgressionService.get(player)
	if not p or not Quests.hasFlag(p.log, "gardenRepaired") or p.gift == window() then
		return false
	end
	p.gift = window()
	for item, n in TownConfig.GardenGift do
		PlayerService.give(player, item, n)
	end
	return true
end

function ProgressionService.buy(player: Player, offerId: string)
	local p = ProgressionService.get(player)
	local offer = offerById(offerId)
	if not p or not offer or not locator then
		return
	end
	local root = PlayerService.root(player)
	local at = (locator :: (string, Player?) -> Vector3?)("npc:" .. offer.vendor, player)
	if not root or not at or (root.Position - at).Magnitude > 16 then
		notify(player, "You need to be at the counter.", "info")
		return
	end
	local tierIndex = Town.tier(p.town.reputation, TownConfig.Tiers)
	local ok, why = Town.buy(p.town, offer, { window = window(), tier = tierIndex, flags = p.log.flags })
	if not ok then
		local reasons: { [string]: string } = {
			closed = "Not for sale yet.",
			reputation = "Pinehaven doesn't know you well enough yet.",
			owned = "You already have one.",
			soldout = "Sold out for today.",
			credits = "Not enough credits.",
		}
		notify(player, reasons[why or ""] or "Can't buy that.", "info")
		return
	end
	local added = PlayerService.give(player, offer.item, offer.amount)
	if added <= 0 then
		Town.refund(p.town, offer)
		return
	end
	notify(player, string.format("Bought %d %s.", added, ItemConfig.Items[offer.item].name), "good")
	changed(player)
end

-- Offers for a vendor, with whether each can be bought now.
function ProgressionService.offers(player: Player, vendor: string): { any }
	local p = ProgressionService.get(player)
	local out = {}
	if not p then
		return out
	end
	local tierIndex = Town.tier(p.town.reputation, TownConfig.Tiers)
	local bc = { window = window(), tier = tierIndex, flags = p.log.flags }
	for _, o in OFFERS do
		if o.vendor == vendor and (not o.flag or p.log.flags[o.flag]) then
			local ok, why = Town.canBuy(p.town, o, bc)
			table.insert(out, {
				id = o.id,
				name = string.format("%d %s", o.amount, ItemConfig.Items[o.item].name),
				price = o.price,
				ok = ok,
				why = why,
			})
		end
	end
	return out
end

-- Persistence --------------------------------------------------------------------

local function snapshot(p: Progress): { [string]: any }
	return {
		v = 1,
		quests = Quests.snapshot(p.log),
		town = Town.snapshot(p.town),
		projects = table.clone(p.projects),
		tracking = p.tracking,
		gift = p.gift,
		tracked = p.tracked,
	}
end

local function restoreInto(p: Progress, data: any)
	local d = if type(data) == "table" then data else {}
	p.log = Quests.restore(d.quests, DEFS)
	p.town = Town.restore(d.town, LIMITS)
	p.projects = Restoration.restore(d.projects, PROJECTS)
	local tracking: any = d.tracking
	p.tracking = if type(tracking) == "number" and tracking == tracking
		then math.clamp(math.floor(tracking), 0, TRACKING_MAX)
		else 0
	p.gift = if type(d.gift) == "number" and d.gift == d.gift then math.floor(d.gift) else -1
	local tracked: any = d.tracked
	p.tracked = if type(tracked) == "string" and BY_ID[tracked] then tracked else nil
end

-- Studio check of the rejoin path without a DataStore: the exact snapshot
-- goes through JSON and back into a fresh state.
-- Command bar (server): require(game.ServerScriptService.Server.Services.ProgressionService).debugRejoin(game.Players:GetPlayers()[1])
function ProgressionService.debugRejoin(player: Player): boolean
	local p = ProgressionService.get(player)
	if not p then
		return false
	end
	local json = HttpService:JSONEncode(snapshot(p))
	local fresh: Progress = {
		player = player,
		ready = true,
		log = Quests.new(),
		town = Town.new(),
		projects = Restoration.new(),
		tracking = 0,
		gift = -1,
		tracked = nil,
		seconds = {},
	}
	restoreInto(fresh, HttpService:JSONDecode(json))
	states[player] = fresh
	print(string.format("[Progression] rejoin check for %s: %d bytes restored", player.Name, #json))
	notify(player, "Progress reloaded from save data.", "info")
	changed(player)
	return true
end

-- Studio checks: a short summary of the saved state.
function ProgressionService.debugSummary(player: Player): string
	local p = ProgressionService.get(player)
	if not p then
		return "not loaded"
	end
	local parts = {
		string.format("credits=%d rep=%d", p.town.credits, p.town.reputation),
	}
	for _, def in DEFS do
		local e = p.log.entries[def.id]
		if e then
			table.insert(parts, string.format("%s=%s:%d", def.id, e.status, e.step))
		end
	end
	for id, stage in p.projects do
		table.insert(parts, string.format("%s@%d", id, stage))
	end
	local flags = {}
	for f in p.log.flags do
		table.insert(flags, f)
	end
	table.sort(flags)
	table.insert(parts, "flags=" .. table.concat(flags, ","))
	table.insert(parts, "tracking=" .. p.tracking)
	return table.concat(parts, " ")
end

local function addPlayer(player: Player)
	local p: Progress = {
		player = player,
		ready = false,
		log = Quests.new(),
		town = Town.new(),
		projects = Restoration.new(),
		tracking = 0,
		gift = -1,
		tracked = nil,
		seconds = {},
	}
	states[player] = p
	task.spawn(function()
		local waited = 0
		while PlayerService.loadStatus(player) == "pending" and waited < 90 and player.Parent do
			task.wait(0.25)
			waited += 0.25
		end
		if states[player] ~= p then
			return
		end
		if PlayerService.loadStatus(player) == "ok" then
			restoreInto(p, PlayerService.savedSection(player, "progression"))
		end
		p.ready = true
		changed(player)
	end)
end

-- Ticking ------------------------------------------------------------------------

local function near(player: Player, key: string, radius: number): boolean
	if not locator then
		return false
	end
	local at = (locator :: (string, Player?) -> Vector3?)(key, player)
	local root = PlayerService.root(player)
	return at ~= nil and root ~= nil and (root.Position - at).Magnitude <= radius
end

local function tickPlayer(p: Progress, dt: number)
	local player = p.player
	if not PlayerService.isActive(player) then
		return
	end
	for _, def in DEFS do
		for _, obj in Quests.currentOptions(p.log, def) do
			local t = obj.target or ""
			if obj.kind == "collect" then
				ProgressionService.event(player, "inventory")
			elseif obj.kind == "reach" and near(player, "site:" .. t, TownConfig.ReachRadius) then
				-- Bringing someone home needs them along.
				if t ~= "MarthaHouse" or near(player, "missing:Biscuit", 20) then
					ProgressionService.event(player, "reach", t)
				end
			elseif obj.kind == "locate" and near(player, "missing:" .. t, TownConfig.LocateRadius) then
				ProgressionService.event(player, "locate", t)
			elseif obj.kind == "weather" then
				local s = PlayerService.get(player)
				local label = WeatherService.label()
				local matches = label == t or (t == "Rain" and label == "Storm")
				if s and s.shelter and matches then
					local acc = (p.seconds[def.id] or 0) + dt
					local whole = math.floor(acc)
					p.seconds[def.id] = acc - whole
					if whole > 0 then
						ProgressionService.event(player, "weather", t, whole)
					end
				end
			end
		end
	end
	local expired = Quests.expire(p.log, DEFS, now())
	if #expired > 0 then
		for _, id in expired do
			notify(player, "Missed: " .. BY_ID[id].title .. ". It may come up again.", "info")
		end
		changed(player)
	end
end

local function onDay(snap: any)
	-- Forecast from the station, for players who fixed the sensor. Not on
	-- day 1: the opening owns the radio then.
	if snap.phase ~= "Day" or snap.day < 2 then
		return
	end
	local text = forecastPhrase()
	forecastText = text
	for _, p in ProgressionService.all() do
		if Quests.hasFlag(p.log, "forecastUnlocked") then
			Net.event("Radio"):FireClient(p.player, "Dr. Hale: Morning, station forecast. " .. text)
			Net.event("SoundCue"):FireClient(p.player, "radioStatic", nil, 0.3)
		end
		ProgressionService.push(p.player)
	end
end

function ProgressionService.start()
	PlayerService.persist("progression", function(player: Player): any
		local p = states[player]
		return if p and p.ready then snapshot(p) else nil
	end)
	Players.PlayerAdded:Connect(addPlayer)
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- PlayerService saves on removal too; keep the state until it has.
		task.delay(20, function()
			if not player.Parent then
				states[player] = nil
			end
		end)
	end)
	ProgressBus.listen(function(player, kind, target, amount, evidence)
		ProgressionService.event(player, kind, target, amount, evidence)
	end)
	TimeService.onPhaseChanged(onDay)

	Net.func("GetLife").OnServerInvoke = function(player: Player): any
		local p = ProgressionService.get(player)
		if not p or not Net.allow(player, "getLife", 3) then
			return nil
		end
		local ok, view = pcall(buildView, p)
		return if ok then view else nil
	end
	Net.event("LifeRequest").OnServerEvent:Connect(function(player: Player, kind: any, id: any)
		if type(kind) ~= "string" or type(id) ~= "string" or #id > 40 or not Net.allow(player, "life", 4) then
			return
		end
		local p = ProgressionService.get(player)
		if not p then
			return
		end
		if kind == "track" and BY_ID[id] then
			p.tracked = id
			ProgressionService.push(player)
		elseif kind == "buy" then
			ProgressionService.buy(player, id)
		end
	end)

	task.spawn(function()
		while true do
			local dt = task.wait(1)
			for _, p in ProgressionService.all() do
				local ok, err = pcall(tickPlayer :: any, p, dt)
				if not ok then
					warn("[Progression] " .. tostring(err))
				end
			end
		end
	end)
end

return ProgressionService

--!strict
-- Specs for Chapter 37 progression: objectives, quests, town standing,
-- restoration, incidents, dog training, dialogue, the Life Journal view and
-- the config that ties them together. Required from logic.spec.luau.

local serde = require("@lune/serde")
local t = require("./harness")
local describe, it, eq, truthy, falsy = t.describe, t.it, t.eq, t.truthy, t.falsy

local Objectives = require("../src/shared/Logic/Objectives")
local Quests = require("../src/shared/Logic/Quests")
local Town = require("../src/shared/Logic/Town")
local Restoration = require("../src/shared/Logic/Restoration")
local Incidents = require("../src/shared/Logic/Incidents")
local Dialogue = require("../src/shared/Logic/Dialogue")
local LifeJournal = require("../src/shared/Logic/LifeJournal")
local QuestConfig = require("../src/shared/Config/QuestConfig")
local TownConfig = require("../src/shared/Config/TownConfig")
local ItemConfig = require("../src/shared/Config/ItemConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local CreatureConfig = require("../src/shared/Config/CreatureConfig")

local DEFS: { Quests.Def } = QuestConfig.List :: any
local PROJECTS: { Restoration.Project } = TownConfig.Projects :: any
local DOG_SKILLS = TownConfig.DogSkills
local LIMITS: Town.Limits = TownConfig.Limits
local BY_ID = Quests.byId(DEFS)

local function ctx(town: Town.State?, now: number?): Quests.Context
	return {
		reputation = if town then town.reputation else 0,
		trust = if town then town.trust else {},
		now = now or 1000,
	}
end

local function projectById(id: string): Restoration.Project
	for _, p in PROJECTS do
		if p.id == id then
			return p
		end
	end
	error("no project " .. id)
end

describe("Objectives", function()
	it("collect follows what is in the pack, item by item", function()
		local o: Objectives.Objective = { kind = "collect", items = { Wood = 4, Fiber = 2 }, text = "" }
		eq(Objectives.goal(o), 6)
		local p, done = Objectives.apply(o, 0, { kind = "inventory", inventory = { Wood = 9, Fiber = 1 } })
		eq(p, 5)
		falsy(done)
		p, done = Objectives.apply(o, p, { kind = "inventory", inventory = { Wood = 4, Fiber = 2 } })
		eq(p, 6)
		truthy(done)
		eq(Objectives.progressText(o, 5, { Wood = 9, Fiber = 1 }), "Fiber 1/2 · Wood 4/4")
	end)
	it("targeted kinds ignore other targets and other event kinds", function()
		local o: Objectives.Objective = { kind = "talk", target = "frank", text = "" }
		local p, done = Objectives.apply(o, 0, { kind = "talk", target = "ellen" })
		eq(p, 0)
		falsy(done)
		p, done = Objectives.apply(o, 0, { kind = "reach", target = "frank" })
		falsy(done)
		p, done = Objectives.apply(o, 0, { kind = "talk", target = "frank" })
		truthy(done)
		eq(p, 1)
	end)
	it("counts interactions, observations and sheltered seconds", function()
		local w: Objectives.Objective = { kind = "weather", target = "Rain", count = 60, text = "" }
		local p = 0
		for _ = 1, 59 do
			p = Objectives.apply(w, p, { kind = "weather", target = "Rain", amount = 1 })
		end
		eq(p, 59)
		eq(Objectives.progressText(w, p), "59/60 s")
		local _, done = Objectives.apply(w, p, { kind = "weather", target = "Rain", amount = 5 })
		truthy(done, "clamps at the goal")
		local obs: Objectives.Objective = { kind = "observe", target = "Watcher", count = 2, text = "" }
		local q = Objectives.apply(obs, 0, { kind = "observe", target = "Watcher" })
		eq(q, 1)
	end)
	it("repair tracks the project's furthest stage, never backwards", function()
		local o: Objectives.Objective = { kind = "repair", target = "FrankShed", count = 3, text = "" }
		local p = Objectives.apply(o, 0, { kind = "repair", target = "FrankShed", amount = 2 })
		eq(p, 2)
		p = Objectives.apply(o, p, { kind = "repair", target = "FrankShed", amount = 1 })
		eq(p, 2)
	end)
	it("phase-limited objectives wait for the right time of day", function()
		local o: Objectives.Objective =
			{ kind = "interact", target = "MayaTable", phases = { "Day", "Dusk" }, text = "" }
		local _, done = Objectives.apply(o, 0, { kind = "interact", target = "MayaTable", phase = "Night" })
		falsy(done)
		_, done = Objectives.apply(o, 0, { kind = "interact", target = "MayaTable", phase = "Dusk" })
		truthy(done)
	end)
	it("ships every component the chapter asks for", function()
		for _, kind in
			{
				"collect",
				"deliver",
				"repair",
				"reach",
				"talk",
				"interact",
				"observe",
				"weather",
				"investigate",
				"locate",
			}
		do
			truthy(Objectives.known(kind), kind)
		end
	end)
end)

describe("Quests", function()
	it("offers only quests whose prerequisites are met", function()
		local log = Quests.new()
		eq(Quests.status(log, BY_ID.frank_shed, ctx()), "available")
		eq(Quests.status(log, BY_ID.hale_sensor, ctx()), "locked")
		eq(Quests.status(log, BY_ID.maya_garden, ctx()), "locked", "needs metMaya")
		Quests.setFlag(log, "metMaya")
		eq(Quests.status(log, BY_ID.maya_garden, ctx()), "available")
	end)
	it("runs objectives in order and completes with consequences", function()
		local log = Quests.new()
		truthy(Quests.start(log, BY_ID.frank_shed, ctx()))
		falsy((Quests.start(log, BY_ID.frank_shed, ctx())), "no double start")
		-- Talking to Frank too early does nothing.
		eq(#Quests.apply(log, DEFS, { kind = "talk", target = "frank" }, Objectives, 1), 0)
		Quests.apply(log, DEFS, { kind = "inventory", inventory = { Wood = 8 } }, Objectives, 2)
		local obj = Quests.current(log, BY_ID.frank_shed)
		eq(obj and obj.kind, "repair")
		Quests.apply(log, DEFS, { kind = "repair", target = "FrankShed", amount = 3 }, Objectives, 3)
		local changes = Quests.apply(log, DEFS, { kind = "talk", target = "frank" }, Objectives, 4)
		eq(#changes, 1)
		truthy(changes[1].completed)
		truthy(Quests.isDone(log, "frank_shed"))
		truthy(Quests.hasFlag(log, "frankShedRepaired"))
		eq(Quests.status(log, BY_ID.hale_sensor, ctx()), "available", "completion opens the follow-up")
	end)
	it("expires a timed quest and offers it again", function()
		local def: Quests.Def = {
			id = "timed",
			giver = "frank",
			title = "",
			context = "",
			category = "town",
			objectives = { { kind = "talk", target = "frank", text = "" } },
			rewards = {},
			expiresAfter = 60,
		}
		local log = Quests.new()
		Quests.start(log, def, ctx(nil, 100))
		eq(#Quests.expire(log, { def }, 159), 0)
		eq(Quests.expire(log, { def }, 160)[1], "timed")
		eq(Quests.status(log, def, ctx()), "available")
	end)
	it("restores from untrusted data without trusting bad entries", function()
		local log = Quests.restore({
			entries = {
				frank_shed = { status = "active", step = 99, progress = 2, startedAt = 5 },
				nope = { status = "done", step = 1, progress = 0, startedAt = 1 },
				ellen_meal = { status = "hacked", step = 1, progress = 0, startedAt = 1 },
				martha_dog = { status = "done", step = 2, progress = 0 / 0, startedAt = 1 },
			},
			flags = { metMaya = true, [5] = true, evil = "yes" },
		}, DEFS)
		eq(log.entries.frank_shed.step, #BY_ID.frank_shed.objectives, "step clamped")
		eq(log.entries.nope, nil)
		eq(log.entries.ellen_meal, nil)
		eq(log.entries.martha_dog, nil, "NaN progress rejected")
		truthy(log.flags.metMaya)
		eq(log.flags.evil, nil)
		local empty = Quests.restore("garbage", DEFS)
		eq(next(empty.entries), nil)
	end)
end)

describe("Town", function()
	it("pays a keyed reward once", function()
		local st = Town.new()
		truthy(
			Town.grant(
				st,
				"quest:frank_shed",
				{ credits = 15, reputation = 10, trust = { frank = 3 } },
				LIMITS
			)
		)
		falsy(Town.grant(st, "quest:frank_shed", { credits = 15, reputation = 10 }, LIMITS))
		eq(st.credits, 15)
		eq(st.reputation, 10)
		eq(st.trust.frank, 3)
	end)
	it("caps small earnings per real-time window, across a rejoin", function()
		local st = Town.new()
		local cap = { credits = 8, reputation = 3 }
		for _ = 1, 10 do
			Town.earn(st, { credits = 2, reputation = 1 }, 7, cap, LIMITS)
		end
		eq(st.credits, 8)
		eq(st.reputation, 3)
		local again = Town.restore(serde.decode("json", serde.encode("json", Town.snapshot(st))), LIMITS)
		local paid = Town.earn(again, { credits = 2 }, 7, cap, LIMITS)
		eq(paid.credits, 0, "a rejoin in the same window pays nothing")
		paid = Town.earn(again, { credits = 2 }, 8, cap, LIMITS)
		eq(paid.credits, 2, "the next window pays again")
	end)
	it("finds the tier and progress to the next", function()
		local i, tier, nextTier, f = Town.tier(30, TownConfig.Tiers)
		eq(i, 3)
		eq(tier.name, "Neighbour")
		eq(nextTier and nextTier.name, "Friend of Pinehaven")
		truthy(f > 0.19 and f < 0.21)
		local top = select(3, Town.tier(500, TownConfig.Tiers))
		eq(top, nil)
	end)
	it("enforces shop flags, tiers, limits, one-offs and credits", function()
		local st = Town.new()
		st.credits = 100
		local function offer(id: string): Town.Offer
			for _, o in TownConfig.Shop do
				if o.id == id then
					return o :: any
				end
			end
			error(id)
		end
		local bc: Town.BuyContext = { window = 1, tier = 1, flags = {} }
		eq(select(2, Town.buy(st, offer("ellen_stew"), bc)), "closed")
		bc.flags.dinerOpen = true
		truthy(Town.buy(st, offer("ellen_stew"), bc))
		truthy(Town.buy(st, offer("ellen_stew"), bc))
		eq(select(2, Town.buy(st, offer("ellen_stew"), bc)), "soldout")
		bc.window = 2
		truthy(Town.buy(st, offer("ellen_stew"), bc), "next window restocks")
		bc.flags.frankShedRepaired = true
		eq(select(2, Town.buy(st, offer("frank_binoculars"), bc)), "reputation")
		bc.tier = 3
		truthy(Town.buy(st, offer("frank_binoculars"), bc))
		eq(select(2, Town.buy(st, offer("frank_binoculars"), bc)), "owned")
		st.credits = 1
		eq(select(2, Town.buy(st, offer("frank_scrap"), bc)), "credits")
	end)
	it("clamps restored data", function()
		local st = Town.restore(
			{ credits = 1e9, reputation = -5, trust = { frank = 99 }, granted = { x = 1 } },
			LIMITS
		)
		eq(st.credits, LIMITS.maxCredits)
		eq(st.reputation, 0)
		eq(st.trust.frank, LIMITS.maxTrust)
		eq(st.granted.x, nil)
	end)
end)

describe("Restoration", function()
	it("advances one paid action at a time and stops when restored", function()
		local p = projectById("FrankShed")
		local st = Restoration.new()
		eq(Restoration.stageName(st, p), "Storm-wrecked")
		eq((Restoration.nextAction(st, p) :: any).id, "walls")
		Restoration.advance(st, p)
		Restoration.advance(st, p)
		local stage, done = Restoration.advance(st, p)
		eq(stage, 3)
		truthy(done)
		eq(Restoration.stageName(st, p), "Repaired")
		local again, doneAgain = Restoration.advance(st, p)
		eq(again, 3)
		falsy(doneAgain, "finishing twice never pays twice")
		eq(Restoration.nextAction(st, p), nil)
	end)
	it("shows the furthest stage among present players", function()
		local p = projectById("MayaGarden")
		eq(Restoration.union({ { MayaGarden = 1 }, { MayaGarden = 2 }, {} }, p), 2)
	end)
	it("restores only known projects with sane stages", function()
		local st = Restoration.restore({ FrankShed = 9, MayaGarden = 1.5, Fake = 2 }, PROJECTS)
		eq(st.FrankShed, 3)
		eq(st.MayaGarden, nil)
		eq(st.Fake, nil)
	end)
end)

describe("Incidents", function()
	local defs: { Incidents.Def } = TownConfig.Incidents :: any
	local function plainDay(day: number): Incidents.Context
		return { day = day, phase = "Day", weather = "Clear", lastNight = "Peaceful", flags = {} }
	end
	it("always has a peaceful errand on a plain day", function()
		local list = Incidents.eligible(defs, Incidents.new(), plainDay(2), 2)
		local peaceful = 0
		for _, d in list do
			if d.peaceful then
				peaceful += 1
			end
			falsy(d.id == "strange_tracks", "mystery waits for an uneasy night")
			falsy(d.id == "lost_basket", "needs the diner open")
		end
		truthy(peaceful >= 1)
	end)
	it("respects weather, flags and night conditions", function()
		local st = Incidents.new()
		local c = plainDay(3)
		c.weather = "Rain"
		c.lastNight = "Uneasy"
		c.flags.dinerOpen = true
		local ids = {}
		for _, d in Incidents.eligible(defs, st, c, 5) do
			ids[d.id] = true
		end
		truthy(ids.mushroom_flush and ids.lost_basket and ids.strange_tracks)
	end)
	it("cools down and keeps to a daily budget", function()
		local st = Incidents.new()
		local branch = defs[1]
		Incidents.fire(st, branch, 4)
		falsy(Incidents.isEligible(branch, st, plainDay(4)))
		truthy(Incidents.isEligible(branch, st, plainDay(5)))
		Incidents.fire(st, defs[4], 4)
		eq(#Incidents.eligible(defs, st, plainDay(4), 2), 0)
	end)
	it("weighted choice is deterministic for a roll", function()
		local list = Incidents.eligible(defs, Incidents.new(), plainDay(2), 2)
		eq((Incidents.choose(list, 0) :: any).id, list[1].id)
		eq((Incidents.choose(list, 0.9999) :: any).id, list[#list].id)
		eq(Incidents.choose({}, 0.5), nil)
	end)
end)

describe("Dialogue", function()
	it("changes after the relevant mission", function()
		local entries: { Dialogue.Entry } = TownConfig.Dialogue.hale :: any
		local before = Dialogue.pick(entries, { quests = {}, flags = {}, trust = 0 }) :: { string }
		truthy(string.find(before[1], "no parts", 1, true))
		local mid =
			Dialogue.pick(entries, { quests = { frank_shed = "done" }, flags = {}, trust = 0 }) :: { string }
		truthy(string.find(mid[1], "spare parts", 1, true))
		local after =
			Dialogue.pick(entries, { quests = {}, flags = { forecastUnlocked = true }, trust = 0 }) :: { string }
		truthy(string.find(after[1], "radio", 1, true))
	end)
	it("can require trust", function()
		local entries: { Dialogue.Entry } = TownConfig.Dialogue.ellen :: any
		local warm =
			Dialogue.pick(entries, { quests = {}, flags = { dinerOpen = true }, trust = 6 }) :: { string }
		truthy(string.find(warm[1], "usual", 1, true))
	end)
end)

describe("Progression config", function()
	local sites = TownConfig.Sites
	local function npcExists(id: string): boolean
		return TownConfig.Npcs[id] ~= nil or id == "maya"
	end
	local observeTargets = {}
	for _, a in CreatureConfig.Archetypes do
		observeTargets[(a :: any).journalSubject] = true
	end
	it("every quest resolves its people, items, places and links", function()
		local seen = {}
		for _, q in DEFS do
			falsy(seen[q.id], "duplicate id " .. q.id)
			seen[q.id] = true
			truthy(npcExists(q.giver), q.id .. " giver")
			for _, dep in (q.requires and q.requires.quests) or {} do
				truthy(BY_ID[dep], q.id .. " requires " .. dep)
			end
			for _, f in q.followUps or {} do
				truthy(BY_ID[f], q.id .. " follow-up " .. f)
			end
			for item in q.rewards.items or {} do
				truthy(ItemConfig.Items[item], q.id .. " reward item " .. item)
			end
			for skill in q.rewards.dogSkill or {} do
				truthy(DOG_SKILLS[skill], q.id .. " skill " .. skill)
			end
			for _, o in q.objectives do
				local where = q.id .. "/" .. o.kind
				truthy(Objectives.known(o.kind), where)
				for item in o.items or {} do
					truthy(ItemConfig.Items[item], where .. " item " .. item)
				end
				local target = o.target or ""
				if o.kind == "talk" or o.kind == "deliver" then
					truthy(npcExists(target), where .. " npc " .. target)
				elseif o.kind == "reach" or o.kind == "investigate" then
					truthy(sites[target], where .. " site " .. target)
				elseif o.kind == "interact" then
					truthy(TownConfig.Interactions[target], where .. " interaction " .. target)
				elseif o.kind == "locate" then
					truthy(TownConfig.Missing[target], where .. " missing " .. target)
				elseif o.kind == "observe" then
					truthy(observeTargets[target], where .. " creature " .. target)
				elseif o.kind == "weather" then
					truthy(GameConfig.Weather.Weights[target], where .. " weather " .. target)
				elseif o.kind == "repair" then
					local p = projectById(target)
					eq(o.count, #p.actions, where .. " counts every action")
					eq(p.quest, q.id, where .. " project belongs to this quest")
				end
			end
		end
	end)
	it("each repair quest asks the pack for exactly what the repairs cost", function()
		for _, q in DEFS do
			local need: { [string]: number }? = nil
			for _, o in q.objectives do
				if o.kind == "collect" then
					need = o.items
				elseif o.kind == "repair" and need then
					local cost: { [string]: number } = {}
					for _, a in projectById(o.target :: string).actions do
						for item, n in a.cost do
							cost[item] = (cost[item] or 0) + n
						end
					end
					for item, n in cost do
						eq((need :: any)[item], n, q.id .. " " .. item)
					end
				end
			end
		end
	end)
	it("projects, sites, shop, incidents and NPCs line up", function()
		for _, p in PROJECTS do
			truthy(sites[p.site], p.id .. " site")
			eq(#p.stages, #p.actions + 1, p.id .. " stage names")
			truthy(p.ack == nil or npcExists(p.ack.npc), p.id .. " ack")
		end
		for id, npc in TownConfig.Npcs do
			truthy(sites[npc.site], id .. " site")
			truthy(TownConfig.Dialogue[id], id .. " dialogue")
		end
		for _, o in TownConfig.Shop do
			truthy(ItemConfig.Items[o.item], o.id)
			truthy(TownConfig.Npcs[o.vendor], o.id .. " vendor")
			truthy(o.minTier == nil or TownConfig.Tiers[o.minTier], o.id .. " tier")
		end
		for _, inc in TownConfig.Incidents do
			truthy(#inc.spots > 0, inc.id)
			for item in inc.items or {} do
				truthy(ItemConfig.Items[item], inc.id .. " " .. item)
			end
			truthy(inc.deliverTo == nil or npcExists(inc.deliverTo), inc.id)
		end
		for _, site in TownConfig.Missing do
			truthy(sites[site], site)
		end
	end)
	it("monster research is never required for the main missions", function()
		for _, q in DEFS do
			for _, o in q.objectives do
				if o.kind == "observe" then
					truthy(q.optional, q.id .. " must be optional")
				end
			end
			for _, dep in (q.requires and q.requires.quests) or {} do
				falsy(BY_ID[dep].optional and not q.optional, q.id .. " depends on optional " .. dep)
			end
		end
	end)
end)

-- Plays the five slice missions through the real logic, the way the server
-- does: events, one-time payouts, a save to JSON and a restore.
describe("Progression slice", function()
	local function play()
		local log, town, restore = Quests.new(), Town.new(), Restoration.new()
		local dog = { tracking = 0 }
		local inv: { [string]: number } = {}
		local now = 1000
		local function grant(id: string)
			local def = BY_ID[id]
			local paid = Town.grant(town, "quest:" .. id, def.rewards :: any, LIMITS)
			if paid then
				for item, n in def.rewards.items or {} do
					inv[item] = (inv[item] or 0) + n
				end
				-- As ProgressionService: a skill reward is an increment, capped.
				for skill, n in def.rewards.dogSkill or {} do
					dog[skill] = math.clamp((dog[skill] or 0) + n, 0, DOG_SKILLS[skill].max)
				end
			end
			return paid
		end
		local function send(ev: any)
			now += 1
			ev.inventory = ev.inventory or inv
			local completed = {}
			for _, ch in Quests.apply(log, DEFS, ev, Objectives, now) do
				if ch.completed then
					table.insert(completed, ch.id)
					grant(ch.id)
				end
			end
			return completed
		end
		local function repair(projectId: string)
			local p = projectById(projectId)
			while not Restoration.complete(restore, p) do
				local a = Restoration.nextAction(restore, p) :: Restoration.Action
				for item, n in a.cost do
					assert((inv[item] or 0) >= n, "pack short of " .. item)
					inv[item] -= n
				end
				local stage = Restoration.advance(restore, p)
				send({ kind = "repair", target = projectId, amount = stage })
			end
		end
		local function start(id: string)
			assert(Quests.start(log, BY_ID[id], ctx(town, now)), "could not start " .. id)
		end
		return {
			log = log,
			town = town,
			restore = restore,
			dog = dog,
			inv = inv,
			send = send,
			repair = repair,
			start = start,
			grant = grant,
		}
	end

	local function journal(s: any): LifeJournal.View
		local rows = {}
		for _, def in DEFS do
			local status = Quests.status(s.log, def, ctx(s.town))
			if status ~= "locked" then
				local obj, prog = Quests.current(s.log, def)
				table.insert(rows, {
					id = def.id,
					title = def.title,
					giverName = def.giver,
					place = "",
					status = status,
					category = def.category,
					optional = def.optional == true,
					context = def.context,
					objective = obj and obj.text,
					progress = obj and Objectives.progressText(obj :: any, prog, s.inv),
				})
			end
		end
		local _, tier = Town.tier(s.town.reputation, TownConfig.Tiers)
		return LifeJournal.build({
			quests = rows,
			credits = s.town.credits,
			reputation = s.town.reputation,
			tier = tier.name,
			tierFraction = 0,
			people = {},
			projects = {},
			skills = { { name = "Tracking", level = s.dog.tracking, max = DOG_SKILLS.tracking.max } },
			milestones = {},
			changes = {},
			observations = 0,
		})
	end

	it("all five missions start and complete with the right rewards", function()
		local s = play()
		-- Frank
		s.start("frank_shed")
		s.inv.Wood = 8
		s.send({ kind = "inventory" })
		s.repair("FrankShed")
		eq(s.send({ kind = "talk", target = "frank" })[1], "frank_shed")
		eq(s.inv.Scrap, 2)
		-- Ellen
		s.start("ellen_meal")
		s.inv.Berries, s.inv.Mushroom = 2, 1
		s.send({ kind = "inventory" })
		s.send({ kind = "interact", target = "DinerStove" })
		eq(s.send({ kind = "talk", target = "ellen" })[1], "ellen_meal")
		-- Martha
		s.start("martha_dog")
		s.send({ kind = "interact", target = "BiscuitScarf" })
		s.send({ kind = "locate", target = "Biscuit" })
		s.send({ kind = "reach", target = "MarthaHouse" })
		eq(s.send({ kind = "talk", target = "martha" })[1], "martha_dog")
		eq(s.dog.tracking, 1, "Martha's reward raises Tracking by one")
		falsy(s.grant("martha_dog"))
		eq(s.dog.tracking, 1, "and only once")
		-- Maya
		Quests.setFlag(s.log, "metMaya")
		s.start("maya_garden")
		s.inv.Wood, s.inv.Fiber = 4, 2
		s.send({ kind = "inventory" })
		s.repair("MayaGarden")
		eq(s.send({ kind = "talk", target = "maya" })[1], "maya_garden")
		s.start("maya_meal")
		s.send({ kind = "deliver", target = "maya" })
		falsy(Quests.isDone(s.log, "maya_meal"))
		s.send({ kind = "interact", target = "MayaTable", phase = "Night" })
		falsy(Quests.isDone(s.log, "maya_meal"), "no supper at night")
		eq(s.send({ kind = "interact", target = "MayaTable", phase = "Dusk" })[1], "maya_meal")
		-- Dr. Hale
		s.start("hale_sensor")
		s.send({ kind = "reach", target = "SensorMast" })
		s.send({ kind = "investigate", target = "SensorMast" })
		s.inv.Fiber = 1
		s.send({ kind = "inventory" })
		s.repair("WeatherSensor")
		eq(s.send({ kind = "talk", target = "hale" })[1], "hale_sensor")

		eq(s.town.credits, 15 + 10 + 10 + 15)
		eq(s.town.reputation, 10 + 8 + 8 + 3 + 10)
		eq(s.town.trust.maya, 7)
		for _, flag in
			{
				"frankShedRepaired",
				"dinerOpen",
				"biscuitHome",
				"gardenRepaired",
				"sharedMeal",
				"forecastUnlocked",
			}
		do
			truthy(Quests.hasFlag(s.log, flag), flag)
		end
		local _, tier = Town.tier(s.town.reputation, TownConfig.Tiers)
		eq(tier.name, "Neighbour")
		-- New opportunities opened, optional ones stay optional.
		eq(Quests.status(s.log, BY_ID.hale_watchers, ctx(s.town)), "available")
		truthy(BY_ID.hale_watchers.optional)
		-- A finished quest never pays again.
		falsy(s.grant("frank_shed"))
		eq(s.town.credits, 50)
	end)

	it("survives a save and rejoin: same journal, nothing to claim twice", function()
		local s = play()
		s.start("frank_shed")
		s.inv.Wood = 8
		s.send({ kind = "inventory" })
		s.repair("FrankShed")
		s.send({ kind = "talk", target = "frank" })
		s.start("ellen_meal")
		s.inv.Berries = 1
		s.send({ kind = "inventory" })
		Quests.setFlag(s.log, "metMaya")
		s.start("maya_garden")
		s.inv.Wood = 4
		s.inv.Fiber = 2
		s.send({ kind = "inventory" })
		local p = projectById("MayaGarden")
		s.inv.Wood -= 4
		Restoration.advance(s.restore, p)
		s.send({ kind = "repair", target = "MayaGarden", amount = 1 })

		-- DataStore saves JSON: encode, decode, restore as untrusted data.
		local blob = serde.encode("json", {
			quests = Quests.snapshot(s.log),
			town = Town.snapshot(s.town),
			projects = s.restore,
			tracking = s.dog.tracking,
		})
		local data = serde.decode("json", blob)
		local r = play()
		r.log = Quests.restore(data.quests, DEFS)
		r.town = Town.restore(data.town, LIMITS)
		r.restore = Restoration.restore(data.projects, PROJECTS)
		r.dog = { tracking = data.tracking }
		r.inv = s.inv

		eq(
			serde.encode("json", journal(r)),
			serde.encode("json", journal(s)),
			"journal identical after rejoin"
		)
		eq(Restoration.stage(r.restore, projectById("FrankShed")), 3)
		eq(Restoration.stage(r.restore, p), 1)
		falsy(Town.grant(r.town, "quest:frank_shed", { credits = 15 }, LIMITS), "no re-claim")
		eq(r.town.credits, 15)
		local obj = Quests.current(r.log, BY_ID.maya_garden)
		eq(obj and obj.kind, "repair", "mid-quest step kept")
		-- And the rest of that quest still works after the rejoin.
		local stage = Restoration.advance(r.restore, p)
		local changes = Quests.apply(
			r.log,
			DEFS,
			{ kind = "repair", target = "MayaGarden", amount = stage },
			Objectives,
			9
		)
		truthy(changes[1].objectiveDone)
	end)

	it("the journal shows real progress and the tracker follows the errand", function()
		local s = play()
		local before = journal(s)
		truthy(before.tracker and before.tracker.available, "nothing in hand points at someone to help")
		s.start("frank_shed")
		s.inv.Wood = 5
		s.send({ kind = "inventory" })
		local view = journal(s)
		eq(#view.tabs, 4)
		eq(view.tabs[1].id, "HOME")
		eq(view.tabs[4].id, "MYSTERIES")
		local errand = view.tabs[1].sections[2].rows[1]
		eq(errand.title, "Frank's tool shed")
		truthy(string.find(errand.detail or "", "Wood 5/8", 1, true), errand.detail)
		eq(view.tracker and view.tracker.objective, "Gather 8 wood for Frank's shed")
		eq(view.tracker and view.tracker.progress, "Wood 5/8")
	end)
end)

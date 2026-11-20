--!strict
-- Day 1 of the Revision 2.0 opening. It only sequences what the real systems
-- already do (radio card, creature AI, coat, lights, curtains, breath); it
-- never fakes a mechanic. Every step has a gentle fallback so a lost or slow
-- player is nudged, never stuck:
--   morning radio call -> firewood -> fire -> visit Maya -> home at dusk ->
--   first Watcher with Maya coaching -> it leaves -> calm rain, her lamp on.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Creature = require(script.Parent.Parent.Creatures.Creature)
local CreatureService = require(script.Parent.CreatureService)
local InteractionService = require(script.Parent.InteractionService)
local LightService = require(script.Parent.LightService)
local MayaService = require(script.Parent.MayaService)
local PlayerService = require(script.Parent.PlayerService)
local StoryService = require(script.Parent.StoryService)
local TimeService = require(script.Parent.TimeService)
local WeatherService = require(script.Parent.WeatherService)

local OpeningService = {}

local MORNING = {
	"Morning. I can see smoke coming from your chimney. Are you awake yet?",
	"Come over later—I made something for you.",
	"Bring in some firewood first. The radio says it'll be a cold one.",
}

local morningStarted = false
local tutorialStarted = false

local function fact(key: string): boolean
	return StoryService.getFact(key) == true
end

local function lines(list: { string }, gap: number)
	for i, text in list do
		MayaService.radio(text)
		if i < #list then
			task.wait(gap)
		end
	end
end

local function morningCall()
	if morningStarted then
		return
	end
	morningStarted = true
	task.spawn(function()
		lines(MORNING, 4)
		StoryService.setFact("mayaMorning", true)
	end)
end

local function cabinCurtainsClosed(): boolean
	for _, w in CollectionService:GetTagged("Window") do
		if w:GetAttribute("Shelter") == "Cabin" then
			if not (w:GetAttribute("CurtainsClosed") == true or w:GetAttribute("Shuttered") == true) then
				return false
			end
		end
	end
	return true
end

local function anyPlayer(test: (PlayerService.PState) -> boolean): boolean
	for _, s in PlayerService.all() do
		if s.spawned and test(s) then
			return true
		end
	end
	return false
end

-- Waits until done() or the timeout. Returns true when done() fired.
local function waitFor(done: () -> boolean, timeout: number, tick: (() -> ())?): boolean
	local started = os.clock()
	while os.clock() - started < timeout do
		if done() then
			return true
		end
		if tick then
			tick()
		end
		task.wait(0.5)
	end
	return done()
end

local function alive(c: Creature.Creature): boolean
	for _, other in CreatureService.list() do
		if other == c then
			return c.alive
		end
	end
	return false
end

local function firstWatcher()
	-- Wait for the player to be home (or a minute of night), then it comes.
	if not fact("homeAtDusk1") then
		MayaService.radio("Where are you? Get inside. Now.")
		waitFor(function()
			return fact("homeAtDusk1")
		end, 60)
	end
	local home = CreatureService.edgePoint(0, 85)
	local far: { Vector3 } = {}
	for i = 1, 5 do
		table.insert(far, CreatureService.edgePoint((i - 3) * 22, 70 + (i % 2) * 18))
	end
	local c = CreatureService.spawn(
		"Watcher",
		home,
		{ patrol = far, leash = 95, retreatTo = CreatureService.edgePoint(0, 300) }
	)
	MayaService.setRoom("Upstairs", false)
	MayaService.setRoom("Downstairs", false)

	-- Forgiving: if it starts hunting someone, it loses them after a moment.
	local lastSave = 0
	local function guard()
		if c.state == "HUNT" and os.clock() - lastSave > 20 then
			lastSave = os.clock()
			Creature.flee(c, 6)
			MayaService.radio("Don't move! ...Okay. Okay. It lost you.")
		end
	end

	task.wait(6)
	MayaService.radio("Hey. Don't panic. Something's walking along the treeline north of you.")
	task.wait(4)
	MayaService.radio("Look out your north window. Slowly.")
	waitFor(function()
		return c.observedFor > 0.5 or anyPlayer(function(s)
			return s.observing ~= nil
		end)
	end, 45, guard)
	StoryService.setFact("watcherSeen", true)

	MayaService.radio("That's a Watcher. Light and movement draw them. Stillness doesn't.")
	task.wait(4)
	MayaService.radio("Put on your grandfather's coat. Slowly.")
	waitFor(function()
		return anyPlayer(function(s)
			return s.coat
		end)
	end, 600, guard)
	StoryService.setFact("tutorialCoat", true)

	MayaService.radio("Good. Now go dark. The fuse box by the door kills every light. Then the curtains.")
	local nudged = false
	waitFor(
		function()
			local electric = LightService.shelterLights("Cabin")
			return electric == 0 and cabinCurtainsClosed()
		end,
		600,
		function()
			guard()
			if not nudged and LightService.shelterLights("Cabin") == 0 and not cabinCurtainsClosed() then
				nudged = true
				MayaService.radio("The curtains too. Every window.")
			end
		end
	)
	StoryService.setFact("tutorialDark", true)

	-- Now it comes to the house and looks. The window behaviour is its own.
	local near: { Vector3 } = {}
	for i = 1, 4 do
		table.insert(near, CreatureService.edgePoint((i - 2.5) * 18, 22 + (i % 2) * 6))
	end
	c.patrol = near
	c.goal = nil
	MayaService.radio("It's coming closer. Crouch. Stay still.")
	task.wait(5)
	MayaService.radio("If it's right at the glass, hold your breath.")
	waitFor(function()
		return not alive(c)
	end, 45, guard)

	if alive(c) then
		Creature.flee(c, 400)
		waitFor(function()
			return not alive(c)
		end, 50)
		if alive(c) then
			CreatureService.remove(c)
		end
	end
	StoryService.setFact("watcherGone", true)
	WeatherService.force("Rain")
	task.wait(6)
	MayaService.setRoom("Upstairs", true)
	MayaService.goTo("Upstairs")
	task.wait(3)
	MayaService.radio("You okay over there? I can still see your house.")
	task.wait(5)
	MayaService.radio("Get some sleep. I'll leave my lamp on.")
	Net.event("Notify"):FireAllClients("It's gone. Rain starts on the roof.", "good")
end

local function derive()
	local snap = TimeService.snapshot()
	if snap.day ~= 1 then
		return
	end
	local evening = snap.phase == "Dusk" or snap.phase == "Night"
	if evening and not fact("homeAtDusk1") then
		if anyPlayer(function(s)
			return s.shelter == "Cabin"
		end) then
			StoryService.setFact("homeAtDusk1", true)
		end
	end
end

local function onPhase(snap: any)
	if snap.day ~= 1 then
		return
	end
	if snap.phase == "Dusk" then
		if fact("talkedToMaya") then
			MayaService.radio("Sun's going down. Head home before dark, okay?")
		else
			MayaService.radio(
				"You didn't make it over. That's okay, I'll save you a plate. Get home before dark."
			)
		end
	elseif snap.phase == "Night" then
		-- Never let a missed visit block the night lesson.
		StoryService.setFact("talkedToMaya", true)
		if not tutorialStarted then
			tutorialStarted = true
			task.spawn(firstWatcher)
		end
	end
end

function OpeningService.start()
	InteractionService.setRadioHook(function(_player: Player): boolean
		if fact("mayaMorning") or morningStarted then
			return false
		end
		morningCall()
		return true
	end)
	PlayerService.onSpawned(function(player: Player)
		-- Grandfather's coat hangs by the door from the start.
		PlayerService.setCoatFound(player)
		StoryService.setFact("coatFound", true)
		if TimeService.snapshot().day ~= 1 or morningStarted then
			return
		end
		task.delay(4, function()
			if not morningStarted then
				Net.event("SoundCue"):FireAllClients("radioStatic", nil, 0.6)
				Net.event("Notify"):FireAllClients("The radio on the table crackles.", "info")
			end
		end)
		-- If nobody answers, she keeps calling until the speaker carries it.
		task.delay(45, morningCall)
	end)
	TimeService.onPhaseChanged(onPhase)
	task.spawn(function()
		while true do
			task.wait(1)
			derive()
		end
	end)
end

return OpeningService

--!strict
-- The dog: a companion, an early warning, and a reason to stay home.
-- One per player. It never dies and never gets permanently lost: if it is
-- stuck or far away it catches up out of sight.
--
-- Dog model attributes: Owner (UserId), DogState (follow, stay, sit, sleep,
-- home, hide, come), Pose (stand, sit, sleep, hide, alert, happy), Alert,
-- Agitation (0..1), DogMood (RELAXED, ALERT, SUSPICIOUS, AFRAID, PANICKED,
-- CONCEALED, RECOVERING).
--
-- Chapter 38: he senses creatures with his own ears, eyes and a nose for
-- presence, imperfectly. His mood (Logic/DogMind) drives what you see and
-- hear: head up, a quiet growl, whimpering and seeking you or his bed,
-- barking. Barks are real noise events creatures can hear. You can calm him
-- step by step, and hide together under the coat.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CreatureBrain = require(ReplicatedStorage.Shared.Logic.CreatureBrain)
local DogMind = require(ReplicatedStorage.Shared.Logic.DogMind)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Rigs = require(script.Parent.Parent.Creatures.Rigs)
local CreatureService = require(script.Parent.CreatureService)
local NoiseService = require(script.Parent.NoiseService)
local PlayerService = require(script.Parent.PlayerService)
local ShelterService = require(script.Parent.ShelterService)
local TimeService = require(script.Parent.TimeService)
local WeatherService = require(script.Parent.WeatherService)

local DogService = {}

type Dog = {
	owner: Player,
	rig: Rigs.Rig,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	state: string,
	waypoints: { PathWaypoint },
	wpIndex: number,
	pathAt: number,
	computing: boolean,
	lastPos: Vector3,
	stuckFor: number,
	lastBark: number,
	ownerIdleFor: number,
	lastOwnerPos: Vector3,
	happyUntil: number,
	auto: string?, -- automatic override: "hide", "bed" or "seek"
	-- Chapter 38
	mind: DogMind.Mind,
	concealed: boolean,
	concealSince: number,
	concealLoose: number,
	nextGrowl: number,
	nextWhine: number,
	barkNoticeAt: number,
	seenKinds: { [string]: boolean },
	quietTrained: boolean,
	hideTrained: boolean,
	gustAt: number,
	threatDist: number,
	startle: number,
	lastStartle: number,
	petPrompt: ProximityPrompt?,
	hidePrompt: ProximityPrompt?,
}

local D = GameConfig.Dog
local dogs: { [Player]: Dog } = {}
local folder: Folder

local COMMANDS: { [string]: boolean } = {
	follow = true,
	stay = true,
	come = true,
	sit = true,
	sleep = true,
	home = true,
	calm = true,
	hide = true,
}

local function now(): number
	return os.clock()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function dogBed(): BasePart?
	for _, b in CollectionService:GetTagged("DogBed") do
		if b:IsA("BasePart") then
			return b
		end
	end
	return nil
end

local function groundNear(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position else pos
end

local function setPose(d: Dog, pose: string)
	if d.model:GetAttribute("Pose") ~= pose then
		d.model:SetAttribute("Pose", pose)
	end
end

local function teleportNear(d: Dog, target: Vector3, behind: Vector3?)
	local offset = if behind and behind.Magnitude > 0.1 then -behind.Unit * 4 else Vector3.new(3, 0, 3)
	local p = groundNear(target + offset)
	d.model:PivotTo(CFrame.new(p + Vector3.new(0, d.humanoid.HipHeight + 1, 0)))
	d.waypoints = {}
	d.stuckFor = 0
end

local function computePath(d: Dog, goal: Vector3)
	if d.computing or now() - d.pathAt < 1 then
		return
	end
	d.computing = true
	d.pathAt = now()
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 1.2,
			AgentHeight = 3,
			AgentCanJump = true,
			Costs = { Water = 20 },
		})
		local ok = pcall(function()
			path:ComputeAsync(d.root.Position, goal)
		end)
		d.computing = false
		if ok and path.Status == Enum.PathStatus.Success then
			d.waypoints = path:GetWaypoints()
			d.wpIndex = math.min(2, #d.waypoints)
		else
			d.waypoints = {}
		end
	end)
end

local function walkTo(d: Dog, goal: Vector3, run: boolean)
	d.humanoid.WalkSpeed = if run then D.RunSpeed else D.WalkSpeed
	local dist = flat(goal - d.root.Position).Magnitude
	if dist > 14 then
		computePath(d, goal)
		local wp = d.waypoints[d.wpIndex]
		if wp then
			if flat(wp.Position - d.root.Position).Magnitude < 2.5 then
				d.wpIndex += 1
				wp = d.waypoints[d.wpIndex]
			end
			if wp then
				if wp.Action == Enum.PathWaypointAction.Jump then
					d.humanoid.Jump = true
				end
				d.humanoid:MoveTo(wp.Position)
				return
			end
		end
	end
	d.humanoid:MoveTo(goal)
end

local function hold(d: Dog)
	d.humanoid:MoveTo(d.root.Position)
end

local function faceToward(d: Dog, pos: Vector3)
	local p = d.root.Position
	local dir = flat(pos - p)
	if dir.Magnitude > 0.5 then
		d.root.CFrame = CFrame.lookAt(p, p + dir)
	end
end

-- What he picks up: movement he hears, silhouettes he sees, a presence he
-- feels through walls, all further than you would. He is not perfect: deer,
-- crows and gusts can set him off, heavy rain hides footsteps, and a
-- perfectly still Watcher can slip past his eyes.
local function sense(d: Dog): (number, string?, Vector3?, number)
	local pos = d.root.Position
	local head = pos + Vector3.new(0, 1.5, 0)
	local rain = (ReplicatedStorage:GetAttribute("RainIntensity") :: number?) or 0
	local best, bestDist = 0, math.huge
	local bestKind: string?, bestPos: Vector3? = nil, nil
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { d.model }
	for _, c in CreatureService.list() do
		if c.state == "DORMANT" or c.state == "RETREAT" then
			continue
		end
		local cpos = c.root.Position
		local dist = (cpos - pos).Magnitude
		if dist > 120 then
			continue
		end
		local moving = c.root.AssemblyLinearVelocity.Magnitude > 1.5
		local still = not moving and c.temperament == "Patient"
		local seen = dist < 90
			and not (still and dist > 35)
			and workspace:Raycast(head, cpos - head, params) == nil
		local s = DogMind.signal(d.mind, c.kind, dist, {
			heard = moving and (rain < 3 or dist < 35),
			seen = seen,
			presence = dist < 30,
		})
		if s > best then
			best, bestKind, bestPos, bestDist = s, c.kind, cpos, dist
		end
	end
	if best < 0.2 then
		for _, w in CollectionService:GetTagged("Wildlife") do
			if w:IsA("Model") then
				local wpos = w:GetPivot().Position
				local dist = (wpos - pos).Magnitude
				local s = DogMind.signal(
					d.mind,
					"Wildlife",
					dist,
					{ heard = true, seen = dist < 25, presence = false }
				)
				if s > best then
					best, bestKind, bestPos, bestDist = s, "Wildlife", wpos, dist
				end
			end
		end
		if now() - d.gustAt < 2 and DogMind.KindWeight.Wind > best then
			best, bestKind, bestPos, bestDist = DogMind.KindWeight.Wind, "Wind", nil, math.huge
		end
	end
	return best, bestKind, bestPos, bestDist
end

local function mayaNear(pos: Vector3): boolean
	for _, m in CollectionService:GetTagged("Maya") do
		if m:IsA("Model") and (m:GetPivot().Position - pos).Magnitude < 20 then
			return true
		end
	end
	return false
end

-- Barking is a real sound: creatures can hear it. A panic bark is two or
-- three; a single defensive bark can startle a Crawler right on top of him.
local function bark(d: Dog, panic: boolean, threatDist: number)
	local owner = d.owner
	local n = if panic then math.random(2, 3) else 1
	task.spawn(function()
		for _ = 1, n do
			if not d.model.Parent then
				return
			end
			local p = d.root.Position
			NoiseService.emit(p, "bark", owner)
			Net.event("SoundCue"):FireAllClients("bark", p, 1)
			task.wait(0.45)
		end
	end)
	-- A single bark can make the nearest Crawler lose interest for a moment.
	-- Only one, and it forgets rather than leaving, so a breach still holds.
	if not panic and threatDist < 14 and math.random() < 0.5 then
		local nearest, nearestD = nil, 14
		for _, c in CreatureService.list() do
			local cd = (c.root.Position - d.root.Position).Magnitude
			if c.kind == "Crawler" and cd < nearestD then
				nearest, nearestD = c, cd
			end
		end
		if nearest then
			CreatureBrain.forget(nearest.brain)
			nearest.brain.state = "PATROL"
		end
	end
	if now() - d.barkNoticeAt > 20 then
		d.barkNoticeAt = now()
		Net.event("Notify"):FireClient(
			owner,
			"Caramelo is barking. Calm him (T), or crouch in your coat and hide together (E).",
			"warning"
		)
	end
end

-- One calming moment. It never erases panic at once, and less so with the
-- thing still close. Calming him down from real fear teaches him quiet.
local function calmDog(d: Dog)
	local before = d.mind.level
	DogMind.calm(d.mind, d.threatDist < 40, DogMind.Default)
	d.happyUntil = 0
	if d.mind.agitation < DogMind.Default.down[2] then
		if before >= 3 and not d.quietTrained then
			d.quietTrained = true
			DogMind.train(d.mind, "quietness", 0.05)
		end
		Net.event("Notify"):FireClient(d.owner, "He settles against your leg.", "info")
	else
		Net.event("Notify")
			:FireClient(d.owner, "You stroke his back and murmur. He is still trembling.", "info")
	end
	Net.event("SoundCue"):FireAllClients("whine", d.root.Position, 0.25)
end

local function conceal(d: Dog)
	d.concealed = true
	d.concealSince = now()
	d.concealLoose = 0
	d.auto = nil
end

local function command(player: Player, cmd: any)
	if type(cmd) ~= "string" or not COMMANDS[cmd] or not Net.allow(player, "dog", 4) then
		return
	end
	local d = dogs[player]
	if not d then
		return
	end
	d.auto = nil
	if cmd == "calm" then
		calmDog(d)
		return
	end
	d.state = cmd
	d.model:SetAttribute("DogState", cmd)
end

local function tickDog(d: Dog, dt: number)
	local owner = d.owner
	local ownerRoot = PlayerService.root(owner)
	local s = PlayerService.get(owner)
	if not ownerRoot or not s or not s.spawned then
		hold(d)
		return
	end
	local pos = d.root.Position
	local ownerPos = ownerRoot.Position
	local dist = flat(ownerPos - pos).Magnitude
	local snap = TimeService.snapshot()
	local night = snap.phase == "Night" or snap.phase == "Dusk"

	-- Owner idle time (for settling down on the dog bed).
	if (ownerPos - d.lastOwnerPos).Magnitude < 1 then
		d.ownerIdleFor += dt
	else
		d.ownerIdleFor = 0
	end
	d.lastOwnerPos = ownerPos

	-- His senses, his mood, his reactions.
	local signal, kind, threatPos, threatDist = sense(d)
	d.threatDist = threatDist
	-- A tap at the glass, a scratch on the wall, a dash past the window.
	local startledAt = d.model:GetAttribute("StartledAt") :: number?
	if startledAt and startledAt > d.lastStartle then
		d.lastStartle = startledAt
		d.startle = math.max(d.startle, (d.model:GetAttribute("StartleStrength") :: number?) or 0.3)
	end
	d.startle = math.max(0, d.startle - 0.08 * dt)
	local target = DogMind.target(d.mind, signal, {
		ownerNear = dist < 12,
		concealed = d.concealed,
		mayaNear = mayaNear(pos),
		inShelter = ShelterService.shelterAt(pos, 1) ~= nil,
		thunder = false,
		startle = d.startle,
	})
	local wasLevel, peakBefore = d.mind.level, d.mind.peak
	DogMind.step(d.mind, target, dt, DogMind.Default)
	local level = d.mind.level
	if level >= 2 and kind and kind ~= "Wildlife" and kind ~= "Wind" then
		d.seenKinds[kind] = true
	end
	if level == 0 and wasLevel > 0 and peakBefore >= 2 then
		-- It came, it went, nothing happened: next time it is a little less.
		if not s.captured then
			for k in d.seenKinds do
				DogMind.learn(d.mind, k)
			end
		end
		table.clear(d.seenKinds)
		d.quietTrained = false
		d.hideTrained = false
	end
	local alert = level >= 1
	d.model:SetAttribute("Alert", alert)
	d.model:SetAttribute("Agitation", math.floor(d.mind.agitation * 100 + 0.5) / 100)
	d.model:SetAttribute("DogMood", DogMind.state(d.mind, d.concealed))
	local uneasy = ReplicatedStorage:GetAttribute("BadNightWarning") == true
	d.model:SetAttribute("Uneasy", uneasy)
	local t = now()
	if level == 2 and t >= d.nextGrowl then
		d.nextGrowl = t + 7 + math.random() * 5
		Net.event("SoundCue"):FireAllClients("growl", pos, 0.4)
	elseif level == 3 and t >= d.nextWhine then
		d.nextWhine = t + 6 + math.random() * 4
		Net.event("SoundCue"):FireAllClients("whine", pos, 0.45)
	end
	if
		t - d.lastBark > 4
		and math.random() < DogMind.barkChance(d.mind, d.concealed, dt, DogMind.Default)
	then
		d.lastBark = t
		bark(d, d.mind.agitation > 0.9, threatDist)
	end
	if d.petPrompt then
		d.petPrompt.ActionText = if level >= 2 then "Calm" else "Pet"
	end
	if d.hidePrompt then
		d.hidePrompt.Enabled = s.coat
		d.hidePrompt.ActionText = if d.concealed then "Release" else "Hide together"
	end

	-- Hiding together under the coat lasts while you stay crouched in it.
	if d.concealed then
		if s.coat and s.crouch and dist < 8 then
			d.concealLoose = 0
		else
			d.concealLoose += dt
			if d.concealLoose > 1.5 then
				d.concealed = false
				Net.event("Notify"):FireClient(owner, "Caramelo slips out from under the coat.", "info")
			end
		end
		if d.concealed and not d.hideTrained and level >= 2 and t - d.concealSince > 20 then
			d.hideTrained = true
			DogMind.train(d.mind, "sharedHiding", 0.1)
		end
	elseif level >= 3 and s.coat and s.crouch and dist < 15 and d.mind.sharedHiding >= 0.3 then
		conceal(d) -- trained: he comes under the coat on his own
	end

	-- Automatic behaviours layered over commands.
	local ownerHiding = (s.crouch or s.breath.holding) and s.threat >= 1
	if ownerHiding and dist < 30 then
		d.auto = "hide"
	elseif d.auto == "hide" and not ownerHiding then
		d.auto = nil
	end
	local bed = dogBed()
	if
		not d.auto
		and d.state == "follow"
		and night
		and s.shelter ~= nil
		and ShelterService.shelterAt(pos, 1) == s.shelter
		and d.ownerIdleFor > 20
		and bed
	then
		d.auto = "bed"
	elseif d.auto == "bed" and (s.shelter == nil or d.ownerIdleFor < 1) then
		d.auto = nil
	end
	-- Frightened: to you if you are close, otherwise to his bed.
	if not d.concealed and level >= 3 then
		if dist < 40 then
			d.auto = "seek"
		elseif bed then
			d.auto = "bed"
		end
	elseif d.auto == "seek" and level < 3 then
		d.auto = nil
	end

	local mode = if d.concealed then "conceal" else (d.auto or d.state)
	if mode == "conceal" then
		-- Tucked against your front, under the coat's hem.
		local look = flat(ownerRoot.CFrame.LookVector)
		local spot = ownerPos + look * 1.4 - Vector3.new(0, 2, 0)
		if flat(spot - pos).Magnitude > 1.2 then
			walkTo(d, spot, true)
			setPose(d, "stand")
		else
			hold(d)
			if look.Magnitude > 0.1 then
				d.root.CFrame = CFrame.lookAt(pos, pos + look)
			end
			setPose(d, "hide")
		end
	elseif mode == "seek" then
		local spot = ownerPos + ownerRoot.CFrame.RightVector * 2 - Vector3.new(0, 2, 0)
		if flat(spot - pos).Magnitude > 1.8 then
			walkTo(d, spot, level >= 4)
			setPose(d, "stand")
		else
			hold(d)
			if threatPos then
				faceToward(d, threatPos)
			end
			setPose(d, "hide")
		end
	elseif mode == "hide" then
		local side = ownerRoot.CFrame.RightVector * 2
		local spot = ownerPos + side - Vector3.new(0, 2, 0)
		if flat(spot - pos).Magnitude > 1.5 then
			walkTo(d, spot, false)
			setPose(d, "stand")
		else
			hold(d)
			setPose(d, "hide")
		end
	elseif mode == "bed" or mode == "home" then
		if bed and flat(bed.Position - pos).Magnitude > 2 then
			walkTo(d, bed.Position, false)
			setPose(d, "stand")
		else
			hold(d)
			if bed then
				faceToward(d, bed.Position + bed.CFrame.LookVector)
			end
			setPose(d, if alert then "alert" else "sleep")
			if mode == "home" and night then
				d.state = "sleep"
				d.model:SetAttribute("DogState", "sleep")
			end
		end
	elseif mode == "stay" or mode == "sit" or mode == "sleep" then
		hold(d)
		local pose = if mode == "sit" then "sit" elseif mode == "sleep" then "sleep" else "stand"
		if alert and threatPos then
			pose = if mode == "sleep" then "alert" else pose
			if mode ~= "sleep" then
				faceToward(d, threatPos)
			end
		end
		setPose(d, if now() < d.happyUntil then "happy" else pose)
	else -- follow / come
		if dist > D.TeleportDistance then
			teleportNear(d, ownerPos, ownerRoot.CFrame.LookVector)
		elseif dist > D.FollowDistance then
			walkTo(d, ownerPos - flat(ownerRoot.CFrame.LookVector) * 3, dist > D.CatchUpDistance)
			setPose(d, "stand")
		else
			hold(d)
			if d.state == "come" then
				d.state = "stay"
				d.model:SetAttribute("DogState", "stay")
			end
			if alert and threatPos then
				faceToward(d, threatPos)
				setPose(d, "alert")
			else
				setPose(d, if now() < d.happyUntil then "happy" elseif uneasy then "alert" else "stand")
			end
		end
	end

	-- Stuck: jump, then catch up out of sight.
	local moving = d.humanoid.MoveDirection.Magnitude > 0.1
		or (#d.waypoints >= d.wpIndex and dist > D.FollowDistance)
	if moving and (pos - d.lastPos).Magnitude < 0.2 then
		d.stuckFor += dt
		if d.stuckFor > 1.5 then
			d.humanoid.Jump = true
		end
		if d.stuckFor > D.StuckSeconds and (mode == "follow" or mode == "come") then
			teleportNear(d, ownerPos, ownerRoot.CFrame.LookVector)
		elseif d.stuckFor > D.StuckSeconds * 2 then
			d.stuckFor = 0
			d.waypoints = {}
		end
	else
		d.stuckFor = 0
	end
	d.lastPos = pos
	-- Fell out of the world somehow: bring it back.
	if pos.Y < -40 then
		teleportNear(d, ownerPos, nil)
	end
end

local function createDog(player: Player, character: Model)
	if dogs[player] then
		return
	end
	local rig = Rigs.dog()
	rig.model:SetAttribute("Owner", player.UserId)
	rig.model:SetAttribute("DogState", "follow")
	rig.model:SetAttribute("Pose", "stand")
	rig.model:SetAttribute("Alert", false)
	rig.model.Name = player.Name .. "_Dog"
	CollectionService:AddTag(rig.model, "Dog")
	local ownerRoot = character:FindFirstChild("HumanoidRootPart")
	local start = if ownerRoot and ownerRoot:IsA("BasePart")
		then ownerRoot.Position + ownerRoot.CFrame.RightVector * 3
		else Vector3.new(0, 20, 0)
	rig.model:PivotTo(CFrame.new(groundNear(start) + Vector3.new(0, 3, 0)))
	rig.model.Parent = folder
	pcall(function()
		rig.root:SetNetworkOwner(nil)
	end)
	local petPart = rig.model:FindFirstChild("Body")
	if petPart then
		local p = Instance.new("ProximityPrompt")
		p.Name = "PetPrompt"
		p.ActionText = "Pet"
		p.ObjectText = "Caramelo"
		-- Own key, so standing next to the dog never hides other E prompts.
		p.KeyboardKeyCode = Enum.KeyCode.T
		p.HoldDuration = 0.4
		p.MaxActivationDistance = 7
		p.RequiresLineOfSight = false
		p.Style = Enum.ProximityPromptStyle.Custom
		p.Parent = petPart
		p.Triggered:Connect(function(who)
			if who ~= player or not Net.allow(who, "pet", 1) then
				return
			end
			local d = dogs[player]
			if d and d.mind.level >= 2 then
				calmDog(d)
			elseif d then
				d.happyUntil = now() + 3
				PlayerService.markPetted(player)
				-- Stop and turn to face the player for the petting.
				local proot = PlayerService.root(player)
				if proot then
					d.humanoid:MoveTo(d.root.Position)
					local look = Vector3.new(proot.Position.X, d.root.Position.Y, proot.Position.Z)
					if (look - d.root.Position).Magnitude > 0.5 then
						d.root.CFrame = CFrame.lookAt(d.root.Position, look)
					end
				end
				d.model:SetAttribute("PettedAt", workspace:GetServerTimeNow())
				Net.event("SoundCue"):FireAllClients("whine", d.root.Position, 0.3)
				local lines = {
					"Caramelo leans into your hand. His tail won't stop.",
					"Caramelo rolls onto his back for belly rubs.",
					"Caramelo sighs and presses his head against your knee.",
				}
				Net.event("Notify"):FireClient(player, lines[math.random(1, #lines)], "info")
			end
		end)
	end
	-- Hide together: you crouch in the coat and he crawls under its hem.
	local hidePrompt: ProximityPrompt? = nil
	if petPart then
		local hp = Instance.new("ProximityPrompt")
		hp.Name = "HidePrompt"
		hp.ActionText = "Hide together"
		hp.ObjectText = "Caramelo"
		hp.HoldDuration = 0.5
		hp.MaxActivationDistance = 8
		hp.RequiresLineOfSight = false
		hp.Style = Enum.ProximityPromptStyle.Custom
		hp.Enabled = false
		hp.Parent = petPart
		hp.Triggered:Connect(function(who)
			if who ~= player or not Net.allow(who, "dogHide", 2) then
				return
			end
			local d = dogs[player]
			local s = PlayerService.get(player)
			if not d or not s then
				return
			end
			if d.concealed then
				d.concealed = false
				Net.event("Notify"):FireClient(player, "You lift the coat. Caramelo stays close.", "info")
			elseif not s.coat then
				Net.event("Notify"):FireClient(player, "Put on the coat first (Q).", "info")
			elseif not s.crouch then
				Net.event("Notify"):FireClient(player, "Crouch first (C), then hide together.", "info")
			else
				conceal(d)
				Net.event("Notify"):FireClient(
					player,
					"Caramelo crawls under the coat against you. Stay low. Stay quiet.",
					"info"
				)
			end
		end)
		hidePrompt = hp
	end
	dogs[player] = {
		owner = player,
		rig = rig,
		model = rig.model,
		root = rig.root,
		humanoid = rig.humanoid,
		state = "follow",
		waypoints = {},
		wpIndex = 1,
		pathAt = 0,
		computing = false,
		lastPos = rig.root.Position,
		stuckFor = 0,
		lastBark = 0,
		ownerIdleFor = 0,
		lastOwnerPos = Vector3.zero,
		happyUntil = 0,
		auto = nil,
		mind = DogMind.new(),
		concealed = false,
		concealSince = 0,
		concealLoose = 0,
		nextGrowl = 0,
		nextWhine = 0,
		barkNoticeAt = 0,
		seenKinds = {},
		quietTrained = false,
		hideTrained = false,
		gustAt = -1e9,
		threatDist = math.huge,
		startle = 0,
		lastStartle = 0,
		petPrompt = if petPart then petPart:FindFirstChild("PetPrompt") :: ProximityPrompt? else nil,
		hidePrompt = hidePrompt,
	}
end

function DogService.dogOf(player: Player): Model?
	local d = dogs[player]
	return if d then d.model else nil
end

function DogService.start()
	folder = Instance.new("Folder")
	folder.Name = "Dogs"
	folder.Parent = workspace
	PlayerService.onSpawned(createDog)
	Players.PlayerRemoving:Connect(function(p)
		local d = dogs[p]
		if d then
			d.model:Destroy()
			dogs[p] = nil
		end
	end)
	Net.event("DogCommand").OnServerEvent:Connect(command)
	-- A hard gust can make him jump at nothing.
	WeatherService.onGust(function(strength: number)
		if strength > 0.6 then
			for _, d in dogs do
				d.gustAt = now()
			end
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < 0.2 then
			return
		end
		for _, d in dogs do
			local ok, err = pcall(tickDog :: any, d, acc)
			if not ok then
				warn("[Dog] " .. tostring(err))
			end
		end
		acc = 0
	end)
end

return DogService

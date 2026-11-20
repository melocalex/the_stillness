--!strict
-- The dog: a companion, an early warning, and a reason to stay home.
-- One per player. It never dies and never gets permanently lost: if it is
-- stuck or far away it catches up out of sight.
--
-- Dog model attributes: Owner (UserId), DogState (follow, stay, sit, sleep,
-- home, hide, come), Pose (stand, sit, sleep, hide, alert, happy), Alert,
-- Calmed.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Rigs = require(script.Parent.Parent.Creatures.Rigs)
local CreatureService = require(script.Parent.CreatureService)
local NoiseService = require(script.Parent.NoiseService)
local PlayerService = require(script.Parent.PlayerService)
local ShelterService = require(script.Parent.ShelterService)
local TimeService = require(script.Parent.TimeService)

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
	lastGrowl: number,
	calmedDay: number,
	ownerIdleFor: number,
	lastOwnerPos: Vector3,
	happyUntil: number,
	auto: string?, -- automatic override: "hide" or "bed"
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

local function nearestThreat(pos: Vector3): (Vector3?, number)
	local best, bestD = nil, math.huge
	for _, c in CreatureService.list() do
		if c.state ~= "DORMANT" and c.state ~= "RETREAT" then
			local dd = (c.root.Position - pos).Magnitude
			if dd < bestD then
				best, bestD = c.root.Position, dd
			end
		end
	end
	return best, bestD
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
		d.calmedDay = TimeService.snapshot().day
		d.model:SetAttribute("Calmed", true)
		d.happyUntil = now() + 2
		Net.event("Notify"):FireClient(player, "You hush the dog. It settles against your leg.", "info")
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
	if snap.day ~= d.calmedDay then
		d.model:SetAttribute("Calmed", false)
	end

	-- Owner idle time (for settling down on the dog bed).
	if (ownerPos - d.lastOwnerPos).Magnitude < 1 then
		d.ownerIdleFor += dt
	else
		d.ownerIdleFor = 0
	end
	d.lastOwnerPos = ownerPos

	-- Threat awareness: alert, growl, maybe bark.
	local threatPos, threatDist = nearestThreat(pos)
	local alert = threatPos ~= nil and threatDist < D.AlertRange
	d.model:SetAttribute("Alert", alert)
	local uneasy = ReplicatedStorage:GetAttribute("BadNightWarning") == true
	d.model:SetAttribute("Uneasy", uneasy)
	local calmed = d.calmedDay == snap.day
	if alert and threatPos then
		if now() - d.lastGrowl > 8 then
			d.lastGrowl = now()
			Net.event("SoundCue"):FireAllClients(if calmed then "whine" else "growl", pos, 0.6)
		end
		if not calmed and threatDist < D.BarkRange and now() - d.lastBark > D.BarkCooldown then
			d.lastBark = now()
			NoiseService.emit(pos, "bark", owner)
			Net.event("SoundCue"):FireAllClients("bark", pos, 1)
			Net.event("Notify"):FireClient(owner, "Your dog barks at the dark. Calm it (G).", "warning")
		end
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

	local mode = d.auto or d.state
	if mode == "hide" then
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
			if d then
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
		lastGrowl = 0,
		calmedDay = 0,
		ownerIdleFor = 0,
		lastOwnerPos = Vector3.zero,
		happyUntil = 0,
		auto = nil,
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

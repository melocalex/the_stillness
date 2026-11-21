--!strict
-- Caramelo follows a scent trail (Chapter 37, Martha's missing dog). Built
-- on DogService's public API only: dogOf() to find the dog and setDriver()
-- to steer it while tracking. Dog behaviour, emotion, barking, hiding and
-- training belong to DogService and DogMind; this module only walks the
-- trail.
--
-- On the trail he sniffs first, then leads nose-down toward the target,
-- leaving paw prints and a faint scent. He waits when he gets ahead, comes
-- back when stuck or far away, and gives up gently after a while. Nothing is
-- lost if the trail runs cold: let him smell the scarf again.

local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local DogService = require(script.Parent.DogService)
local PlayerService = require(script.Parent.PlayerService)

local DogTracking = {}

local LEAD = 26 -- waits for the owner beyond this
local ARRIVE = 5
local TIMEOUT = 150
local SNIFF = 2.5
local TOO_FAR = 120
local STUCK = 4

type Trail = {
	target: () -> Vector3?,
	label: string,
	since: number,
	sniffUntil: number,
	sniffAt: Vector3?,
	onDone: ((boolean) -> ())?,
	lastPrint: Vector3,
	side: number,
	waitNoteAt: number,
	waypoints: { PathWaypoint },
	wp: number,
	pathAt: number,
	computing: boolean,
	lastPos: Vector3,
	stuckFor: number,
	lastTick: number,
}

local trails: { [Player]: Trail } = {}

local function now(): number
	return os.clock()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

local function groundBelow(pos: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
	return if hit then hit.Position else pos
end

local function pawPrint(dog: Model, root: BasePart, side: number)
	local ignore: { Instance } = { dog }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local ground = groundBelow(root.Position + root.CFrame.RightVector * 0.35 * side, ignore)
	local mark = Instance.new("Part")
	mark.Name = "PawPrint"
	mark.Shape = Enum.PartType.Cylinder
	mark.Size = Vector3.new(0.08, 0.55, 0.55)
	mark.Color = Color3.fromRGB(70, 52, 38)
	mark.Material = Enum.Material.SmoothPlastic
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.CastShadow = false
	mark.Transparency = 0.15
	mark.CFrame = CFrame.new(ground + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	mark.Parent = workspace
	Debris:AddItem(mark, 30)
end

local function scent(root: BasePart, on: boolean)
	local e = root:FindFirstChild("TrackingScent")
	if not e and on then
		local made = Instance.new("ParticleEmitter")
		made.Name = "TrackingScent"
		made.Color = ColorSequence.new(Color3.fromRGB(255, 214, 140))
		made.LightEmission = 0.6
		made.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
		made.Transparency = NumberSequence.new(0.35, 1)
		made.Lifetime = NumberRange.new(1.2, 2)
		made.Rate = 10
		made.Speed = NumberRange.new(0.4, 1)
		made.SpreadAngle = Vector2.new(25, 25)
		made.Acceleration = Vector3.new(0, 0.6, 0)
		made.Parent = root
		e = made
	end
	if e and e:IsA("ParticleEmitter") then
		e.Enabled = on
	end
end

local function face(root: BasePart, pos: Vector3)
	local p = root.Position
	local dir = flat(pos - p)
	if dir.Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(p, p + dir)
	end
end

local function computePath(t: Trail, from: Vector3, goal: Vector3)
	if t.computing or now() - t.pathAt < 1.5 then
		return
	end
	t.computing = true
	t.pathAt = now()
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 1.2,
			AgentHeight = 3,
			AgentCanJump = true,
			Costs = { Water = 20 },
		})
		local ok = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		t.computing = false
		if ok and path.Status == Enum.PathStatus.Success then
			t.waypoints = path:GetWaypoints()
			t.wp = math.min(2, #t.waypoints)
		else
			t.waypoints = {}
		end
	end)
end

local function walk(t: Trail, humanoid: Humanoid, root: BasePart, goal: Vector3)
	humanoid.WalkSpeed = 14
	if flat(goal - root.Position).Magnitude > 14 then
		computePath(t, root.Position, goal)
		local wp = t.waypoints[t.wp]
		if wp and flat(wp.Position - root.Position).Magnitude < 2.5 then
			t.wp += 1
			wp = t.waypoints[t.wp]
		end
		if wp then
			if wp.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
			humanoid:MoveTo(wp.Position)
			return
		end
	end
	humanoid:MoveTo(goal)
end

function DogTracking.stop(player: Player, found: boolean)
	local t = trails[player]
	if not t then
		return
	end
	trails[player] = nil
	DogService.setDriver(player, nil)
	local dog = DogService.dogOf(player)
	local root = dog and dog.PrimaryPart
	if root then
		scent(root, false)
	end
	if dog then
		dog:SetAttribute("Tracking", false)
		dog:SetAttribute("Pose", if found then "alert" else "stand")
	end
	if found then
		notify(player, "Caramelo stops, tail high: he found " .. t.label .. "!", "good")
		if root then
			Net.event("SoundCue"):FireAllClients("whine", root.Position, 0.4)
		end
	else
		notify(
			player,
			"Caramelo lost the trail and trots back to you. Let him smell the scarf again.",
			"info"
		)
	end
	if t.onDone then
		task.spawn(t.onDone, found)
	end
end

local function step(player: Player, t: Trail, dog: Model, humanoid: Humanoid, root: BasePart)
	local dt = math.min(now() - t.lastTick, 1)
	t.lastTick = now()
	local ownerRoot = PlayerService.root(player)
	if not ownerRoot then
		humanoid:MoveTo(root.Position)
		return
	end
	local pos = root.Position
	-- Learning the scent: nose to the scarf for a moment.
	if now() < t.sniffUntil then
		humanoid:MoveTo(pos)
		if t.sniffAt then
			face(root, t.sniffAt)
		end
		dog:SetAttribute("Pose", "track")
		return
	end
	local goal = t.target()
	if not goal then
		DogTracking.stop(player, false)
		return
	end
	if flat(goal - pos).Magnitude < ARRIVE then
		humanoid:MoveTo(pos)
		face(root, goal)
		DogTracking.stop(player, true)
		return
	end
	if now() - t.since > TIMEOUT then
		DogTracking.stop(player, false)
		return
	end
	local ownerPos = ownerRoot.Position
	local ownerDist = flat(ownerPos - pos).Magnitude
	if ownerDist > TOO_FAR then
		-- Lost track of the owner: catch up out of sight, then carry on.
		dog:PivotTo(
			CFrame.new(
				groundBelow(ownerPos - ownerRoot.CFrame.LookVector * 4, { dog }) + Vector3.new(0, 3, 0)
			)
		)
		t.waypoints = {}
	elseif ownerDist > LEAD then
		humanoid:MoveTo(pos)
		face(root, ownerPos)
		dog:SetAttribute("Pose", "sit")
		if now() - t.waitNoteAt > 10 then
			t.waitNoteAt = now()
			notify(player, "Caramelo waits for you, ears up, then looks ahead.", "info")
		end
	else
		walk(t, humanoid, root, goal)
		dog:SetAttribute("Pose", "track")
		if (pos - t.lastPrint).Magnitude > 2.6 then
			t.lastPrint = pos
			t.side = -t.side
			pawPrint(dog, root, t.side)
		end
		-- Stuck on something: hop, then come back to the owner and retry.
		if (pos - t.lastPos).Magnitude < 0.2 then
			t.stuckFor += dt
			if t.stuckFor > 1.5 then
				humanoid.Jump = true
			end
			if t.stuckFor > STUCK then
				t.stuckFor = 0
				t.waypoints = {}
				dog:PivotTo(
					CFrame.new(
						groundBelow(ownerPos + ownerRoot.CFrame.RightVector * 3, { dog })
							+ Vector3.new(0, 3, 0)
					)
				)
			end
		else
			t.stuckFor = 0
		end
	end
	t.lastPos = pos
end

-- Starts a trail toward target() (re-read every tick, so a moving target
-- works). sniffAt: where he learns the scent first. onDone(found) runs once.
function DogTracking.track(
	player: Player,
	target: () -> Vector3?,
	label: string,
	sniffAt: Vector3?,
	onDone: ((boolean) -> ())?
): boolean
	local dog = DogService.dogOf(player)
	local root = dog and dog.PrimaryPart
	if not dog or not root then
		return false
	end
	if trails[player] then
		DogTracking.stop(player, false)
	end
	local t: Trail = {
		target = target,
		label = label,
		since = now(),
		sniffUntil = if sniffAt then now() + SNIFF else 0,
		sniffAt = sniffAt,
		onDone = onDone,
		lastPrint = root.Position,
		side = 1,
		waitNoteAt = 0,
		waypoints = {},
		wp = 1,
		pathAt = 0,
		computing = false,
		lastPos = root.Position,
		stuckFor = 0,
		lastTick = now(),
	}
	trails[player] = t
	scent(root, true)
	dog:SetAttribute("Tracking", true)
	DogService.setDriver(player, function(d: Model, humanoid: Humanoid, r: BasePart)
		if trails[player] == t then
			step(player, t, d, humanoid, r)
		end
	end)
	notify(player, "Caramelo buries his nose in it, then sets off. Follow him.", "info")
	return true
end

function DogTracking.isTracking(player: Player): boolean
	return trails[player] ~= nil
end

function DogTracking.start()
	Players.PlayerRemoving:Connect(function(player)
		if trails[player] then
			trails[player] = nil
			DogService.setDriver(player, nil)
		end
	end)
end

return DogTracking

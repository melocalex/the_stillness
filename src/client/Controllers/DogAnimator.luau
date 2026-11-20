--!strict
-- Procedural dog animation on the client: walking legs, a tail that wags
-- with mood, head tilt, and the sit / sleep / hide / alert poses the server
-- sets in the Pose attribute. Visual only.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local DogAnimator = {}

type Joints = {
	root: Motor6D?,
	neck: Motor6D?,
	tail: Motor6D?,
	earL: Motor6D?,
	earR: Motor6D?,
	legs: { [string]: Motor6D },
	phase: number,
	pose: { body: CFrame, neck: CFrame, tail: CFrame },
}

local cache: { [Model]: Joints } = {}

-- The mesh dog (Caramelo) plays the asset's own walk/idle keyframe
-- sequences when the client can register them (Studio), and otherwise swings
-- its leg bones procedurally.
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local TweenService = game:GetService("TweenService")

type MeshAnim = {
	walk: AnimationTrack?,
	idle: AnimationTrack?,
	bones: { [string]: Bone },
	rest: { [string]: CFrame },
}
local meshCache: { [Model]: MeshAnim } = {}

local function heart(m: Model)
	local root = m.PrimaryPart
	if not root then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(60, 60)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = root
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "♥"
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 120, 110)
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	gui.Parent = root
	local info = TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, 5.5, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	task.delay(1.7, function()
		gui:Destroy()
	end)
end

-- The local player visibly pets their own dog: turns to face it, bends at the
-- waist and strokes its back with the right hand (IKControl over the normal
-- animations, so no animation upload is needed). Movement pauses meanwhile.
local Players = game:GetService("Players")
local petting = false

local function petAnimation(m: Model)
	local player = Players.LocalPlayer
	if petting or m.Name ~= player.Name .. "_Dog" then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local dogRoot = m.PrimaryPart
	if not char or not hum or not root or not root:IsA("BasePart") or not dogRoot then
		return
	end
	if (root.Position - dogRoot.Position).Magnitude > 10 then
		return
	end
	local hand = char:FindFirstChild("RightHand")
	local chainRoot = char:FindFirstChild("LowerTorso")
	if not hand or not hand:IsA("BasePart") or not chainRoot or not chainRoot:IsA("BasePart") then
		return -- R15 only
	end
	petting = true
	local flat = Vector3.new(dogRoot.Position.X, root.Position.Y, dogRoot.Position.Z)
	root.CFrame = CFrame.lookAt(root.Position, flat)
	local target = Instance.new("Attachment")
	target.Name = "PetTarget"
	target.Parent = dogRoot
	local ik = Instance.new("IKControl")
	ik.Type = Enum.IKControlType.Position
	ik.EndEffector = hand
	ik.ChainRoot = chainRoot
	ik.Target = target
	ik.Weight = 0
	ik.SmoothTime = 0.06
	ik.Parent = hum
	local walk = hum.WalkSpeed
	hum.WalkSpeed = 0
	task.spawn(function()
		local duration = 2.4
		local t = 0
		while t < duration do
			t += RunService.RenderStepped:Wait()
			ik.Weight = math.clamp(math.min(t / 0.35, (duration - t) / 0.45), 0, 1)
			-- Stroke along the back, from the neck toward the tail and back.
			target.Position = Vector3.new(0, 0.7, -0.3 + math.sin(t * 5) * 0.55)
		end
		ik:Destroy()
		target:Destroy()
		if hum.WalkSpeed == 0 then
			hum.WalkSpeed = walk
		end
		petting = false
	end)
end

local function meshAnim(m: Model): MeshAnim?
	if m:GetAttribute("MeshDog") ~= true then
		return nil
	end
	local existing = meshCache[m]
	if existing then
		return existing
	end
	local mesh = m:FindFirstChild("DogMesh")
	if not mesh then
		return nil
	end
	local rec: MeshAnim = { bones = {}, rest = {} }
	for _, d in mesh:GetDescendants() do
		if d:IsA("Bone") then
			rec.bones[d.Name] = d
			rec.rest[d.Name] = d.Transform
		end
	end
	local controller = mesh:FindFirstChildWhichIsA("AnimationController", true)
	if controller then
		local animator: Animator? = controller:FindFirstChildOfClass("Animator")
		if not animator then
			local created = Instance.new("Animator")
			created.Parent = controller
			animator = created
		end
		for _, kfs in mesh:GetDescendants() do
			if kfs:IsA("KeyframeSequence") then
				local ok, id = pcall(function()
					return KeyframeSequenceProvider:RegisterKeyframeSequence(kfs)
				end)
				if ok and animator then
					local anim = Instance.new("Animation")
					anim.AnimationId = id :: any
					local loaded, track = pcall(function()
						return (animator :: Animator):LoadAnimation(anim)
					end)
					if loaded and track then
						track.Looped = true
						if string.find(kfs.Name, "Walk") then
							rec.walk = track
						else
							rec.idle = track
						end
					end
				end
			end
		end
	end
	meshCache[m] = rec
	m:GetAttributeChangedSignal("PettedAt"):Connect(function()
		heart(m)
		petAnimation(m)
	end)
	m.Destroying:Once(function()
		meshCache[m] = nil
	end)
	return rec
end

local function animateMesh(m: Model, speed: number, pose: string, phase: number)
	local rec = meshAnim(m)
	if not rec then
		return
	end
	local moving = speed > 0.8 and pose ~= "sit" and pose ~= "sleep" and pose ~= "hide"
	if rec.walk or rec.idle then
		if moving then
			if rec.walk and not rec.walk.IsPlaying then
				rec.walk:Play(0.25)
			end
			if rec.walk then
				rec.walk:AdjustSpeed(math.clamp(speed / 9, 0.6, 2.2))
			end
			if rec.idle and rec.idle.IsPlaying then
				rec.idle:Stop(0.25)
			end
		else
			if rec.walk and rec.walk.IsPlaying then
				rec.walk:Stop(0.25)
			end
			if rec.idle and not rec.idle.IsPlaying then
				rec.idle:Play(0.4)
			end
		end
		return
	end
	-- Procedural fallback: swing the leg bones.
	local swing = if moving then math.min(speed / 12, 1) * 0.6 else 0
	local legs: { [string]: number } = {
		["DEF-thigh.L"] = 0,
		["DEF-thigh.R"] = math.pi,
		["DEF-front_thigh.L"] = math.pi,
		["DEF-front_thigh.R"] = 0,
	}
	for name: string, offset: number in legs do
		local bone = rec.bones[name]
		if bone then
			bone.Transform = (rec.rest[name] or CFrame.new())
				* CFrame.Angles(math.sin(phase + offset) * swing, 0, 0)
		end
	end
end

local function joints(m: Model): Joints
	local j = cache[m]
	if j then
		return j
	end
	local found: { [string]: Motor6D } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("Motor6D") then
			found[d.Name] = d
		end
	end
	local nj: Joints = {
		root = found.Root,
		neck = found.Neck,
		tail = found.TailJoint,
		earL = found.EarL,
		earR = found.EarR,
		legs = { LegFL = found.LegFL, LegFR = found.LegFR, LegBL = found.LegBL, LegBR = found.LegBR },
		phase = math.random() * 10,
		pose = { body = CFrame.new(), neck = CFrame.new(), tail = CFrame.new() },
	}
	cache[m] = nj
	m.Destroying:Once(function()
		cache[m] = nil
	end)
	return nj
end

local function lerp(a: CFrame, b: CFrame, t: number): CFrame
	return a:Lerp(b, math.clamp(t, 0, 1))
end

local function animate(m: Model, dt: number)
	local j = joints(m)
	local root = m.PrimaryPart
	if not root then
		return
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local pose = (m:GetAttribute("Pose") :: string?) or "stand"
	j.phase += dt * (2 + speed * 0.9)
	animateMesh(m, speed, pose, j.phase)
	local t = os.clock()

	local body, neck, tail = CFrame.new(), CFrame.new(), CFrame.new()
	local legSwing = if speed > 0.8 then math.min(speed / 12, 1) * 0.7 else 0
	local legs: { [string]: CFrame } = {}
	for name in j.legs do
		local front = string.sub(name, 4, 4) == "F"
		local left = string.sub(name, 5, 5) == "L"
		local offset = (if front then 0 else math.pi) + (if left then 0 else math.pi)
		legs[name] = CFrame.Angles(math.sin(j.phase + offset) * legSwing, 0, 0)
	end

	local wag = 0.25
	if pose == "sit" then
		body = CFrame.new(0, -0.35, 0.2) * CFrame.Angles(math.rad(22), 0, 0)
		legs.LegBL = CFrame.Angles(math.rad(-70), 0, 0)
		legs.LegBR = CFrame.Angles(math.rad(-70), 0, 0)
		neck = CFrame.Angles(math.rad(-10), 0, 0)
	elseif pose == "sleep" then
		body = CFrame.new(0, -1.05, 0) * CFrame.Angles(0, 0, math.rad(4))
		for name in legs do
			legs[name] = CFrame.Angles(math.rad(if string.sub(name, 4, 4) == "F" then -80 else 80), 0, 0)
		end
		neck = CFrame.new(0, -0.35, 0) * CFrame.Angles(math.rad(20), 0, 0)
		-- slow sleeping breath
		body *= CFrame.new(0, math.sin(t * 1.6) * 0.04, 0)
		wag = 0
	elseif pose == "hide" then
		body = CFrame.new(0, -0.95, 0)
		for name in legs do
			legs[name] = CFrame.Angles(math.rad(if string.sub(name, 4, 4) == "F" then -80 else 80), 0, 0)
		end
		neck = CFrame.new(0, -0.3, -0.1) * CFrame.Angles(math.rad(12), 0, 0)
		tail = CFrame.Angles(math.rad(-40), 0, 0)
		wag = 0
	elseif pose == "alert" then
		neck = CFrame.Angles(math.rad(-18), 0, 0)
		tail = CFrame.Angles(math.rad(-25), 0, 0)
		wag = 0.02
	elseif pose == "happy" then
		-- Being petted: sit, head up toward the player, tail going.
		wag = 1.1
		body = CFrame.new(0, -0.3, 0.2) * CFrame.Angles(math.rad(18), 0, 0)
		legs.LegBL = CFrame.Angles(math.rad(-65), 0, 0)
		legs.LegBR = CFrame.Angles(math.rad(-65), 0, 0)
		neck = CFrame.Angles(math.rad(-14), math.sin(t * 3) * 0.15, 0)
	end
	-- His mood on top of the pose (Chapter 38): suspicious, he leans in low;
	-- frightened, he crouches and trembles, harder when panicked. Read from
	-- his body, not from a meter. The mesh rides the body joint, so this shows.
	local mood = m:GetAttribute("DogMood")
	if pose ~= "sleep" and pose ~= "hide" and pose ~= "happy" then
		if mood == "SUSPICIOUS" then
			body *= CFrame.new(0, -0.12, -0.05) * CFrame.Angles(math.rad(-5), 0, 0)
			wag = 0
		elseif mood == "AFRAID" or mood == "PANICKED" then
			local shake = if mood == "PANICKED" then 0.04 else 0.025
			body *= CFrame.new(math.sin(t * 41) * shake, -0.35, 0.05) * CFrame.Angles(math.rad(-7), 0, 0)
			tail = CFrame.Angles(math.rad(-50), 0, 0)
			wag = 0
		end
	elseif pose == "hide" and (mood == "AFRAID" or mood == "PANICKED") then
		body *= CFrame.new(math.sin(t * 37) * 0.015, 0, 0)
	end
	if speed > 0.8 then
		body *= CFrame.new(0, math.abs(math.sin(j.phase)) * 0.08, 0)
	end
	tail *= CFrame.Angles(0, math.sin(t * (6 + wag * 10)) * wag * 0.6, 0)

	local k = dt * 6
	j.pose.body = lerp(j.pose.body, body, k)
	j.pose.neck = lerp(j.pose.neck, neck, k)
	j.pose.tail = lerp(j.pose.tail, tail, k * 2)
	if j.root then
		j.root.Transform = j.pose.body
	end
	if j.neck then
		j.neck.Transform = j.pose.neck
	end
	if j.tail then
		j.tail.Transform = j.pose.tail
	end
	for name, motor in j.legs do
		motor.Transform = lerp(motor.Transform, legs[name] or CFrame.new(), k * 1.5)
	end
	local earAngle = if pose == "alert" then math.rad(-15) else math.rad(10)
	if j.earL then
		j.earL.Transform = CFrame.Angles(earAngle, 0, 0)
	end
	if j.earR then
		j.earR.Transform = CFrame.Angles(earAngle, 0, 0)
	end
end

function DogAnimator.start()
	RunService.PreSimulation:Connect(function(dt: number)
		for _, d in CollectionService:GetTagged("Dog") do
			if d:IsA("Model") then
				animate(d, dt)
			end
		end
	end)
end

return DogAnimator

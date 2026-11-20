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
		wag = 1.1
		neck = CFrame.Angles(math.rad(-8), math.sin(t * 3) * 0.15, 0)
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

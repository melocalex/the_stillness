--!strict
-- Part-built creature and dog rigs. Each has an invisible collidable
-- HumanoidRootPart, a Humanoid that cannot die, and massless visual parts
-- joined with Motor6Ds so clients can animate them procedurally.

local Assets = require(script.Parent.Parent.World.Assets)

local Rigs = {}

local dressDog: (Model, BasePart, BasePart) -> ()

local function part(
	model: Model,
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function motor(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = c1
	m.Parent = p0
	return m
end

local function humanoid(model: Model, hipHeight: number, speed: number): Humanoid
	local h = Instance.new("Humanoid")
	h.RigType = Enum.HumanoidRigType.R15
	h.HipHeight = hipHeight
	h.WalkSpeed = speed
	h.RequiresNeck = false
	h.BreakJointsOnDeath = false
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	h.MaxHealth = 1000
	h.Health = 1000
	h.AutoJumpEnabled = true
	h.Parent = model
	for _, st in
		{
			Enum.HumanoidStateType.Dead,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Seated,
			Enum.HumanoidStateType.PlatformStanding,
			Enum.HumanoidStateType.Swimming,
		}
	do
		h:SetStateEnabled(st, false)
	end
	return h
end

local function root(model: Model, size: Vector3, hipHeight: number): Part
	local r = Instance.new("Part")
	r.Name = "HumanoidRootPart"
	r.Size = size
	r.Transparency = 1
	r.CanCollide = true
	r.CanQuery = false
	r.CanTouch = false
	r.CFrame = CFrame.new(0, hipHeight + size.Y / 2, 0)
	r.Parent = model
	model.PrimaryPart = r
	return r
end

export type Rig = { model: Model, root: BasePart, humanoid: Humanoid, eyeHeight: number }

local DARK = Color3.fromRGB(10, 10, 12)

-- Tall, thin, too still. About 11 studs.
function Rigs.watcher(): Rig
	local m = Instance.new("Model")
	m.Name = "Watcher"
	local hip = 5
	local r = root(m, Vector3.new(1.6, 2, 1), hip)
	local torso = part(m, "Torso", Vector3.new(1.5, 3.6, 0.8), DARK)
	motor("Waist", r, torso, CFrame.new(0, 1.6, 0), CFrame.new(0, -1.4, 0))
	local head =
		part(m, "Head", Vector3.new(1, 1.5, 1), DARK, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	motor("Neck", torso, head, CFrame.new(0, 1.8, 0), CFrame.new(0, -0.7, 0))
	for _, s in { -1, 1 } do
		local eye =
			part(m, "Eye", Vector3.new(0.12, 0.08, 0.05), Color3.fromRGB(210, 210, 196), Enum.Material.Neon)
		eye.Transparency = 0.35
		local w = Instance.new("Weld")
		w.Part0 = head
		w.Part1 = eye
		w.C0 = CFrame.new(s * 0.18, 0.15, -0.48)
		w.Parent = eye
		local arm = part(m, "Arm", Vector3.new(0.35, 5.4, 0.35), DARK)
		motor(
			if s < 0 then "ArmL" else "ArmR",
			torso,
			arm,
			CFrame.new(s * 0.9, 1.6, 0),
			CFrame.new(0, 2.6, 0)
		)
		local leg = part(m, "Leg", Vector3.new(0.45, 5.6, 0.45), DARK)
		motor(if s < 0 then "LegL" else "LegR", r, leg, CFrame.new(s * 0.4, -0.9, 0), CFrame.new(0, 2.5, 0))
	end
	local h = humanoid(m, hip, 9)
	return { model = m, root = r, humanoid = h, eyeHeight = 4.5 }
end

-- Hunched, long-armed, low to the floor of dark rooms.
function Rigs.dweller(): Rig
	local m = Instance.new("Model")
	m.Name = "Dweller"
	local hip = 2.2
	local r = root(m, Vector3.new(2, 1.6, 2), hip)
	local color = Color3.fromRGB(28, 24, 22)
	local back = part(m, "Back", Vector3.new(2.2, 1.8, 3.2), color)
	motor("Spine", r, back, CFrame.new(0, 1, 0.2) * CFrame.Angles(math.rad(-25), 0, 0), CFrame.new())
	local head =
		part(m, "Head", Vector3.new(1.1, 1.1, 1.3), color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	motor("Neck", back, head, CFrame.new(0, 0.2, -2), CFrame.new())
	for _, s in { -1, 1 } do
		local arm = part(m, "Arm", Vector3.new(0.4, 4.2, 0.4), color)
		motor(
			if s < 0 then "ArmL" else "ArmR",
			back,
			arm,
			CFrame.new(s * 1.1, 0, -1.2),
			CFrame.new(0, 1.8, 0)
		)
		local leg = part(m, "Leg", Vector3.new(0.5, 3, 0.5), color)
		motor(if s < 0 then "LegL" else "LegR", r, leg, CFrame.new(s * 0.6, -0.6, 0.5), CFrame.new(0, 1.2, 0))
	end
	local h = humanoid(m, hip, 10)
	return { model = m, root = r, humanoid = h, eyeHeight = 2.5 }
end

-- Low and fast, close to the ground.
function Rigs.crawler(): Rig
	local m = Instance.new("Model")
	m.Name = "Crawler"
	local hip = 1
	local r = root(m, Vector3.new(2, 1, 3), hip)
	local color = Color3.fromRGB(18, 18, 18)
	local body = part(m, "Body", Vector3.new(1.8, 0.9, 3.6), color)
	motor("Spine", r, body, CFrame.new(0, 0.3, 0), CFrame.new())
	local head = part(m, "Head", Vector3.new(0.9, 0.7, 1.1), color)
	motor("Neck", body, head, CFrame.new(0, 0.1, -2.1), CFrame.new())
	for i, z in { -1.3, 1.3 } do
		for _, s in { -1, 1 } do
			local leg = part(m, "Leg", Vector3.new(0.3, 1.6, 0.3), color)
			motor(
				string.format("Leg%d%s", i, if s < 0 then "L" else "R"),
				body,
				leg,
				CFrame.new(s * 1, -0.2, z) * CFrame.Angles(0, 0, s * math.rad(35)),
				CFrame.new(0, 0.7, 0)
			)
		end
	end
	local h = humanoid(m, hip, 12)
	return { model = m, root = r, humanoid = h, eyeHeight = 1.4 }
end

-- Caramelo: the vetted rigged dog mesh (assets/StillnessAssets.rbxm, "Dog"),
-- tinted to a caramel street-dog coat and welded over the part rig. The part
-- rig stays as the invisible physics/animation skeleton, so poses applied to
-- its Root motor (sit, sleep, hide) still move the mesh. Falls back to the
-- visible part-built dog when the asset is missing.
local CARAMEL = Color3.fromRGB(255, 196, 138)

dressDog = function(m: Model, r: BasePart, body: BasePart)
	local mesh = Assets.clone("Dog")
	if not mesh then
		return
	end
	mesh.Name = "DogMesh"
	mesh:ScaleTo(mesh:GetScale() * 1.2)
	local meshPart: MeshPart? = nil
	for _, d in mesh:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if d:IsA("MeshPart") then
				meshPart = d
			end
		elseif d:IsA("SurfaceAppearance") then
			d.Color = CARAMEL
		end
	end
	if not meshPart then
		mesh:Destroy()
		return
	end
	-- Place the mesh standing on the ground under the rig, facing -Z.
	body.CFrame = r.CFrame * CFrame.new(0, 0.1, 0)
	local groundY = r.Position.Y - r.Size.Y / 2 - 1.5 -- minus the dog's HipHeight
	local cf, size = mesh:GetBoundingBox()
	mesh:PivotTo(
		mesh:GetPivot() + (Vector3.new(r.Position.X, groundY + size.Y / 2, r.Position.Z - 0.2) - cf.Position)
	)
	mesh.Parent = m
	local weld = Instance.new("Weld")
	weld.Name = "MeshWeld"
	weld.Part0 = body
	weld.Part1 = meshPart
	weld.C0 = body.CFrame:ToObjectSpace(meshPart.CFrame)
	weld.Parent = meshPart
	-- Hide the stand-in parts; keep them as the skeleton.
	for _, child in m:GetChildren() do
		if child:IsA("BasePart") and child ~= r then
			child.Transparency = 1
			child.CastShadow = false
		end
	end
	m:SetAttribute("MeshDog", true)
end

-- A golden dog: body, head with snout and ears, four legs, tail.
function Rigs.dog(): Rig
	local m = Instance.new("Model")
	m.Name = "Dog"
	local hip = 1.5
	local r = root(m, Vector3.new(1.4, 1.2, 3), hip)
	local fur = Color3.fromRGB(196, 142, 82)
	local dark = Color3.fromRGB(120, 78, 44)
	local body = part(m, "Body", Vector3.new(1.6, 1.4, 3.3), fur, Enum.Material.Fabric)
	motor("Root", r, body, CFrame.new(0, 0.1, 0), CFrame.new())
	local head = part(m, "Head", Vector3.new(1.05, 1.05, 1.2), fur, Enum.Material.Fabric)
	motor("Neck", body, head, CFrame.new(0, 0.75, -1.75), CFrame.new(0, 0, 0.35))
	local snout = part(m, "Snout", Vector3.new(0.55, 0.45, 0.7), fur, Enum.Material.Fabric)
	local ws = Instance.new("Weld")
	ws.Part0 = head
	ws.Part1 = snout
	ws.C0 = CFrame.new(0, -0.18, -0.8)
	ws.Parent = snout
	local nose = part(m, "Nose", Vector3.new(0.22, 0.16, 0.12), Color3.fromRGB(30, 24, 22))
	local wn = Instance.new("Weld")
	wn.Part0 = snout
	wn.Part1 = nose
	wn.C0 = CFrame.new(0, 0.1, -0.38)
	wn.Parent = nose
	for _, s in { -1, 1 } do
		local ear = part(m, "Ear", Vector3.new(0.18, 0.6, 0.4), dark, Enum.Material.Fabric)
		motor(
			if s < 0 then "EarL" else "EarR",
			head,
			ear,
			CFrame.new(s * 0.5, 0.25, 0.1),
			CFrame.new(0, 0.25, 0)
		)
		local eye = part(m, "Eye", Vector3.new(0.12, 0.12, 0.05), Color3.fromRGB(20, 16, 14))
		local we = Instance.new("Weld")
		we.Part0 = head
		we.Part1 = eye
		we.C0 = CFrame.new(s * 0.26, 0.18, -0.6)
		we.Parent = eye
	end
	local legs: { { name: string, x: number, z: number } } = {
		{ name = "LegFL", x = -0.5, z = -1.2 },
		{ name = "LegFR", x = 0.5, z = -1.2 },
		{ name = "LegBL", x = -0.5, z = 1.2 },
		{ name = "LegBR", x = 0.5, z = 1.2 },
	}
	for _, leg in legs do
		local l = part(m, "Leg", Vector3.new(0.38, 1.6, 0.38), fur, Enum.Material.Fabric)
		motor(leg.name, body, l, CFrame.new(leg.x, -0.5, leg.z), CFrame.new(0, 0.75, 0))
	end
	local tail = part(m, "Tail", Vector3.new(0.22, 0.22, 1.4), fur, Enum.Material.Fabric)
	motor(
		"TailJoint",
		body,
		tail,
		CFrame.new(0, 0.45, 1.6) * CFrame.Angles(math.rad(35), 0, 0),
		CFrame.new(0, 0, -0.65)
	)
	local h = humanoid(m, hip, 15)
	h.JumpPower = 40
	dressDog(m, r, body)
	return { model = m, root = r, humanoid = h, eyeHeight = 2.4 }
end

return Rigs

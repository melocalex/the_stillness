--!strict
-- Ambient wildlife: deer herds, rabbits and crows. They make the forest feel
-- alive by day and make its silence meaningful at night.
--
--   * Day: graze, hop, peck; wander within a home range.
--   * Dusk: nervous; they drift into the trees and fade out before night.
--   * Threats: a running player startles them; any creature (or the Old One)
--     sends them fleeing well before the player could see it coming. Crows
--     burst out of the trees, which players can notice from far away.
--   * They come back after a while, only by day and only when it is calm.
--
-- Server-owned so every player sees the same animals react to the same events.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local Assets = require(script.Parent.Assets)
local Builder = require(script.Parent.Builder)
local Terrain = require(script.Parent.Terrain)

local Wildlife = {}

type Kind = "Deer" | "Rabbit" | "Crow"
type State = "idle" | "move" | "flee" | "fly" | "leaving" | "gone"

type Animal = {
	kind: Kind,
	model: Model,
	home: Vector3,
	range: number,
	pos: Vector3,
	yaw: number,
	state: State,
	target: Vector3?,
	speed: number,
	wait: number,
	alpha: number, -- 1 visible, 0 gone
	fadeTo: number,
	respawnAt: number,
	baseTransparency: { [BasePart]: number },
	yawOffset: number,
	lift: number,
	foot: number, -- pivot height above the hooves or paws
	phase: number, -- gait
}

export type Threat = { position: Vector3, radius: number }

local SPECS = {
	Deer = {
		walk = 5,
		run = 26,
		startle = 28,
		creatureStartle = 110,
		range = 30,
		scale = 1.15,
		yawOffset = 0,
		lift = 0,
	},
	Rabbit = {
		walk = 4,
		run = 18,
		startle = 12,
		creatureStartle = 70,
		range = 14,
		scale = 1.6,
		yawOffset = 0,
		lift = 0,
	},
	Crow = {
		walk = 2,
		run = 38,
		startle = 18,
		creatureStartle = 130,
		range = 10,
		scale = 0.12,
		yawOffset = 0,
		lift = 0.3,
	},
}

local animals: { Animal } = {}
local folder: Folder
local threatProviders: { () -> { Threat } } = {}
local cueCallback: ((string, Vector3) -> ())? = nil
local clock = 0

local function phase(): string
	return (ReplicatedStorage:GetAttribute("Phase") :: string?) or "Day"
end

local function setAlpha(a: Animal, alpha: number)
	a.alpha = alpha
	for part, base in a.baseTransparency do
		part.Transparency = base + (1 - base) * (1 - alpha)
	end
end

local function procedural(kind: Kind): Model
	local m = Instance.new("Model")
	m.Name = kind
	local color = if kind == "Deer"
		then Color3.fromRGB(128, 92, 62)
		elseif kind == "Rabbit" then Color3.fromRGB(150, 140, 126)
		else Color3.fromRGB(20, 20, 24)
	local size = if kind == "Deer"
		then Vector3.new(1.6, 2.2, 4.2)
		elseif kind == "Rabbit" then Vector3.new(0.7, 0.8, 1.1)
		else Vector3.new(0.5, 0.5, 0.9)
	local body = Builder.part({
		name = "Body",
		size = size,
		cframe = CFrame.new(0, size.Y / 2 + (if kind == "Deer" then 2 else 0), 0),
		color = color,
		material = Enum.Material.SmoothPlastic,
		canCollide = false,
		canQuery = false,
		parent = m,
	})
	m.PrimaryPart = body
	return m
end

local function makeModel(kind: Kind): Model
	local m = Assets.clone(kind)
	if m then
		local spec = SPECS[kind]
		if spec.scale ~= 1 then
			m:ScaleTo(m:GetScale() * spec.scale)
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CastShadow = kind ~= "Crow"
			end
		end
		return m
	end
	return procedural(kind)
end

-- The real terrain surface, not the height formula: voxels round the ground
-- off higher in places, which buried legs up to the knees.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { workspace.Terrain }
groundParams.IgnoreWater = true

local function groundAt(pos: Vector3): number
	local guess = Terrain.heightAt(pos.X, pos.Z)
	local hit =
		workspace:Raycast(Vector3.new(pos.X, guess + 60, pos.Z), Vector3.new(0, -160, 0), groundParams)
	return if hit then hit.Position.Y else guess
end

-- From the pivot down to the lowest visible point, measured once from the
-- real meshes (some packs carry tiny helper parts away from the body).
local function footOffset(m: Model): number
	local pivot = m:GetPivot()
	m:PivotTo(CFrame.new(pivot.Position))
	local pivotY = pivot.Position.Y
	local lowest = math.huge
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Size.Magnitude > 0.5 and d.Transparency < 1 then
			local h = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = d.CFrame:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
						lowest = math.min(lowest, corner.Y)
					end
				end
			end
		end
	end
	return if lowest < math.huge then pivotY - lowest else 0
end

local function spawnAnimal(kind: Kind, home: Vector3)
	local m = makeModel(kind)
	m.Parent = folder
	local spec = SPECS[kind]
	local a: Animal = {
		kind = kind,
		model = m,
		home = home,
		range = spec.range,
		pos = home,
		yaw = math.random() * math.pi * 2,
		state = "idle",
		target = nil,
		speed = spec.walk,
		wait = math.random() * 4,
		alpha = 1,
		fadeTo = 1,
		respawnAt = 0,
		baseTransparency = {},
		yawOffset = spec.yawOffset,
		lift = spec.lift,
		foot = footOffset(m),
		phase = math.random() * math.pi * 2,
	}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			a.baseTransparency[d] = d.Transparency
		end
	end
	m:SetAttribute("Wildlife", kind)
	CollectionService:AddTag(m, "Wildlife")
	table.insert(animals, a)
end

local function pose(a: Animal, dt: number?)
	local ground = groundAt(a.pos)
	local y = if a.state == "fly" then a.pos.Y else ground + a.lift
	a.pos = Vector3.new(a.pos.X, y, a.pos.Z)
	-- The deer is one rigid mesh and cannot move its legs; a gait bob that
	-- follows its speed keeps it from gliding like a statue.
	local moving = a.state == "move" or a.state == "flee" or a.state == "leaving"
	a.phase += (dt or 0) * (if moving then 2 + a.speed * 0.8 else 0)
	local bob = if moving and a.state ~= "fly"
		then math.abs(math.sin(a.phase)) * math.clamp(a.speed / 12, 0.05, 0.3)
		else 0
	a.model:PivotTo(
		CFrame.new(a.pos.X, y + a.foot + bob, a.pos.Z)
			* CFrame.Angles(0, a.yaw + a.yawOffset, 0)
			* CFrame.Angles(if moving then math.sin(a.phase * 2) * 0.025 else 0, 0, 0)
	)
end

local function threats(): { Threat }
	local list: { Threat } = {}
	for _, provider in threatProviders do
		for _, t in provider() do
			table.insert(list, t)
		end
	end
	return list
end

-- Players startle animals according to how they move.
local function playerThreats(): { Threat }
	local list = {}
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local speed = root.AssemblyLinearVelocity.Magnitude
			local radius = if speed > 19 then 1.6 elseif speed > 10 then 1 elseif speed > 1 then 0.45 else 0.2
			table.insert(list, { position = root.Position, radius = radius })
		end
	end
	return list
end

local function nearestThreat(a: Animal, list: { Threat }): (Vector3?, boolean)
	local spec = SPECS[a.kind]
	for _, t in list do
		-- radius <= 2 marks a player multiplier; larger values are absolute (creatures)
		local reach = if t.radius <= 2
			then spec.startle * t.radius
			else math.max(t.radius, spec.creatureStartle)
		if (t.position - a.pos).Magnitude < reach then
			return t.position, t.radius > 2
		end
	end
	return nil, false
end

local function pickWander(a: Animal): Vector3
	for _ = 1, 8 do
		local ang = math.random() * math.pi * 2
		local r = math.random() * a.range
		local p = a.home + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
		if not Terrain.isWater(p.X, p.Z) then
			return p
		end
	end
	return a.home
end

local function moveToward(a: Animal, dt: number, target: Vector3, speed: number): boolean
	local delta = Vector3.new(target.X - a.pos.X, 0, target.Z - a.pos.Z)
	local dist = delta.Magnitude
	if dist < 0.5 then
		return true
	end
	local step = math.min(speed * dt, dist)
	a.pos += delta.Unit * step
	local desired = math.atan2(-delta.X, -delta.Z)
	local diff = (desired - a.yaw + math.pi) % (2 * math.pi) - math.pi
	a.yaw += diff * math.min(dt * 6, 1)
	return false
end

local function startFlee(a: Animal, from: Vector3)
	local away = Vector3.new(a.pos.X - from.X, 0, a.pos.Z - from.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(1, 0, 0)
	end
	a.target = a.pos + away.Unit * 90
	if a.kind == "Crow" then
		a.state = "fly"
		if cueCallback then
			cueCallback("birdsTakeOff", a.pos)
		end
	else
		a.state = "flee"
	end
	a.speed = SPECS[a.kind].run
	a.fadeTo = 0
	a.respawnAt = clock + math.random(90, 180)
end

local function step(dt: number)
	clock += dt
	local list = threats()
	local ph = phase()
	local nightish = ph == "Night" or ph == "Dusk"
	for _, a in animals do
		-- Fading
		if a.alpha ~= a.fadeTo then
			local rate = if a.fadeTo < a.alpha then 0.35 else 0.25
			local na = if a.fadeTo < a.alpha
				then math.max(a.alpha - rate * dt, a.fadeTo)
				else math.min(a.alpha + rate * dt, a.fadeTo)
			setAlpha(a, na)
			if na <= 0 and a.state ~= "gone" then
				a.state = "gone"
			end
		end

		if a.state == "gone" then
			-- Return only by day, after the cooldown, when nothing is near home.
			if not nightish and clock >= a.respawnAt then
				local danger = false
				for _, t in list do
					if t.radius > 2 and (t.position - a.home).Magnitude < 150 then
						danger = true
					end
				end
				if not danger then
					a.pos = pickWander(a)
					a.state = "idle"
					a.wait = 2
					a.fadeTo = 1
					a.speed = SPECS[a.kind].walk
					pose(a)
				end
			end
			continue
		end

		local threatPos, isCreature = nearestThreat(a, list)
		local current: State = a.state
		local fleeing = current == "flee" or current == "fly"
		if threatPos and not fleeing then
			startFlee(a, threatPos)
			if isCreature then
				a.respawnAt = clock + math.random(200, 320)
			end
		elseif nightish and not fleeing and current ~= "leaving" then
			-- Dusk: drift out toward the trees and fade.
			a.state = "leaving"
			a.target = pickWander(a) + Vector3.new(math.random(-40, 40), 0, math.random(-40, 40))
			a.fadeTo = 0
			a.respawnAt = clock + 30
		end

		if a.state == "idle" then
			a.wait -= dt
			if a.wait <= 0 then
				a.state = "move"
				a.target = pickWander(a)
				a.speed = SPECS[a.kind].walk
			end
		elseif a.state == "move" or a.state == "leaving" or a.state == "flee" then
			local target = a.target or a.home
			if moveToward(a, dt, target, a.speed) and a.state == "move" then
				a.state = "idle"
				a.wait = 2 + math.random() * 6
			end
		elseif a.state == "fly" then
			local target = a.target or a.home
			moveToward(a, dt, target, a.speed)
			a.pos = Vector3.new(a.pos.X, math.min(a.pos.Y + dt * 14, groundAt(a.pos) + 70), a.pos.Z)
		end
		pose(a, dt)
	end
end

-- Extra threat sources (creatures, the Old One). Each returns world positions
-- with an absolute startle radius in studs (> 2).
function Wildlife.addThreatProvider(fn: () -> { Threat })
	table.insert(threatProviders, fn)
end

-- Called when animals make a notable sound (crows bursting out of the trees).
function Wildlife.setCueCallback(fn: (string, Vector3) -> ())
	cueCallback = fn
end

-- Default provider: anything tagged "Creature" or the visible Old One.
local function creatureThreats(): { Threat }
	local list = {}
	for _, m in CollectionService:GetTagged("Creature") do
		if m:IsA("Model") and m.PrimaryPart then
			table.insert(list, { position = (m.PrimaryPart :: BasePart).Position, radius = 110 })
		end
	end
	for _, m in CollectionService:GetTagged("OldOne") do
		if m:IsA("Model") and m:GetAttribute("Visible") == true and m.PrimaryPart then
			table.insert(list, { position = (m.PrimaryPart :: BasePart).Position, radius = 260 })
		end
	end
	return list
end

function Wildlife.start(parent: Instance)
	folder = Builder.folder("Wildlife", parent)
	Wildlife.addThreatProvider(playerThreats)
	Wildlife.addThreatProvider(creatureThreats)
	local herds = {}
	for _, meadow in WorldConfig.Meadows do
		table.insert(herds, Vector3.new(meadow.x, 0, meadow.z))
	end
	for _, h in herds do
		for _ = 1, 3 do
			spawnAnimal("Deer", h + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)))
		end
	end
	for _, r in
		{
			Vector3.new(30, 0, 30),
			Vector3.new(-34, 0, 24),
			Vector3.new(36, 0, -30),
			Vector3.new(-60, 0, 60),
			Vector3.new(120, 0, 10),
			Vector3.new(-40, 0, -90),
		}
	do
		spawnAnimal("Rabbit", r)
	end
	for _, c in
		{
			Vector3.new(30, 0, -95),
			Vector3.new(-30, 0, -100),
			Vector3.new(150, 0, 60),
			Vector3.new(-150, 0, -40),
		}
	do
		for _ = 1, 3 do
			spawnAnimal("Crow", c + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6)))
		end
	end
	for _, a in animals do
		pose(a)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 1 / 15 then
			step(acc)
			acc = 0
		end
	end)
end

return Wildlife

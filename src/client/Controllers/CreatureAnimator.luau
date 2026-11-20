--!strict
-- Client-side creature presentation:
-- * The single-mesh Crawler gets a gait: a quick bob, a low pitch and a
--   side-to-side sway that scale with its speed.
-- * Watchers and Dwellers turn their heads, slowly and independently of the
--   body, toward this player's camera. Each player sees it look at them.
-- The bodies are animated on the server; nothing here moves a creature.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local CreatureAnimator = {}

local STARE_RANGE = 140
local TURN_RATE = 0.9 -- per second: a delayed, deliberate turn
local base: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local aim: { [Motor6D]: Vector2 } = setmetatable({}, { __mode = "k" }) :: any

local function bob(m: Model, t: number)
	local root = m.PrimaryPart
	local motor = m:FindFirstChild("MeshMotor", true)
	if root and motor and motor:IsA("Motor6D") then
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local k = math.clamp(speed / 12, 0, 1.5)
		local phase = t * (3 + speed * 0.7)
		motor.Transform = CFrame.new(0, math.abs(math.sin(phase)) * 0.35 * k, 0)
			* CFrame.Angles(math.sin(phase * 2) * 0.05 * k, 0, math.sin(phase) * 0.08 * k)
	end
end

local function stare(m: Model, cam: Vector3, dt: number)
	local head = m:FindFirstChild("Head")
	local neck = head and head:FindFirstChild("Neck")
	if not neck or not neck:IsA("Motor6D") or not neck.Part0 then
		return
	end
	local c0 = base[neck]
	if not c0 then
		c0 = neck.C0
		base[neck] = c0
	end
	local want = Vector2.zero
	local torso = neck.Part0 :: BasePart
	if (torso.Position - cam).Magnitude < STARE_RANGE and m:GetAttribute("State") ~= "RETREAT" then
		local rel = (torso.CFrame * c0):PointToObjectSpace(cam)
		local flatDist = math.max(Vector2.new(rel.X, rel.Z).Magnitude, 0.1)
		want = Vector2.new(
			math.clamp(math.atan2(-rel.X, -rel.Z), -1.3, 1.3),
			math.clamp(math.atan2(rel.Y, flatDist), -0.5, 0.5)
		)
	end
	local now = aim[neck] or Vector2.zero
	now += (want - now) * math.min(1, TURN_RATE * dt)
	aim[neck] = now
	neck.C0 = c0 * CFrame.Angles(now.Y, now.X, 0)
end

function CreatureAnimator.start()
	local t = 0
	RunService.RenderStepped:Connect(function(dt: number)
		t += dt
		local camera = workspace.CurrentCamera
		local cam = if camera then camera.CFrame.Position else nil
		for _, m in CollectionService:GetTagged("Creature") do
			if not m:IsA("Model") then
				continue
			end
			if m:GetAttribute("MeshCrawler") == true then
				bob(m, t)
			elseif cam then
				local kind = m:GetAttribute("Kind")
				if kind == "Watcher" or kind == "Dweller" then
					stare(m, cam, dt)
				end
			end
		end
	end)
end

return CreatureAnimator

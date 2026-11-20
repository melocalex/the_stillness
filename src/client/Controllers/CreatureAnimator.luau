--!strict
-- Gives the single-mesh Crawler a gait: a quick bob, a low pitch and a
-- side-to-side sway that scale with its speed. The Watcher and the Dweller
-- are R15 rigs animated on the server, so they need nothing here.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local CreatureAnimator = {}

function CreatureAnimator.start()
	local t = 0
	RunService.RenderStepped:Connect(function(dt: number)
		t += dt
		for _, m in CollectionService:GetTagged("Creature") do
			if m:GetAttribute("MeshCrawler") ~= true or not m:IsA("Model") then
				continue
			end
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
	end)
end

return CreatureAnimator

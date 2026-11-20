--!strict
-- Small town effects on the client: parts the server marks Spinning (the
-- repaired anemometer) turn locally. Visual only.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TownFx = {}

function TownFx.start()
	local spinners: { BasePart } = {}
	local function consider(inst: Instance)
		if inst:IsA("BasePart") and inst:GetAttribute("Spin") ~= nil and not table.find(spinners, inst) then
			table.insert(spinners, inst)
		end
	end
	for _, inst in CollectionService:GetTagged("TownVisual") do
		consider(inst)
	end
	CollectionService:GetInstanceAddedSignal("TownVisual"):Connect(consider)
	RunService.RenderStepped:Connect(function(dt: number)
		for _, p in spinners do
			if p.Parent and p:GetAttribute("Spinning") == true then
				local speed = (p:GetAttribute("Spin") :: number?) or 0
				p.CFrame *= CFrame.Angles(0, math.rad(speed) * dt, 0)
			end
		end
	end)
end

return TownFx

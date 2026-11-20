--!strict
-- Hand tools. The axe lives in StarterPack so every spawn gets it. Swinging
-- uses Roblox's built-in tool slash animation (the default Animate script
-- plays it when a "toolanim" StringValue appears in the tool), so it works
-- in published games without uploading animations. Hits are validated on the
-- server and applied through GatherService.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local StarterPack = game:GetService("StarterPack")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Assets = require(script.Parent.Parent.World.Assets)
local GatherService = require(script.Parent.GatherService)

local ToolService = {}

local SWING_COOLDOWN = 0.65
local REACH = 11

-- Plays the default slash animation on whoever holds this tool.
function ToolService.swing(tool: Tool)
	local v = Instance.new("StringValue")
	v.Name = "toolanim"
	v.Value = "Slash"
	v.Parent = tool
	task.delay(0.5, function()
		if v.Parent then
			v:Destroy()
		end
	end)
end

local function proceduralAxe(): Tool
	local tool = Instance.new("Tool")
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 3.6, 0.35)
	handle.Color = Color3.fromRGB(120, 84, 52)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Parent = tool
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(0.25, 0.8, 1.3)
	head.Color = Color3.fromRGB(90, 92, 96)
	head.Material = Enum.Material.Metal
	head.CanCollide = false
	head.Massless = true
	head.CFrame = handle.CFrame * CFrame.new(0, 1.5, -0.45)
	head.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = head
	tool.GripPos = Vector3.new(0, -1.1, 0)
	return tool
end

local function makeAxe(): Tool
	local tool: Tool? = nil
	local model = Assets.clone("Axe")
	if model then
		local found = model:FindFirstChildWhichIsA("Tool", true)
		if found then
			found.Parent = nil
			tool = found
		end
		model:Destroy()
	end
	local axe = tool or proceduralAxe()
	axe.Name = "Axe"
	axe.ToolTip = "Axe: click near a marked tree to chop"
	axe.CanBeDropped = false
	axe.RequiresHandle = true
	for _, d in axe:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.Massless = d.Name ~= "Handle"
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	CollectionService:AddTag(axe, "AxeTool")
	return axe
end

local function onActivated(tool: Tool)
	local character = tool.Parent
	if not character or not character:IsA("Model") then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player or not Net.allow(player, "axe", 1 / SWING_COOLDOWN) then
		return
	end
	ToolService.swing(tool)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	-- Nearest standing tree in front of the player, within reach.
	local best: Instance? = nil
	local bestDist = REACH
	for _, node in CollectionService:GetTagged("ResourceNode") do
		if node:GetAttribute("ResourceKind") == "Tree" and node:GetAttribute("Depleted") ~= true then
			local part = if node:IsA("Model")
				then node.PrimaryPart
				elseif node:IsA("BasePart") then node
				else nil
			if part then
				local offset =
					Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z)
				local dist = offset.Magnitude
				if dist < bestDist and (dist < 3 or root.CFrame.LookVector:Dot(offset.Unit) > 0.2) then
					best = node
					bestDist = dist
				end
			end
		end
	end
	if best then
		task.delay(0.25, function()
			GatherService.chop(player, best :: Instance)
		end)
	end
end

function ToolService.hasAxe(player: Player): boolean
	local character = player.Character
	return character ~= nil and character:FindFirstChild("Axe") ~= nil
end

function ToolService.start()
	local template = makeAxe()
	template.Parent = StarterPack
	local function hook(inst: Instance)
		if inst:IsA("Tool") and inst ~= template and inst.Parent ~= StarterPack then
			local tool: Tool = inst
			tool.Activated:Connect(function()
				onActivated(tool)
			end)
		end
	end
	for _, inst in CollectionService:GetTagged("AxeTool") do
		hook(inst)
	end
	CollectionService:GetInstanceAddedSignal("AxeTool"):Connect(hook)
	GatherService.setAxeCheck(function(player: Player): Tool?
		local character = player.Character
		local axe = character and character:FindFirstChild("Axe")
		return if axe and axe:IsA("Tool") then axe else nil
	end, ToolService.swing)
	-- Players already in the game get one too.
	for _, p in Players:GetPlayers() do
		local backpack = p:FindFirstChildOfClass("Backpack")
		if
			backpack
			and not backpack:FindFirstChild("Axe")
			and not (p.Character and p.Character:FindFirstChild("Axe"))
		then
			template:Clone().Parent = backpack
		end
	end
end

return ToolService

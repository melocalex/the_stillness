--!strict
-- Build mode (B): a ghost preview snapped to the grid, R rotates, 1-8 picks
-- a buildable, click places, X or B leaves. The server re-validates all of it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Parent.UI.Theme)

local BuildController = {}

local player = Players.LocalPlayer
local active = false
local index = 1
local yaw = 0
local ghost: Part? = nil
local conn: RBXScriptConnection? = nil
local gui: ScreenGui
local label: TextLabel

local function affordable(cost: { [string]: number }): boolean
	for item, n in cost do
		if (ClientState.items[item] or 0) < n then
			return false
		end
	end
	return true
end

local function costText(cost: { [string]: number }): string
	local parts = {}
	for item, n in cost do
		table.insert(
			parts,
			n .. " " .. (if ItemConfig.Items[item] then ItemConfig.Items[item].name else item)
		)
	end
	return table.concat(parts, ", ")
end

local function refreshLabel()
	local b = ItemConfig.Buildables[index]
	label.Text = string.format(
		"BUILD  ·  [%d] %s  (%s)\n1-%d choose  ·  R rotate  ·  click place  ·  X leave",
		index,
		b.name,
		costText(b.cost),
		#ItemConfig.Buildables
	)
end

local function makeGhost()
	if ghost then
		ghost:Destroy()
	end
	local b = ItemConfig.Buildables[index]
	local g = Instance.new("Part")
	g.Name = "BuildGhost"
	g.Anchored = true
	g.CanCollide = false
	g.CanQuery = false
	g.CanTouch = false
	g.Transparency = 0.5
	g.Material = Enum.Material.ForceField
	g.Size = Vector3.new(b.size[1], b.size[2], b.size[3])
	g.Parent = workspace.CurrentCamera
	ghost = g
	refreshLabel()
end

local function snapped(hit: Vector3): CFrame
	local grid = GameConfig.Build.Grid
	local b = ItemConfig.Buildables[index]
	local x = math.floor(hit.X / grid + 0.5) * grid
	local z = math.floor(hit.Z / grid + 0.5) * grid
	return CFrame.new(x, hit.Y + b.size[2] / 2, z) * CFrame.Angles(0, yaw, 0)
end

local function mouseHit(): Vector3?
	local pos = UserInputService:GetMouseLocation()
	local ray = workspace.CurrentCamera:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { workspace.CurrentCamera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(ray.Origin, ray.Direction * 80, params)
	return if result then result.Position else nil
end

function BuildController.exit()
	if not active then
		return
	end
	active = false
	ClientState.building = false
	gui.Enabled = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	ContextActionService:UnbindAction("StillBuildKeys")
	ContextActionService:UnbindAction("StillBuildPlace")
end

function BuildController.toggle()
	if active then
		BuildController.exit()
		return
	end
	if ClientState.inMenu or ClientState.observing then
		return
	end
	active = true
	ClientState.building = true
	gui.Enabled = true
	makeGhost()
	conn = RunService.RenderStepped:Connect(function()
		local g = ghost
		if not g then
			return
		end
		local hit = mouseHit()
		if hit then
			g.CFrame = snapped(hit)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local inReach = root ~= nil
				and root:IsA("BasePart")
				and (root.Position - hit).Magnitude <= GameConfig.Build.MaxDistance
			local ok = inReach and affordable(ItemConfig.Buildables[index].cost)
			g.Color = if ok then Color3.fromRGB(140, 200, 140) else Color3.fromRGB(200, 90, 80)
		end
	end)
	local numberKeys = {
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
		Enum.KeyCode.Six,
		Enum.KeyCode.Seven,
		Enum.KeyCode.Eight,
	}
	ContextActionService:BindActionAtPriority("StillBuildKeys", function(_, state, input)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		if input.KeyCode == Enum.KeyCode.R then
			yaw += math.pi / 2
		elseif input.KeyCode == Enum.KeyCode.X then
			BuildController.exit()
		else
			for i, k in numberKeys do
				if input.KeyCode == k and ItemConfig.Buildables[i] then
					index = i
					makeGhost()
				end
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.KeyCode.R, Enum.KeyCode.X, table.unpack(numberKeys))
	ContextActionService:BindActionAtPriority("StillBuildPlace", function(_, state)
		if state == Enum.UserInputState.Begin and ghost then
			Net.event("Build"):FireServer(ItemConfig.Buildables[index].id, (ghost :: Part).CFrame)
		end
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
end

function BuildController.start()
	gui = Theme.screen("BuildGui", 15)
	gui.Enabled = false
	label = Theme.create("TextLabel", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(560, 46),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.25,
		TextSize = 14,
		FontFace = Theme.FontMedium,
		TextColor3 = Theme.Colors.Text,
		Text = "",
	}, { Theme.corner(8) })
	player.CharacterAdded:Connect(BuildController.exit)
end

return BuildController

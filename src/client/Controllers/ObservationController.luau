--!strict
-- Window observation: the camera moves to the window's observe point, looks
-- out within a natural cone, and zooms with the mouse wheel (further with
-- binoculars). The character stays where it is; geometry is respected.
-- Also opens the crafting and storage panels from their prompts.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local Net = require(ReplicatedStorage.Shared.Net)
local Panels = require(script.Parent.Parent.UI.Panels)

local ObservationController = {}

local player = Players.LocalPlayer
local YAW_LIMIT = math.rad(38)
local PITCH_LIMIT = math.rad(22)

local active: Instance? = nil
local yaw, pitch = 0, 0
local fov = 70
local conn: RBXScriptConnection? = nil
local startPos: Vector3? = nil
local lastExit = 0

local function setCharacterHidden(hidden: boolean)
	local c = player.Character
	if not c then
		return
	end
	for _, d in c:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

function ObservationController.exit()
	if not active then
		return
	end
	active = nil
	ClientState.observing = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
	ContextActionService:UnbindAction("StillObserveExit")
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	setCharacterHidden(false)
	Net.event("SetObserving"):FireServer(nil)
	lastExit = os.clock()
	-- Prompts come back a moment later so the exit key doesn't re-enter.
	task.delay(0.35, function()
		if not active then
			ProximityPromptService.Enabled = true
		end
	end)
end

local function enter(window: Instance)
	local glass = window:FindFirstChild("Glass")
	local att = glass and glass:FindFirstChild("ObservePoint")
	if not att or not att:IsA("Attachment") then
		return
	end
	active = window
	ClientState.observing = true
	ProximityPromptService.Enabled = false
	yaw, pitch, fov = 0, 0, 70
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	startPos = if root and root:IsA("BasePart") then root.Position else nil
	Net.event("SetObserving"):FireServer(window)
	setCharacterHidden(true)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	ContextActionService:BindActionAtPriority("StillObserveExit", function(_, state)
		if state == Enum.UserInputState.Begin then
			ObservationController.exit()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.E, Enum.KeyCode.Escape, Enum.KeyCode.Space, Enum.KeyCode.ButtonB)
	conn = RunService.RenderStepped:Connect(function(dt: number)
		if not active or not att.Parent then
			ObservationController.exit()
			return
		end
		-- Leave if the window was shuttered or the player was moved.
		if window:GetAttribute("Shuttered") == true then
			ObservationController.exit()
			return
		end
		local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not r or not r:IsA("BasePart") or (startPos and (r.Position - startPos).Magnitude > 4) then
			ObservationController.exit()
			return
		end
		local delta = UserInputService:GetMouseDelta()
		local zoomFactor = fov / 70
		yaw = math.clamp(yaw - delta.X * 0.0035 * zoomFactor, -YAW_LIMIT, YAW_LIMIT)
		pitch = math.clamp(pitch - delta.Y * 0.0035 * zoomFactor, -PITCH_LIMIT, PITCH_LIMIT)
		-- Breathing sway, damped while holding breath.
		local sway = if player:GetAttribute("HoldingBreath") == true then 0.0004 else 0.0018
		local t = os.clock()
		local cf = att.WorldCFrame
			* CFrame.Angles(0, yaw + math.sin(t * 0.8) * sway, 0)
			* CFrame.Angles(pitch + math.sin(t * 1.3) * sway, 0, 0)
		camera.CFrame = cf
		camera.FieldOfView += (fov - camera.FieldOfView) * math.min(dt * 8, 1)
	end)
end

function ObservationController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local action = prompt:GetAttribute("ClientAction")
		if action == "Observe" then
			local glass = prompt.Parent
			local window = glass and glass.Parent
			if window and not active and os.clock() - lastExit > 0.4 then
				enter(window)
			end
		elseif action == "Craft" then
			Panels.toggle("Craft")
		elseif action == "Storage" then
			Panels.toggle("Storage")
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if active and input.UserInputType == Enum.UserInputType.MouseWheel then
			local minFov = if (ClientState.items.Binoculars or 0) > 0 then 9 else 30
			fov = math.clamp(fov - input.Position.Z * 6, minFov, 70)
		end
	end)
	player.CharacterAdded:Connect(function()
		ObservationController.exit()
	end)
end

return ObservationController

--!strict
-- Keyboard/gamepad intent. Sends requests; the server decides.
-- Shift run (hold), C crouch (toggle), H hold breath (hold), Q coat,
-- G dog, P pack, J journal, B build. Also streams the camera direction
-- (used server-side to know when a creature is being watched).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Panels = require(script.Parent.Parent.UI.Panels)

local InputController = {}

local player = Players.LocalPlayer
local sprint, crouch = false, false
local onBuildToggle: (() -> ())? = nil

function InputController.setBuildToggle(fn: () -> ())
	onBuildToggle = fn
end

local function sendStance()
	Net.event("SetStance"):FireServer(sprint, crouch)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if h then
		h.CameraOffset = if crouch then Vector3.new(0, -1.3, 0) else Vector3.zero
	end
end

local function blocked(): boolean
	return ClientState.inMenu
end

function InputController.start()
	ContextActionService:BindAction("StillSprint", function(_, state)
		if blocked() then
			return Enum.ContextActionResult.Pass
		end
		sprint = state == Enum.UserInputState.Begin
		if sprint then
			crouch = false
		end
		sendStance()
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)

	ContextActionService:BindAction("StillCrouch", function(_, state)
		if blocked() or state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		crouch = not crouch
		if crouch then
			sprint = false
		end
		sendStance()
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.C, Enum.KeyCode.ButtonB)

	ContextActionService:BindAction("StillBreath", function(_, state)
		if blocked() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			Net.event("SetBreath"):FireServer(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			Net.event("SetBreath"):FireServer(false)
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.H, Enum.KeyCode.ButtonR1)

	local function key(name: string, keys: { Enum.KeyCode }, fn: () -> ())
		ContextActionService:BindAction(name, function(_, state)
			if blocked() or state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			fn()
			return Enum.ContextActionResult.Sink
		end, false, table.unpack(keys))
	end
	key("StillCoat", { Enum.KeyCode.Q, Enum.KeyCode.ButtonY }, function()
		Net.event("ToggleCoat"):FireServer()
	end)
	key("StillDog", { Enum.KeyCode.G, Enum.KeyCode.DPadUp }, function()
		Panels.toggle("Dog")
	end)
	-- P, not Tab (player list) or I (camera zoom), which Roblox already uses.
	key("StillPack", { Enum.KeyCode.P, Enum.KeyCode.DPadLeft }, function()
		Panels.toggle("Pack")
	end)
	-- The Life Journal; observations live in its MYSTERIES tab.
	key("StillJournal", { Enum.KeyCode.J, Enum.KeyCode.DPadRight }, function()
		Panels.toggle("Life")
	end)
	key("StillBuild", { Enum.KeyCode.B, Enum.KeyCode.DPadDown }, function()
		if onBuildToggle then
			onBuildToggle()
		end
	end)

	player.CharacterAdded:Connect(function()
		sprint, crouch = false, false
		task.wait(0.5)
		sendStance()
	end)

	-- Camera direction at a low, fixed rate.
	local acc = 0
	local interval = 1 / GameConfig.Net.LookRate
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= interval and not ClientState.inMenu then
			acc = 0
			Net.unreliable("LookVector"):FireServer(workspace.CurrentCamera.CFrame.LookVector)
		end
	end)
end

return InputController

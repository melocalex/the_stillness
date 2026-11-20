--!strict
-- Loading screen, then the main menu with a slow camera drift over the cabin.
-- Play asks the server to spawn the player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.Parent.ClientState)
local Net = require(ReplicatedStorage.Shared.Net)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local Theme = require(script.Parent.Theme)

local Menu = {}

local C = Theme.Colors

function Menu.start()
	local gui = Theme.screen("MenuGui", 50)
	local bg = Theme.create("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Bg,
		BackgroundTransparency = 0,
	})
	local loading = Theme.create("TextLabel", {
		Parent = bg,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromScale(0, 0.62),
		BackgroundTransparency = 1,
		Text = "The forest is growing...",
		TextSize = 18,
		FontFace = Theme.Font,
		TextColor3 = C.Muted,
	})
	local title = Theme.create("TextLabel", {
		Parent = gui,
		Size = UDim2.new(1, 0, 0, 90),
		Position = UDim2.fromScale(0, 0.22),
		BackgroundTransparency = 1,
		Text = "THE STILLNESS",
		TextSize = 64,
		FontFace = Theme.FontSerif,
		TextColor3 = C.Text,
		TextTransparency = 0,
	})
	local subtitle = Theme.create("TextLabel", {
		Parent = gui,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0.22, 92),
		BackgroundTransparency = 1,
		Text = "Something is outside. You are home.",
		TextSize = 18,
		FontFace = Theme.Font,
		TextColor3 = C.Amber,
	})

	local playBtn = Theme.button("Play", 220)
	playBtn.AnchorPoint = Vector2.new(0.5, 0)
	playBtn.Position = UDim2.fromScale(0.5, 0.5)
	playBtn.TextSize = 20
	playBtn.Visible = false
	playBtn.Parent = gui

	local controls = Theme.create("TextLabel", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 56),
		Size = UDim2.fromOffset(560, 120),
		BackgroundTransparency = 1,
		Visible = false,
		TextWrapped = true,
		TextSize = 14,
		FontFace = Theme.Font,
		TextColor3 = C.Muted,
		Text = "WASD move  ·  Shift run  ·  C crouch  ·  H hold breath  ·  Q coat\nE / F / R / V interact  ·  T pet dog  ·  G dog  ·  I pack  ·  J journal  ·  B build\nAt a window, E looks outside. Mouse wheel zooms.",
	})

	-- Wait for the server to finish building the world.
	while workspace:GetAttribute("WorldReady") ~= true do
		task.wait(0.25)
	end
	loading.Visible = false
	TweenService:Create(bg, TweenInfo.new(2.5), { BackgroundTransparency = 1 }):Play()
	playBtn.Visible = true
	controls.Visible = true

	-- Menu camera: a slow drift past the cabin.
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local cabin = Vector3.new(WorldConfig.Cabin.x, WorldConfig.Cabin.floorY + 5, WorldConfig.Cabin.z)
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - t0) * 0.03
		local eye = cabin + Vector3.new(math.sin(t) * 55, 16 + math.sin(t * 0.7) * 3, 60 + math.cos(t) * 18)
		camera.CFrame = CFrame.lookAt(eye, cabin)
	end)

	playBtn.Activated:Connect(function()
		playBtn.Active = false
		Net.event("RequestSpawn"):FireServer()
		conn:Disconnect()
		camera.CameraType = Enum.CameraType.Custom
		ClientState.inMenu = false
		for _, inst in { title, subtitle, controls } do
			TweenService:Create(inst, TweenInfo.new(1), { TextTransparency = 1 }):Play()
		end
		playBtn.Visible = false
		task.delay(1.2, function()
			gui:Destroy()
		end)
	end)
end

return Menu

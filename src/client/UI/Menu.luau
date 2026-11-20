--!strict
-- Loading screen, then the main menu: a slow camera drift past the cabin at
-- the current hour, a dark gradient panel on the left with the title and
-- three working options: Begin, Settings (music, ambience and effects volume)
-- and Credits. Begin asks the server to spawn the player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local ClientState = require(script.Parent.Parent.ClientState)
local Net = require(ReplicatedStorage.Shared.Net)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local Theme = require(script.Parent.Theme)

local Menu = {}

local C = Theme.Colors

-- Baselines so the volume sliders scale the configured mix.
local BASE = {
	music = AudioConfig.Mix.MusicVolume,
	ambience = AudioConfig.Mix.AmbienceVolume,
	cues = AudioConfig.Mix.CueVolume,
}
local settings = ClientState.settings

local function menuButton(parent: Instance, text: string, order: number): TextButton
	local b = Theme.create("TextButton", {
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.fromOffset(280, 40),
		BackgroundTransparency = 1,
		Text = text,
		TextSize = 22,
		FontFace = Theme.FontSerif,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutoButtonColor = false,
	}) :: TextButton
	local underline = Theme.create("Frame", {
		Parent = b,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -2),
		Size = UDim2.fromOffset(0, 2),
		BackgroundColor3 = C.Amber,
		BorderSizePixel = 0,
	})
	b.MouseEnter:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.15), { TextColor3 = C.Amber }):Play()
		TweenService:Create(underline, TweenInfo.new(0.2), { Size = UDim2.fromOffset(60, 2) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.15), { TextColor3 = C.Text }):Play()
		TweenService:Create(underline, TweenInfo.new(0.2), { Size = UDim2.fromOffset(0, 2) }):Play()
	end)
	return b
end

local function slider(
	parent: Instance,
	label: string,
	order: number,
	initial: number,
	onChange: (number) -> ()
)
	local row = Theme.create("Frame", {
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.fromOffset(300, 44),
		BackgroundTransparency = 1,
	})
	local text = Theme.create("TextLabel", {
		Parent = row,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = string.upper(label),
		TextSize = 11,
		FontFace = Theme.FontBold,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local track = Theme.create("TextButton", {
		Parent = row,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, -50, 0, 6),
		BackgroundColor3 = C.PanelLight,
		AutoButtonColor = false,
		Text = "",
	}, { Theme.corner(3) })
	local fill = Theme.create("Frame", {
		Parent = track,
		Size = UDim2.fromScale(initial, 1),
		BackgroundColor3 = C.Amber,
		BorderSizePixel = 0,
	}, { Theme.corner(3) })
	local value = Theme.create("TextLabel", {
		Parent = row,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 16),
		Size = UDim2.fromOffset(44, 20),
		BackgroundTransparency = 1,
		Text = string.format("%d%%", math.floor(initial * 100 + 0.5)),
		TextSize = 13,
		FontFace = Theme.FontMedium,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local dragging = false
	local function set(x: number)
		local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		fill.Size = UDim2.fromScale(rel, 1)
		value.Text = string.format("%d%%", math.floor(rel * 100 + 0.5))
		onChange(rel)
	end
	track.MouseButton1Down:Connect(function(x: number)
		dragging = true
		set(x)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			set(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	local _ = text
end

function Menu.start()
	local gui = Theme.screen("MenuGui", 50)
	local bg = Theme.create("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Bg,
		BackgroundTransparency = 0,
		ZIndex = 10,
	})
	local loading = Theme.create("TextLabel", {
		Parent = bg,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromScale(0, 0.62),
		BackgroundTransparency = 1,
		Text = "Pinehaven is waking up...",
		TextSize = 18,
		FontFace = Theme.FontSerif,
		TextColor3 = C.Muted,
		ZIndex = 11,
	})

	-- Left gradient panel and a soft bottom vignette.
	local shade = Theme.create("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(0.62, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
	}, {
		Theme.create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(0.55, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	Theme.create("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.3),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
	}, {
		Theme.create("UIGradient", {
			Rotation = -90,
			Transparency = NumberSequence.new(0.35, 1),
		}),
	})

	local column = Theme.create("Frame", {
		Parent = gui,
		Position = UDim2.new(0, 72, 0.2, 0),
		Size = UDim2.fromOffset(420, 520),
		BackgroundTransparency = 1,
	}, {
		Theme.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local kicker = Theme.create("TextLabel", {
		Parent = column,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(420, 18),
		BackgroundTransparency = 1,
		Text = "P I N E H A V E N",
		TextSize = 13,
		FontFace = Theme.FontBold,
		TextColor3 = C.Amber,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local title = Theme.create("TextLabel", {
		Parent = column,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(520, 76),
		BackgroundTransparency = 1,
		Text = "THE STILLNESS",
		TextSize = 62,
		FontFace = Theme.FontSerif,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local tagline = Theme.create("TextLabel", {
		Parent = column,
		LayoutOrder = 3,
		Size = UDim2.fromOffset(420, 30),
		BackgroundTransparency = 1,
		Text = "Something is outside. You are home.",
		TextSize = 17,
		FontFace = Theme.Font,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Theme.create(
		"Frame",
		{ Parent = column, LayoutOrder = 4, Size = UDim2.fromOffset(10, 28), BackgroundTransparency = 1 }
	)

	local buttons = Theme.create("Frame", {
		Parent = column,
		LayoutOrder = 5,
		Size = UDim2.fromOffset(300, 150),
		BackgroundTransparency = 1,
		Visible = false,
	}, { Theme.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local beginBtn = menuButton(buttons, "Begin", 1)
	local settingsBtn = menuButton(buttons, "Settings", 2)
	local creditsBtn = menuButton(buttons, "Credits", 3)

	-- Side panels (settings, credits)
	local function sidePanel(name: string): Frame
		return Theme.create("Frame", {
			Parent = column,
			LayoutOrder = 6,
			Name = name,
			Size = UDim2.fromOffset(340, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.25,
			Visible = false,
		}, {
			Theme.corner(10),
			Theme.padding(16),
			Theme.create(
				"UIListLayout",
				{ Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }
			),
		}) :: Frame
	end
	local settingsPanel = sidePanel("Settings")
	slider(settingsPanel, "Music", 1, settings.music, function(v)
		settings.music = v
		AudioConfig.Mix.MusicVolume = BASE.music * v
	end)
	slider(settingsPanel, "Ambience and weather", 2, settings.ambience, function(v)
		settings.ambience = v
		AudioConfig.Mix.AmbienceVolume = BASE.ambience * v
	end)
	slider(settingsPanel, "Effects and creatures", 3, settings.cues, function(v)
		settings.cues = v
		AudioConfig.Mix.CueVolume = BASE.cues * v
	end)

	local creditsPanel = sidePanel("Credits")
	local credits = Theme.label(
		'Models: Letaij, V1VEX, RSG_Ukraine, fashionzoo10, SakakiAme, V_alor, Hypermatter, Roblox, THExWRATHxKING, arnavmahesh (Roblox Creator Store).\n\nSound and music: ProSoundEffects, APM Music and DistroKid catalogs on Roblox.\n\n"The Mechanism", the world, the town and all code: made for THE STILLNESS.',
		13,
		Theme.Font,
		C.Muted
	)
	credits.Parent = creditsPanel

	local function toggle(panel: Frame)
		local show = not panel.Visible
		settingsPanel.Visible = false
		creditsPanel.Visible = false
		panel.Visible = show
	end
	settingsBtn.Activated:Connect(function()
		toggle(settingsPanel)
	end)
	creditsBtn.Activated:Connect(function()
		toggle(creditsPanel)
	end)

	local controls = Theme.create("TextLabel", {
		Parent = gui,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 72, 1, -36),
		Size = UDim2.fromOffset(720, 40),
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextSize = 13,
		FontFace = Theme.Font,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "WASD move  ·  Shift run  ·  C crouch  ·  H hold breath  ·  Q coat  ·  1 axe\nE / F / R interact  ·  T pet the dog  ·  G dog  ·  P pack  ·  J journal  ·  B build",
		Visible = false,
	})

	-- Wait for the server to finish building the world.
	while workspace:GetAttribute("WorldReady") ~= true do
		task.wait(0.25)
	end
	loading.Visible = false
	TweenService:Create(bg, TweenInfo.new(2.5), { BackgroundTransparency = 1 }):Play()
	buttons.Visible = true
	controls.Visible = true

	-- Menu camera: a slow drift past the cabin, looking toward the lake.
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local cabin = Vector3.new(WorldConfig.Cabin.x, WorldConfig.Cabin.floorY + 6, WorldConfig.Cabin.z)
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - t0) * 0.025
		local eye = cabin
			+ Vector3.new(38 + math.sin(t) * 30, 14 + math.sin(t * 0.7) * 2.5, 52 + math.cos(t) * 12)
		local focus = cabin + Vector3.new(-6 + math.sin(t * 0.5) * 4, -1, -8)
		camera.CFrame = CFrame.lookAt(eye, focus)
	end)

	beginBtn.Activated:Connect(function()
		beginBtn.Active = false
		Net.event("RequestSpawn"):FireServer()
		conn:Disconnect()
		camera.CameraType = Enum.CameraType.Custom
		ClientState.inMenu = false
		for _, inst in { kicker, title, tagline, controls } do
			TweenService:Create(inst, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
		end
		buttons.Visible = false
		settingsPanel.Visible = false
		creditsPanel.Visible = false
		TweenService:Create(shade, TweenInfo.new(1), { BackgroundTransparency = 1 }):Play()
		task.delay(1.2, function()
			gui:Destroy()
		end)
	end)
end

return Menu

--!strict
-- The H-17 Chaoscope on the cabin table (Chapter 36), client side.
--
-- Presentation only. Draws what the server publishes on the model: the
-- needle (Needle, wobbling by Jitter), the oscilloscope trace (Wave), the
-- four lamps (Powered, Level, Emit) and the hum, whose pitch climbs with
-- sensitivity so a player can hear the scan risk rise. "Look closely"
-- frames the instrument and shows three plain controls. There is no HUD
-- meter: the scope is only readable by looking at it.
--
-- The Echo replays this client's own recent in-game sounds from the scope's
-- speaker, with the wrong timing. Never recordings, never a microphone.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local Dissonance = require(ReplicatedStorage.Shared.Logic.Dissonance)
local DissonanceConfig = require(ReplicatedStorage.Shared.Config.DissonanceConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Parent.UI.Theme)
local AudioController = require(script.Parent.AudioController)

local ChaoscopeController = {}

type Scope = {
	model: Model,
	case: BasePart,
	needle: Frame,
	dots: { Frame },
	lamps: { [string]: BasePart },
	hum: Sound?,
	tone: Sound?,
	shown: number,
	phase: number,
}

local player = Players.LocalPlayer
local rng = Random.new()
local scope: Scope? = nil
local viewing = false
local gui: ScreenGui? = nil
local renderConn: RBXScriptConnection? = nil

local DOTS = 48
local SWEEP = 120 -- degrees from 0 to 100 CEU
local LAMP_OFF = Color3.fromRGB(40, 40, 38)
local GREEN = Color3.fromRGB(90, 220, 120)
local AMBER = Color3.fromRGB(240, 170, 70)
local RED = Color3.fromRGB(230, 60, 50)
local PALE = Color3.fromRGB(220, 230, 235)
local TRACE = Color3.fromRGB(120, 255, 150)

local function attr(name: string, default: any): any
	local s = scope
	if not s then
		return default
	end
	local v = s.model:GetAttribute(name)
	return if v == nil then default else v
end

-- Dial ------------------------------------------------------------------------

-- A square holder centred on the pivot: rotating it swings its contents
-- around the pivot (GuiObject.Rotation turns around the centre).
local function arm(parent: Instance, pivot: UDim2, size: number, angle: number): Frame
	return Theme.create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pivot,
		Size = UDim2.fromOffset(size, size),
		Rotation = angle,
		Parent = parent,
	})
end

local function buildDial(dial: BasePart): Frame
	local sg = Instance.new("SurfaceGui")
	sg.Name = "DialGui"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 400
	sg.LightInfluence = 0.6
	sg.Parent = dial
	local pivot = UDim2.fromScale(0.5, 0.8)
	for ceu = 0, 100, 10 do
		local angle = -SWEEP / 2 + SWEEP * ceu / 100
		local holder = arm(sg, pivot, 200, angle)
		Theme.create("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = if ceu >= 80 then Color3.fromRGB(170, 40, 30) else Color3.fromRGB(40, 36, 30),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(if ceu % 20 == 0 then 3 else 2, if ceu % 20 == 0 then 16 else 10),
			Parent = holder,
		})
		if ceu % 20 == 0 then
			local rad = math.rad(angle)
			Theme.create("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.sin(rad) * 72, 0.8, -math.cos(rad) * 72),
				Size = UDim2.fromOffset(30, 14),
				Font = Enum.Font.Code,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(50, 44, 36),
				Text = tostring(ceu),
				Parent = sg,
			})
		end
	end
	Theme.create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromOffset(60, 14),
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(110, 98, 80),
		Text = "CEU",
		Parent = sg,
	})
	local holder = arm(sg, pivot, 200, -SWEEP / 2)
	Theme.create("Frame", {
		Name = "Needle",
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(150, 30, 24),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.06),
		Size = UDim2.new(0, 3, 0.44, 0),
		Parent = holder,
	})
	Theme.create("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(30, 28, 26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pivot,
		Size = UDim2.fromOffset(14, 14),
		Parent = sg,
	}, { Theme.corner(7) })
	return holder
end

local function buildScreen(screen: BasePart): { Frame }
	local sg = Instance.new("SurfaceGui")
	sg.Name = "TraceGui"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 400
	sg.LightInfluence = 0
	sg.Brightness = 1.4
	sg.Parent = screen
	Theme.create("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(40, 90, 55),
		BackgroundTransparency = 0.6,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = sg,
	})
	local dots: { Frame } = {}
	for i = 1, DOTS do
		table.insert(
			dots,
			Theme.create("Frame", {
				BorderSizePixel = 0,
				BackgroundColor3 = TRACE,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale((i - 0.5) / DOTS, 0.5),
				Size = UDim2.fromOffset(4, 4),
				Visible = false,
				Parent = sg,
			})
		)
	end
	return dots
end

local function makeLoop(id: string, parent: Instance): Sound?
	if id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.RollOffMinDistance = 2
	s.RollOffMaxDistance = 20
	local group = SoundService:FindFirstChild("Hushable")
	if group and group:IsA("SoundGroup") then
		s.SoundGroup = group
	end
	s.Parent = parent
	s:Play()
	return s
end

local function setLamp(part: BasePart?, color: Color3?)
	if not part then
		return
	end
	if color then
		part.Color = color
		part.Material = Enum.Material.Neon
	else
		part.Color = LAMP_OFF
		part.Material = Enum.Material.Glass
	end
end

local function hook(model: Model)
	if scope then
		return
	end
	local case = model:WaitForChild("Case", 10)
	local dial = model:WaitForChild("Dial", 10)
	local screen = model:WaitForChild("Screen", 10)
	if
		not (
			case
			and case:IsA("BasePart")
			and dial
			and dial:IsA("BasePart")
			and screen
			and screen:IsA("BasePart")
		)
	then
		return
	end
	local lamps: { [string]: BasePart } = {}
	for _, name in { "LampPower", "LampSignal", "LampEmit", "LampFault" } do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			lamps[name] = p
		end
	end
	local C = AudioConfig.Chaoscope
	scope = {
		model = model,
		case = case,
		needle = buildDial(dial),
		dots = buildScreen(screen),
		lamps = lamps,
		hum = makeLoop(C.hum, case),
		tone = makeLoop(C.tone, case),
		shown = 0,
		phase = 0,
	}
end

-- Per frame ---------------------------------------------------------------------

local function blink(hz: number): boolean
	return math.floor(os.clock() * hz * 2) % 2 == 0
end

local function render(dt: number)
	local s = scope
	if not s then
		return
	end
	local camera = workspace.CurrentCamera
	if (camera.CFrame.Position - s.case.Position).Magnitude > 90 then
		return
	end
	local powered = attr("Powered", false) == true
	local target = attr("Needle", 0) :: number
	local jitter = attr("Jitter", 0) :: number
	local wave = attr("Wave", 0) :: number
	local level = attr("Level", "") :: string
	local emit = attr("Emit", "off") :: string
	local sens = attr("Sensitivity", DissonanceConfig.Sensitivity.default) :: number

	-- Needle: a damped swing, trembling with measurement noise while on.
	s.shown += (target - s.shown) * math.min(dt * 2.5, 1)
	local wobble = if powered then math.noise(os.clock() * 1.7, 0.3) * jitter * 0.3 else 0
	s.needle.Rotation = -SWEEP / 2 + SWEEP * math.clamp((s.shown + wobble) / 100, 0, 1)

	-- Trace: a sine that frays as the field turns irregular.
	s.phase += dt * (2 + wave * 6)
	local amp = math.clamp(s.shown / 120, 0.06, 0.42)
	for i, dot in s.dots do
		dot.Visible = powered
		if powered then
			local clean = math.sin(s.phase + i * 0.38)
			local rough = math.noise(i * 0.31, os.clock() * 3.1) * 2 + (rng:NextNumber() - 0.5) * wave
			local y = 0.5 - amp * (clean * (1 - wave) + rough * wave)
			dot.Position = UDim2.fromScale((i - 0.5) / DOTS, math.clamp(y, 0.04, 0.96))
		end
	end

	-- Lamps.
	local L = s.lamps
	setLamp(L.LampPower, if powered then GREEN else nil)
	local signal: Color3? = nil
	if powered then
		if level == "DRIFT" then
			signal = AMBER:Lerp(LAMP_OFF, 0.55)
		elseif level == "DISTURBANCE" then
			signal = AMBER
		elseif level == "CONVERGENCE" or level == "THRESHOLD" then
			signal = if blink(if level == "THRESHOLD" then 4 else 2) then AMBER else nil
		elseif level == "UNKNOWN" then
			signal = if rng:NextNumber() < 0.5 then PALE else nil
		end
	end
	setLamp(L.LampSignal, signal)
	local emitColor: Color3? = nil
	if powered then
		if emit == "warm" then
			emitColor = RED:Lerp(LAMP_OFF, 0.6)
		elseif emit == "blink" then
			emitColor = if blink(3) then RED else nil
		elseif emit == "pulse" then
			emitColor = RED
		elseif emit == "cool" then
			emitColor = if blink(0.5) then RED:Lerp(LAMP_OFF, 0.75) else nil
		end
	end
	setLamp(L.LampEmit, emitColor)
	setLamp(L.LampFault, if powered and (level == "UNKNOWN" or jitter >= 7) then PALE else nil)

	-- Hum (silent until an id is verified): quiet, higher with sensitivity,
	-- with a tremor while the scan is charging.
	local hum = s.hum
	if hum then
		local tremor = if emit == "blink" then 0.6 + 0.4 * math.sin(os.clock() * 18) else 1
		hum.Volume = if powered then 0.12 * (0.7 + sens * 0.08) * tremor * AudioConfig.Mix.CueVolume else 0
		hum.PlaybackSpeed = 0.85 + sens * 0.05
	end
	local tone = s.tone
	if tone then
		local rising = level == "DRIFT"
			or level == "DISTURBANCE"
			or level == "CONVERGENCE"
			or level == "THRESHOLD"
		tone.Volume = if powered and rising then 0.03 + math.clamp(s.shown / 100, 0, 1) * 0.05 else 0
		tone.PlaybackSpeed = 0.8 + math.clamp(s.shown / 100, 0, 1) * 0.5
	end
end

-- Close-up view -------------------------------------------------------------------

local function send(action: string, value: any?)
	Net.event("Chaoscope"):FireServer(action, value)
end

local function close()
	if not viewing then
		return
	end
	viewing = false
	ClientState.panelOpen = false
	ContextActionService:UnbindAction("StillScopeExit")
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	local g = gui
	if g then
		g.Enabled = false
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	task.delay(0.35, function()
		if not viewing then
			ProximityPromptService.Enabled = true
		end
	end)
end

local function buildGui(): ScreenGui
	local screen = Theme.screen("ChaoscopeGui", 15)
	screen.Enabled = false
	local bar = Theme.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(0, 48),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.15,
		Parent = screen,
	}, {
		Theme.corner(10),
		Theme.stroke(),
		Theme.padding(6),
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local power = Theme.button("POWER", 92)
	power.LayoutOrder = 1
	power.Parent = bar
	power.Activated:Connect(function()
		send("power")
	end)
	local mode = Theme.button("PASSIVE", 120)
	mode.LayoutOrder = 2
	mode.Parent = bar
	mode.Activated:Connect(function()
		local order = DissonanceConfig.ModeOrder
		local cur = attr("Mode", "PASSIVE") :: string
		local nextMode = order[1]
		for i, name in order do
			if name == cur then
				nextMode = order[i % #order + 1]
			end
		end
		send("mode", nextMode)
	end)
	local minus = Theme.button("-", 36)
	minus.LayoutOrder = 3
	minus.Parent = bar
	local sensLabel = Theme.label("", 16, Theme.FontMedium, Theme.Colors.Amber)
	sensLabel.LayoutOrder = 4
	sensLabel.AutomaticSize = Enum.AutomaticSize.None
	sensLabel.Size = UDim2.fromOffset(84, 36)
	sensLabel.TextXAlignment = Enum.TextXAlignment.Center
	sensLabel.Parent = bar
	local plus = Theme.button("+", 36)
	plus.LayoutOrder = 5
	plus.Parent = bar
	minus.Activated:Connect(function()
		send("sensitivity", (attr("Sensitivity", 2) :: number) - 1)
	end)
	plus.Activated:Connect(function()
		send("sensitivity", (attr("Sensitivity", 2) :: number) + 1)
	end)
	local leave = Theme.button("×", 36)
	leave.LayoutOrder = 6
	leave.Parent = bar
	leave.Activated:Connect(close)
	-- Keep the labels in step with the instrument.
	RunService.Heartbeat:Connect(function()
		if not screen.Enabled then
			return
		end
		power.TextColor3 = if attr("Powered", false) == true then GREEN else Theme.Colors.Muted
		mode.Text = attr("Mode", "PASSIVE") :: string
		local sens = attr("Sensitivity", 2) :: number
		local pips = ""
		for i = DissonanceConfig.Sensitivity.min, DissonanceConfig.Sensitivity.max do
			pips ..= if i <= sens then "●" else "○"
		end
		sensLabel.Text = pips
	end)
	return screen
end

local function open()
	local s = scope
	if viewing or not s or ClientState.observing then
		return
	end
	viewing = true
	ClientState.panelOpen = true
	ProximityPromptService.Enabled = false
	local g = gui or buildGui()
	gui = g
	g.Enabled = true
	UserInputService.MouseIconEnabled = true
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local case = s.case
	local eye = case.Position + case.CFrame.LookVector * 2.4 + Vector3.new(0, 0.55, 0)
	local goal = CFrame.lookAt(eye, case.Position)
	local start = camera.CFrame
	local t = 0
	renderConn = RunService.RenderStepped:Connect(function(dt: number)
		t = math.min(t + dt / 0.6, 1)
		local k = 1 - (1 - t) ^ 3
		camera.CFrame = start:Lerp(goal, k)
		camera.FieldOfView = 70 + (45 - 70) * k
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or (root.Position - case.Position).Magnitude > 12 then
			close()
		end
	end)
	ContextActionService:BindActionAtPriority(
		"StillScopeExit",
		function(_, state)
			if state == Enum.UserInputState.Begin then
				close()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		3000,
		Enum.KeyCode.F,
		Enum.KeyCode.E,
		Enum.KeyCode.Escape,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonB
	)
end

-- The Echo ------------------------------------------------------------------------

local function playEcho(name: string, position: Vector3, speed: number)
	local id = AudioConfig.Cues[name]
	if not id or id == "" then
		return
	end
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.35 * AudioConfig.Mix.CueVolume
	s.PlaybackSpeed = speed
	s.RollOffMaxDistance = 40
	-- A small, tired speaker.
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain = -6
	eq.MidGain = 2
	eq.HighGain = -16
	eq.Parent = s
	local dist = Instance.new("DistortionSoundEffect")
	dist.Level = 0.3
	dist.Parent = s
	s.Parent = holder
	s:Play()
	s.Ended:Once(function()
		holder:Destroy()
	end)
end

local function echo(position: Vector3, seed: number)
	local times: { number } = {}
	local names: { string } = {}
	for _, c in AudioController.recentCues() do
		if DissonanceConfig.EchoCues[c.name] and os.clock() - c.at < 240 then
			table.insert(times, c.at)
			table.insert(names, c.name)
		end
	end
	for _, step in Dissonance.echoPlan(times, seed, 3) do
		task.delay(step.delay, playEcho, names[step.index], position, step.speed)
	end
end

function ChaoscopeController.start()
	for _, m in CollectionService:GetTagged("Chaoscope") do
		if m:IsA("Model") then
			task.spawn(hook, m)
		end
	end
	CollectionService:GetInstanceAddedSignal("Chaoscope"):Connect(function(m)
		if m:IsA("Model") then
			hook(m)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("ClientAction") == "Chaoscope" then
			open()
		end
	end)
	Net.event("Dissonance").OnClientEvent:Connect(function(kind: any, position: any, seed: any)
		if kind == "echo" and typeof(position) == "Vector3" and type(seed) == "number" then
			echo(position, seed)
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		local ok, err = pcall(render :: any, dt)
		if not ok then
			warn("[Chaoscope] " .. tostring(err))
		end
	end)
end

return ChaoscopeController

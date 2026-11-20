--!strict
-- The restrained HUD: clock and day, the current objective, a few quiet
-- status lines that fade when nothing changes, toasts, the note reader, the
-- radio subtitle, the capture fade and the end card.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.Parent.ClientState)
local Journal = require(ReplicatedStorage.Shared.Logic.Journal)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Theme)

local HUD = {}

local C = Theme.Colors
local player = Players.LocalPlayer

local PHASE_TEXT: { [string]: string } = { Day = "Day", Dusk = "Dusk", Night = "Night", Dawn = "Dawn" }

function HUD.start()
	local gui = Theme.screen("HudGui", 10)

	-- Clock (top-left)
	local clock = Theme.create("TextLabel", {
		Parent = gui,
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.fromOffset(320, 26),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 18,
		FontFace = Theme.FontSerif,
		TextColor3 = C.Text,
		Text = "",
	})
	local nightLine = Theme.create("TextLabel", {
		Parent = gui,
		Position = UDim2.fromOffset(20, 42),
		Size = UDim2.fromOffset(420, 20),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 13,
		FontFace = Theme.Font,
		TextColor3 = C.Muted,
		Text = "",
	})

	-- Objective (top-right)
	local objective = Theme.create("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 16),
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.35,
		Visible = false,
	}, { Theme.corner(8), Theme.padding(10), Theme.create("UIListLayout", { Padding = UDim.new(0, 4) }) })
	local objTitle = Theme.label("", 15, Theme.FontMedium, C.Amber)
	objTitle.Parent = objective
	local objHint = Theme.label("", 13, Theme.Font, C.Muted)
	objHint.Parent = objective

	-- Status (bottom-left): fades out when unchanged.
	local status = Theme.create("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -20),
		Size = UDim2.fromOffset(260, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Theme.create(
			"UIListLayout",
			{ Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Bottom }
		),
	})
	local function bar(name: string, color: Color3): (Frame, Frame, TextLabel)
		local row = Theme.create(
			"Frame",
			{ Name = name, Parent = status, Size = UDim2.fromOffset(260, 18), BackgroundTransparency = 1 }
		)
		local lbl = Theme.create("TextLabel", {
			Parent = row,
			Size = UDim2.fromOffset(90, 18),
			BackgroundTransparency = 1,
			Text = name,
			TextSize = 13,
			FontFace = Theme.Font,
			TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local track = Theme.create("Frame", {
			Parent = row,
			Position = UDim2.fromOffset(92, 7),
			Size = UDim2.fromOffset(160, 4),
			BackgroundColor3 = C.PanelLight,
			BorderSizePixel = 0,
		}, { Theme.corner(2) })
		local fill = Theme.create("Frame", {
			Parent = track,
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, { Theme.corner(2) })
		return row, fill, lbl
	end
	local comfortRow, comfortFill, comfortLbl = bar("Comfort", C.Amber)
	local exposureRow, exposureFill = bar("Exposure", C.Cold)
	local staminaRow, staminaFill = bar("Stamina", C.Good)
	local breathRow, breathFill, breathLbl = bar("Breath", C.Text)
	local coatLine = Theme.create("TextLabel", {
		Parent = status,
		Size = UDim2.fromOffset(260, 18),
		BackgroundTransparency = 1,
		TextSize = 13,
		FontFace = Theme.Font,
		TextColor3 = C.Amber,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})

	-- Toasts (bottom-center)
	local toasts = Theme.create("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90),
		Size = UDim2.fromOffset(520, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Theme.create("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	})
	local KIND_COLOR: { [string]: Color3 } =
		{ good = C.Good, warning = C.Amber, danger = C.Danger, info = C.Text }
	local function toast(text: string, kind: string?)
		local t = Theme.create("TextLabel", {
			Parent = toasts,
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.25,
			Text = "  " .. text .. "  ",
			TextSize = 15,
			FontFace = Theme.FontMedium,
			TextColor3 = KIND_COLOR[kind or "info"] or C.Text,
		}, { Theme.corner(6) })
		task.delay(5, function()
			TweenService:Create(t, TweenInfo.new(1), { TextTransparency = 1, BackgroundTransparency = 1 })
				:Play()
			task.wait(1)
			t:Destroy()
		end)
	end
	HUD.toast = toast

	-- Radio subtitle
	local radio = Theme.create("TextLabel", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(640, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextSize = 16,
		FontFace = Theme.FontNote,
		TextColor3 = Color3.fromRGB(200, 220, 200),
		TextStrokeTransparency = 0.5,
		Text = "",
	})

	-- Note reader
	local note = Theme.create("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(226, 214, 190),
		Visible = false,
		ZIndex = 20,
	}, { Theme.corner(4), Theme.padding(24), Theme.create("UIListLayout", { Padding = UDim.new(0, 12) }) })
	local noteTitle = Theme.label("", 22, Theme.FontSerif, Color3.fromRGB(60, 40, 30))
	noteTitle.Parent = note
	local noteBody = Theme.label("", 17, Theme.FontNote, Color3.fromRGB(50, 40, 34))
	noteBody.Parent = note
	local noteClose = Theme.button("Close", 120)
	noteClose.Parent = note
	noteClose.Activated:Connect(function()
		note.Visible = false
	end)

	-- Full-screen fade (capture) and end card
	local fade = Theme.create("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 30,
	})
	local fadeText = Theme.create("TextLabel", {
		Parent = fade,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextTransparency = 1,
		TextSize = 22,
		FontFace = Theme.FontSerif,
		TextColor3 = C.Text,
		TextWrapped = true,
		Text = "",
		ZIndex = 31,
	})

	local lastStatusChange = os.clock()
	local lastValues = ""

	RunService.RenderStepped:Connect(function()
		local day = (ReplicatedStorage:GetAttribute("Day") :: number?) or 1
		local phase = (ReplicatedStorage:GetAttribute("Phase") :: string?) or "Day"
		local clockTime = (ReplicatedStorage:GetAttribute("ClockTime") :: number?) or 12
		clock.Text = string.format(
			"Day %d  ·  %s  ·  %s",
			day,
			PHASE_TEXT[phase] or phase,
			Journal.formatClock(clockTime)
		)
		local nightType = ReplicatedStorage:GetAttribute("NightType")
		local weather = (ReplicatedStorage:GetAttribute("Weather") :: string?) or "Clear"
		local parts = {}
		if weather ~= "Clear" then
			table.insert(parts, string.lower(weather))
		end
		if
			(phase == "Dusk" or phase == "Night")
			and type(nightType) == "string"
			and nightType ~= "Day"
			and nightType ~= "Peaceful"
		then
			table.insert(parts, string.lower(nightType) .. " night")
		end
		nightLine.Text = table.concat(parts, "  ·  ")

		local comfort = (player:GetAttribute("Comfort") :: number?) or 0
		local exposure = (player:GetAttribute("Exposure") :: number?) or 0
		local stamina = (player:GetAttribute("Stamina") :: number?) or 100
		local breath = (player:GetAttribute("Breath") :: number?) or 1
		local holding = player:GetAttribute("HoldingBreath") == true
		local straining = player:GetAttribute("Straining") == true
		comfortFill.Size = UDim2.fromScale(comfort / 100, 1)
		exposureFill.Size = UDim2.fromScale(exposure / 100, 1)
		staminaFill.Size = UDim2.fromScale(stamina / 100, 1)
		breathFill.Size = UDim2.fromScale(breath, 1)
		breathFill.BackgroundColor3 = if straining then C.Danger else C.Text
		breathLbl.Text = if holding then "Holding breath" else "Breath"
		local sheltered = player:GetAttribute("Sheltered") == true
		comfortLbl.Text = if sheltered and player:GetAttribute("ShelterSecure") == true
			then "Comfort · home"
			else "Comfort"
		coatLine.Text = if player:GetAttribute("Coat") == true then "Wearing the coat" else ""
		staminaRow.Visible = stamina < 99
		breathRow.Visible = holding or breath < 0.99
		local key = string.format("%d|%d|%s", comfort // 5, exposure // 10, tostring(sheltered))
		if key ~= lastValues then
			lastValues = key
			lastStatusChange = os.clock()
		end
		local idle = os.clock() - lastStatusChange
		local alpha = if idle > 8 then math.min((idle - 8) / 2, 0.85) else 0
		for _, row in { comfortRow, exposureRow } do
			for _, d in row:GetDescendants() do
				if d:IsA("TextLabel") then
					d.TextTransparency = alpha
				elseif d:IsA("Frame") then
					d.BackgroundTransparency = alpha
				end
			end
		end
		status.Visible = not ClientState.inMenu
		objective.Visible = not ClientState.inMenu and objTitle.Text ~= ""
		clock.Visible = not ClientState.inMenu
	end)

	Net.event("Notify").OnClientEvent:Connect(function(text: any, kind: any)
		if type(text) == "string" then
			toast(text, if type(kind) == "string" then kind else nil)
		end
	end)
	Net.event("Story").OnClientEvent:Connect(function(label: any, hint: any, completed: any)
		objTitle.Text = if type(label) == "string" then label else ""
		objHint.Text = if type(hint) == "string" then hint else ""
		objHint.Visible = objHint.Text ~= ""
		if type(completed) == "string" then
			toast("Done: " .. completed, "good")
			ClientState.lastDiscovery = os.clock()
		end
	end)
	Net.event("Note").OnClientEvent:Connect(function(title: any, body: any)
		if type(title) == "string" and type(body) == "string" then
			noteTitle.Text = title
			noteBody.Text = body
			note.Visible = true
			ClientState.lastDiscovery = os.clock()
		end
	end)
	Net.event("Radio").OnClientEvent:Connect(function(text: any)
		if type(text) ~= "string" then
			return
		end
		radio.Text = text
		radio.TextTransparency = 0
		task.delay(9, function()
			if radio.Text == text then
				TweenService:Create(radio, TweenInfo.new(1.5), { TextTransparency = 1 }):Play()
			end
		end)
	end)
	Net.event("Journal").OnClientEvent:Connect(function(entry: any)
		if type(entry) == "table" and type(entry.title) == "string" then
			toast("Journal: " .. entry.title, "warning")
		end
	end)
	Net.event("Captured").OnClientEvent:Connect(function(text: any)
		fadeText.Text = if type(text) == "string" then text else ""
		TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
		TweenService:Create(fadeText, TweenInfo.new(1.2), { TextTransparency = 0 }):Play()
		task.delay(4.5, function()
			TweenService:Create(fade, TweenInfo.new(2), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(fadeText, TweenInfo.new(1), { TextTransparency = 1 }):Play()
		end)
	end)
	Net.event("EndCard").OnClientEvent:Connect(function(text: any)
		fadeText.Text = if type(text) == "string" then text else ""
		TweenService:Create(fade, TweenInfo.new(2), { BackgroundTransparency = 0.15 }):Play()
		TweenService:Create(fadeText, TweenInfo.new(2), { TextTransparency = 0 }):Play()
		task.delay(10, function()
			TweenService:Create(fade, TweenInfo.new(3), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(fadeText, TweenInfo.new(3), { TextTransparency = 1 }):Play()
		end)
	end)
end

HUD.toast = function(_text: string, _kind: string?) end

return HUD

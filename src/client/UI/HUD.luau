--!strict
-- The restrained HUD.
--   top center   time pill (day, clock, phase, weather) and toasts under it
--   top right    objective card (slides in on change, shows completions)
--   bottom left  vitals: comfort, exposure, and stamina/breath only when used;
--                chips for "home, secure" and "coat on"
--   lower middle radio transcript card with the speaker's name
-- Everything sits below Roblox's top bar and away from interaction prompts.
-- Also: note reader, capture fade and end card.

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
local TOP = 58 -- clear of Roblox's top bar

local WEATHER_TEXT: { [string]: string } = {
	Clear = "Clear",
	Fog = "Fog",
	Rain = "Rain",
	Storm = "Storm",
}

local function chip(parent: Instance, text: string, color: Color3): TextLabel
	return Theme.create("TextLabel", {
		Parent = parent,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.82,
		Text = "  " .. text .. "  ",
		TextSize = 11,
		FontFace = Theme.FontBold,
		TextColor3 = color,
		Visible = false,
	}, { Theme.corner(10) }) :: TextLabel
end

local function twelveHour(clock: number): string
	local h = math.floor(clock) % 24
	local m = math.floor((clock - math.floor(clock)) * 60)
	local suffix = if h < 12 then "AM" else "PM"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, m, suffix)
end

function HUD.start()
	local gui = Theme.screen("HudGui", 10)

	-- Time pill (top center)
	local pill = Theme.create("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP - 44),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.3,
	}, {
		Theme.corner(17),
		Theme.stroke(C.Line, 1, 0.5),
		Theme.create("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	})
	local dayLabel = Theme.create("TextLabel", {
		Parent = pill,
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		BackgroundTransparency = 1,
		TextSize = 12,
		FontFace = Theme.FontBold,
		TextColor3 = C.Amber,
		Text = "DAY 1",
	})
	local timeLabel = Theme.create("TextLabel", {
		Parent = pill,
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		BackgroundTransparency = 1,
		TextSize = 16,
		FontFace = Theme.FontSerif,
		TextColor3 = C.Text,
		Text = "",
	})
	local weatherLabel = Theme.create("TextLabel", {
		Parent = pill,
		LayoutOrder = 3,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		BackgroundTransparency = 1,
		TextSize = 12,
		FontFace = Theme.FontMedium,
		TextColor3 = C.Muted,
		Text = "",
	})

	-- Toasts (under the pill, stacking down)
	local toasts = Theme.create("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP + 2),
		Size = UDim2.fromOffset(560, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Theme.create("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local KIND_COLOR: { [string]: Color3 } =
		{ good = C.Good, warning = C.Amber, danger = C.Danger, info = C.Text, pickup = C.Amber }
	local toastCount = 0
	local function toast(text: string, kind: string?)
		toastCount += 1
		local color = KIND_COLOR[kind or "info"] or C.Text
		local t = Theme.create("TextLabel", {
			Parent = toasts,
			LayoutOrder = toastCount,
			Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 1,
			Text = "   " .. text .. "   ",
			TextSize = 14,
			FontFace = Theme.FontMedium,
			TextColor3 = color,
			TextTransparency = 1,
		}, { Theme.corner(14), Theme.stroke(color, 1, 1) })
		local stroke = t:FindFirstChildOfClass("UIStroke")
		TweenService:Create(t, TweenInfo.new(0.25), { TextTransparency = 0, BackgroundTransparency = 0.25 })
			:Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 0.7 }):Play()
		end
		-- Keep at most four on screen.
		local visible = {}
		for _, child in toasts:GetChildren() do
			if child:IsA("TextLabel") then
				table.insert(visible, child)
			end
		end
		if #visible > 4 then
			table.sort(visible, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			visible[1]:Destroy()
		end
		task.delay(4.5, function()
			if t.Parent then
				TweenService
					:Create(t, TweenInfo.new(0.8), { TextTransparency = 1, BackgroundTransparency = 1 })
					:Play()
				if stroke then
					TweenService:Create(stroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()
				end
				task.wait(0.85)
				t:Destroy()
			end
		end)
	end
	HUD.toast = toast

	-- Objective card (top right)
	local objective = Theme.create("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, TOP + 40),
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.28,
		Visible = false,
	}, {
		Theme.corner(10),
		Theme.stroke(C.Line, 1, 0.55),
		Theme.create("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 14),
		}),
		Theme.create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local objKicker = Theme.label("OBJECTIVE", 10, Theme.FontBold, C.Amber)
	objKicker.LayoutOrder = 1
	objKicker.Parent = objective
	local objTitle = Theme.label("", 16, Theme.FontSerif, C.Text)
	objTitle.LayoutOrder = 2
	objTitle.Parent = objective
	local objHint = Theme.label("", 12, Theme.Font, C.Muted)
	objHint.LayoutOrder = 3
	objHint.Parent = objective

	-- Vitals (bottom left)
	local vitals = Theme.create("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -18),
		Size = UDim2.fromOffset(230, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.4,
	}, {
		Theme.corner(10),
		Theme.padding(10),
		Theme.create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	})
	local chips = Theme.create("Frame", {
		Parent = vitals,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
		}),
	})
	local homeChip = chip(chips, "HOME · SECURE", C.Good)
	local coatChip = chip(chips, "COAT ON", C.Amber)
	local nightChip = chip(chips, "", C.Danger)

	local function meter(order: number, name: string, color: Color3): (Frame, Frame, TextLabel)
		local row = Theme.create("Frame", {
			Parent = vitals,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
		})
		local lbl = Theme.create("TextLabel", {
			Parent = row,
			Size = UDim2.new(1, 0, 0, 12),
			BackgroundTransparency = 1,
			Text = string.upper(name),
			TextSize = 10,
			FontFace = Theme.FontBold,
			TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local track = Theme.create("Frame", {
			Parent = row,
			Position = UDim2.fromOffset(0, 15),
			Size = UDim2.new(1, 0, 0, 5),
			BackgroundColor3 = C.PanelLight,
			BorderSizePixel = 0,
		}, { Theme.corner(3) })
		local fill = Theme.create("Frame", {
			Parent = track,
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, {
			Theme.corner(3),
			Theme.create("UIGradient", {
				Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.25), color),
			}),
		})
		return row, fill, lbl
	end
	local _comfortRow, comfortFill, comfortLbl = meter(2, "Comfort", C.Amber)
	local _exposureRow, exposureFill, exposureLbl = meter(3, "Exposure", C.Cold)
	local staminaRow, staminaFill = meter(4, "Stamina", C.Good)
	local breathRow, breathFill, breathLbl = meter(5, "Breath", C.Text)

	-- Key hints (bottom right), fade after a while
	local hints = Theme.create("TextLabel", {
		Parent = gui,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.fromOffset(420, 18),
		BackgroundTransparency = 1,
		Text = "1 Axe   ·   C Crouch   ·   H Hold breath   ·   Q Coat   ·   G Dog   ·   P Pack   ·   J Journal",
		TextSize = 12,
		FontFace = Theme.FontMedium,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTransparency = 0.2,
	})

	-- Radio transcript (lower middle, above prompts)
	local radio = Theme.create("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -170),
		Size = UDim2.fromOffset(560, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(14, 18, 16),
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		Theme.corner(10),
		Theme.padding(12),
		Theme.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local radioWho = Theme.label("", 11, Theme.FontBold, Color3.fromRGB(150, 210, 160))
	radioWho.LayoutOrder = 1
	radioWho.Parent = radio
	local radioText = Theme.label("", 16, Theme.FontNote, Color3.fromRGB(214, 232, 214))
	radioText.LayoutOrder = 2
	radioText.Parent = radio

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

	local spawnedAt = os.clock()
	local lastStatusChange = os.clock()
	local lastValues = ""

	RunService.RenderStepped:Connect(function()
		local inMenu = ClientState.inMenu
		pill.Visible = not inMenu
		vitals.Visible = not inMenu
		hints.Visible = not inMenu
		objective.Visible = not inMenu and objTitle.Text ~= ""
		if inMenu then
			spawnedAt = os.clock()
			return
		end
		local day = (ReplicatedStorage:GetAttribute("Day") :: number?) or 1
		local phase = (ReplicatedStorage:GetAttribute("Phase") :: string?) or "Day"
		local clockTime = (ReplicatedStorage:GetAttribute("ClockTime") :: number?) or 12
		dayLabel.Text = "DAY " .. tostring(day)
		timeLabel.Text = twelveHour(clockTime)
		local weather = (ReplicatedStorage:GetAttribute("Weather") :: string?) or "Clear"
		local rain = (ReplicatedStorage:GetAttribute("RainIntensity") :: number?) or 0
		local weatherWord = WEATHER_TEXT[weather] or weather
		if weather == "Rain" and rain < 1.6 then
			weatherWord = "Light rain"
		end
		weatherLabel.Text = string.upper(phase) .. "  ·  " .. string.upper(weatherWord)
		weatherLabel.TextColor3 = if phase == "Night"
			then C.Cold
			elseif phase == "Dusk" then C.Amber
			else C.Muted

		local nightType = ReplicatedStorage:GetAttribute("NightType")
		local dangerous = (phase == "Dusk" or phase == "Night")
			and (nightType == "Bad" or nightType == "Black" or nightType == "Uneasy")
		nightChip.Visible = dangerous
		if dangerous and type(nightType) == "string" then
			nightChip.Text = "  " .. string.upper(nightType) .. " NIGHT  "
			nightChip.TextColor3 = if nightType == "Uneasy" then C.Amber else C.Danger
			nightChip.BackgroundColor3 = nightChip.TextColor3
		end

		local comfort = (player:GetAttribute("Comfort") :: number?) or 0
		local exposure = (player:GetAttribute("Exposure") :: number?) or 0
		local stamina = (player:GetAttribute("Stamina") :: number?) or 100
		local breath = (player:GetAttribute("Breath") :: number?) or 1
		local holding = player:GetAttribute("HoldingBreath") == true
		local straining = player:GetAttribute("Straining") == true
		local sheltered = player:GetAttribute("Sheltered") == true
		local secure = sheltered and player:GetAttribute("ShelterSecure") == true
		comfortFill.Size = UDim2.fromScale(math.clamp(comfort / 100, 0, 1), 1)
		exposureFill.Size = UDim2.fromScale(math.clamp(exposure / 100, 0, 1), 1)
		staminaFill.Size = UDim2.fromScale(math.clamp(stamina / 100, 0, 1), 1)
		breathFill.Size = UDim2.fromScale(math.clamp(breath, 0, 1), 1)
		breathFill.BackgroundColor3 = if straining then C.Danger else C.Text
		breathLbl.Text = if holding then "HOLDING BREATH" else "BREATH"
		comfortLbl.Text = if comfort >= 80
			then "COMFORT · COZY"
			elseif comfort < 25 then "COMFORT · UNEASY"
			else "COMFORT"
		exposureLbl.Text = if exposure >= 70
			then "EXPOSURE · SEEN EASILY"
			elseif exposure <= 20 then "EXPOSURE · HIDDEN"
			else "EXPOSURE"
		homeChip.Visible = secure
		coatChip.Visible = player:GetAttribute("Coat") == true
		chips.Visible = homeChip.Visible or coatChip.Visible or nightChip.Visible
		staminaRow.Visible = stamina < 99
		breathRow.Visible = holding or breath < 0.99

		-- Quiet when nothing changes.
		local key =
			string.format("%d|%d|%s|%s", comfort // 5, exposure // 10, tostring(secure), tostring(holding))
		if key ~= lastValues then
			lastValues = key
			lastStatusChange = os.clock()
		end
		local idle = os.clock() - lastStatusChange
		vitals.BackgroundTransparency = if idle > 10 then math.min(0.4 + (idle - 10) * 0.1, 0.9) else 0.4
		local since = os.clock() - spawnedAt
		hints.TextTransparency = if since > 25 then math.min(0.2 + (since - 25) * 0.1, 1) else 0.2
	end)

	Net.event("Notify").OnClientEvent:Connect(function(text: any, kind: any)
		if type(text) == "string" then
			toast(text, if type(kind) == "string" then kind else nil)
		end
	end)
	local lastObjective = ""
	Net.event("Story").OnClientEvent:Connect(function(label: any, hint: any, completed: any)
		local newTitle = if type(label) == "string" then label else ""
		objTitle.Text = newTitle
		objHint.Text = if type(hint) == "string" then hint else ""
		objHint.Visible = objHint.Text ~= ""
		if newTitle ~= lastObjective and newTitle ~= "" then
			lastObjective = newTitle
			-- Slide in from the right.
			objective.Position = UDim2.new(1, 340, 0, TOP + 40)
			TweenService:Create(
				objective,
				TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ Position = UDim2.new(1, -18, 0, TOP + 40) }
			):Play()
		end
		if type(completed) == "string" then
			toast("✓  " .. completed, "good")
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
	local radioSerial = 0
	Net.event("Radio").OnClientEvent:Connect(function(text: any)
		if type(text) ~= "string" then
			return
		end
		radioSerial += 1
		local serial = radioSerial
		-- "Maya: Morning..." shows the speaker separately.
		local who, said = string.match(text, "^([%w%s'%.]+):%s*(.+)$")
		radioWho.Text = "RADIO" .. (if who then "  ·  " .. string.upper(who) else "")
		radioText.Text = if said then said else text
		radio.Visible = true
		radio.BackgroundTransparency = 0.2
		radioWho.TextTransparency = 0
		radioText.TextTransparency = 0
		task.delay(math.clamp(#text / 14, 5, 12), function()
			if radioSerial == serial then
				TweenService:Create(radio, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
				TweenService:Create(radioWho, TweenInfo.new(1.2), { TextTransparency = 1 }):Play()
				TweenService:Create(radioText, TweenInfo.new(1.2), { TextTransparency = 1 }):Play()
			end
		end)
	end)
	Net.event("Journal").OnClientEvent:Connect(function(entry: any)
		if type(entry) == "table" and type(entry.title) == "string" then
			toast("Journal  ·  " .. entry.title, "warning")
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
	local _ = Journal
end

HUD.toast = function(_text: string, _kind: string?) end

return HUD

--!strict
-- The Life Journal (J): HOME, TOWN, PEOPLE and MYSTERIES tabs built by the
-- server from saved progress (Logic/LifeJournal). Also the errand card in
-- the top left, a marker over the current objective, and the shop counter
-- panel. Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)
local Net = require(ReplicatedStorage.Shared.Net)
local Panels = require(script.Parent.Panels)
local Theme = require(script.Parent.Theme)

local LifeJournal = {}

local C = Theme.Colors
local TABS = { "HOME", "TOWN", "PEOPLE", "MYSTERIES" }
local TONE: { [string]: Color3 } = { good = C.Good, warn = C.Amber, muted = C.Muted }

local view: any = nil
local observations: { any } = {}
local currentTab = "HOME"
local panel: Frame
local body: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}
local shop: Frame
local shopBody: ScrollingFrame
local shopState: { vendor: string, name: string, offers: { any }, credits: number }? = nil

local function clear(container: Instance)
	for _, c in container:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local function text(v: any): string
	return if type(v) == "string" then v elseif type(v) == "number" then tostring(v) else ""
end

local function row(parent: Instance, r: any, order: number)
	local f = Theme.create("Frame", {
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.4,
	}, {
		Theme.corner(6),
		Theme.padding(8),
		Theme.create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local top = Theme.create("Frame", {
		Parent = f,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
	})
	local tone = TONE[text(r.tone)]
	Theme.create("TextLabel", {
		Parent = top,
		Size = UDim2.new(1, -120, 1, 0),
		BackgroundTransparency = 1,
		Text = text(r.title),
		TextSize = 15,
		FontFace = Theme.FontMedium,
		TextColor3 = tone or C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if r.right then
		Theme.create("TextLabel", {
			Parent = top,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 116, 1, 0),
			BackgroundTransparency = 1,
			Text = text(r.right),
			TextSize = 12,
			FontFace = Theme.FontBold,
			TextColor3 = tone or C.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
	if r.detail and r.detail ~= "" then
		local d = Theme.label(text(r.detail), 12, Theme.Font, C.Muted)
		d.LayoutOrder = 2
		d.Parent = f
	end
	if type(r.bar) == "number" then
		local track = Theme.create("Frame", {
			Parent = f,
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 4),
			BackgroundColor3 = C.Panel,
			BorderSizePixel = 0,
		}, { Theme.corner(2) })
		Theme.create("Frame", {
			Parent = track,
			Size = UDim2.fromScale(math.clamp(r.bar, 0, 1), 1),
			BackgroundColor3 = tone or C.Amber,
			BorderSizePixel = 0,
		}, { Theme.corner(2) })
	end
end

local function render()
	clear(body)
	for name, b in tabButtons do
		b.BackgroundColor3 = if name == currentTab then C.AmberDim else C.PanelLight
	end
	if type(view) ~= "table" or type(view.tabs) ~= "table" then
		Theme.label("Opening your journal...", 14, Theme.FontNote, C.Muted).Parent = body
		return
	end
	local order = 0
	local function add(inst: GuiObject)
		order += 1
		inst.LayoutOrder = order
		inst.Parent = body
	end
	local standing = Theme.label(
		string.format("%s  ·  %s Pinehaven Credits", text(view.tier), text(view.credits)),
		12,
		Theme.FontBold,
		C.Amber
	)
	add(standing)
	for _, tab in view.tabs do
		if type(tab) == "table" and tab.id == currentTab then
			for _, section in tab.sections or {} do
				add(Theme.label(string.upper(text(section.heading)), 11, Theme.FontBold, C.Amber))
				local rows = section.rows or {}
				if currentTab == "MYSTERIES" and section.heading == "Observations" then
					rows = {
						{
							title = string.format("%d entries in your observation journal", #observations),
							detail = if #observations == 0
								then "Watch from a window at night, if you want to. Be patient."
								else "Newest first.",
							tone = "muted",
						},
					}
				end
				if #rows == 0 and section.empty then
					add(Theme.label(text(section.empty), 13, Theme.FontNote, C.Muted))
				end
				for _, r in rows do
					order += 1
					row(body, r, order)
				end
			end
		end
	end
	if currentTab == "MYSTERIES" then
		for i = #observations, math.max(1, #observations - 11), -1 do
			local e = observations[i]
			if type(e) == "table" then
				order += 1
				row(body, {
					title = text(e.title),
					detail = string.format(
						"Day %s, %s · %s. %s",
						text(e.day),
						text(e.clock),
						string.lower(text(e.weather)),
						text(e.text)
					),
					tone = "muted",
				}, order)
			end
		end
	end
end

local function refresh()
	task.spawn(function()
		local ok, v = pcall(function()
			return Net.func("GetLife"):InvokeServer()
		end)
		if ok and type(v) == "table" then
			view = v
		end
		local okJ, entries = pcall(function()
			return Net.func("GetJournal"):InvokeServer()
		end)
		if okJ and type(entries) == "table" then
			observations = entries
		end
		if panel.Visible then
			render()
		end
	end)
	render()
end

-- Shop -------------------------------------------------------------------------

local function renderShop()
	clear(shopBody)
	local s = shopState
	if not s then
		return
	end
	local credits = if type(view) == "table" and type(view.credits) == "number"
		then view.credits
		else s.credits
	local title = shop:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = s.name .. "'s counter"
	end
	Theme.label(string.format("You have %d Pinehaven Credits.", credits), 13, Theme.FontBold, C.Amber).Parent =
		shopBody
	local reasons: { [string]: string } = {
		reputation = "Needs more standing",
		owned = "You have one",
		soldout = "Sold out today",
		credits = "Not enough credits",
		closed = "Not yet",
	}
	for i, o in s.offers do
		local r = Theme.create("Frame", {
			Parent = shopBody,
			LayoutOrder = i + 1,
			Size = UDim2.new(1, -8, 0, 36),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.4,
		}, { Theme.corner(6) })
		Theme.create("TextLabel", {
			Parent = r,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -230, 1, 0),
			BackgroundTransparency = 1,
			Text = text(o.name),
			TextSize = 15,
			FontFace = Theme.FontMedium,
			TextColor3 = C.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		Theme.create("TextLabel", {
			Parent = r,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -110, 0, 0),
			Size = UDim2.fromOffset(110, 36),
			BackgroundTransparency = 1,
			Text = if o.ok then string.format("%d credits", o.price) else reasons[text(o.why)] or "",
			TextSize = 12,
			FontFace = Theme.Font,
			TextColor3 = if o.ok then C.Amber else C.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local b = Theme.button("Buy", 90)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -6, 0.5, 0)
		b.Size = UDim2.fromOffset(90, 28)
		b.TextSize = 14
		b.AutoButtonColor = o.ok == true
		b.TextTransparency = if o.ok then 0 else 0.6
		b.Parent = r
		b.Activated:Connect(function()
			if o.ok then
				Net.event("LifeRequest"):FireServer("buy", text(o.id))
			end
		end)
	end
end

-- Errand card and marker --------------------------------------------------------------

local function errandCard(gui: ScreenGui): (Frame, TextLabel, TextLabel, TextLabel)
	local card = Theme.create("Frame", {
		Parent = gui,
		-- Left side, below Roblox's chat window.
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 18, 0.45, 0),
		Size = UDim2.fromOffset(290, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.35,
		Visible = false,
	}, {
		Theme.corner(10),
		Theme.stroke(C.Line, 1, 0.6),
		Theme.create("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 12),
		}),
		Theme.create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local kicker = Theme.label("ERRAND  ·  J", 10, Theme.FontBold, C.Amber)
	kicker.LayoutOrder = 1
	kicker.Parent = card
	local title = Theme.label("", 14, Theme.FontSerif, C.Text)
	title.LayoutOrder = 2
	title.Parent = card
	local objective = Theme.label("", 12, Theme.FontMedium, C.Text)
	objective.LayoutOrder = 3
	objective.Parent = card
	local hint = Theme.label("", 11, Theme.Font, C.Muted)
	hint.LayoutOrder = 4
	hint.Parent = card
	return card, title, objective, hint
end

function LifeJournal.start()
	local player = Players.LocalPlayer
	local gui = Theme.screen("LifeGui", 20)

	panel = Theme.panel("Life Journal", UDim2.fromOffset(620, 520))
	panel.Name = "Life"
	panel.Parent = gui
	body = panel:FindFirstChild("Body") :: ScrollingFrame
	body.Position = UDim2.fromOffset(0, 82)
	body.Size = UDim2.new(1, 0, 1, -82)
	local close = Theme.button("×", 32)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, -4)
	close.Size = UDim2.fromOffset(32, 32)
	close.Parent = panel
	close.Activated:Connect(Panels.close)
	local bar = Theme.create("Frame", {
		Parent = panel,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, name in TABS do
		local b = Theme.button(name, 136)
		b.Size = UDim2.fromOffset(136, 30)
		b.TextSize = 13
		b.FontFace = Theme.FontBold
		b.LayoutOrder = i
		b.Parent = bar
		tabButtons[name] = b
		b.Activated:Connect(function()
			currentTab = name
			render()
		end)
	end
	Panels.register("Life", panel, refresh)

	shop = Theme.panel("Counter", UDim2.fromOffset(440, 380))
	shop.Name = "Shop"
	shop.Parent = gui
	shopBody = shop:FindFirstChild("Body") :: ScrollingFrame
	local shopClose = Theme.button("×", 32)
	shopClose.AnchorPoint = Vector2.new(1, 0)
	shopClose.Position = UDim2.new(1, 0, 0, -4)
	shopClose.Size = UDim2.fromOffset(32, 32)
	shopClose.Parent = shop
	shopClose.Activated:Connect(Panels.close)
	Panels.register("Shop", shop, renderShop)

	local card, title, objective, hint = errandCard(gui)
	local anchor = Instance.new("Attachment")
	anchor.Name = "ErrandMarker"
	anchor.Parent = workspace.Terrain
	local marker = Instance.new("BillboardGui")
	marker.Name = "ErrandMarker"
	marker.Adornee = anchor
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Size = UDim2.fromOffset(160, 44)
	marker.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	marker.Enabled = false
	marker.Parent = player:WaitForChild("PlayerGui")
	local diamond = Theme.create("TextLabel", {
		Parent = marker,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = "◆",
		TextSize = 22,
		FontFace = Theme.FontBold,
		TextColor3 = C.Amber,
		TextStrokeTransparency = 0.5,
	})
	local distance = Theme.create("TextLabel", {
		Parent = marker,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 12,
		FontFace = Theme.FontMedium,
		TextColor3 = C.Text,
		TextStrokeTransparency = 0.4,
	})
	local _ = diamond
	local hasWhere = false

	local function applyTracker()
		local t = if type(view) == "table" then view.tracker else nil
		if type(t) ~= "table" then
			hasWhere = false
			return
		end
		title.Text = text(t.title)
		objective.Text = text(t.objective) .. (if t.progress then "  ·  " .. text(t.progress) else "")
		hint.Text = text(t.hint)
		hint.Visible = hint.Text ~= ""
		hasWhere = typeof(t.where) == "Vector3"
		if hasWhere then
			anchor.WorldPosition = t.where
		end
	end

	Net.event("Life").OnClientEvent:Connect(function(v: any)
		if type(v) == "table" then
			view = v
			applyTracker()
			if panel.Visible then
				render()
			end
			if shop.Visible then
				renderShop()
			end
		end
	end)
	Net.event("Shop").OnClientEvent:Connect(function(vendor: any, name: any, offers: any, credits: any)
		if type(vendor) ~= "string" or type(offers) ~= "table" then
			return
		end
		shopState = {
			vendor = vendor,
			name = text(name),
			offers = offers,
			credits = if type(credits) == "number" then credits else 0,
		}
		if shop.Visible then
			renderShop()
		else
			Panels.toggle("Shop")
		end
	end)
	Net.event("Journal").OnClientEvent:Connect(function(entry: any)
		table.insert(observations, entry)
		if panel.Visible and currentTab == "MYSTERIES" then
			render()
		end
	end)

	RunService.RenderStepped:Connect(function()
		local hidden = ClientState.inMenu or ClientState.observing
		card.Visible = not hidden and type(view) == "table" and type(view.tracker) == "table"
		local show = false
		if hasWhere and not hidden then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local d = (root.Position - anchor.WorldPosition).Magnitude
				distance.Text = string.format("%d studs", math.floor(d))
				show = d >= 14
			end
		end
		marker.Enabled = show
	end)
	refresh()
end

return LifeJournal

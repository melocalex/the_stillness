--!strict
-- Pack, crafting, storage, journal and dog panels. One open at a time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Theme)

local Panels = {}

local C = Theme.Colors
local panels: { [string]: Frame } = {}
local refreshers: { [string]: () -> () } = {}
local current: string? = nil
local journalCache: { any } = {}

local function clear(body: Instance)
	for _, c in body:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local function bodyOf(name: string): ScrollingFrame
	return panels[name]:FindFirstChild("Body") :: ScrollingFrame
end

local function sortedItems(items: { [string]: number }): { string }
	local keys = {}
	for k, n in items do
		if n > 0 and ItemConfig.Items[k] then
			table.insert(keys, k)
		end
	end
	table.sort(keys, function(a, b)
		return ItemConfig.Items[a].order < ItemConfig.Items[b].order
	end)
	return keys
end

local function costText(cost: { [string]: number }): string
	local parts = {}
	for item, n in cost do
		local have = ClientState.items[item] or 0
		table.insert(
			parts,
			string.format(
				"%d %s%s",
				n,
				ItemConfig.Items[item] and ItemConfig.Items[item].name or item,
				if have < n then " (have " .. have .. ")" else ""
			)
		)
	end
	return table.concat(parts, ", ")
end

local function row(parent: Instance, left: string, right: string?, button: string?, onClick: (() -> ())?)
	local r = Theme.create("Frame", {
		Parent = parent,
		Size = UDim2.new(1, -8, 0, 34),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.4,
	}, { Theme.corner(6) })
	Theme.create("TextLabel", {
		Parent = r,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.fromScale(0.55, 1),
		BackgroundTransparency = 1,
		Text = left,
		TextSize = 15,
		FontFace = Theme.FontMedium,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if right then
		Theme.create("TextLabel", {
			Parent = r,
			Position = UDim2.fromScale(0.4, 0),
			Size = UDim2.new(0.6, if button then -110 else -10, 1, 0),
			BackgroundTransparency = 1,
			Text = right,
			TextSize = 13,
			FontFace = Theme.Font,
			TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	if button and onClick then
		local b = Theme.button(button, 96)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -4, 0.5, 0)
		b.Size = UDim2.fromOffset(96, 28)
		b.TextSize = 14
		b.Parent = r
		b.Activated:Connect(onClick)
	end
end

local function refreshPack()
	local body = bodyOf("Pack")
	clear(body)
	local keys = sortedItems(ClientState.items)
	if #keys == 0 then
		Theme.label(
			"Your pack is empty. Gather wood, stone and fiber in the forest.",
			14,
			Theme.Font,
			C.Muted
		).Parent =
			body
	end
	for _, k in keys do
		local n = ClientState.items[k]
		if k == "Stew" then
			row(body, ItemConfig.Items[k].name, tostring(n), "Eat", function()
				Net.event("EatStew"):FireServer()
			end)
		else
			row(body, ItemConfig.Items[k].name, tostring(n))
		end
	end
	local coat = Players.LocalPlayer:GetAttribute("CoatFound") == true
	Theme.label(if coat then "The coat: Q to wear or remove." else "", 13, Theme.Font, C.Amber).Parent = body
end

local function refreshCraft()
	local body = bodyOf("Craft")
	clear(body)
	for _, r in ItemConfig.Recipes do
		if r.station == "workbench" then
			row(body, r.name, costText(r.cost), "Craft", function()
				Net.event("Craft"):FireServer(r.id)
			end)
			Theme.label("    " .. r.description, 12, Theme.Font, C.Muted).Parent = body
		end
	end
	Theme.label(
		"Cabin upgrades are done at the door and windows themselves. Build furniture with B.",
		13,
		Theme.Font,
		C.Muted
	).Parent =
		body
end

local function refreshStorage()
	local body = bodyOf("Storage")
	clear(body)
	Theme.label("Your pack", 15, Theme.FontMedium, C.Amber).Parent = body
	for _, k in sortedItems(ClientState.items) do
		row(body, ItemConfig.Items[k].name, tostring(ClientState.items[k]), "Store all", function()
			Net.event("StorageMove"):FireServer(k, ClientState.items[k] or 0, true)
		end)
	end
	Theme.label("Cabin storage", 15, Theme.FontMedium, C.Amber).Parent = body
	for _, k in sortedItems(ClientState.chest) do
		row(body, ItemConfig.Items[k].name, tostring(ClientState.chest[k]), "Take all", function()
			Net.event("StorageMove"):FireServer(k, ClientState.chest[k] or 0, false)
		end)
	end
end

local function refreshJournal()
	local body = bodyOf("Journal")
	clear(body)
	if #journalCache == 0 then
		Theme.label(
			"No observations yet. Watch from a window at night. Be patient.",
			14,
			Theme.FontNote,
			C.Muted
		).Parent =
			body
	end
	for i = #journalCache, 1, -1 do
		local e = journalCache[i]
		if type(e) == "table" then
			local f = Theme.create("Frame", {
				Parent = body,
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Color3.fromRGB(46, 40, 34),
				BackgroundTransparency = 0.2,
			}, {
				Theme.corner(6),
				Theme.padding(10),
				Theme.create("UIListLayout", { Padding = UDim.new(0, 2) }),
			})
			Theme.label(tostring(e.title), 15, Theme.FontSerif, C.Amber).Parent = f
			Theme.label(
				string.format(
					"Day %s, %s · %s · %s",
					tostring(e.day),
					tostring(e.clock),
					string.lower(tostring(e.weather)),
					tostring(e.certainty)
				),
				12,
				Theme.Font,
				C.Muted
			).Parent =
				f
			Theme.label(tostring(e.text), 14, Theme.FontNote, C.Text).Parent = f
		end
	end
end

local DOG_COMMANDS = {
	{ "follow", "Follow" },
	{ "come", "Come" },
	{ "stay", "Stay" },
	{ "sit", "Sit" },
	{ "sleep", "Sleep" },
	{ "home", "Go to bed" },
	{ "hide", "Hide with me" },
	{ "calm", "Calm" },
}

local function refreshDog()
	local body = bodyOf("Dog")
	clear(body)
	local dog: Instance? = nil
	for _, d in workspace:FindFirstChild("Dogs") and (workspace :: any).Dogs:GetChildren() or {} do
		if d:GetAttribute("Owner") == Players.LocalPlayer.UserId then
			dog = d
		end
	end
	local state = if dog then tostring(dog:GetAttribute("DogState")) else "?"
	local alert = dog ~= nil and dog:GetAttribute("Alert") == true
	Theme.label(
		string.format("Your dog is %s.%s", state, if alert then " Ears up. Something is out there." else ""),
		14,
		Theme.Font,
		if alert then C.Amber else C.Muted
	).Parent =
		body
	local grid = Theme.create("Frame", {
		Parent = body,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Theme.create(
			"UIGridLayout",
			{ CellSize = UDim2.fromOffset(150, 36), CellPadding = UDim2.fromOffset(8, 8) }
		),
	})
	for i, c in DOG_COMMANDS do
		local b = Theme.button(c[2], 150)
		b.LayoutOrder = i
		b.Parent = grid
		b.Activated:Connect(function()
			Net.event("DogCommand"):FireServer(c[1])
			task.delay(0.3, refreshDog)
		end)
	end
end

-- Another UI module adds its own panel under the one-panel-at-a-time rule.
function Panels.register(name: string, panel: Frame, refresh: (() -> ())?)
	panels[name] = panel
	if refresh then
		refreshers[name] = refresh
	end
end

function Panels.toggle(name: string)
	if current == name then
		Panels.close()
		return
	end
	Panels.close()
	local p = panels[name]
	if not p then
		return
	end
	current = name
	ClientState.panelOpen = true
	local r = refreshers[name]
	if r then
		r()
	end
	p.Visible = true
	UserInputService.MouseIconEnabled = true
end

function Panels.close()
	if current then
		panels[current].Visible = false
	end
	current = nil
	ClientState.panelOpen = false
end

function Panels.isOpen(): boolean
	return current ~= nil
end

function Panels.start()
	local gui = Theme.screen("PanelGui", 20)
	local size = UDim2.fromOffset(480, 420)
	local titles: { [string]: string } = {
		Pack = "Pack",
		Craft = "Workbench",
		Storage = "Storage",
		Journal = "Observation journal",
		Dog = "Your dog",
	}
	for name, title in titles do
		local p = Theme.panel(title, size)
		p.Name = name
		p.Parent = gui
		local close = Theme.button("×", 32)
		close.AnchorPoint = Vector2.new(1, 0)
		close.Position = UDim2.new(1, 0, 0, -4)
		close.Size = UDim2.fromOffset(32, 32)
		close.Parent = p
		close.Activated:Connect(Panels.close)
		panels[name] = p
	end
	refreshers.Pack = refreshPack
	refreshers.Craft = refreshCraft
	refreshers.Storage = refreshStorage
	refreshers.Journal = function()
		local ok, entries = pcall(function()
			return Net.func("GetJournal"):InvokeServer()
		end)
		if ok and type(entries) == "table" then
			journalCache = entries
		end
		refreshJournal()
	end
	refreshers.Dog = refreshDog
	ClientState.onInventory(function()
		if current == "Pack" or current == "Storage" or current == "Craft" then
			(refreshers[current] :: () -> ())()
		end
	end)
	Net.event("Inventory").OnClientEvent:Connect(function(items: any, chest: any)
		if type(items) == "table" then
			ClientState.setInventory(items, if type(chest) == "table" then chest else nil)
		end
	end)
	Net.event("Journal").OnClientEvent:Connect(function(entry: any)
		table.insert(journalCache, entry)
		if current == "Journal" then
			refreshJournal()
		end
	end)
end

return Panels

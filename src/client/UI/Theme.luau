--!strict
-- Shared UI look: dark, muted panels with warm amber highlights.

local Players = game:GetService("Players")

local Theme = {}

Theme.Colors = {
	Bg = Color3.fromRGB(16, 14, 13),
	Panel = Color3.fromRGB(26, 23, 21),
	PanelLight = Color3.fromRGB(40, 35, 31),
	Line = Color3.fromRGB(70, 60, 50),
	Text = Color3.fromRGB(232, 222, 206),
	Muted = Color3.fromRGB(160, 148, 132),
	Amber = Color3.fromRGB(232, 168, 92),
	AmberDim = Color3.fromRGB(150, 104, 58),
	Danger = Color3.fromRGB(196, 72, 60),
	Good = Color3.fromRGB(140, 180, 120),
	Cold = Color3.fromRGB(120, 150, 180),
}

Theme.Font = Font.fromEnum(Enum.Font.Gotham)
Theme.FontBold = Font.fromEnum(Enum.Font.GothamBold)
Theme.FontMedium = Font.fromEnum(Enum.Font.GothamMedium)
Theme.FontSerif = Font.fromEnum(Enum.Font.Merriweather)
Theme.FontNote = Font.fromEnum(Enum.Font.SpecialElite)

-- Instance builder: create("Frame", { Size = ... }, { children })
function Theme.create(className: string, props: { [string]: any }?, children: { any }?): any
	local inst = Instance.new(className) :: any
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Decorators return `any` so they mix freely in `children` lists.
function Theme.corner(radius: number?): any
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	return c
end

function Theme.stroke(color: Color3?, thickness: number?, transparency: number?): any
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.Colors.Line
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0.3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return s
end

function Theme.padding(px: number): any
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	return p
end

function Theme.label(text: string, size: number, font: Font?, color: Color3?): TextLabel
	return Theme.create("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		FontFace = font or Theme.Font,
		TextColor3 = color or Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, size + 6),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
end

function Theme.button(text: string, width: number?): TextButton
	local b = Theme.create("TextButton", {
		Text = text,
		TextSize = 16,
		FontFace = Theme.FontMedium,
		TextColor3 = Theme.Colors.Text,
		BackgroundColor3 = Theme.Colors.PanelLight,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(width or 160, 36),
	}, { Theme.corner(6), Theme.stroke(Theme.Colors.AmberDim, 1, 0.4) })
	return b
end

function Theme.screen(name: string, order: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = order or 0
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function Theme.panel(title: string, size: UDim2): Frame
	local f = Theme.create("Frame", {
		Size = size,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.06,
		Visible = false,
	}, { Theme.corner(10), Theme.stroke(), Theme.padding(16) })
	local header = Theme.label(title, 22, Theme.FontSerif, Theme.Colors.Amber)
	header.Name = "Title"
	header.Parent = f
	local body = Theme.create("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Colors.AmberDim,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, {
		Theme.create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	body.Parent = f
	return f
end

return Theme

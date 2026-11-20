--!strict
-- Renders every ProximityPrompt (all use the Custom style): key cap, action,
-- object, and a hold-progress bar. Several prompts on one part stack using
-- their UIOffset.

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local Prompts = {}

local C = Theme.Colors

local function keyText(prompt: ProximityPrompt): string
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return prompt.GamepadKeyCode.Name:gsub("Button", "")
	end
	local name = prompt.KeyboardKeyCode.Name
	return if #name > 3 then string.sub(name, 1, 3) else name
end

function Prompts.start()
	local gui = Theme.screen("PromptGui", 5)
	local active: { [ProximityPrompt]: BillboardGui } = {}

	ProximityPromptService.PromptShown:Connect(
		function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
			if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
				return
			end
			local adornee = prompt.Parent
			if not adornee or not adornee:IsA("BasePart") then
				return
			end
			local bb = Instance.new("BillboardGui")
			bb.Name = "Prompt"
			bb.Adornee = adornee
			bb.AlwaysOnTop = true
			bb.Size = UDim2.fromOffset(280, 46)
			bb.SizeOffset = Vector2.new(0, -prompt.UIOffset.Y / 46)
			bb.LightInfluence = 0
			bb.MaxDistance = prompt.MaxActivationDistance + 4
			local frame = Theme.create("Frame", {
				Parent = bb,
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.Panel,
				BackgroundTransparency = 0.2,
			}, { Theme.corner(8), Theme.stroke(C.AmberDim, 1, 0.5) })
			Theme.create("TextLabel", {
				Parent = frame,
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.fromOffset(6, 6),
				BackgroundColor3 = C.PanelLight,
				Text = keyText(prompt),
				TextSize = 15,
				FontFace = Theme.FontBold,
				TextColor3 = C.Amber,
			}, { Theme.corner(6) })
			Theme.create("TextLabel", {
				Parent = frame,
				Name = "Action",
				Size = UDim2.new(1, -52, 0, 22),
				Position = UDim2.fromOffset(48, 4),
				BackgroundTransparency = 1,
				Text = prompt.ActionText,
				TextSize = 15,
				FontFace = Theme.FontMedium,
				TextColor3 = C.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			Theme.create("TextLabel", {
				Parent = frame,
				Size = UDim2.new(1, -52, 0, 16),
				Position = UDim2.fromOffset(48, 25),
				BackgroundTransparency = 1,
				Text = prompt.ObjectText,
				TextSize = 12,
				FontFace = Theme.Font,
				TextColor3 = C.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			local bar = Theme.create("Frame", {
				Parent = frame,
				Size = UDim2.fromOffset(0, 2),
				Position = UDim2.new(0, 0, 1, -2),
				BackgroundColor3 = C.Amber,
				BorderSizePixel = 0,
			})
			bb.Parent = gui
			active[prompt] = bb
			local changed = prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
				local a = frame:FindFirstChild("Action")
				if a and a:IsA("TextLabel") then
					a.Text = prompt.ActionText
				end
			end)
			local holdTween: Tween? = nil
			local began = prompt.PromptButtonHoldBegan:Connect(function()
				if prompt.HoldDuration > 0 then
					bar.Size = UDim2.fromOffset(0, 2)
					holdTween = TweenService:Create(
						bar,
						TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear),
						{ Size = UDim2.new(1, 0, 0, 2) }
					);
					(holdTween :: Tween):Play()
				end
			end)
			local ended = prompt.PromptButtonHoldEnded:Connect(function()
				if holdTween then
					holdTween:Cancel()
				end
				bar.Size = UDim2.fromOffset(0, 2)
			end)
			local triggered = prompt.Triggered:Connect(function()
				frame.BackgroundColor3 = C.AmberDim
				task.delay(0.15, function()
					frame.BackgroundColor3 = C.Panel
				end)
			end)
			prompt.PromptHidden:Once(function()
				changed:Disconnect()
				began:Disconnect()
				ended:Disconnect()
				triggered:Disconnect()
				bb:Destroy()
				active[prompt] = nil
			end)
			local _ = inputType
		end
	)
end

return Prompts

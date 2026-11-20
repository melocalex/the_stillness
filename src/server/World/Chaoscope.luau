--!strict
-- The H-17 Chaoscope (Chapter 36): a boxy field instrument that sits on the
-- cabin table. Geometry and prompts only; ChaoticEnergyService owns its
-- state and ChaoscopeController draws the dial, the trace and the lamps.
--
-- Contract: tag Chaoscope; parts Case, Face, Dial (needle SurfaceGui),
-- Screen (waveform SurfaceGui), LampPower, LampSignal, LampEmit, LampFault,
-- Knob, Switch; prompts ScopePrompt (Dial, ClientAction "Chaoscope") and
-- ScopePowerPrompt (Switch, key R).

local CollectionService = game:GetService("CollectionService")

local Builder = require(script.Parent.Builder)

local Chaoscope = {}

local CASE = Color3.fromRGB(58, 64, 54)
local PANEL = Color3.fromRGB(32, 34, 31)
local DARK = Color3.fromRGB(40, 40, 38)

local SIZE = Vector3.new(1.5, 0.95, 0.9)

-- Builds the scope standing on top of tableTop. offset is in the table's
-- space (x along the table, z across it); the scope faces +Z of the table.
function Chaoscope.build(tableTop: BasePart, offset: Vector3): Model
	local model = Builder.model("Chaoscope", tableTop.Parent)
	-- Local space: the front panel is -Z. Turning half a revolution makes it
	-- face +Z of the table, toward the stools.
	local base = tableTop.CFrame
		* CFrame.new(offset.X, tableTop.Size.Y / 2 + SIZE.Y / 2, offset.Z)
		* CFrame.Angles(0, math.pi, 0)
	local function part(
		name: string,
		size: Vector3,
		at: CFrame,
		color: Color3,
		material: Enum.Material?
	): Part
		return Builder.part({
			name = name,
			size = size,
			cframe = base * at,
			color = color,
			material = material or Enum.Material.SmoothPlastic,
			canCollide = false,
			parent = model,
		})
	end
	local case = part("Case", SIZE, CFrame.new(), CASE, Enum.Material.Metal)
	local face = part("Face", Vector3.new(1.42, 0.87, 0.04), CFrame.new(0, 0, -0.46), PANEL)
	local dial = part(
		"Dial",
		Vector3.new(0.62, 0.62, 0.03),
		CFrame.new(-0.36, 0.08, -0.49),
		Color3.fromRGB(222, 214, 186)
	)
	part("Screen", Vector3.new(0.56, 0.4, 0.03), CFrame.new(0.33, 0.16, -0.49), Color3.fromRGB(10, 20, 14))
	local lamps = { "LampPower", "LampSignal", "LampEmit", "LampFault" }
	for i, name in lamps do
		local lamp = part(
			name,
			Vector3.new(0.1, 0.1, 0.1),
			CFrame.new(0.12 + (i - 1) * 0.15, -0.28, -0.5),
			DARK,
			Enum.Material.Glass
		)
		lamp.Shape = Enum.PartType.Ball
	end
	local knob = part(
		"Knob",
		Vector3.new(0.08, 0.2, 0.2),
		CFrame.new(-0.55, -0.32, -0.52) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(28, 26, 24)
	)
	knob.Shape = Enum.PartType.Cylinder
	part(
		"SwitchPlate",
		Vector3.new(0.18, 0.14, 0.02),
		CFrame.new(-0.2, -0.32, -0.49),
		Color3.fromRGB(150, 150, 140)
	)
	local switch = part(
		"Switch",
		Vector3.new(0.05, 0.16, 0.05),
		CFrame.new(-0.2, -0.3, -0.53) * CFrame.Angles(math.rad(-25), 0, 0),
		Color3.fromRGB(200, 200, 190),
		Enum.Material.Metal
	)
	local antenna = part(
		"Antenna",
		Vector3.new(0.9, 0.04, 0.04),
		CFrame.new(0.6, SIZE.Y / 2 + 0.42, 0.3) * CFrame.Angles(0, 0, math.rad(84)),
		Color3.fromRGB(170, 170, 160),
		Enum.Material.Metal
	)
	antenna.Shape = Enum.PartType.Cylinder

	-- Maker's plate: the only printed text on the instrument.
	local plate = Instance.new("SurfaceGui")
	plate.Name = "Plate"
	plate.Face = Enum.NormalId.Front
	plate.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plate.PixelsPerStud = 120
	plate.LightInfluence = 1
	plate.Parent = face
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(1, 1)
	label.Position = UDim2.new(1, -6, 1, -4)
	label.Size = UDim2.fromOffset(120, 16)
	label.Font = Enum.Font.Code
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextColor3 = Color3.fromRGB(190, 182, 150)
	label.Text = "H-17"
	label.Parent = plate

	local look = Builder.prompt(dial, "Look closely", "Chaoscope", 0, 7)
	look.Name = "ScopePrompt"
	look:SetAttribute("ClientAction", "Chaoscope")
	local power = Builder.prompt(switch, "Switch on", "Chaoscope", 0, 7)
	power.Name = "ScopePowerPrompt"
	power.KeyboardKeyCode = Enum.KeyCode.R

	model.PrimaryPart = case
	model:SetAttribute("Model", "H-17")
	CollectionService:AddTag(model, "Chaoscope")
	return model
end

return Chaoscope

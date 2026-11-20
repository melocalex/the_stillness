--!strict
-- Small helpers for building procedural geometry.

local Builder = {}

-- House window glass while the room is dark: grey-blue and a little
-- reflective by day, dark at night from the lighting alone. (Near-black
-- glass read as holes in the walls in daylight.)
Builder.PaneUnlit = { color = Color3.fromRGB(96, 112, 122), transparency = 0.3, reflectance = 0.2 }

export type PartProps = {
	name: string?,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	parent: Instance?,
	anchored: boolean?,
	canCollide: boolean?,
	canQuery: boolean?,
	canTouch: boolean?,
	transparency: number?,
	castShadow: boolean?,
	shape: Enum.PartType?,
	reflectance: number?,
}

function Builder.part(p: PartProps): Part
	local part = Instance.new("Part")
	part.Name = p.name or "Part"
	if p.shape then
		part.Shape = p.shape
	end
	part.Size = p.size
	part.CFrame = p.cframe
	part.Anchored = if p.anchored == nil then true else p.anchored
	part.CanCollide = if p.canCollide == nil then true else p.canCollide
	part.CanQuery = if p.canQuery == nil then true else p.canQuery
	part.CanTouch = if p.canTouch == nil then false else p.canTouch
	part.Color = p.color or Color3.fromRGB(120, 110, 100)
	part.Material = p.material or Enum.Material.SmoothPlastic
	part.Transparency = p.transparency or 0
	part.Reflectance = p.reflectance or 0
	part.CastShadow = if p.castShadow == nil then true else p.castShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = p.parent
	return part
end

function Builder.wedge(p: PartProps): WedgePart
	local part = Instance.new("WedgePart")
	part.Name = p.name or "Wedge"
	part.Size = p.size
	part.CFrame = p.cframe
	part.Anchored = true
	part.CanCollide = if p.canCollide == nil then true else p.canCollide
	part.CanQuery = if p.canQuery == nil then true else p.canQuery
	part.CanTouch = false
	part.Color = p.color or Color3.fromRGB(120, 110, 100)
	part.Material = p.material or Enum.Material.SmoothPlastic
	part.Transparency = p.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = p.parent
	return part
end

function Builder.model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Builder.folder(name: string, parent: Instance?): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Builder.rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function Builder.prompt(
	parent: Instance,
	action: string,
	object: string,
	holdDuration: number?,
	distance: number?
): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = holdDuration or 0
	p.MaxActivationDistance = distance or 9
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Custom
	p.Parent = parent
	return p
end

function Builder.pointLight(
	parent: Instance,
	color: Color3,
	range: number,
	brightness: number,
	shadows: boolean?
): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = shadows == true
	l.Parent = parent
	return l
end

function Builder.attachment(parent: Instance, name: string, cframe: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cframe
	a.Parent = parent
	return a
end

return Builder

--!strict
-- Lights, switches and circuits. Electric lights obey their circuit's master
-- power; the fireplace and lanterns do not. Light state is server-owned and
-- feeds creature perception through illumination and house visibility.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LightVisibility = require(ReplicatedStorage.Shared.Logic.LightVisibility)

local LightService = {}

local power: { [string]: boolean } = {}
local listeners: { () -> () } = {}

local function lightOf(part: Instance): Light?
	return part:FindFirstChildWhichIsA("Light")
end

function LightService.isLit(part: Instance): boolean
	return part:GetAttribute("Lit") == true
end

local function apply(part: Instance)
	local on = part:GetAttribute("On") == true
	if part:GetAttribute("Electric") == true then
		local circuit = (part:GetAttribute("Circuit") :: string?) or "Cabin"
		on = on and power[circuit] ~= false
		if part:GetAttribute("Flicker") == true then
			on = false
		end
	end
	part:SetAttribute("Lit", on)
	local l = lightOf(part)
	if l then
		l.Enabled = on
	end
	if part:IsA("BasePart") and part:GetAttribute("Electric") == true then
		part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local function notify()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function LightService.onChanged(fn: () -> ())
	table.insert(listeners, fn)
end

function LightService.start()
	for _, part in CollectionService:GetTagged("StillnessLight") do
		apply(part)
	end
	CollectionService:GetInstanceAddedSignal("StillnessLight"):Connect(function(part)
		apply(part)
	end)
end

function LightService.set(part: Instance, on: boolean)
	part:SetAttribute("On", on)
	apply(part)
	notify()
end

function LightService.toggle(part: Instance): boolean
	local on = not (part:GetAttribute("On") == true)
	LightService.set(part, on)
	return on
end

function LightService.setPower(circuit: string, on: boolean)
	power[circuit] = on
	for _, part in CollectionService:GetTagged("StillnessLight") do
		if part:GetAttribute("Circuit") == circuit then
			apply(part)
		end
	end
	notify()
end

function LightService.hasPower(circuit: string): boolean
	return power[circuit] ~= false
end

-- Brief electrical disturbance (storms, bad nights). Does not change switches.
function LightService.flicker(circuit: string, seconds: number)
	task.spawn(function()
		local t = 0
		while t < seconds do
			local off = math.random() < 0.5
			for _, part in CollectionService:GetTagged("StillnessLight") do
				if part:GetAttribute("Circuit") == circuit and part:GetAttribute("Electric") == true then
					part:SetAttribute("Flicker", off)
					apply(part)
				end
			end
			local step = 0.05 + math.random() * 0.2
			task.wait(step)
			t += step
		end
		for _, part in CollectionService:GetTagged("StillnessLight") do
			if part:GetAttribute("Circuit") == circuit then
				part:SetAttribute("Flicker", nil)
				apply(part)
			end
		end
		notify()
	end)
end

-- Light falling on a point: sky plus lit sources in range.
function LightService.illuminationAt(pos: Vector3, sky: number): number
	local samples = {}
	for _, part in CollectionService:GetTagged("StillnessLight") do
		if part:IsA("BasePart") and part:GetAttribute("Lit") == true then
			local l = lightOf(part)
			if l and l:IsA("PointLight") then
				local d = (part.Position - pos).Magnitude
				if d < l.Range then
					table.insert(samples, {
						brightness = (part:GetAttribute("Brightness") :: number?) or l.Brightness,
						range = l.Range,
						distance = d,
					})
				end
			end
		end
	end
	return LightVisibility.illumination(sky, samples, false)
end

-- How many electric lights are lit inside a shelter, and is its fire lit.
function LightService.shelterLights(shelterId: string): (number, boolean)
	local electric, fire = 0, false
	for _, part in CollectionService:GetTagged("StillnessLight") do
		if part:GetAttribute("Shelter") == shelterId and part:GetAttribute("Lit") == true then
			if part:GetAttribute("Electric") == true then
				if part:GetAttribute("Indoor") == true then
					electric += 1
				else
					electric += 0.6 -- a porch light advertises the house too
				end
			else
				fire = true
			end
		end
	end
	return electric, fire
end

return LightService

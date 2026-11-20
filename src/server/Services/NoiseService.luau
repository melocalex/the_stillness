--!strict
-- Noise events. Anything audible (footsteps, doors, tools, a dropped object,
-- a gasp, a bark) is emitted here; creatures subscribe and judge whether they
-- heard it, through walls and over the rain.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Noise = require(ReplicatedStorage.Shared.Logic.Noise)
local ShelterService = require(script.Parent.ShelterService)

local NoiseService = {}

export type NoiseEvent = {
	position: Vector3,
	loudness: number,
	kind: string,
	source: Player?,
	time: number,
	sourceShelter: string?,
	sourceSealed: boolean,
}

local listeners: { (NoiseEvent) -> () } = {}
local weatherLabel = "Clear"

function NoiseService.setWeather(label: string)
	weatherLabel = label
end

function NoiseService.onNoise(fn: (NoiseEvent) -> ())
	table.insert(listeners, fn)
end

function NoiseService.emit(position: Vector3, kind: string, source: Player?, loudnessOverride: number?)
	local loudness = loudnessOverride or Noise.Loudness[kind] or 10
	if loudness <= 0 then
		return
	end
	local shelter = ShelterService.shelterAt(position)
	local ev: NoiseEvent = {
		position = position,
		loudness = loudness,
		kind = kind,
		source = source,
		time = os.clock(),
		sourceShelter = shelter,
		sourceSealed = if shelter then ShelterService.isSecure(shelter) else false,
	}
	for _, fn in listeners do
		fn(ev)
	end
end

-- 0..1 how clearly a listener at pos with this hearing heard the event.
function NoiseService.strengthAt(ev: NoiseEvent, listenerPos: Vector3, hearingMultiplier: number): number
	local listenerShelter = ShelterService.shelterAt(listenerPos)
	local sourceInside = ev.sourceShelter ~= nil
	local listenerInside = listenerShelter ~= nil and listenerShelter == ev.sourceShelter
	local sealed = ev.sourceSealed
	if not sourceInside and listenerShelter ~= nil then
		-- outside sound reaching someone inside
		sealed = ShelterService.isSecure(listenerShelter)
		sourceInside = false
		listenerInside = true
	end
	local att = Noise.attenuation(sourceInside, listenerInside, sealed, weatherLabel)
	return Noise.perceivedStrength(ev.loudness, (ev.position - listenerPos).Magnitude, att, hearingMultiplier)
end

function NoiseService.positionError(distance: number, strength: number): number
	return Noise.positionError(distance, strength)
end

return NoiseService

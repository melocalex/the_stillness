--!strict
-- Registered shelters and their entry points. Applies the pure Shelter rules
-- to live state and publishes "Secure" and "Reasons" on each shelter model.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shelter = require(ReplicatedStorage.Shared.Logic.Shelter)

local ShelterService = {}

type ShelterRec = {
	id: string,
	model: Model,
	volume: BasePart,
	entries: { Instance },
	evaluation: Shelter.Evaluation,
}

local shelters: { [string]: ShelterRec } = {}
local listeners: { (string, Shelter.Evaluation) -> () } = {}

local function entryOf(inst: Instance): Shelter.EntryPoint
	return {
		id = (inst:GetAttribute("EntryId") :: string?) or inst.Name,
		kind = ((inst:GetAttribute("EntryKind") :: string?) or "door") :: any,
		installed = inst:GetAttribute("Installed") == true,
		open = inst:GetAttribute("Open") == true,
		health = (inst:GetAttribute("Health") :: number?) or 0,
		maxHealth = (inst:GetAttribute("MaxHealth") :: number?) or 100,
		shuttered = inst:GetAttribute("Shuttered") == true,
	}
end

local function recompute(rec: ShelterRec)
	local list = {}
	for _, e in rec.entries do
		table.insert(list, entryOf(e))
	end
	local before = rec.evaluation
	rec.evaluation = Shelter.evaluate(list)
	rec.model:SetAttribute("Secure", rec.evaluation.secure)
	rec.model:SetAttribute("Reasons", table.concat(rec.evaluation.reasons, ", "))
	rec.model:SetAttribute("Weakest", rec.evaluation.weakest)
	if
		before == nil
		or before.secure ~= rec.evaluation.secure
		or before.weakest ~= rec.evaluation.weakest
	then
		for _, fn in listeners do
			task.spawn(fn, rec.id, rec.evaluation)
		end
	end
end

function ShelterService.start()
	for _, model in CollectionService:GetTagged("Shelter") do
		if model:IsA("Model") then
			local id = (model:GetAttribute("ShelterId") :: string?) or model.Name
			local volume = model:FindFirstChild("ShelterVolume")
			if volume and volume:IsA("BasePart") then
				local rec: ShelterRec = {
					id = id,
					model = model,
					volume = volume,
					entries = {},
					evaluation = Shelter.evaluate({}),
				}
				for _, e in CollectionService:GetTagged("EntryPoint") do
					if e:GetAttribute("Shelter") == id then
						table.insert(rec.entries, e)
						e.AttributeChanged:Connect(function(attr)
							if attr == "Installed" or attr == "Open" or attr == "Health" then
								recompute(rec)
							end
						end)
					end
				end
				shelters[id] = rec
				recompute(rec)
			end
		end
	end
end

function ShelterService.onChanged(fn: (string, Shelter.Evaluation) -> ())
	table.insert(listeners, fn)
end

local function inside(volume: BasePart, pos: Vector3, margin: number): boolean
	local p = volume.CFrame:PointToObjectSpace(pos)
	local h = volume.Size / 2
	return math.abs(p.X) <= h.X + margin and math.abs(p.Y) <= h.Y + margin and math.abs(p.Z) <= h.Z + margin
end

-- Id of the shelter whose registered interior contains pos, if any.
function ShelterService.shelterAt(pos: Vector3, margin: number?): string?
	for id, rec in shelters do
		if inside(rec.volume, pos, margin or 0) then
			return id
		end
	end
	return nil
end

function ShelterService.evaluation(id: string): Shelter.Evaluation?
	local rec = shelters[id]
	return if rec then rec.evaluation else nil
end

function ShelterService.isSecure(id: string): boolean
	local rec = shelters[id]
	return rec ~= nil and rec.evaluation.secure
end

-- Is this position protected from ordinary creatures right now?
function ShelterService.isProtected(pos: Vector3): boolean
	local id = ShelterService.shelterAt(pos)
	return id ~= nil and ShelterService.isSecure(id)
end

function ShelterService.entries(id: string): { Instance }
	local rec = shelters[id]
	return if rec then rec.entries else {}
end

function ShelterService.model(id: string): Model?
	local rec = shelters[id]
	return if rec then rec.model else nil
end

function ShelterService.volume(id: string): BasePart?
	local rec = shelters[id]
	return if rec then rec.volume else nil
end

-- Openings a creature could use right now (open or breached entry points).
function ShelterService.openings(id: string): { Instance }
	local out = {}
	for _, e in ShelterService.entries(id) do
		local ep = entryOf(e)
		if ep.kind ~= "roof" and ((not ep.installed) or ep.open or ep.health <= 0) then
			table.insert(out, e)
		end
	end
	return out
end

function ShelterService.all(): { string }
	local ids = {}
	for id in shelters do
		table.insert(ids, id)
	end
	return ids
end

return ShelterService

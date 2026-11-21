--!strict
-- The shared town for every server: community buildings, routes and town
-- flags (Logic/SharedTown), in its own DataStore key, never inside a
-- player's save. Saves merge with what is stored (UpdateAsync), so servers
-- running at the same time never erase each other's progress. Without
-- DataStore access (an unpublished Studio place) it lives in memory.
--
-- Chapter 37's projects are personal (each player repairs Frank's shed in
-- their own story); a project with `scope = "town"` uses this instead.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedTown = require(ReplicatedStorage.Shared.Logic.SharedTown)

local SharedTownService = {}

local KEY = "pinehaven"
local SAVE_EVERY = 120

local state: SharedTown.State = SharedTown.new()
local store: DataStore? = nil
local loadOk = false
local dirty = false
local listeners: { () -> () } = {}

local function changed()
	dirty = true
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function SharedTownService.get(): SharedTown.State
	return state
end

function SharedTownService.onChanged(fn: () -> ())
	table.insert(listeners, fn)
end

-- Buildings use the same {id = stage} shape as a player's projects, so
-- Restoration works on `get().buildings` directly; call this after.
function SharedTownService.touched()
	changed()
end

function SharedTownService.raiseBuilding(id: string, stage: number)
	if SharedTown.raiseBuilding(state, id, stage) then
		changed()
	end
end

function SharedTownService.openRoute(id: string)
	if SharedTown.openRoute(state, id) then
		changed()
	end
end

function SharedTownService.setFlag(id: string)
	if SharedTown.setFlag(state, id) then
		changed()
	end
end

local function save()
	-- Never write when the stored town could not be read.
	if not store or not loadOk or not dirty then
		return
	end
	local ok = pcall(function()
		(store :: DataStore):UpdateAsync(KEY, function(old: any): any
			state = SharedTown.merge(SharedTown.restore(old), state)
			return SharedTown.snapshot(state)
		end)
	end)
	if ok then
		dirty = false
	end
end

function SharedTownService.start()
	pcall(function()
		store = DataStoreService:GetDataStore("StillnessTown_v1")
	end)
	task.spawn(function()
		if not store then
			loadOk = true
			return
		end
		local ok, data = pcall(function()
			return (store :: DataStore):GetAsync(KEY)
		end)
		if ok then
			state = SharedTown.merge(SharedTown.restore(data), state)
			loadOk = true
			changed()
		else
			warn("[SharedTown] could not read the shared town; changes this session stay in memory")
		end
	end)
	game:BindToClose(save)
	task.spawn(function()
		while true do
			task.wait(SAVE_EVERY)
			save()
		end
	end)
end

return SharedTownService

--!strict
-- Remote definitions. The server creates them; clients wait for them.
-- Every client-to-server remote is validated and rate limited on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- Client -> server
Net.ClientEvents = {
	"RequestSpawn",
	"SetStance", -- (sprint: boolean, crouch: boolean)
	"SetBreath", -- (holding: boolean)
	"ToggleCoat",
	"DogCommand", -- (command: string)
	"SetObserving", -- (window: Instance?)
	"Craft", -- (recipeId: string)
	"Build", -- (buildableId: string, cframe: CFrame)
	"EatStew",
	"StorageMove", -- (item: string, amount: number, toChest: boolean)
}
Net.ClientUnreliable = {
	"LookVector", -- (Vector3) camera direction for "is the creature being watched"
}
-- Server -> client
Net.ServerEvents = {
	"Notify", -- (text: string, kind: string?)
	"Inventory", -- (items: {[string]: number}, chest: {[string]: number}?)
	"Story", -- (label: string?, hint: string?, completedText: string?)
	"Journal", -- (entry)
	"SoundCue", -- (cue: string, position: Vector3?, volume: number?)
	"Lightning", -- (position: Vector3)
	"Captured", -- (text: string)
	"Note", -- (title: string, body: string)
	"EndCard", -- (text: string)
	"Radio", -- (text: string)
}
Net.Functions = {
	"GetJournal",
}

local folder: Folder? = nil

local function getFolder(): Folder
	local existing = folder
	if existing then
		return existing
	end
	local result: Folder
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild("Remotes")
		if f and f:IsA("Folder") then
			result = f
		else
			result = Instance.new("Folder")
			result.Name = "Remotes"
			result.Parent = ReplicatedStorage
		end
	else
		result = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	folder = result
	return result
end

function Net.setup()
	local f = getFolder()
	local function make(className: string, name: string)
		if not f:FindFirstChild(name) then
			local r = Instance.new(className)
			r.Name = name
			r.Parent = f
		end
	end
	for _, n in Net.ClientEvents do
		make("RemoteEvent", n)
	end
	for _, n in Net.ServerEvents do
		make("RemoteEvent", n)
	end
	for _, n in Net.ClientUnreliable do
		make("UnreliableRemoteEvent", n)
	end
	for _, n in Net.Functions do
		make("RemoteFunction", n)
	end
end

function Net.event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	return getFolder():WaitForChild(name) :: UnreliableRemoteEvent
end

function Net.func(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

-- Token bucket per player per remote.
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}

function Net.allow(player: Player, key: string, ratePerSecond: number): boolean
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local b = perPlayer[key]
	if not b then
		b = { tokens = ratePerSecond, last = now }
		perPlayer[key] = b
	end
	b.tokens = math.min(ratePerSecond, b.tokens + (now - b.last) * ratePerSecond)
	b.last = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

function Net.forget(player: Player)
	buckets[player] = nil
end

return Net

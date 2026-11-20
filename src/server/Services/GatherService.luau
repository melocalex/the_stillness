--!strict
-- Resource gathering. Every node tagged ResourceNode gets a prompt; yields are
-- server-side, nodes deplete and respawn on timers, and every action makes
-- noise (chopping carries far).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local NoiseService = require(script.Parent.NoiseService)
local PlayerService = require(script.Parent.PlayerService)
local StoryService = require(script.Parent.StoryService)

local GatherService = {}

type Kind = {
	action: string,
	object: string,
	hold: number,
	yields: { [string]: number },
	hits: number,
	respawn: number,
	noise: string,
	noiseLoudness: number?,
	cue: string,
}

local G = GameConfig.Gather
local KINDS: { [string]: Kind } = {
	Tree = {
		action = "Chop",
		object = "Pine",
		hold = 1.2,
		yields = { Wood = G.TreeWood },
		hits = G.TreeHits,
		respawn = G.TreeRespawn,
		noise = "chop",
		cue = "chop",
	},
	Rock = {
		action = "Mine",
		object = "Rock",
		hold = 1.4,
		yields = { Stone = G.RockStone },
		hits = G.RockHits,
		respawn = G.RockRespawn,
		noise = "mine",
		cue = "mine",
	},
	Bush = {
		action = "Gather fiber",
		object = "Bush",
		hold = 0.8,
		yields = { Fiber = G.BushFiber },
		hits = 1,
		respawn = G.BushRespawn,
		noise = "crouch",
		cue = "pickup",
	},
	BerryBush = {
		action = "Pick berries",
		object = "Berry bush",
		hold = 0.8,
		yields = { Fiber = 1, Berries = 2 },
		hits = 1,
		respawn = G.BushRespawn,
		noise = "crouch",
		cue = "pickup",
	},
	Mushroom = {
		action = "Pick",
		object = "Mushroom",
		hold = 0.3,
		yields = { Mushroom = 1 },
		hits = 1,
		respawn = G.MushroomRespawn,
		noise = "crouch",
		cue = "pickup",
	},
	Scrap = {
		action = "Salvage",
		object = "Scrap",
		hold = 1.5,
		yields = { Scrap = 2 },
		hits = 1,
		respawn = G.ScrapRespawn,
		noise = "cabinet",
		noiseLoudness = 16,
		cue = "mine",
	},
}

local STORY_COUNTERS: { [string]: string } =
	{ Wood = "woodGathered", Stone = "stoneGathered", Fiber = "fiberGathered" }

local function primary(node: Instance): BasePart?
	if node:IsA("BasePart") then
		return node
	elseif node:IsA("Model") then
		return node.PrimaryPart or node:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

local function setVisible(node: Instance, visible: boolean, kind: string)
	local parts: { BasePart } = {}
	if node:IsA("BasePart") then
		table.insert(parts, node)
	end
	for _, d in node:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	for _, p in parts do
		local base = p:GetAttribute("BaseTransparency") :: number?
		if base == nil then
			base = p.Transparency
			p:SetAttribute("BaseTransparency", base)
			p:SetAttribute("BaseCollide", p.CanCollide)
		end
		if visible then
			p.Transparency = base :: number
			p.CanCollide = p:GetAttribute("BaseCollide") == true
		elseif kind == "Tree" and p.Name == "Trunk" then
			-- A felled tree leaves a stump.
			p.Transparency = base :: number
		elseif kind == "Bush" or kind == "BerryBush" then
			p.Transparency = if p.Name == "Berry" then 1 else math.max(base :: number, 0.55)
		else
			p.Transparency = 1
			p.CanCollide = false
		end
	end
	if kind == "Tree" then
		local trunk = node:FindFirstChild("Trunk")
		if trunk and trunk:IsA("BasePart") then
			local full = trunk:GetAttribute("FullSize") :: Vector3?
			local fullCF = trunk:GetAttribute("FullCFrame") :: CFrame?
			if not full then
				full = trunk.Size
				fullCF = trunk.CFrame
				trunk:SetAttribute("FullSize", full)
				trunk:SetAttribute("FullCFrame", fullCF)
			end
			local f = full :: Vector3
			local cf = fullCF :: CFrame
			if visible then
				trunk.Size = f
				trunk.CFrame = cf
			else
				local stump = 1.6
				trunk.Size = Vector3.new(stump, f.Y, f.Z)
				-- Cylinder axis is the part's X axis, rotated to world up.
				trunk.CFrame = cf * CFrame.new(-(f.X - stump) / 2, 0, 0)
			end
		end
	end
end

local function setup(node: Instance)
	local kindName = node:GetAttribute("ResourceKind") :: string?
	local kind = if kindName then KINDS[kindName] else nil
	local part = primary(node)
	if not kind or not part or not kindName then
		return
	end
	if kindName == "Tree" and part:IsA("BasePart") then
		-- A bright ribbon around the trunk marks the trees you can chop.
		local bottomY = part.Position.Y - part.Size.X / 2
		local ribbon = Instance.new("Part")
		ribbon.Name = "Ribbon"
		ribbon.Shape = Enum.PartType.Cylinder
		ribbon.Size = Vector3.new(0.7, 3.6, 3.6)
		ribbon.CFrame = CFrame.new(part.Position.X, bottomY + 3.6, part.Position.Z)
			* CFrame.Angles(0, 0, math.rad(90))
		ribbon.Color = Color3.fromRGB(235, 110, 30)
		ribbon.Material = Enum.Material.Fabric
		ribbon.Anchored = true
		ribbon.CanCollide = false
		ribbon.CanQuery = false
		ribbon.CanTouch = false
		ribbon.CastShadow = false
		ribbon.Parent = node
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GatherPrompt"
	prompt.ActionText = kind.action
	prompt.ObjectText = if kindName == "Tree" then "Marked tree" else kind.object
	prompt.HoldDuration = kind.hold
	prompt.MaxActivationDistance = if kindName == "Tree" then 13 else 9
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = part
	if (node:GetAttribute("HitsLeft") :: number?) == nil then
		node:SetAttribute("HitsLeft", kind.hits)
	end
	prompt.Triggered:Connect(function(player)
		if node:GetAttribute("Depleted") == true or not PlayerService.isActive(player) then
			return
		end
		local root = PlayerService.root(player)
		if not root or (root.Position - part.Position).Magnitude > G.MaxDistance + 4 then
			return
		end
		if not Net.allow(player, "gather", 1 / G.Cooldown) then
			return
		end
		for item, n in kind.yields do
			local added = PlayerService.give(player, item, n)
			local counter = STORY_COUNTERS[item]
			if counter and added > 0 then
				StoryService.addFact(counter, added)
			end
		end
		NoiseService.emit(part.Position, kind.noise, player, kind.noiseLoudness)
		Net.event("SoundCue"):FireAllClients(kind.cue, part.Position, 0.8)
		local left = ((node:GetAttribute("HitsLeft") :: number?) or 1) - 1
		node:SetAttribute("HitsLeft", left)
		if left <= 0 then
			node:SetAttribute("Depleted", true)
			prompt.Enabled = false
			setVisible(node, false, kindName)
			task.delay(kind.respawn, function()
				node:SetAttribute("HitsLeft", kind.hits)
				node:SetAttribute("Depleted", false)
				setVisible(node, true, kindName)
				prompt.Enabled = true
			end)
		end
	end)
end

function GatherService.start()
	for _, node in CollectionService:GetTagged("ResourceNode") do
		setup(node)
	end
	CollectionService:GetInstanceAddedSignal("ResourceNode"):Connect(setup)
end

return GatherService

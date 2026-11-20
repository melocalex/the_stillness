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

local prompts: { [Instance]: ProximityPrompt } = {}
local stumps: { [Instance]: BasePart } = {}
local axeCheck: ((Player) -> Tool?)? = nil
local swingFn: ((Tool) -> ())? = nil
local harvest: (Player, Instance) -> ()
local chips: (Vector3, Vector3) -> ()
local shake: (Instance, Vector3) -> ()
local fell: (Model, Vector3, () -> ()) -> ()

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
		local groundY = part.Position.Y - part.Size.X / 2
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local hit = workspace:Raycast(
			Vector3.new(part.Position.X, part.Position.Y + 40, part.Position.Z),
			Vector3.new(0, -120, 0),
			params
		)
		if hit then
			groundY = hit.Position.Y
		end
		local ribbon = Instance.new("Part")
		ribbon.Name = "Ribbon"
		ribbon.Shape = Enum.PartType.Cylinder
		ribbon.Size = Vector3.new(0.55, 2.9, 2.9)
		ribbon.CFrame = CFrame.new(part.Position.X, groundY + 4.2, part.Position.Z)
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
	prompts[node] = prompt
	if kindName == "Tree" then
		prompt.ActionText = "Chop (axe)"
		prompt.HoldDuration = 0
	end
	prompt.Triggered:Connect(function(player)
		if kindName == "Tree" then
			local axe = axeCheck and axeCheck(player)
			if not axe then
				if Net.allow(player, "axehint", 0.5) then
					Net.event("Notify"):FireClient(player, "Equip your axe first: press 1.", "info")
				end
				return
			end
			if swingFn then
				swingFn(axe)
			end
			task.delay(0.25, function()
				GatherService.chop(player, node)
			end)
			return
		end
		harvest(player, node)
	end)
end

-- One validated hit on a node. Trees go through GatherService.chop (axe only).
harvest = function(player: Player, node: Instance)
	local kindName = node:GetAttribute("ResourceKind") :: string?
	local kind = if kindName then KINDS[kindName] else nil
	local part = primary(node)
	if not kind or not part or not kindName then
		return
	end
	if node:GetAttribute("Depleted") == true or not PlayerService.isActive(player) then
		return
	end
	local root = PlayerService.root(player)
	if not root or (root.Position - part.Position).Magnitude > G.MaxDistance + 6 then
		return
	end
	if not Net.allow(player, "gather", 1 / G.Cooldown) then
		return
	end
	local gained = {}
	for item, n in kind.yields do
		local added = PlayerService.give(player, item, n)
		local counter = STORY_COUNTERS[item]
		if counter and added > 0 then
			StoryService.addFact(counter, added)
		end
		if added > 0 then
			table.insert(gained, string.format("+%d %s", added, item))
		end
	end
	NoiseService.emit(part.Position, kind.noise, player, kind.noiseLoudness)
	Net.event("SoundCue"):FireAllClients(kind.cue, part.Position, 0.8)
	local left = ((node:GetAttribute("HitsLeft") :: number?) or 1) - 1
	node:SetAttribute("HitsLeft", left)
	if kindName == "Tree" then
		chips(part.Position, root.Position)
		if left > 0 then
			shake(node, root.Position)
		end
	end
	if #gained > 0 and (kindName ~= "Tree" or left <= 0) then
		Net.event("Notify"):FireClient(player, table.concat(gained, "  "), "pickup")
	end
	if left <= 0 then
		node:SetAttribute("Depleted", true)
		local prompt = prompts[node]
		if prompt then
			prompt.Enabled = false
		end
		local function hide()
			setVisible(node, false, kindName)
		end
		if kindName == "Tree" and node:IsA("Model") then
			fell(node, root.Position, hide)
		else
			hide()
		end
		task.delay(kind.respawn, function()
			local stump = stumps[node]
			if stump then
				stump:Destroy()
				stumps[node] = nil
			end
			local home = node:GetAttribute("HomePivot") :: CFrame?
			if home and node:IsA("Model") then
				node:PivotTo(home)
			end
			node:SetAttribute("HitsLeft", kind.hits)
			node:SetAttribute("Depleted", false)
			setVisible(node, true, kindName)
			if prompt then
				prompt.Enabled = true
			end
		end)
	end
end

-- Trees: the axe swings, the trunk shakes and throws chips, and on the last
-- hit the tree falls away from the player, fades and leaves a stump.
function GatherService.chop(player: Player, node: Instance)
	if node:GetAttribute("ResourceKind") ~= "Tree" then
		return
	end
	if not (axeCheck and axeCheck(player)) then
		return
	end
	harvest(player, node)
end

function GatherService.setAxeCheck(check: (Player) -> Tool?, swing: (Tool) -> ())
	axeCheck = check
	swingFn = swing
end

chips = function(at: Vector3, from: Vector3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	local dir = Vector3.new(from.X - at.X, 0, from.Z - at.Z)
	local hitPoint = Vector3.new(at.X, from.Y, at.Z)
		+ (if dir.Magnitude > 0 then dir.Unit * 1.2 else Vector3.zero)
	p.CFrame = CFrame.new(hitPoint)
	p.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromRGB(196, 160, 112), Color3.fromRGB(140, 100, 64))
	e.Size = NumberSequence.new(0.22, 0.05)
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(8, 16)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Acceleration = Vector3.new(0, -40, 0)
	e.Rate = 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-300, 300)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = p
	e:Emit(16)
	task.delay(1.5, function()
		p:Destroy()
	end)
end

shake = function(node: Instance, from: Vector3)
	if not node:IsA("Model") then
		return
	end
	local home = node:GetAttribute("HomePivot") :: CFrame?
	if not home then
		home = node:GetPivot()
		node:SetAttribute("HomePivot", home)
	end
	local h = home :: CFrame
	local away = Vector3.new(h.Position.X - from.X, 0, h.Position.Z - from.Z)
	local axis = if away.Magnitude > 0 then away.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
	task.spawn(function()
		for _, a in { 2.5, -1.8, 1.0, -0.4, 0 } do
			if node:GetAttribute("Depleted") == true then
				return
			end
			node:PivotTo(CFrame.fromAxisAngle(axis, math.rad(-a)) * (h - h.Position) + h.Position)
			task.wait(0.05)
		end
	end)
end

fell = function(node: Model, from: Vector3, done: () -> ())
	local home = node:GetAttribute("HomePivot") :: CFrame?
	if not home then
		home = node:GetPivot()
		node:SetAttribute("HomePivot", home)
	end
	local h = home :: CFrame
	local base = node.PrimaryPart
	local groundY = if base then base.Position.Y - base.Size.X / 2 else h.Position.Y
	local pivotPoint = Vector3.new(h.Position.X, groundY, h.Position.Z)
	local away = Vector3.new(h.Position.X - from.X, 0, h.Position.Z - from.Z)
	local axis = if away.Magnitude > 0 then away.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
	-- The stump stays behind.
	local stump = Instance.new("Part")
	stump.Name = "Stump"
	stump.Shape = Enum.PartType.Cylinder
	stump.Size = Vector3.new(1.4, 2.4, 2.4)
	stump.CFrame = CFrame.new(pivotPoint + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	stump.Color = Color3.fromRGB(104, 76, 52)
	stump.Material = Enum.Material.Wood
	stump.Anchored = true
	stump.Parent = node.Parent
	stumps[node] = stump
	Net.event("SoundCue"):FireAllClients("doorBreak", pivotPoint, 0.9)
	task.spawn(function()
		local duration = 1.5
		local t = 0
		while t < duration do
			local dt = task.wait()
			t += dt
			local k = math.clamp(t / duration, 0, 1)
			local angle = math.rad(88) * k * k -- accelerating fall
			local rot = CFrame.fromAxisAngle(axis, -angle)
			local rel = h.Position - pivotPoint
			node:PivotTo(CFrame.new(pivotPoint + rot * rel) * rot * (h - h.Position))
		end
		NoiseService.emit(pivotPoint, "doorSlam")
		Net.event("SoundCue"):FireAllClients("doorPound", pivotPoint + away.Unit * 12, 1)
		task.wait(1.2)
		done()
	end)
end

function GatherService.start()
	for _, node in CollectionService:GetTagged("ResourceNode") do
		setup(node)
	end
	CollectionService:GetInstanceAddedSignal("ResourceNode"):Connect(setup)
end

return GatherService

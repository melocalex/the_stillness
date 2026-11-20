--!strict
-- Access to the vetted Creator Store models in ServerStorage.StillnessAssets
-- (assets/StillnessAssets.rbxm). Every getter returns nil when the asset is
-- missing so world building can fall back to procedural geometry.

local ServerStorage = game:GetService("ServerStorage")

local Assets = {}

local root: Instance? = ServerStorage:FindFirstChild("StillnessAssets")
local variants: { [string]: { Model } } = {}

local function collectVariants(kind: string, container: Instance?, depth: number)
	if not container then
		return
	end
	local list = variants[kind] or {}
	variants[kind] = list
	-- A pack is Model > Model(pack) > Model(tree); a single tree is Model > Model.
	for _, child in container:GetChildren() do
		if child:IsA("Model") then
			local hasModels = false
			for _, c in child:GetChildren() do
				if c:IsA("Model") and depth > 0 then
					hasModels = true
				end
			end
			if hasModels and depth > 0 then
				collectVariants(kind, child, depth - 1)
			else
				table.insert(list, child)
			end
		end
	end
end

local function find(name: string): Instance?
	return if root then root:FindFirstChild(name) else nil
end

function Assets.available(): boolean
	return root ~= nil
end

function Assets.init()
	root = ServerStorage:FindFirstChild("StillnessAssets")
	if not root then
		warn("[Assets] ServerStorage.StillnessAssets missing; using procedural fallbacks")
		return
	end
	collectVariants("Ponderosa", find("Trees_Ponderosa"), 1)
	collectVariants("Birch", find("Trees_Birch"), 1)
	collectVariants("Cedar", find("Trees_RedCedar"), 0)
	collectVariants("Oak", find("Tree_AutumnOak"), 0)
	collectVariants("SnowPine", find("Tree_SnowPine"), 0)
	for kind, list in variants do
		print(string.format("[Assets] %s: %d variants", kind, #list))
	end
end

-- Prepare a clone: anchored, non-colliding meshes (a simple collider is added
-- by the caller), shadows on, no physics cost.
local function prepare(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		elseif d:IsA("Camera") then
			d:Destroy()
		end
	end
end

-- Places a model so its bounding-box bottom sits on groundY at (x, z).
function Assets.place(model: Model, x: number, groundY: number, z: number, yaw: number, sink: number?)
	local cf, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local bottomOffset = (cf.Position.Y - size.Y / 2) - pivot.Position.Y
	local flat = CFrame.new(x, groundY - bottomOffset - (sink or 0.4), z) * CFrame.Angles(0, yaw, 0)
	-- keep the model's own rotation relative to its pivot (packs are authored upright)
	model:PivotTo(flat * (pivot - pivot.Position))
end

-- Clone a random variant of a tree kind, scaled. Returns nil if unavailable.
function Assets.tree(kind: string, rng: Random, scale: number): Model?
	local list = variants[kind]
	if not list or #list == 0 then
		return nil
	end
	local src = list[rng:NextInteger(1, #list)]
	local m = src:Clone()
	prepare(m)
	if scale ~= 1 then
		m:ScaleTo(m:GetScale() * scale)
	end
	return m
end

function Assets.clone(name: string): Model?
	local src = find(name)
	if not src then
		return nil
	end
	local inner = src:FindFirstChildWhichIsA("Model")
	local m = (if inner and #src:GetChildren() == 1 then inner else src):Clone() :: Model
	if not m:IsA("Model") then
		return nil
	end
	prepare(m)
	return m
end

-- Height of a model's bounding box.
function Assets.height(model: Model): number
	local _, size = model:GetBoundingBox()
	return size.Y
end

return Assets

--!strict
-- Player building. The client only proposes a CFrame; the server snaps it to
-- the grid, checks reach, cost, cap and overlap, then builds.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local NoiseService = require(script.Parent.NoiseService)
local PlayerService = require(script.Parent.PlayerService)
local ShelterService = require(script.Parent.ShelterService)

local BuildService = {}

local counts: { [number]: number } = {}
local folder: Folder

local function find(id: string): ItemConfig.Buildable?
	for _, b in ItemConfig.Buildables do
		if b.id == id then
			return b
		end
	end
	return nil
end

-- Server-side snapping: grid position, 90-degree yaw, resting on the surface.
function BuildService.snap(cf: CFrame, size: Vector3): CFrame
	local g = GameConfig.Build.Grid
	local p = cf.Position
	local x = math.floor(p.X / g + 0.5) * g
	local z = math.floor(p.Z / g + 0.5) * g
	local look = cf.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	yaw = math.floor(yaw / (math.pi / 2) + 0.5) * (math.pi / 2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(Vector3.new(x, p.Y + 6, z), Vector3.new(0, -30, 0), params)
	local y = if hit then hit.Position.Y else p.Y
	return CFrame.new(x, y + size.Y / 2, z) * CFrame.Angles(0, yaw, 0)
end

local function build(player: Player, id: any, cf: any)
	if type(id) ~= "string" or typeof(cf) ~= "CFrame" or not Net.allow(player, "build", 2) then
		return
	end
	local b = find(id)
	local root = PlayerService.root(player)
	if not b or not root or not PlayerService.isActive(player) then
		return
	end
	local size = Vector3.new(b.size[1], b.size[2], b.size[3])
	local placed = BuildService.snap(cf, size)
	if (placed.Position - root.Position).Magnitude > GameConfig.Build.MaxDistance then
		Net.event("Notify"):FireClient(player, "Too far away to build there.", "info")
		return
	end
	if (counts[player.UserId] or 0) >= GameConfig.Build.MaxPerPlayer then
		Net.event("Notify"):FireClient(player, "You've built as much as you can manage for now.", "info")
		return
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { workspace.Terrain }
	for _, part in workspace:GetPartBoundsInBox(placed, size * 0.96, overlap) do
		if part.CanCollide then
			Net.event("Notify"):FireClient(player, "Something is in the way.", "info")
			return
		end
	end
	if not PlayerService.spend(player, b.cost) then
		return
	end
	counts[player.UserId] = (counts[player.UserId] or 0) + 1
	local part: BasePart
	if id == "Chair" then
		local seat = Instance.new("Seat")
		CollectionService:AddTag(seat, "ComfortSeat")
		part = seat
	else
		part = Instance.new("Part")
	end
	part.Name = b.id
	part.Size = size
	part.CFrame = placed
	part.Anchored = true
	part.Color = Color3.fromRGB(b.color[1], b.color[2], b.color[3])
	local okMat, mat = pcall(function()
		return (Enum.Material :: any)[b.material]
	end)
	part.Material = if okMat and mat then mat else Enum.Material.Wood
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("Owner", player.UserId)
	if id == "DogBed" then
		CollectionService:AddTag(part, "DogBed")
		part.CanCollide = false
	elseif id == "StorageBox" then
		CollectionService:AddTag(part, "Chest")
		local p = Instance.new("ProximityPrompt")
		p.Name = "ChestPrompt"
		p.ActionText = "Open storage"
		p.ObjectText = "Storage box"
		p.Style = Enum.ProximityPromptStyle.Custom
		p.MaxActivationDistance = 8
		p:SetAttribute("ClientAction", "Storage")
		p.Parent = part
	end
	if b.light then
		local shelter = ShelterService.shelterAt(placed.Position)
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(255, 200, 130)
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 176, 110)
		l.Range = 16
		l.Brightness = 1.2
		l.Parent = part
		part:SetAttribute("On", true)
		part:SetAttribute("Electric", false)
		part:SetAttribute("Indoor", shelter ~= nil)
		part:SetAttribute("Shelter", shelter or "")
		part:SetAttribute("Brightness", 1)
		CollectionService:AddTag(part, "StillnessLight")
		local p = Instance.new("ProximityPrompt")
		p.Name = "LampPrompt"
		p.ActionText = "Lantern off"
		p.ObjectText = "Lantern"
		p.Style = Enum.ProximityPromptStyle.Custom
		p.MaxActivationDistance = 7
		p.Parent = part
		p.Triggered:Connect(function(who)
			if not Net.allow(who, "prompt", 6) then
				return
			end
			local on = not (part:GetAttribute("On") == true)
			part:SetAttribute("On", on)
			part:SetAttribute("Lit", on)
			l.Enabled = on
			part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			p.ActionText = if on then "Lantern off" else "Lantern on"
			NoiseService.emit(part.Position, "switch", who)
		end)
	end
	part.Parent = folder
	NoiseService.emit(placed.Position, "chop", player)
	Net.event("SoundCue"):FireAllClients("craft", placed.Position)
	if b.comfort then
		ReplicatedStorage:SetAttribute(
			"CabinUpgrades",
			((ReplicatedStorage:GetAttribute("CabinUpgrades") :: number?) or 0)
				+ (if ShelterService.shelterAt(placed.Position) then 1 else 0)
		)
	end
end

function BuildService.start()
	folder = Instance.new("Folder")
	folder.Name = "Built"
	folder.Parent = workspace
	Net.event("Build").OnServerEvent:Connect(build)
end

return BuildService

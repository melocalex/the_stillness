-- Studio command-bar helper (Edit mode). Loads the vetted Creator Store
-- models by id into ServerStorage.StillnessAssets, strips any scripts and
-- prints a summary. The folder is then saved to assets/StillnessAssets.rbxm.
-- Ids, creators and licenses are listed in docs/ASSET_LICENSES.md.
local f = game.ServerStorage:FindFirstChild("StillnessAssets") or Instance.new("Folder")
f.Name = "StillnessAssets"
f.Parent = game.ServerStorage
f:ClearAllChildren()
local picks = {
	Trees_RedCedar = 113109119460825,
	Trees_Birch = 11351912067,
	Trees_Ponderosa = 130515502281374,
	Tree_AutumnOak = 10071825333,
	Tree_SnowPine = 11590212184,
	Dog = 72361172511972,
	Deer = 5114925772,
	Rabbit = 8984402484,
	Crow = 676471054,
	RockingChair = 303336108,
	Bookshelf = 56449804,
	Bed = 98266706858536,
	Lantern = 9666312574,
	Creature_Watcher = 18629586862,
	Creature_Dweller = 15020057104,
	Creature_Crawler = 103037817796984,
	Axe = 87307912628259,
}
for name, id in picks do
	local ok, objs = pcall(function()
		return game:GetObjects("rbxassetid://" .. id)
	end)
	if ok and objs[1] then
		local m = Instance.new("Model")
		m.Name = name
		for _, o in objs do
			o.Parent = m
		end
		m:SetAttribute("AssetId", id)
		m.Parent = f
	else
		print("ASSETX FAILED", name, id, objs)
	end
end
local removed = 0
for _, d in f:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		d:Destroy()
		removed += 1
	end
end
for _, ch in f:GetChildren() do
	local _, size = ch:GetBoundingBox()
	local names = {}
	for _, c in ch:GetChildren() do
		table.insert(names, c.Name .. ":" .. c.ClassName .. ":" .. #c:GetChildren())
	end
	print("ASSETX", ch.Name, math.floor(size.X), math.floor(size.Y), math.floor(size.Z), #ch:GetDescendants(), string.sub(table.concat(names, ","), 1, 160))
end
print("ASSETX removed scripts", removed)

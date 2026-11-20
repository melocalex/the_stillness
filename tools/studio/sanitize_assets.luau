-- Studio command-bar helper. Run in Edit mode after inserting Creator Store
-- models. Moves loose Workspace models into ServerStorage.StillnessAssets,
-- deletes every script inside them (free models often hide backdoors), and
-- prints an inventory so the asset list can be documented.
local f = game.ServerStorage:FindFirstChild("StillnessAssets") or Instance.new("Folder")
f.Name = "StillnessAssets"
f.Parent = game.ServerStorage
for _, c in workspace:GetChildren() do
	if not c:IsA("Camera") and not c:IsA("Terrain") and c.Name ~= "World" then
		c.Parent = f
	end
end
local removed = 0
for _, d in f:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		d:Destroy()
		removed += 1
	end
end
local remaining = 0
for _, d in f:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		remaining += 1
	end
end
print("removed scripts:", removed, "remaining:", remaining)
for _, ch in f:GetChildren() do
	local size = Vector3.zero
	if ch:IsA("Model") then
		size = ch:GetExtentsSize()
	elseif ch:IsA("BasePart") then
		size = ch.Size
	end
	print("ASSET", ch.Name, ch.ClassName, #ch:GetDescendants(), math.floor(size.X), math.floor(size.Y), math.floor(size.Z))
end

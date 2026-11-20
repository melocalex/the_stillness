--!strict
-- Extracts ServerStorage.StillnessAssets from a place saved in Studio into
-- assets/StillnessAssets.rbxm, refusing if any script slipped in.
-- Usage: lune run tools/assets/extract_assets <place.rbxlx>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "build/TheStillness.rbxlx"
local place = roblox.deserializePlace(fs.readFile(path))
local folder = place:GetService("ServerStorage"):FindFirstChild("StillnessAssets")
assert(folder, "ServerStorage.StillnessAssets not found in " .. path)

for _, d in folder:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		error("refusing: script found at " .. d:GetFullName())
	end
end

fs.writeFile("assets/StillnessAssets.rbxm", roblox.serializeModel({ folder }))
for _, child in folder:GetChildren() do
	print(child.Name, child:GetAttribute("AssetId"), #child:GetDescendants())
end
print("wrote assets/StillnessAssets.rbxm")

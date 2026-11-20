-- Storm library v2 check (generated from tools/assets/audio_candidates.lua).
local ids = {rainOnWindow = 9112857056, rainOnWindow2 = 9112856768, rainGutter = 9112853895, dripBucket = 9112903083, dripPuddle = 9112893331, windTrees = 9116258071, windTrees2 = 9116258282, windGusts2 = 9114057128, shutterBang = 9119128490, latchClick = 9116725218, glassBreak = 9114590297, glassBreak2 = 9114592245, floorCreak = 9125563505, floorCreak2 = 9114496277, wetFootsteps = 9120589946, dogGrowl = 9120788137, dogWhimper = 9113951726, exhaleSoft = 9113586280, thunderDistant3 = 9120018692, thunderStrike = 9120021539, musicBoxUnease = 1837805876}
local CP = game:GetService("ContentProvider")
local folder = Instance.new("Folder")
folder.Parent = game:GetService("SoundService")
local sounds = {}
for name, id in ids do
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxassetid://" .. id
	s.Parent = folder
	table.insert(sounds, s)
end
CP:PreloadAsync(sounds)
task.wait(2)
local ok, bad = 0, {}
for _, s in sounds do
	if s.IsLoaded and s.TimeLength > 0 then ok += 1 else table.insert(bad, s.Name) end
end
print("AUDIOCHECK2 ok=" .. ok .. " bad=" .. #bad .. " " .. table.concat(bad, ","))
folder:Destroy()
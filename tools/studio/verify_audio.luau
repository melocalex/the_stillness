-- Generated from tools/assets/audio_candidates.lua: loads every id and reports failures.
local ids = {
	birdsDay = 9112835056,
	birdsDay2 = 9112835068,
	cricketsNight = 9112764573,
	owl = 9117181540,
	wolvesDistant = 9120051816,
	coyotesDistant = 9114683804,
	crowsDistant = 9114009761,
	windLight = 9114057104,
	windHowl = 81404060588532,
	windGust = 9120697823,
	rainLight = 9120020741,
	rainOutside = 9112853422,
	rainRoof = 9112853653,
	rainRoofHeavy = 9112853563,
	thunderDistant = 9120018411,
	thunderDistant2 = 9120018695,
	thunderCrack = 9120016037,
	thunderCrack2 = 9120016256,
	fireplace = 77688442375055,
	eerieRumble = 9112795463,
	eeriePresence = 9112775612,
	windowRattle = 9120762268,
	windowRattleLong = 9120766393,
	curtain = 9114018343,
	switch = 9125609743,
	doorOpen = 9120839581,
	doorClose = 9120839870,
	doorSlam = 1837829565,
	doorPound = 9114148088,
	doorBreak = 9120805690,
	woodCreak = 9126282474,
	woodScrape = 9116908825,
	chop = 9120808574,
	mine = 9118612665,
	gasp = 9125572450,
	exhale = 9113586144,
	heartbeat = 9043365842,
	radioStatic = 9125774208,
	creatureBreath = 9113983944,
	creatureBreath2 = 9113984054,
	creatureGrowl = 9125467848,
	creatureRoarDeep = 9113985466,
	birdsTakeOff = 9125738421,
	wingFlaps = 9113444620,
	dogBarkFar = 9114370187,
	musicMenu = 1838792473,
	musicHome = 113205710506304,
	musicHome2 = 129193633608000,
	musicHomeRain = 133914369779227,
	musicDay = 135947284128563,
	musicDay2 = 113725748108878,
	musicDusk = 9046385674,
	musicNightSafe = 84591888439601,
	musicNightOutside = 99895453377463,
	musicCreatureNear = 1839621827,
	musicCreatureHunt = 1837795171,
	musicCreatureLost = 1835935237,
	musicDawn = 9042042586,
	musicDiscovery = 113592187486066,
}
local CP = game:GetService("ContentProvider")
local folder = Instance.new("Folder")
folder.Name = "AudioCheck"
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
local ok, bad = 0, {}
for _, s in sounds do
	if s.IsLoaded and s.TimeLength > 0 then
		ok += 1
	else
		table.insert(bad, s.Name)
	end
end
print("AUDIOCHECK ok=" .. ok .. " bad=" .. #bad .. " " .. table.concat(bad, ","))
folder:Destroy()

-- Chapter 36 candidates for the Chaoscope's hum, tone and relay click. All
-- from the ProSoundEffects catalog, found with tools/assets/search_store.py.
-- Paste into the Studio command bar (Edit mode is fine) and click Run. Only
-- ids that print as loaded may go into AudioConfig.Chaoscope.
local ids = {
	humTransformer1 = 9112889082, -- Transformer Hum 1 (SFX), 36 s
	humTransformer2 = 9112889525, -- Transformer Hum 2 (SFX), 52 s
	humPowerThrob = 9125784811, -- Power Throb Tonal Hum Slow Pulse Electrical (SFX), 4 s
	toneOscillating = 9120972942, -- Woo Woo Sci Fi Tone Constant Oscillating 1 (SFX), 27 s
	clickRelay6 = 9118145455, -- Relay Clicks 6 (SFX), 1 s
}
local CP = game:GetService("ContentProvider")
local folder = Instance.new("Folder")
folder.Name = "DissonanceAudioCheck"
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
for _, s in sounds do
	print(string.format("DISSONANCEAUDIO %s %s loaded=%s length=%.1f", s.Name, s.SoundId, tostring(s.IsLoaded), s.TimeLength))
end
folder:Destroy()

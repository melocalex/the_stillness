--!strict
-- Ambience mixer, one-shot cues and the adaptive MusicDirector.
--
-- Every id comes from AudioConfig; an empty id is skipped silently. The mix
-- reacts to time of day, rain intensity, wind, being indoors (rain moves to
-- the roof, wind is muffled), open windows in your shelter (the storm comes
-- into the room), lit fires nearby, and the night's mood. Music uses
-- Logic/MusicState: it changes with the danger, never restarts for nothing,
-- and leaves long silences on purpose.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local ClientState = require(script.Parent.Parent.ClientState)
local MusicState = require(ReplicatedStorage.Shared.Logic.MusicState)
local Net = require(ReplicatedStorage.Shared.Net)

local AudioController = {}

local player = Players.LocalPlayer
local layers: { [string]: Sound } = {}
local rng = Random.new()
local cueFolder: Folder
-- Music, ambience and fire share one group so the Dissonance's silence
-- (the Hush attribute) can pause them all together.
local hushGroup: SoundGroup

export type RecentCue = { name: string, at: number }
local recent: { RecentCue } = {}

local function makeSound(id: string, parent: Instance, looped: boolean, volume: number): Sound?
	if id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = looped
	s.Volume = volume
	s.Parent = parent
	return s
end

-- One-shot sound, positional when a position is given.
function AudioController.cue(name: string, position: Vector3?, volume: number?)
	local id = AudioConfig.Cues[name]
	if not id or id == "" then
		return
	end
	-- Remembered for the Echo (Chapter 36): names and times only.
	table.insert(recent, { name = name, at = os.clock() })
	if #recent > 16 then
		table.remove(recent, 1)
	end
	local parent: Instance = SoundService
	local holder: Attachment? = nil
	if position then
		holder = Instance.new("Attachment");
		(holder :: Attachment).WorldPosition = position;
		(holder :: Attachment).Parent = workspace.Terrain
		parent = holder :: Attachment
	end
	local s = makeSound(id, parent, false, (volume or 1) * AudioConfig.Mix.CueVolume)
	if not s then
		return
	end
	s.PlaybackSpeed = rng:NextNumber(0.94, 1.06)
	s.RollOffMaxDistance = 400
	s:Play()
	s.Ended:Once(function()
		if holder then
			holder:Destroy()
		else
			s:Destroy()
		end
	end)
end

-- The last in-game cues this client played, oldest first.
function AudioController.recentCues(): { RecentCue }
	return table.clone(recent)
end

local function cameraInside(): (boolean, string?)
	local pos = workspace.CurrentCamera.CFrame.Position
	for _, v in CollectionService:GetTagged("ShelterVolume") do
		if v:IsA("BasePart") then
			local p = v.CFrame:PointToObjectSpace(pos)
			local h = v.Size / 2
			if math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y + 6 and math.abs(p.Z) <= h.Z then
				return true, v:GetAttribute("Shelter") :: string?
			end
		end
	end
	return false, nil
end

local function openWindowsIn(shelter: string?): number
	if not shelter then
		return 0
	end
	local n = 0
	for _, w in CollectionService:GetTagged("Window") do
		if w:GetAttribute("Shelter") == shelter then
			local h = (w:GetAttribute("Health") :: number?) or 100
			if w:GetAttribute("Open") == true or h <= 0 then
				n += 1
			end
		end
	end
	return n
end

-- Music --------------------------------------------------------------------------

local currentState: string = ""
local currentTrack: Sound? = nil
local lastCueAt = -1e9
local lastIds: { [string]: string } = {}

local function fadeOut(s: Sound)
	local t = TweenService:Create(s, TweenInfo.new(AudioConfig.Mix.MusicFade), { Volume = 0 })
	t:Play()
	t.Completed:Once(function()
		s:Destroy()
	end)
end

local function playMusic(state: string)
	local list = AudioConfig.Music[state]
	if not list or #list == 0 then
		return
	end
	local choices = {}
	for _, id in list do
		if id ~= "" and (id ~= lastIds[state] or #list == 1) then
			table.insert(choices, id)
		end
	end
	if #choices == 0 then
		return
	end
	local id = choices[rng:NextInteger(1, #choices)]
	lastIds[state] = id
	local s = makeSound(id, SoundService, MusicState.isAlwaysOn(state :: any), 0)
	if not s then
		return
	end
	s.SoundGroup = hushGroup
	s:Play()
	TweenService:Create(s, TweenInfo.new(AudioConfig.Mix.MusicFade), { Volume = AudioConfig.Mix.MusicVolume })
		:Play()
	currentTrack = s
	lastCueAt = os.clock()
	s.Ended:Once(function()
		if currentTrack == s then
			currentTrack = nil
		end
		s:Destroy()
	end)
end

local function musicTick()
	local threat = (player:GetAttribute("Threat") :: number?) or 0
	if threat > 0 then
		ClientState.lastThreatTime = os.clock()
	end
	local cabinPowerOff = false
	for _, s in CollectionService:GetTagged("Shelter") do
		if s:GetAttribute("Power") == false then
			cabinPowerOff = true
		end
	end
	local nightType = ReplicatedStorage:GetAttribute("NightType")
	local state = MusicState.choose({
		menu = ClientState.inMenu,
		phase = (ReplicatedStorage:GetAttribute("Phase") :: string?) or "Day",
		sheltered = player:GetAttribute("Sheltered") == true,
		raining = ((ReplicatedStorage:GetAttribute("RainIntensity") :: number?) or 0) > 0.6,
		storm = ((ReplicatedStorage:GetAttribute("RainIntensity") :: number?) or 0) >= 3.4,
		threat = threat,
		secondsSinceThreat = os.clock() - ClientState.lastThreatTime,
		discovery = os.clock() - ClientState.lastDiscovery < 6,
		lightsOff = cabinPowerOff,
		badNight = nightType == "Bad" or nightType == "Black",
	})
	if state ~= currentState then
		local wasAlways = currentState ~= "" and MusicState.isAlwaysOn(currentState :: any)
		currentState = state
		if currentTrack and (wasAlways or MusicState.isAlwaysOn(state :: any)) then
			fadeOut(currentTrack)
			currentTrack = nil
		end
		if MusicState.isAlwaysOn(state :: any) then
			playMusic(state)
			return
		end
	end
	if state == "BLACKOUT" and currentTrack then
		fadeOut(currentTrack)
		currentTrack = nil
	end
	if not currentTrack then
		if
			MusicState.shouldStartCue(
				state :: any,
				os.clock() - lastCueAt,
				AudioConfig.Mix.MusicMinGap,
				AudioConfig.Mix.MusicChance,
				rng:NextNumber()
			)
		then
			lastCueAt = os.clock()
			playMusic(state)
		end
	end
end

-- Ambience ----------------------------------------------------------------------

function AudioController.start()
	cueFolder = Instance.new("Folder")
	cueFolder.Name = "StillnessAudio"
	cueFolder.Parent = SoundService
	hushGroup = Instance.new("SoundGroup")
	hushGroup.Name = "Hushable"
	hushGroup.Parent = SoundService
	for name, id in AudioConfig.Ambience :: { [string]: string } do
		local s = if name == "fireplace" then nil else makeSound(id, cueFolder, true, 0)
		if s then
			s.Name = name
			s.SoundGroup = hushGroup
			s:Play()
			layers[name] = s
		end
	end
	-- Fireplace crackle is positional at each hearth and follows the fire.
	local function hookFire(f: Instance)
		local s = makeSound(AudioConfig.Ambience.fireplace, f, true, 0)
		if not s then
			return
		end
		local sound = s
		sound.RollOffMaxDistance = 40
		sound.SoundGroup = hushGroup
		sound:Play()
		local function update()
			sound.Volume = if f:GetAttribute("Lit") == true then 0.7 * AudioConfig.Mix.AmbienceVolume else 0
		end
		f:GetAttributeChangedSignal("Lit"):Connect(update)
		update()
	end
	for _, f in CollectionService:GetTagged("Fireplace") do
		hookFire(f)
	end
	CollectionService:GetInstanceAddedSignal("Fireplace"):Connect(hookFire)
	local targets: { [string]: number } = {}
	RunService.Heartbeat:Connect(function(dt: number)
		local inside, shelter = cameraInside()
		local nf = (ReplicatedStorage:GetAttribute("NightFactor") :: number?) or 0
		local rain = math.clamp(((ReplicatedStorage:GetAttribute("RainIntensity") :: number?) or 0) / 5, 0, 1)
		local wind = (ReplicatedStorage:GetAttribute("WindStrength") :: number?) or 0
		local birdsQuiet = ReplicatedStorage:GetAttribute("BirdsQuiet") == true
		local open = math.min(openWindowsIn(shelter), 2) / 2
		local outside = if inside then 0.15 + 0.6 * open else 1
		targets.dayBirds = (1 - nf) * (if birdsQuiet then 0 else 0.5) * outside * (1 - rain)
		targets.dayLeaves = (1 - nf) * 0.3 * outside
		targets.nightInsects = nf * (if birdsQuiet then 0.1 else 0.45) * outside * (1 - rain * 0.8)
		targets.nightDistant = nf * 0.3 * outside
		targets.windLight = math.clamp(wind * 1.2, 0, 0.6) * (if inside then 0.25 + 0.5 * open else 1)
		targets.windStrong = math.clamp((wind - 0.45) * 1.8, 0, 1) * (if inside then 0.3 + 0.6 * open else 1)
		targets.rainOutside = rain * (if inside then 0.12 + 0.75 * open else 1)
		targets.rainRoof = if inside then rain * 0.9 else 0
		targets.rainWindow = if inside then rain * 0.4 else 0
		targets.cabinCreaks = if inside then 0.15 + wind * 0.3 else 0
		targets.heartbeat = if ((player:GetAttribute("Threat") :: number?) or 0) >= 2 and inside
			then 0.35
			else 0
		local k = math.min(dt / AudioConfig.Mix.AmbienceFade, 1)
		for name, s in layers do
			local target = (targets[name] or 0) * AudioConfig.Mix.AmbienceVolume
			s.Volume += (target - s.Volume) * k
		end
		-- The Dissonance's silence: rain, fire, insects and music all pause,
		-- then come back.
		local hush = math.clamp((ReplicatedStorage:GetAttribute("Hush") :: number?) or 0, 0, 1)
		hushGroup.Volume += ((1 - 0.92 * hush) - hushGroup.Volume) * math.min(dt / 1.2, 1)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(musicTick :: any)
			if not ok then
				warn("[Music] " .. tostring(err))
			end
		end
	end)
	Net.event("SoundCue").OnClientEvent:Connect(function(name: any, position: any, volume: any)
		if type(name) == "string" then
			AudioController.cue(
				name,
				if typeof(position) == "Vector3" then position else nil,
				if type(volume) == "number" then volume else nil
			)
		end
	end)
end

return AudioController

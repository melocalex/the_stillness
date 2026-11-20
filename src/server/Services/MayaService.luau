--!strict
-- Maya lives in her own house across the lake (Revision 2.0). She is an R15
-- NPC who moves between marked spots through the day, talks in person, calls
-- over the radio, and lights her windows at dusk. She is never in danger
-- here: the rescue system (Chapter 32) is not built yet.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Builder = require(script.Parent.Parent.World.Builder)
local HouseActivityService = require(script.Parent.HouseActivityService)
local PlayerService = require(script.Parent.PlayerService)
local StoryService = require(script.Parent.StoryService)
local TimeService = require(script.Parent.TimeService)

local MayaService = {}

local HAIR = "7193448258" -- Roblox catalog "Wavy Middle Part - Brown" (free)
-- Roblox's default R15 idle animations (same IDs the stock Animate script uses).
local IDLE = "rbxassetid://507766666"

local house: Model? = nil
local npc: Model? = nil
local talking: { [Player]: boolean } = {}

local LUNCH = {
	"Maya: There you are. Sit, sit. It's still warm.",
	"Maya: Mushroom stew. My grandmother's recipe, mostly.",
	"Maya: Take the rest home. The radio says it'll be a cold night.",
	"Maya: Head back before it gets dark, okay? I'll call you.",
}
local SMALL_TALK = {
	"Maya: Caramelo stole a sock from my porch again.",
	"Maya: I keep a lamp in the upstairs window. If you see it, I'm fine.",
	"Maya: The lake was so still this morning. Like glass.",
	"Maya: Come by tomorrow? I'm trying bread.",
}

function MayaService.house(): Model?
	return house
end

-- A line from Maya over the radio: everyone hears it, with static.
function MayaService.radio(text: string)
	Net.event("Radio"):FireAllClients("Maya: " .. text)
	Net.event("SoundCue"):FireAllClients("radioStatic", nil, 0.35)
end

function MayaService.setRoom(room: string, on: boolean)
	local h = house
	if h then
		HouseActivityService.setRoomIn(h, room, on)
	end
end

local function spotCFrame(name: string): CFrame?
	local h = house
	if not h then
		return nil
	end
	for _, d in h:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "MayaSpot" and d:GetAttribute("Spot") == name then
			return d.CFrame
		end
	end
	return nil
end

-- Maya stands at a spot. Her root is anchored: she never wanders off a ledge.
function MayaService.goTo(spotName: string)
	local m, cf = npc, spotCFrame(spotName)
	if not m or not cf then
		return
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	local lift = if hum then hum.HipHeight + (m.PrimaryPart :: BasePart).Size.Y / 2 else 3
	m:PivotTo(cf + Vector3.new(0, lift, 0))
	m:SetAttribute("Spot", spotName)
end

local function playerNear(pos: Vector3, radius: number): boolean
	for _, s in PlayerService.all() do
		local r = PlayerService.root(s.player)
		if r and (r.Position - pos).Magnitude < radius then
			return true
		end
	end
	return false
end

-- She only changes place when nobody is close enough to see her pop.
local function moveWhenUnseen(spotName: string)
	task.spawn(function()
		local h = house
		if not h then
			return
		end
		for _ = 1, 120 do
			if not playerNear(h:GetPivot().Position, 70) then
				break
			end
			task.wait(2)
		end
		MayaService.goTo(spotName)
	end)
end

local function buildNpc(h: Model): Model?
	local desc = Instance.new("HumanoidDescription")
	desc.HairAccessory = HAIR
	local skin = Color3.fromRGB(226, 182, 150)
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = Color3.fromRGB(176, 120, 72) -- mustard sweater
	desc.LeftLegColor = Color3.fromRGB(48, 58, 82) -- jeans
	desc.RightLegColor = Color3.fromRGB(48, 58, 82)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[Maya] could not build her rig: " .. tostring(model))
		return nil
	end
	local m: Model = model
	m.Name = "Maya"
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.BreakJointsOnDeath = false
	end
	local root = m.PrimaryPart
	if root then
		root.Anchored = true
	end
	CollectionService:AddTag(m, "Maya")
	m.Parent = h
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = IDLE
		local okTrack, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if okTrack and track then
			track.Looped = true
			track:Play()
		end
	end
	return m
end

local function say(player: Player, lines: { string })
	if talking[player] then
		return
	end
	talking[player] = true
	task.spawn(function()
		for _, line in lines do
			Net.event("Radio"):FireClient(player, line)
			task.wait(3.6)
		end
		talking[player] = nil
	end)
end

local function onTalk(player: Player)
	if not StoryService.getFact("talkedToMaya") then
		say(player, LUNCH)
		PlayerService.give(player, "Stew", 1)
		StoryService.setFact("talkedToMaya", true)
		Net.event("Notify"):FireClient(player, "+1 Warm stew. Eat it from your pack (P).", "good")
	else
		say(player, { SMALL_TALK[math.random(1, #SMALL_TALK)] })
	end
	PlayerService.markRoutine(player, "maya")
end

local function onPhase(snap: any)
	if snap.phase == "Day" then
		MayaService.setRoom("Upstairs", false)
		MayaService.setRoom("Downstairs", false)
		moveWhenUnseen("Kitchen")
	elseif snap.phase == "Dusk" then
		MayaService.setRoom("Downstairs", true)
		moveWhenUnseen("Window")
	elseif snap.phase == "Night" then
		MayaService.setRoom("Upstairs", true)
		moveWhenUnseen("Upstairs")
	elseif snap.phase == "Dawn" then
		MayaService.setRoom("Downstairs", false)
	end
end

function MayaService.start()
	local h = CollectionService:GetTagged("MayaHouse")[1]
	if not h or not h:IsA("Model") then
		warn("[Maya] no MayaHouse in the world")
		return
	end
	house = h
	npc = buildNpc(h)
	-- Without a rig the prompt sits on her table, so the visit still counts.
	local anchor: Instance? = if npc then npc.PrimaryPart else h:FindFirstChild("Table")
	if anchor then
		local prompt = Builder.prompt(anchor, "Talk", "Maya", 0, 10)
		prompt.Name = "MayaPrompt"
		prompt.Triggered:Connect(function(player)
			local r = PlayerService.root(player)
			if r and anchor:IsA("BasePart") and (r.Position - anchor.Position).Magnitude < 14 then
				onTalk(player)
			end
		end)
	end
	local snap = TimeService.snapshot()
	MayaService.goTo(if snap.phase == "Day" then "Kitchen" else "Window")
	TimeService.onPhaseChanged(onPhase)
	Players.PlayerRemoving:Connect(function(player)
		talking[player] = nil
	end)
end

return MayaService

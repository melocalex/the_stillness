--!strict
-- Server entry point: create remotes, build the world, start services in
-- dependency order. Players spawn when they press Play (RequestSpawn).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false

local Net = require(ReplicatedStorage.Shared.Net)
Net.setup()

local World = require(script.Parent.World)
local Services = script.Parent.Services
local TimeService = require(Services.TimeService)
local ShelterService = require(Services.ShelterService)
local LightService = require(Services.LightService)
local WeatherService = require(Services.WeatherService)
local PlayerService = require(Services.PlayerService)
local StoryService = require(Services.StoryService)
local InteractionService = require(Services.InteractionService)
local GatherService = require(Services.GatherService)
local CollectiveService = require(Services.CollectiveService)
local CreatureService = require(Services.CreatureService)
local NightDirector = require(Services.NightDirector)
local DogService = require(Services.DogService)
local HouseActivityService = require(Services.HouseActivityService)
local OldOneService = require(Services.OldOneService)
local ObservationService = require(Services.ObservationService)
local BuildService = require(Services.BuildService)
local ToolService = require(Services.ToolService)
local MayaService = require(Services.MayaService)
local OpeningService = require(Services.OpeningService)
local FearEcologyService = require(Services.FearEcologyService)
local ChaoticEnergyService = require(Services.ChaoticEnergyService)
local ProgressionService = require(Services.ProgressionService)
local DogTracking = require(Services.DogTracking)
local TownService = require(Services.TownService)
local IncidentService = require(Services.IncidentService)
local DebugService = require(Services.DebugService)
local TownWorld = require(script.Parent.World.Town)

local built = World.build()
ReplicatedStorage:SetAttribute("SpawnPoint", built.spawn)
-- Chapter 37 sites, before GatherService registers the trees they clear.
local townOk, townErr = pcall(TownWorld.build, built.root)
if not townOk then
	warn("[Main] town sites failed: " .. tostring(townErr))
end

local function start(name: string, fn: () -> ())
	local ok, err = pcall(fn :: any)
	if not ok then
		warn(string.format("[Main] %s failed to start: %s", name, tostring(err)))
	end
end

start("Time", TimeService.start)
start("Shelter", ShelterService.start)
start("Light", LightService.start)
start("Weather", WeatherService.start)
start("Player", PlayerService.start)
start("Story", StoryService.start)
start("Interaction", InteractionService.start)
start("Gather", GatherService.start)
start("Tools", ToolService.start)
start("Collective", CollectiveService.start)
start("Creature", CreatureService.start)
start("Fear", FearEcologyService.start)
start("Night", NightDirector.start)
start("Dog", DogService.start)
start("House", HouseActivityService.start)
start("Maya", MayaService.start)
start("Opening", OpeningService.start)
start("Progression", ProgressionService.start)
start("DogTracking", DogTracking.start)
start("Town", TownService.start)
start("Incidents", IncidentService.start)
start("Debug", DebugService.start)
start("OldOne", OldOneService.start)
start("Observation", ObservationService.start)
start("Build", BuildService.start)
start("Dissonance", ChaoticEnergyService.start)

workspace:SetAttribute("WorldReady", true)
print("[Main] THE STILLNESS server ready")

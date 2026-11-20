--!strict
-- Client entry point: presentation and input only. The server owns the game.

local Controllers = script.Parent.Controllers
local UI = script.Parent.UI

local LightingController = require(Controllers.LightingController)
local WeatherController = require(Controllers.WeatherController)
local AudioController = require(Controllers.AudioController)
local InputController = require(Controllers.InputController)
local ObservationController = require(Controllers.ObservationController)
local BuildController = require(Controllers.BuildController)
local DogAnimator = require(Controllers.DogAnimator)
local CreatureAnimator = require(Controllers.CreatureAnimator)
local ChaoscopeController = require(Controllers.ChaoscopeController)
local TownFx = require(Controllers.TownFx)
local Prompts = require(UI.Prompts)
local HUD = require(UI.HUD)
local Panels = require(UI.Panels)
local LifeJournal = require(UI.LifeJournal)
local Menu = require(UI.Menu)

local function start(name: string, fn: () -> ())
	local ok, err = pcall(fn :: any)
	if not ok then
		warn(string.format("[Client] %s failed to start: %s", name, tostring(err)))
	end
end

start("Lighting", LightingController.start)
start("Weather", WeatherController.start)
start("Audio", AudioController.start)
start("Prompts", Prompts.start)
start("HUD", HUD.start)
start("Panels", Panels.start)
start("LifeJournal", LifeJournal.start)
start("Input", InputController.start)
start("Observation", ObservationController.start)
start("Build", BuildController.start)
start("DogAnimator", DogAnimator.start)
start("CreatureAnimator", CreatureAnimator.start)
start("Chaoscope", ChaoscopeController.start)
start("TownFx", TownFx.start)
InputController.setBuildToggle(BuildController.toggle)
-- Last: the menu waits for the world, then hands control to the player.
Menu.start()

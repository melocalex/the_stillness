--!strict
-- Studio-only test hooks. The Studio command bar cannot reach live game
-- modules (its require() returns fresh copies), so this exposes a few calls
-- through a BindableFunction. It is never created outside Studio.
--
-- Command bar (Server view):
--   local D = game.ServerStorage.StillnessDebug
--   print(D:Invoke("give", "Wood", 8))
--   print(D:Invoke("goto", "npc:frank"))       -- also site:, project:, interact:, missing:
--   print(D:Invoke("state"))                    -- quests, credits, projects, flags
--   print(D:Invoke("rejoin"))                   -- save data -> JSON -> fresh state
--   print(D:Invoke("incident", "fallen_branch"))
--   print(D:Invoke("phase", "Dusk"))

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local IncidentService = require(script.Parent.IncidentService)
local PlayerService = require(script.Parent.PlayerService)
local ProgressionService = require(script.Parent.ProgressionService)
local TimeService = require(script.Parent.TimeService)
local TownService = require(script.Parent.TownService)

local DebugService = {}

function DebugService.start()
	if not RunService:IsStudio() then
		return
	end
	local f = Instance.new("BindableFunction")
	f.Name = "StillnessDebug"
	f.OnInvoke = function(cmd: any, a: any, b: any): any
		local player = Players:GetPlayers()[1]
		if not player then
			return "no player"
		end
		if cmd == "give" and type(a) == "string" and type(b) == "number" then
			return PlayerService.give(player, a, b)
		elseif cmd == "goto" and type(a) == "string" then
			local at = TownService.locate(a, player)
			local root = PlayerService.root(player)
			local character = player.Character
			if at and root and character then
				local away = Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z)
				local dir = if away.Magnitude > 1 then away.Unit else Vector3.new(0, 0, 1)
				-- People: stand in front of them, not behind a wall.
				local npcId = string.match(a, "^npc:(.+)$")
				for _, m in CollectionService:GetTagged(if npcId == "maya" then "Maya" else "TownNpc") do
					if m:IsA("Model") and (npcId == "maya" or m:GetAttribute("Npc") == npcId) then
						local look = m:GetPivot().LookVector
						dir = Vector3.new(look.X, 0, look.Z).Unit
					end
				end
				local stand = at + dir * (if type(b) == "number" then b else 7) + Vector3.new(0, 3, 0)
				character:PivotTo(CFrame.lookAt(stand, Vector3.new(at.X, stand.Y, at.Z)))
				return tostring(at)
			end
			return "unknown " .. a
		elseif cmd == "state" then
			return ProgressionService.debugSummary(player)
		elseif cmd == "rejoin" then
			return ProgressionService.debugRejoin(player)
		elseif cmd == "incident" and type(a) == "string" then
			IncidentService.debugStart(a)
			return true
		elseif cmd == "phase" and type(a) == "string" then
			TimeService.skipToPhase(a :: any)
			return true
		end
		return "unknown command"
	end
	f.Parent = ServerStorage
end

return DebugService

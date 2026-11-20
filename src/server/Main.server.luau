--!strict
-- Server entry point: build the world, start services, spawn players when
-- they press Play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false

local World = require(script.Parent.World)
local TimeService = require(script.Parent.Services.TimeService)

local built = World.build()
TimeService.start()

workspace:SetAttribute("WorldReady", true)
ReplicatedStorage:SetAttribute("SpawnPoint", built.spawn)

local function spawnPlayer(player: Player)
	player:LoadCharacterAsync()
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(built.spawn) * CFrame.Angles(0, math.rad(200), 0))
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				task.wait(3)
				if player.Parent then
					spawnPlayer(player)
				end
			end)
		end
	end
end

Players.PlayerAdded:Connect(spawnPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(spawnPlayer, p)
end

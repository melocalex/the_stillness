--!strict
-- Builds the whole world once at server start.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local Builder = require(script.Builder)
local Terrain = require(script.Terrain)
local Cabin = require(script.Cabin)
local Forest = require(script.Forest)
local Landmarks = require(script.Landmarks)

local World = {}

export type Built = {
	root: Folder,
	cabin: Cabin.Built,
	lakeHouse: Model,
	abandonedHouse: Model,
	radioTower: Model,
	oldOne: Model,
	spawn: Vector3,
}

World.Terrain = Terrain

function World.build(): Built
	local started = os.clock()
	Terrain.generate()
	local root = Builder.folder("World", workspace)
	local W = WorldConfig
	local cabin = Cabin.build(root, Vector3.new(W.Cabin.x, W.Cabin.floorY, W.Cabin.z))
	Forest.build(Builder.folder("Forest", root), W.Seed)
	local lakeHouse = Landmarks.lakeHouse(root)
	local abandoned = Landmarks.abandonedHouse(root)
	local radio = Landmarks.radioTower(root)
	local oldOne = Landmarks.oldOne(root)
	Landmarks.boundary(root)
	local spawnPos = Vector3.new(W.Spawn.x, Terrain.heightAt(W.Spawn.x, W.Spawn.z) + 4, W.Spawn.z)
	print(string.format("[World] built in %.2fs", os.clock() - started))
	return {
		root = root,
		cabin = cabin,
		lakeHouse = lakeHouse,
		abandonedHouse = abandoned,
		radioTower = radio,
		oldOne = oldOne,
		spawn = spawnPos,
	}
end

return World

--!strict
-- Items, crafting recipes, buildables, and cabin upgrade costs. Pure data.

local ItemConfig = {}

ItemConfig.Items = {
	Wood = { name = "Wood", cap = 60, order = 1 },
	Stone = { name = "Stone", cap = 40, order = 2 },
	Fiber = { name = "Fiber", cap = 40, order = 3 },
	Scrap = { name = "Scrap metal", cap = 20, order = 4 },
	Berries = { name = "Berries", cap = 20, order = 5 },
	Mushroom = { name = "Mushroom", cap = 20, order = 6 },
	Stew = { name = "Warm stew", cap = 5, order = 7 },
	Binoculars = { name = "Binoculars", cap = 1, order = 8 },
} :: { [string]: { name: string, cap: number, order: number } }

export type Recipe = {
	id: string,
	name: string,
	cost: { [string]: number },
	gives: { [string]: number },
	station: string, -- "workbench" | "fireplace"
	description: string,
}

ItemConfig.Recipes = {
	{
		id = "stew",
		name = "Warm stew",
		cost = { Berries = 2, Mushroom = 1 },
		gives = { Stew = 1 },
		station = "fireplace",
		description = "Cook by the fire. Eat to restore stamina and comfort.",
	},
	{
		id = "binoculars",
		name = "Binoculars",
		cost = { Scrap = 3, Fiber = 2 },
		gives = { Binoculars = 1 },
		station = "workbench",
		description = "Better zoom when looking outside.",
	},
} :: { Recipe }

export type Buildable = {
	id: string,
	name: string,
	cost: { [string]: number },
	size: { number }, -- x, y, z studs
	color: { number },
	material: string,
	light: boolean?,
	comfort: boolean?,
}

ItemConfig.Buildables = {
	{
		id = "Wall",
		name = "Wooden wall",
		cost = { Wood = 4 },
		size = { 8, 8, 1 },
		color = { 110, 78, 52 },
		material = "WoodPlanks",
	},
	{
		id = "Floor",
		name = "Wooden floor",
		cost = { Wood = 3 },
		size = { 8, 0.6, 8 },
		color = { 120, 86, 58 },
		material = "WoodPlanks",
	},
	{
		id = "Fence",
		name = "Fence",
		cost = { Wood = 2 },
		size = { 8, 3, 0.6 },
		color = { 96, 70, 48 },
		material = "Wood",
	},
	{
		id = "Chair",
		name = "Chair",
		cost = { Wood = 3 },
		size = { 2.4, 3.6, 2.4 },
		color = { 118, 80, 50 },
		material = "Wood",
		comfort = true,
	},
	{
		id = "StorageBox",
		name = "Storage box",
		cost = { Wood = 4 },
		size = { 4, 2.4, 2.4 },
		color = { 98, 68, 44 },
		material = "WoodPlanks",
	},
	{
		id = "DogBed",
		name = "Dog bed",
		cost = { Wood = 2, Fiber = 3 },
		size = { 4, 0.8, 3 },
		color = { 140, 60, 50 },
		material = "Fabric",
		comfort = true,
	},
	{
		id = "Shelf",
		name = "Shelf",
		cost = { Wood = 3 },
		size = { 4, 5, 1.2 },
		color = { 104, 74, 50 },
		material = "Wood",
	},
	{
		id = "Lantern",
		name = "Lantern",
		cost = { Wood = 1, Scrap = 1 },
		size = { 1, 2, 1 },
		color = { 60, 56, 50 },
		material = "Metal",
		light = true,
	},
} :: { Buildable }

-- Cabin entry-point upgrades. Keyed by upgrade id.
ItemConfig.Upgrades = {
	RepairDoor = { name = "Repair door", cost = { Wood = 5 } },
	ReinforceDoor = { name = "Reinforce door", cost = { Wood = 4, Stone = 3, Scrap = 2 } },
	RepairWindow = { name = "Repair window", cost = { Wood = 2, Scrap = 1 } },
	ShutterWindow = { name = "Add shutters", cost = { Wood = 4, Fiber = 2 } },
	FuelFire = { name = "Add firewood", cost = { Wood = 2 } },
} :: { [string]: { name: string, cost: { [string]: number } } }

return ItemConfig

--!strict
-- Butcher's Hollow - server entry point. Builds the world, then hands over to
-- the story director.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent
local World = Server:WaitForChild("World")
local Systems = Server:WaitForChild("Systems")

require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")) -- create remotes first

local Terrain = require(World.Terrain)
local House = require(World.House)
local Sites = require(World.Sites)
local Forest = require(World.Forest)
local LightingSetup = require(World.Lighting)
local AssetService = require(Systems.AssetService)
local Inventory = require(Systems.Inventory)
local Hiding = require(Systems.Hiding)
local Cannibals = require(Systems.Cannibals)
local Story = require(Systems.Story)
local PlayerService = require(Systems.PlayerService)

local started = os.clock()

for _, group in { "Player", "NPC", "Door" } do
	pcall(function()
		PhysicsService:RegisterCollisionGroup(group)
	end)
end
PhysicsService:CollisionGroupSetCollidable("NPC", "Door", false)
PhysicsService:CollisionGroupSetCollidable("NPC", "NPC", false)

PlayerService.init()
Inventory.init()
Hiding.init()
Cannibals.init()
LightingSetup.apply()

AssetService.preload()
Terrain.generate()

local world = Instance.new("Folder")
world.Name = "World"
world.Parent = workspace

Forest.boundary(world)
local house = House.build(world)
local sites = Sites.build(world)
Forest.build(world)

AssetService.publishItemModels({
	"Flashlight",
	"HuntingKnife",
	"Battery",
	"Bandage",
	"HouseKey",
	"Syringe",
	"EngineBlock",
	"CarBattery",
	"SparkPlugs",
	"TireWheel",
	"CarKeys",
	"Fuse",
	"GasCan",
	"Note",
})
Cannibals.publishTemplates()

Story.init(house, sites, world)

workspace:SetAttribute("WorldReady", true)
print(string.format("[Butcher's Hollow] world ready in %.1fs", os.clock() - started))

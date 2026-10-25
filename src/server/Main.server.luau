--!strict
-- The Cannibal Family - server entry point. Builds the world, then hands over to
-- the story director.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent
local World = Server:WaitForChild("World")
local Systems = Server:WaitForChild("Systems")

-- The place ships with a baked copy of the world (tools/bake, or Server.Bake
-- in Studio) so it isn't empty in edit mode. Generation is deterministic, so
-- rebuilding it here gives the same world with every door and prompt wired.
for _, name in { "World", "Cannibals", "TerrainPreview" } do
	local baked = workspace:FindFirstChild(name)
	if baked then
		baked:Destroy()
	end
end

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

-- R6 bodies for everyone, before the lobby loads anyone in
require(Systems.R6Characters).init()

-- Public servers are the lobby (this call never returns there); party
-- servers and Studio-after-the-lobby carry on and build the game.
require(Server.Lobby).run()

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
if workspace:GetAttribute("TerrainBaked") ~= true then
	Terrain.generate()
end

local world = Instance.new("Folder")
world.Name = "World"
world.Parent = workspace

Forest.boundary(world)
local house = House.build(world)
require(World.HidingSpots).build(house, world) -- more places to hide in the house
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
	"BoltCutters",
	"GasCan",
	"Note",
})
Cannibals.publishTemplates()

Story.init(house, sites, world)

workspace:SetAttribute("WorldReady", true)
print(string.format("[Cannibal Family] world ready in %.1fs", os.clock() - started))

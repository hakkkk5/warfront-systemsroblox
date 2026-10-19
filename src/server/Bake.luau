--!strict
-- Builds the whole world into the place in Studio edit mode, with real smooth
-- terrain and the ForgeGUI meshes, so you can see and walk around it without
-- pressing Play. Run it once from the Command Bar (View > Command Bar), or
-- from a Studio MCP run_code call:
--
--     require(game.ServerScriptService.Server.Bake)()
--
-- then save the place. The game keeps the baked terrain and rebuilds the rest
-- when it starts (it comes out identical).

local RunService = game:GetService("RunService")

local World = script.Parent:WaitForChild("World")
local Systems = script.Parent:WaitForChild("Systems")

return function()
	assert(not RunService:IsRunning(), "Stop the game first - Bake runs in edit mode.")
	local started = os.clock()

	local Terrain = require(World.Terrain) :: any
	local House = require(World.House) :: any
	local Sites = require(World.Sites) :: any
	local Forest = require(World.Forest) :: any
	local LightingSetup = require(World.Lighting) :: any
	local AssetService = require(Systems.AssetService) :: any

	for _, name in { "World", "Cannibals", "TerrainPreview" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	LightingSetup.apply()
	AssetService.preload()
	print("[Bake] generating terrain...")
	Terrain.generate()
	workspace:SetAttribute("TerrainBaked", true)

	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	Forest.boundary(world)
	House.build(world)
	Sites.build(world)
	Forest.build(world)

	-- prompts are created again at runtime; leave them out of the saved place
	for _, d in world:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end

	print(string.format("[Bake] done in %.1fs - save the place (Ctrl+S).", os.clock() - started))
end

--!strict
-- Scatters the forest: pines (ForgeGUI mesh or procedural), oaks, dead
-- trees, bushes, rocks, logs, stumps and mushrooms. Keeps every site, road
-- and the lake clear.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)
local Terrain = require(script.Parent.Terrain)
local AssetService = require(script.Parent.Parent.Systems.AssetService)

local Forest = {}

local function clearOf(x: number, z: number, margin: number): boolean
	local p = Vector2.new(x, z)
	for _, site in Config.Sites do
		if (site.pos - p).Magnitude < site.radius + margin then
			return false
		end
	end
	for _, road in Config.Roads do
		local d = Util.polylineClosest(road.points, p)
		if d < road.width + margin then
			return false
		end
	end
	return true
end

-- Mesh trees get a thin invisible trunk collider instead of hull collisions
-- around the whole canopy.
local function prepareMeshTree(model: Model, parent: Instance, cf: CFrame, height: number)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = true
			p.CanTouch = false
		end
	end
	local trunk = Build.post(parent, height * 0.6, 2, cf * CFrame.new(0, height * 0.3, 0), Color3.new(), Enum.Material.SmoothPlastic, {
		Transparency = 1,
		CanQuery = false,
	})
	trunk.Name = "TrunkCollider"
end

function Forest.build(parent: Instance)
	local folder = Build.folder(parent, "Forest")
	local trees = Build.folder(folder, "Trees")
	local ground = Build.folder(folder, "Ground")
	local rng = Util.rng(Config.Map.Seed)
	local half = Config.Map.PlayHalf + 40
	local cell = 24
	local meshPine = AssetService.hasMesh("PineTree")
	local meshOak = AssetService.hasMesh("OakTree")
	local placed = 0

	for gx = -half, half, cell do
		for gz = -half, half, cell do
			local x = gx + rng:NextNumber(0, cell)
			local z = gz + rng:NextNumber(0, cell)
			if not Terrain.isWater(x, z) and clearOf(x, z, 7) then
				local roll = rng:NextNumber()
				local cf = Terrain.groundCFrame(x, z, rng:NextNumber(0, math.pi * 2))
				if roll < 0.66 then
					if meshPine then
						local tree = AssetService.create("PineTree", rng)
						local scale = rng:NextNumber(0.8, 1.25)
						tree:ScaleTo(tree:GetScale() * scale)
						tree:PivotTo(cf * CFrame.new(0, -0.6, 0))
						tree.Parent = trees
						prepareMeshTree(tree, trees, cf, 46 * scale)
					else
						local tree = Props.PineTree(rng)
						tree:PivotTo(cf * CFrame.new(0, -0.6, 0))
						tree.Parent = trees
					end
					placed += 1
				elseif roll < 0.7 then
					if meshOak then
						local tree = AssetService.create("OakTree", rng)
						local scale = rng:NextNumber(0.8, 1.15)
						tree:ScaleTo(tree:GetScale() * scale)
						tree:PivotTo(cf * CFrame.new(0, -0.5, 0))
						tree.Parent = trees
						prepareMeshTree(tree, trees, cf, 32 * scale)
					else
						local tree = Props.PineTree(rng)
						tree:PivotTo(cf * CFrame.new(0, -0.6, 0))
						tree.Parent = trees
					end
					placed += 1
				elseif roll < 0.76 then
					local tree = Props.DeadTree(rng)
					tree:PivotTo(cf * CFrame.new(0, -0.4, 0))
					tree.Parent = trees
				end
			end
		end
		task.wait()
	end

	-- undergrowth on a finer grid
	local small = 13
	for gx = -half, half, small do
		for gz = -half, half, small do
			local x = gx + rng:NextNumber(0, small)
			local z = gz + rng:NextNumber(0, small)
			if not Terrain.isWater(x, z) and clearOf(x, z, 3) then
				local roll = rng:NextNumber()
				local cf = Terrain.groundCFrame(x, z, rng:NextNumber(0, math.pi * 2))
				local m: Model? = nil
				if roll < 0.2 then
					m = Props.Bush(rng)
				elseif roll < 0.25 then
					m = Props.Rock(rng)
				elseif roll < 0.28 then
					m = Props.Log(rng)
				elseif roll < 0.32 then
					m = Props.Stump(rng)
				elseif roll < 0.36 then
					m = Props.Mushrooms(rng)
				end
				if m then
					m:PivotTo(cf * CFrame.new(0, -0.3, 0))
					m.Parent = ground
				end
			end
		end
		task.wait()
	end

	-- a ring of boulders along the shore of the lake
	local lake = Config.Lake
	for i = 0, 30 do
		local a = i / 31 * math.pi * 2
		local r = lake.radius * rng:NextNumber(0.72, 0.85)
		local x, z = lake.pos.X + math.cos(a) * r, lake.pos.Y + math.sin(a) * r
		if clearOf(x, z, 2) then
			local rock = Props.Rock(rng)
			rock:PivotTo(Terrain.groundCFrame(x, z, rng:NextNumber(0, 6)))
			rock.Parent = ground
		end
	end
	print(string.format("[Forest] placed %d trees", placed))
end

-- Invisible walls at the edge of the playable area.
function Forest.boundary(parent: Instance)
	local folder = Build.folder(parent, "Boundary")
	local h = Config.Map.PlayHalf
	for _, side in { -1, 1 } do
		for _, axis in { "X", "Z" } do
			local size = if axis == "X" then Vector3.new(4, 500, h * 2 + 8) else Vector3.new(h * 2 + 8, 500, 4)
			local pos = if axis == "X" then Vector3.new(side * h, 150, 0) else Vector3.new(0, 150, side * h)
			Build.part(folder, size, CFrame.new(pos), Color3.new(), Enum.Material.SmoothPlastic, {
				Transparency = 1,
				CanQuery = false,
			})
		end
	end
end

return Forest

--!strict
-- Puts the current farmhouse (with its wings) and the last act's places into
-- the baked edit-mode world, and dresses every stand-in in its Blender mesh
-- the way players see it, so Studio's edit view shows the real house instead
-- of grey boxes. The game rebuilds all of this when it starts, so it's only
-- for looking at; run it after importing new meshes or changing the house:
--
--     require(game.ServerScriptService.Server.BakePreview)()
--
-- then save the place. (The full bake, Server.Bake, also regenerates the
-- terrain and every site.)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local World = script.Parent:WaitForChild("World")

-- Edit mode can count as the client, where Net waits for the server's
-- remotes: hand it a folder with all of them (removed again afterwards).
local function stubRemotes(): Folder?
	if ReplicatedStorage:FindFirstChild("Remotes") then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	local source = (ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net") :: ModuleScript).Source
	for name in string.gmatch(source, "\n\t\"(%w+)\",") do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

-- Hides a dressed stand-in's own boxes (in the saved preview only).
local function hideStandIn(target: Instance)
	local baked = target:GetAttribute("MeshBaked") == true
	for _, d in target:GetDescendants() do
		if baked then
			if d:IsA("BasePart") and d:GetAttribute("Baked") then
				d.Transparency = 1
			end
		elseif d:IsA("BasePart") and not d:FindFirstAncestor("BlenderVisual") and not d:GetAttribute("KeepVisible") then
			d.Transparency = 1
		end
	end
	if target:IsA("BasePart") then
		target.Transparency = 1
	end
end

return function(): string
	assert(not RunService:IsRunning(), "Stop the game first - BakePreview runs in edit mode.")
	local started = os.clock()
	local stub = stubRemotes()
	local Config = require(ReplicatedStorage.Shared.Config) :: any
	local House = require(World.House) :: any
	local FinaleSites = require(World.FinaleSites) :: any

	local world = workspace:FindFirstChild("World")
	if not world then
		world = Instance.new("Folder")
		world.Name = "World"
		world.Parent = workspace
	end
	for _, name in { "CannibalHouse", "HeliCrash", "HollowMeats", "PinecrestChurch", "PlantItems", "ChurchItems" } do
		local old = world:FindFirstChild(name, true)
		if old then
			old:Destroy()
		end
	end
	task.wait()
	-- the house grew (HouseLayout) past the clearing the old bake flattened:
	-- level the ground under it, easing back into the hills around it
	local HouseLayout = require(ReplicatedStorage.Shared.HouseLayout) :: any
	local Terrain = require(World.Terrain) :: any
	local site = Config.Sites.House
	local hx0, hx1 = site.pos.X + HouseLayout.x(-68) - 10, site.pos.X + HouseLayout.x(68) + 10
	local hz0, hz1 = site.pos.Y + HouseLayout.z(-24) - 30, site.pos.Y + HouseLayout.z(24) + 10
	local floorY = Terrain.siteY("House")
	local margin, step = 26, 4
	local levelled = 0
	for wx = hx0 - margin, hx1 + margin, step do
		for wz = hz0 - margin, hz1 + margin, step do
			local dx = math.max(hx0 - wx, 0, wx - hx1)
			local dz = math.max(hz0 - wz, 0, wz - hz1)
			local d = math.sqrt(dx * dx + dz * dz)
			if d < margin then
				local current = Terrain.groundY(wx, wz)
				local t = d / margin
				local target = floorY + (current - floorY) * t * t * (3 - 2 * t)
				if current > target + 0.3 then
					workspace.Terrain:FillBlock(CFrame.new(wx, (target + current + 3) / 2, wz), Vector3.new(step, current + 3 - target, step), Enum.Material.Air)
					levelled += 1
				elseif current < target - 0.3 then
					workspace.Terrain:FillBlock(CFrame.new(wx, (current - 2 + target) / 2, wz), Vector3.new(step, target - current + 2, step), Enum.Material.Ground)
					levelled += 1
				end
			end
		end
		if levelled % 200 == 0 then
			task.wait()
		end
	end
	task.wait()
	House.build(world)
	task.wait()
	FinaleSites.build(world)
	task.wait()

	-- the old bake grew trees where the new places and trails are, and where
	-- the house now stands
	local clear: { { pos: Vector2, r: number } } = {}
	for _, name in { "HeliCrash", "Plant", "Church" } do
		local s = Config.Sites[name]
		table.insert(clear, { pos = s.pos, r = s.radius + 6 })
	end
	local cut = 0
	local forest = world:FindFirstChild("Forest")
	if forest then
		for _, d in forest:GetDescendants() do
			if d:IsA("Model") and d.Parent and d.Parent.Parent == forest then
				local p = d:GetPivot().Position
				local inHouse = p.X > hx0 - 8 and p.X < hx1 + 8 and p.Z > hz0 - 8 and p.Z < hz1 + 8
				if inHouse then
					d:Destroy()
					cut += 1
					continue
				end
				for _, c in clear do
					if (Vector2.new(p.X, p.Z) - c.pos).Magnitude < c.r then
						d:Destroy()
						cut += 1
						break
					end
				end
			end
		end
	end

	-- dress the stand-ins in their Blender meshes
	local libraryModule = StarterPlayer:FindFirstChild("MeshLibrary", true)
	local dressed, missing = 0, {}
	if libraryModule and libraryModule:IsA("ModuleScript") then
		local MeshLibrary = require(libraryModule) :: any
		for i, target in CollectionService:GetTagged("BlenderMesh") do
			if target:IsDescendantOf(world) then
				local ok, visual = pcall(MeshLibrary.upgrade, target)
				if ok and visual then
					hideStandIn(target)
					dressed += 1
				elseif typeof(target:GetAttribute("Mesh")) == "string" then
					missing[target:GetAttribute("Mesh")] = true
				end
				if i % 25 == 0 then
					task.wait()
				end
			end
		end
	end

	-- prompts are made again at runtime; keep them out of the saved place
	for _, d in world:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	if stub then
		stub:Destroy()
	end
	local names = {}
	for name in missing do
		table.insert(names, name)
	end
	table.sort(names)
	local message = string.format(
		"[BakePreview] house and last-act places rebuilt, %d stand-ins dressed in Blender meshes, %d trees cleared%s in %.1fs - save the place.",
		dressed,
		cut,
		if #names > 0 then " (no mesh yet: " .. table.concat(names, ", ") .. ")" else "",
		os.clock() - started
	)
	print(message)
	return message
end

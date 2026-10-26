--!strict
-- Thick bushes out in the woods you can crawl into and hide (Hiding, like
-- the wardrobes): a few round every place you'll be sent to and along the
-- way between them, so being chased outdoors isn't just running. The same
-- rule holds: if they see you go in, they drag you out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)
local Terrain = require(script.Parent.Terrain)
local Hiding = require(script.Parent.Parent.Systems.Hiding)

local Bushes = {}

local rgb = Color3.fromRGB
local CF = CFrame.new

-- the ones you only reach in the last act still get a few
local PER_SITE = 4
local BETWEEN = 3 -- along the way from one site to the next

local function clear(at: Vector3, folder: Instance): boolean
	local params = OverlapParams.new()
	params.RespectCanCollide = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	return #workspace:GetPartBoundsInBox(CF(at + Vector3.new(0, 3.5, 0)), Vector3.new(7, 5, 7), params) == 0
end

local function bush(folder: Instance, x: number, z: number, rng: Random)
	if Terrain.isWater(x, z) then
		return
	end
	local ground = Terrain.groundCFrame(x, z, rng:NextNumber() * math.pi * 2)
	if not clear(ground.Position, folder) then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Bush"
	-- a few overlapping leafy lumps you can walk into
	local greens = { rgb(38, 52, 32), rgb(46, 60, 36), rgb(32, 44, 28) }
	local core: Part? = nil
	for i = 1, 5 do
		local size = rng:NextNumber(3.6, 5.2)
		local offset = if i == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(-0.4, 0.6), rng:NextNumber(-2, 2))
		local lump = Build.part(model, Vector3.new(size, size * 0.8, size), ground * CF(offset + Vector3.new(0, size * 0.32, 0)), greens[rng:NextInteger(1, #greens)], Enum.Material.LeafyGrass, {
			Shape = Enum.PartType.Ball,
			CanCollide = false,
			CastShadow = true,
		})
		lump:SetAttribute("KeepVisible", true)
		if i == 1 then
			core = lump
		end
	end
	model.Parent = folder
	local center = core :: Part
	-- crouched in the middle; out the side you came in
	local inside = ground * CF(0, 1.6, 0)
	local exit = ground * CF(0, 3, 4.2)
	Hiding.add(center, inside, exit, "Bush")
end

function Bushes.build(world: Instance)
	local folder = Build.folder(world, "Bushes")
	local rng = Random.new(1971)
	local sites: { Vector2 } = {}
	for name, site in Config.Sites do
		if name ~= "House" then
			table.insert(sites, site.pos)
			for _ = 1, PER_SITE do
				local angle = rng:NextNumber() * math.pi * 2
				local r = site.radius + rng:NextNumber(6, 22)
				bush(folder, site.pos.X + math.cos(angle) * r, site.pos.Y + math.sin(angle) * r, rng)
			end
		end
	end
	-- and the way from the farmhouse out to each of them
	local house = Config.Sites.House
	for _, pos in sites do
		for i = 1, BETWEEN do
			local t = i / (BETWEEN + 1)
			local p = house.pos:Lerp(pos, t)
			local side = Vector2.new(-(pos - house.pos).Y, (pos - house.pos).X).Unit
			local spread = rng:NextNumber(8, 22) * (if rng:NextNumber() < 0.5 then -1 else 1)
			bush(folder, p.X + side.X * spread, p.Y + side.Y * spread, rng)
		end
	end
	return folder
end

return Bushes

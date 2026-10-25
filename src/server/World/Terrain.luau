--!strict
-- Procedural terrain: rolling forest hills, flattened clearings for every site,
-- dirt roads and trails, a lake and a mountain rim that keeps players inside.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local Terrain = {}

local RES = 4
local BASE_Y = -28

local sites = Config.Sites
local lake = Config.Lake
local water = Config.Map.WaterLevel

local function lowFreq(x: number, z: number): number
	return 9 + math.noise(x / 260, z / 260, 0.37) * 16 + math.noise(x / 115, z / 115, 2.31) * 6
end

local function detail(x: number, z: number): number
	return math.noise(x / 38, z / 38, 5.13) * 2.6 + math.noise(x / 13, z / 13, 7.77) * 0.7
end

type SiteInfo = { pos: Vector2, radius: number, height: number }
local siteList: { SiteInfo } = {}
for _, s in sites do
	table.insert(siteList, { pos = s.pos, radius = s.radius, height = lowFreq(s.pos.X, s.pos.Y) })
end

type RoadInfo = {
	points: { Vector2 },
	width: number,
	material: Enum.Material,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}
local roadList: { RoadInfo } = {}
for _, road in Config.Roads do
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in road.points do
		minX = math.min(minX, p.X)
		maxX = math.max(maxX, p.X)
		minZ = math.min(minZ, p.Y)
		maxZ = math.max(maxZ, p.Y)
	end
	local margin = road.width + 10
	table.insert(roadList, {
		points = road.points,
		width = road.width,
		material = road.material,
		minX = minX - margin,
		maxX = maxX + margin,
		minZ = minZ - margin,
		maxZ = maxZ + margin,
	})
end

-- Returns the flattened height and how strongly the point is inside a clearing.
local function siteBlend(x: number, z: number, h: number): (number, number)
	local inside = 0
	for _, s in siteList do
		local dx, dz = x - s.pos.X, z - s.pos.Y
		local d = math.sqrt(dx * dx + dz * dz)
		if d < s.radius then
			local t = Util.smoothstep(s.radius, s.radius * 0.62, d)
			h = Util.lerp(h, s.height, t)
			inside = math.max(inside, t)
		end
	end
	return h, inside
end

local function baseHeight(x: number, z: number): number
	local h = siteBlend(x, z, lowFreq(x, z))
	return h
end

export type Surface = {
	height: number,
	road: Enum.Material?,
	roadBlend: number,
	clearing: number,
}

-- Analytic surface description for any XZ point.
function Terrain.surface(x: number, z: number): Surface
	local h = lowFreq(x, z) + detail(x, z)

	local edge = math.max(math.abs(x), math.abs(z))
	if edge > 575 then
		local t = (edge - 575) / 55
		h += t * t * 24 + math.noise(x / 30, z / 30, 9.1) * 6 * math.min(t, 1)
	end

	local ldx, ldz = x - lake.pos.X, z - lake.pos.Y
	local ld = math.sqrt(ldx * ldx + ldz * ldz)
	if ld < lake.radius then
		h = Util.lerp(h, -9, Util.smoothstep(lake.radius, lake.radius * 0.55, ld))
	end

	local clearing
	h, clearing = siteBlend(x, z, h)

	local roadMat: Enum.Material? = nil
	local roadBlend = 0
	local p = Vector2.new(x, z)
	for _, road in roadList do
		if x >= road.minX and x <= road.maxX and z >= road.minZ and z <= road.maxZ then
			local d, cp = Util.polylineClosest(road.points, p)
			local w = road.width
			if d < w + 8 then
				local t = Util.smoothstep(w + 8, w * 0.7, d)
				if t > roadBlend then
					h = Util.lerp(h, baseHeight(cp.X, cp.Y) - 0.4, t)
					roadBlend = t
				end
				if d < w then
					roadMat = road.material
				end
			end
		end
	end

	return { height = h, road = roadMat, roadBlend = roadBlend, clearing = clearing }
end

-- Water only fills the lake basin; low ground elsewhere stays dry.
local function inLake(x: number, z: number): boolean
	local dx, dz = x - lake.pos.X, z - lake.pos.Y
	return dx * dx + dz * dz < (lake.radius * 0.92) ^ 2
end

function Terrain.isWater(x: number, z: number): boolean
	return inLake(x, z) and Terrain.height(x, z) < water
end

function Terrain.height(x: number, z: number): number
	return Terrain.surface(x, z).height
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace.Terrain }

-- Exact ground height from the generated voxels (falls back to the analytic
-- height before generation).
function Terrain.groundY(x: number, z: number): number
	local result = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -500, 0), rayParams)
	if result then
		return result.Position.Y
	end
	return Terrain.height(x, z)
end

function Terrain.groundCFrame(x: number, z: number, yaw: number?): CFrame
	return CFrame.new(x, Terrain.groundY(x, z), z) * CFrame.Angles(0, yaw or 0, 0)
end

function Terrain.siteY(name: string): number
	local s = sites[name]
	return Terrain.groundY(s.pos.X, s.pos.Y)
end

local function pickMaterial(x: number, z: number, s: Surface, slope: number): Enum.Material
	if s.road then
		if s.road == Enum.Material.Asphalt then
			if math.noise(x / 9, z / 9, 1.9) > 0.42 then
				return Enum.Material.Ground
			end
			return Enum.Material.Asphalt
		end
		if math.noise(x / 7, z / 7, 4.4) > 0.3 then
			return Enum.Material.Mud
		end
		return s.road
	end
	if slope > 1.05 then
		return if math.noise(x / 20, z / 20, 6.6) > 0 then Enum.Material.Rock else Enum.Material.Slate
	end
	if s.height < water + 1.2 and s.height > water - 6 and inLake(x, z) then
		return if math.noise(x / 16, z / 16, 2.2) > 0.1 then Enum.Material.Mud else Enum.Material.Ground
	end
	if s.roadBlend > 0.35 then
		return Enum.Material.Ground
	end
	if s.clearing > 0.55 then
		local n = math.noise(x / 14, z / 14, 8.8)
		if n > 0.25 then
			return Enum.Material.Mud
		elseif n > -0.2 then
			return Enum.Material.Ground
		end
		return Enum.Material.LeafyGrass
	end
	local n = math.noise(x / 45, z / 45, 3.3)
	if n > 0.28 then
		return Enum.Material.LeafyGrass
	elseif n < -0.32 then
		return Enum.Material.Ground
	end
	return Enum.Material.Grass
end

function Terrain.generate()
	local terrain = workspace.Terrain
	terrain:Clear()

	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(48, 58, 36))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(56, 60, 34))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(62, 50, 38))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(46, 36, 28))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(78, 78, 76))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(64, 66, 66))
	terrain:SetMaterialColor(Enum.Material.Asphalt, Color3.fromRGB(42, 42, 44))
	terrain.WaterColor = Color3.fromRGB(16, 26, 28)
	terrain.WaterTransparency = 0.35
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 6

	local half = Config.Map.TerrainHalf
	local cols = math.floor(2 * half / RES)
	local CHUNK = 30
	local chunks = math.ceil(cols / CHUNK)

	for cx = 0, chunks - 1 do
		for cz = 0, chunks - 1 do
			local nx = math.min(CHUNK, cols - cx * CHUNK)
			local nz = math.min(CHUNK, cols - cz * CHUNK)
			local x0 = -half + cx * CHUNK * RES
			local z0 = -half + cz * CHUNK * RES

			-- heights with a one-column border for slope estimation
			local heights: { { number } } = {}
			local surfaces: { { Surface } } = {}
			local wet: { { boolean } } = {}
			local maxH = water
			for i = 0, nx + 1 do
				heights[i] = {}
				surfaces[i] = {}
				wet[i] = {}
				for k = 0, nz + 1 do
					local x = x0 + (i - 0.5) * RES
					local z = z0 + (k - 0.5) * RES
					local s = Terrain.surface(x, z)
					surfaces[i][k] = s
					heights[i][k] = s.height
					wet[i][k] = inLake(x, z)
					if i >= 1 and i <= nx and k >= 1 and k <= nz then
						maxH = math.max(maxH, s.height)
					end
				end
			end

			local ny = math.ceil((maxH - BASE_Y) / RES) + 1
			local materials: { { { Enum.Material } } } = {}
			local occupancy: { { { number } } } = {}
			for i = 1, nx do
				local mi: { { Enum.Material } } = {}
				local oi: { { number } } = {}
				materials[i] = mi
				occupancy[i] = oi
				local x = x0 + (i - 0.5) * RES
				local surfMat: { Enum.Material } = {}
				for k = 1, nz do
					local z = z0 + (k - 0.5) * RES
					local slope = math.max(
						math.abs(heights[i + 1][k] - heights[i - 1][k]),
						math.abs(heights[i][k + 1] - heights[i][k - 1])
					) / (2 * RES)
					surfMat[k] = pickMaterial(x, z, surfaces[i][k], slope)
				end
				for j = 1, ny do
					local yb = BASE_Y + (j - 1) * RES
					local mj: { Enum.Material } = {}
					local oj: { number } = {}
					mi[j] = mj
					oi[j] = oj
					for k = 1, nz do
						local h = heights[i][k]
						local fill = (h - yb) / RES
						if fill > 0 then
							local depth = h - yb
							if depth < RES * 2 then
								mj[k] = surfMat[k]
							elseif depth < RES * 5 then
								mj[k] = Enum.Material.Ground
							else
								mj[k] = Enum.Material.Rock
							end
							oj[k] = math.min(fill, 1)
						elseif yb < water and wet[i][k] then
							mj[k] = Enum.Material.Water
							oj[k] = math.clamp((water - yb) / RES, 0, 1)
						else
							mj[k] = Enum.Material.Air
							oj[k] = 0
						end
					end
				end
			end

			local region = Region3.new(
				Vector3.new(x0, BASE_Y, z0),
				Vector3.new(x0 + nx * RES, BASE_Y + ny * RES, z0 + nz * RES)
			)
			terrain:WriteVoxels(region, RES, materials, occupancy)
			-- a breath between chunks so the server keeps ticking (players
			-- saw a frozen game while the whole map was built in one go)
			task.wait()
		end
	end
end

return Terrain

-- Bake entry point (appended after runtime.luau and the bundled modules by
-- bake.py). Runs the real world builders and prints Rojo .model.json files.

local runtime = BAKE_RUNTIME
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server

require(ReplicatedStorage.Shared.Net)
local Terrain = require(Server.World.Terrain)
local House = require(Server.World.House)
local Sites = require(Server.World.Sites)
local Forest = require(Server.World.Forest)
local AssetService = require(Server.Systems.AssetService)
local Cannibals = require(Server.Systems.Cannibals)
local Story = require(Server.Systems.Story)

local started = os.clock()
AssetService.preload()
Terrain.generate()
local world = Instance.new("Folder")
world.Name = "World"
world.Parent = workspace
Forest.boundary(world)
local house = House.build(world)
local sites = Sites.build(world)
Forest.build(world)
Story.init(house, sites, world)

-- the family, standing where they start (preview only; the game spawns the
-- real ones when their chapter begins)
local previews = {
	{ "Butcher", CFrame.lookAt(house.groundPatrol[1], house.groundPatrol[2]) },
	{ "Brother", CFrame.lookAt(house.upperPatrol[1], house.upperPatrol[2]) },
	{ "Hunter", CFrame.new(sites.patrols.Hunter[1]) },
	{ "Scavenger", CFrame.new(sites.patrols.Scavenger[1]) },
	{ "Papa", sites.wreck * CFrame.new(0, 0, 30) },
}
for _, entry in previews do
	local c = Cannibals.spawn(entry[1], entry[2], { patrol = {} })
	c.alive = false
end
io_stderr(string.format("built in %.1fs, %d warnings", os.clock() - started, runtime.warnings or 0))

---------------------------------------------------------------- serialisation

local function num(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end
	local s = string.format("%.4f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	if s == "-0" then
		s = "0"
	end
	return s
end

local function str(s: string): string
	s = string.gsub(s, '[%c"\\]', function(c)
		if c == "\n" then
			return "\\n"
		elseif c == '"' then
			return '\\"'
		elseif c == "\\" then
			return "\\\\"
		elseif c == "\t" then
			return "\\t"
		end
		return string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. s .. '"'
end

local FONTS = {
	SpecialElite = { "SpecialElite", "Regular" },
	IndieFlower = { "IndieFlower", "Regular" },
	GothamBlack = { "GothamSSm", "Heavy" },
	GothamBold = { "GothamSSm", "Bold" },
	GothamMedium = { "GothamSSm", "Medium" },
	Creepster = { "Creepster", "Regular" },
}

local SKIP_CLASSES = {
	ProximityPrompt = true,
	NumberValue = true,
	PathfindingModifier = true,
	Motor6D = true,
	WeldConstraint = true,
	Weld = true,
	Humanoid = true,
	Animator = true,
	Animation = true,
	HumanoidDescription = true,
	RemoteEvent = true,
}

local SKIP_PROPS = {
	Parent = true,
	Name = true,
	PrimaryPart = true,
	Adornee = true,
	Part0 = true,
	Part1 = true,
	C0 = true,
	C1 = true,
}

local function value(className: string, key: string, v: any): (string?, string?)
	local t = typeof(v)
	if t == "boolean" then
		return key, if v then "true" else "false"
	elseif t == "number" then
		return key, num(v)
	elseif t == "string" then
		return key, str(v)
	elseif t == "Vector3" then
		return key, "[" .. num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z) .. "]"
	elseif t == "Vector2" then
		return key, "[" .. num(v.X) .. "," .. num(v.Y) .. "]"
	elseif t == "Color3" then
		return key, "[" .. num(v.R) .. "," .. num(v.G) .. "," .. num(v.B) .. "]"
	elseif t == "UDim2" then
		return key, '{"UDim2":[[' .. num(v.X.Scale) .. "," .. num(v.X.Offset) .. "],[" .. num(v.Y.Scale) .. "," .. num(v.Y.Offset) .. "]]}"
	elseif t == "CFrame" then
		local body = '{"position":[' .. num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z) .. '],"orientation":[['
			.. num(v.r00) .. "," .. num(v.r01) .. "," .. num(v.r02) .. "],["
			.. num(v.r10) .. "," .. num(v.r11) .. "," .. num(v.r12) .. "],["
			.. num(v.r20) .. "," .. num(v.r21) .. "," .. num(v.r22) .. "]]}"
		if key == "WorldPivot" then
			return "WorldPivotData", '{"OptionalCFrame":' .. body .. "}"
		end
		return key, '{"CFrame":' .. body .. "}"
	elseif t == "EnumItem" then
		if key == "Font" then
			local f = FONTS[v.Name] or { v.Name, "Regular" }
			return "FontFace", '{"Font":{"family":"rbxasset://fonts/families/' .. f[1] .. '.json","weight":"' .. f[2] .. '","style":"Normal"}}'
		end
		return key, str(v.Name)
	end
	return nil, nil
end

local function attributeValue(v: any): string?
	local t = typeof(v)
	if t == "string" then
		return '{"String":' .. str(v) .. "}"
	elseif t == "boolean" then
		return '{"Bool":' .. (if v then "true" else "false") .. "}"
	elseif t == "number" then
		return '{"Float64":' .. num(v) .. "}"
	end
	return nil
end

local function encode(inst: any, out: { string }, anchorAll: boolean)
	local className = inst.ClassName
	table.insert(out, '{"Name":' .. str(inst.Name) .. ',"ClassName":' .. str(className) .. ',"Properties":{')
	local first = true
	local props = rawget(inst, "__props")
	local keys = {}
	for k in props do
		table.insert(keys, k)
	end
	table.sort(keys)
	local function add(k: string, v: string)
		table.insert(out, (if first then "" else ",") .. str(k) .. ":" .. v)
		first = false
	end
	for _, k in keys do
		if not SKIP_PROPS[k] and string.sub(k, 1, 2) ~= "__" then
			local v = props[k]
			if anchorAll and k == "Anchored" then
				v = true
			end
			local outKey, encoded = value(className, k, v)
			if outKey and encoded then
				add(outKey, encoded)
			end
		end
	end
	if anchorAll and inst:IsA("BasePart") and props.Anchored == nil then
		add("Anchored", "true")
	end
	local tags = {}
	for tag in rawget(inst, "__tags") do
		table.insert(tags, str(tag))
	end
	if #tags > 0 then
		table.sort(tags)
		add("Tags", "[" .. table.concat(tags, ",") .. "]")
	end
	local attrs = {}
	for k, v in rawget(inst, "__attrs") do
		local encoded = attributeValue(v)
		if encoded then
			table.insert(attrs, str(k) .. ":" .. encoded)
		end
	end
	if #attrs > 0 then
		table.sort(attrs)
		add("Attributes", '{"Attributes":{' .. table.concat(attrs, ",") .. "}}")
	end
	table.insert(out, '},"Children":[')
	local firstChild = true
	for _, child in rawget(inst, "__children") do
		if not SKIP_CLASSES[child.ClassName] then
			if not firstChild then
				table.insert(out, ",")
			end
			firstChild = false
			encode(child, out, anchorAll)
		end
	end
	table.insert(out, "]}")
end

local function emit(name: string, inst: any, anchorAll: boolean)
	local out = {}
	encode(inst, out, anchorAll)
	print("<<<FILE " .. name .. ">>>")
	print(table.concat(out))
	print("<<<END>>>")
end

-- R6 preview rigs are only positioned through their joints; resolve them so
-- the anchored statues stand correctly.
local function solveJoints(root: any)
	for _ = 1, 4 do
		for _, d in root:GetDescendants() do
			if d.ClassName == "Motor6D" or d.ClassName == "Weld" then
				local p0, p1 = d.Part0, d.Part1
				if p0 and p1 then
					p1.CFrame = p0.CFrame * (d.C0 or CFrame.new()) * (d.C1 or CFrame.new()):Inverse()
				end
			end
		end
	end
end

local cannibalFolder = workspace:FindFirstChild("Cannibals")
solveJoints(cannibalFolder)

emit("World", world, false)
emit("Cannibals", cannibalFolder, true)

---------------------------------------------------------------- terrain preview

-- column heights from the recorded WriteVoxels calls
local heights: { [number]: { [number]: { h: number, mat: string, water: number? } } } = {}
for _, write in runtime.voxelWrites do
	local lo = write.region[1]
	local res = write.res
	for i, column in write.materials do
		for k = 1, #column[1] do
			local top: number? = nil
			local mat = "Grass"
			local water: number? = nil
			for j = #column, 1, -1 do
				local m = column[j][k]
				local o = write.occupancy[i][j][k]
				if m.Name == "Water" and o > 0 and water == nil then
					water = lo.Y + (j - 1) * res + o * res
				elseif m.Name ~= "Air" and m.Name ~= "Water" and o > 0 then
					top = lo.Y + (j - 1) * res + o * res
					mat = m.Name
					break
				end
			end
			local cx = math.floor((lo.X + (i - 0.5) * res) / res)
			local cz = math.floor((lo.Z + (k - 0.5) * res) / res)
			heights[cx] = heights[cx] or {}
			heights[cx][cz] = { h = top or lo.Y, mat = mat, water = water }
		end
	end
end

local function cell(x: number, z: number)
	local col = heights[math.floor(x / 4)]
	return col and col[math.floor(z / 4)]
end
local function hAt(x: number, z: number): number
	local c = cell(x, z)
	return if c then c.h else 0
end

local preview = Instance.new("Folder")
preview.Name = "TerrainPreview"
local TILE = 16
local half = 720
local colors = runtime.materialColors
for x = -half + TILE / 2, half - TILE / 2, TILE do
	for z = -half + TILE / 2, half - TILE / 2, TILE do
		local c = cell(x, z)
		if c then
			local h = (hAt(x - TILE / 2, z) + hAt(x + TILE / 2 - 1, z) + hAt(x, z - TILE / 2) + hAt(x, z + TILE / 2 - 1) + c.h * 2) / 6
			local gx = (hAt(x + TILE / 2 - 1, z) - hAt(x - TILE / 2, z)) / TILE
			local gz = (hAt(x, z + TILE / 2 - 1) - hAt(x, z - TILE / 2)) / TILE
			local up = Vector3.new(-gx, 1, -gz).Unit
			local right = Vector3.new(1, gx, 0).Unit
			local back = right:Cross(up).Unit
			right = up:Cross(back).Unit
			-- thicken steep tiles so neighbouring slabs overlap instead of
			-- leaving stair-step gaps on the mountain rim
			local steep = math.max(math.abs(gx), math.abs(gz)) * TILE
			local thickness = 6 + steep * 1.6
			local tile = Instance.new("Part")
			tile.Name = "Ground"
			tile.Anchored = true
			tile.Size = Vector3.new(TILE + 2, thickness, TILE + 2)
			tile.CFrame = CFrame.fromMatrix(Vector3.new(x, h - thickness / 2, z), right, up, back)
			tile.Material = Enum.Material[c.mat]
			tile.Color = colors[c.mat] or Color3.fromRGB(70, 66, 52)
			tile.TopSurface = Enum.SurfaceType.Smooth
			tile.BottomSurface = Enum.SurfaceType.Smooth
			tile.Parent = preview
			if c.water and c.water > h then
				local water = Instance.new("Part")
				water.Name = "Water"
				water.Anchored = true
				water.CanCollide = false
				water.Size = Vector3.new(TILE, 0.4, TILE)
				water.CFrame = CFrame.new(x, c.water, z)
				water.Material = Enum.Material.Glass
				water.Transparency = 0.35
				water.Color = Color3.fromRGB(16, 26, 28)
				water.Parent = preview
			end
		end
	end
end
emit("TerrainPreview", preview, false)

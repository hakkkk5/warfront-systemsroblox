-- Model export entry point (appended after runtime.luau and the bundled
-- modules by export_models.py). Builds every procedural prop, the house and
-- each site on its own, moves it to the origin and prints one Rojo
-- .model.json per model, plus a META line with its stats.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

---------------------------------------------------------------- engine fix-up

-- Two engine behaviours the mock skips, which the exported pivots need:
--  * PivotTo moves every descendant PVInstance, so nested models (the
--    cleaver on the butcher table, the lanterns in the sites...) keep their
--    pivots on their parts. The mock only moves the parts.
--  * A model whose pivot the code never sets (doors, the house's Structure
--    and Furniture, the helicopter's Rotor) pivots about its bounding box
--    centre. The mock uses the world origin.
local IMT = getmetatable(Instance.new("Folder"))
local index, newindex = IMT.__index, IMT.__newindex
local unpivoted = setmetatable({}, { __mode = "k" }) -- models with no pivot set yet
local newInstance = Instance.new
Instance.new = function(className: string, parent: any?)
	local inst = newInstance(className, parent)
	if className == "Model" then
		unpivoted[inst] = true
	end
	return inst
end

local function pivotOf(inst: any): CFrame
	if unpivoted[inst] then
		return (inst:GetBoundingBox())
	end
	return inst:GetPivot()
end

local function pivotTo(inst: any, target: CFrame)
	if inst:IsA("BasePart") then
		inst.CFrame = target
		return
	end
	local delta = target * pivotOf(inst):Inverse()
	for _, d in inst:GetDescendants() do
		local props = rawget(d, "__props")
		if d:IsA("BasePart") then
			props.CFrame = delta * props.CFrame
		elseif d:IsA("Model") and not props.PrimaryPart and not unpivoted[d] then
			props.WorldPivot = delta * props.WorldPivot
		end
	end
	rawget(inst, "__props").WorldPivot = target
	unpivoted[inst] = nil
end

local function clone(inst: any): any
	local copy = index(inst, "Clone")(inst)
	local from, to = inst:GetDescendants(), copy:GetDescendants()
	table.insert(from, inst)
	table.insert(to, copy)
	for i, d in from do
		unpivoted[to[i]] = unpivoted[d]
	end
	return copy
end

IMT.__index = function(inst, k)
	if k == "PivotTo" then
		return pivotTo
	elseif k == "Clone" then
		return clone
	end
	return index(inst, k)
end
IMT.__newindex = function(inst, k, v)
	if k == "WorldPivot" or k == "PrimaryPart" then
		unpivoted[inst] = nil
	end
	newindex(inst, k, v)
end

require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Props = require(Server.World.Props)
local Terrain = require(Server.World.Terrain)
local House = require(Server.World.House)
local Sites = require(Server.World.Sites)

---------------------------------------------------------------- serialisation
-- (from main.luau, plus: root Name left to the file name, every part
-- anchored, models written with their real pivot, and nothing dropped
-- silently)

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

-- runtime objects the game's scripts drive; they do nothing in a model file
local SKIP_CLASSES = {
	ProximityPrompt = true,
	NumberValue = true,
	PathfindingModifier = true,
	Humanoid = true,
	Animator = true,
	Animation = true,
	HumanoidDescription = true,
	RemoteEvent = true,
}

-- Rojo 7.4 .model.json files cannot express Ref properties, so a joint would
-- lose its Part0/Part1. No builder uses one; refuse rather than write a
-- broken weld.
local JOINTS = { Motor6D = true, Weld = true, WeldConstraint = true }

local SKIP_PROPS = {
	Parent = true,
	Name = true,
	PrimaryPart = true,
	Adornee = true,
	WorldPivot = true, -- written from GetPivot() below
}

local dropped: { [string]: boolean } = {}

local function value(key: string, v: any): (string?, string?)
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

local function encode(inst: any, out: { string }, isRoot: boolean)
	local className = inst.ClassName
	if JOINTS[className] then
		error(inst:GetFullName() .. " is a " .. className .. ": Rojo 7.4 model files cannot keep its Part0/Part1")
	end
	-- the root takes its name from the file / project
	table.insert(out, (if isRoot then "{" else '{"Name":' .. str(inst.Name) .. ",") .. '"ClassName":' .. str(className) .. ',"Properties":{')
	local first = true
	local function add(k: string, v: string)
		table.insert(out, (if first then "" else ",") .. str(k) .. ":" .. v)
		first = false
	end
	local props = rawget(inst, "__props")
	local keys = {}
	for k in props do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in keys do
		if not SKIP_PROPS[k] and string.sub(k, 1, 2) ~= "__" then
			-- static props: every part anchored (joints were refused above)
			local v = if k == "Anchored" and inst:IsA("BasePart") then true else props[k]
			local outKey, encoded = value(k, v)
			if outKey and encoded then
				add(outKey, encoded)
			else
				dropped[className .. "." .. k .. " (" .. typeof(v) .. ")"] = true
			end
		end
	end
	if inst:IsA("BasePart") and props.Anchored == nil then
		add("Anchored", "true")
	end
	if inst:IsA("Model") then
		-- the effective pivot, so a model with a PrimaryPart (which a Ref
		-- cannot carry) still drops in with the right pivot
		local _, encoded = value("WorldPivot", pivotOf(inst))
		add("WorldPivotData", encoded :: string)
		if props.PrimaryPart then
			dropped[className .. ".PrimaryPart (written as WorldPivot)"] = true
		end
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
		if not encoded then
			error(inst:GetFullName() .. " attribute " .. k .. " has unsupported type " .. typeof(v))
		end
		table.insert(attrs, str(k) .. ":" .. encoded)
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
			encode(child, out, false)
		end
	end
	table.insert(out, "]}")
end

local function countParts(inst: any): number
	local n = 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function emit(file: string, inst: any, kind: string, seed: number?)
	local out = {}
	encode(inst, out, true)
	print("<<<FILE " .. file .. ">>>")
	print(table.concat(out))
	print("<<<END>>>")
	local _, size = inst:GetBoundingBox()
	print(string.format(
		'<<<META {"file":%s,"name":%s,"kind":%s,"seed":%s,"parts":%d,"size":[%s,%s,%s]}>>>',
		str(file), str(inst.Name), str(kind), if seed then tostring(seed) else "null",
		countParts(inst), num(size.X), num(size.Y), num(size.Z)
	))
end

---------------------------------------------------------------- props

local SEED = 1
local VARIANT_SEEDS = 16
local RNG = {} -- stands for Util.rng(seed) in an argument list

-- Every Props builder and what to call it with. A prop is named after its
-- Mesh attribute when it has one, so rng builders that pick a mesh variant
-- (DeadTree2, Rock2, GraveCross) are exported once per variant, each from
-- the first seed (SEED, SEED + 1, ...) that produces it.
local PROPS = {
	-- vegetation
	{ "PineTree", RNG },
	{ "DeadTree", RNG },
	{ "Bush", RNG },
	{ "Rock", RNG },
	{ "Log", RNG },
	{ "Stump", RNG },
	{ "Mushrooms", RNG },
	-- vehicles
	{ "PickupTruck" },
	{ "CrashedSedan" },
	-- items
	{ "EngineBlock" },
	{ "CarBattery" },
	{ "SparkPlugs" },
	{ "TireWheel" },
	{ "Syringe" },
	{ "CarKeys" },
	{ "HuntingKnife" },
	{ "Flashlight" },
	{ "Battery" },
	{ "Bandage" },
	{ "HouseKey" },
	{ "Fuse" },
	{ "GasCan" },
	{ "Note" },
	-- weapons / gear
	{ "Cleaver" },
	{ "Chainsaw" },
	{ "Lantern" },
	-- furniture / house props
	{ "ButcherTable", RNG },
	{ "MeatHooks" },
	{ "BodyBag", RNG },
	{ "Chair", false },
	{ "Chair", true }, -- ChairRopes
	{ "Cage" },
	{ "Barrel", RNG },
	{ "Crate", RNG },
	{ "Generator" },
	{ "Radio" },
	{ "Helicopter" },
	-- camp / outdoor
	{ "Tent" },
	{ "Campfire" },
	{ "Gravestone", RNG },
	{ "FenceSegment" },
	{ "Sign", "BUTCHER'S HOLLOW" },
	{ "PowerPole" },
}

local listed = {}
for _, entry in PROPS do
	listed[entry[1]] = true
end
for name, builder in Props :: any do
	if type(builder) == "function" and name ~= "finish" and not listed[name] then
		error("Props." .. name .. " is missing from the PROPS list in export_models.luau")
	end
end

local function buildProp(entry: { any }, seed: number): any
	local args = {}
	for i = 2, #entry do
		args[i - 1] = if entry[i] == RNG then Util.rng(seed) else entry[i]
	end
	local model = (Props :: any)[entry[1]](table.unpack(args, 1, #entry - 1))
	pivotTo(model, CFrame.new())
	model.Name = model:GetAttribute("Mesh") or entry[1]
	return model
end

local exported = {}
local seen = {}
for _, entry in PROPS do
	local usesRng = table.find(entry, RNG) ~= nil
	for seed = SEED, SEED + (if usesRng then VARIANT_SEEDS - 1 else 0) do
		local model = buildProp(entry, seed)
		if seed == SEED and seen[model.Name] then
			error("two PROPS entries both export " .. model.Name)
		end
		if not seen[model.Name] then
			seen[model.Name] = true
			table.insert(exported, { name = model.Name, model = model, seed = if usesRng then seed else nil })
		end
	end
end

for _, prop in exported do
	emit(prop.name, prop.model, "prop", prop.seed)
end

---------------------------------------------------------------- all props

-- Every prop on one sheet: rows of similar size, each prop in a cell sized
-- by its bounding box, with a name board leaning back in front of it.
local GAP = 3
local ROW_WIDTH = 140
local LABEL_DEPTH = 3

local sorted = table.clone(exported)
local function footprint(p): number
	local _, size = p.model:GetBoundingBox()
	return math.max(size.X, size.Z)
end
table.sort(sorted, function(a, b)
	local fa, fb = footprint(a), footprint(b)
	if fa ~= fb then
		return fa < fb
	end
	return a.name < b.name
end)

local sheet = Instance.new("Model")
sheet.Name = "AllProps"
local labels = Instance.new("Folder")
labels.Name = "Labels"
labels.Parent = sheet

local rows = {}
local row = { width = 0, depth = 0, cells = {} }
table.insert(rows, row)
for _, prop in sorted do
	local copy = prop.model:Clone()
	copy.Name = prop.name
	local bbox, size = copy:GetBoundingBox()
	local w = math.max(size.X, 3)
	if row.width > 0 and row.width + w > ROW_WIDTH then
		row = { width = 0, depth = 0, cells = {} }
		table.insert(rows, row)
	end
	table.insert(row.cells, { copy = copy, name = prop.name, x = row.width, w = w, bbox = bbox, size = size })
	row.width += w + GAP
	row.depth = math.max(row.depth, size.Z)
end

local z = 0
local totalWidth = 0
for _, r in rows do
	totalWidth = math.max(totalWidth, r.width - GAP)
	r.z = z + LABEL_DEPTH
	z = r.z + r.depth + GAP
end
local totalDepth = z - GAP
local origin = Vector3.new(-totalWidth / 2, 0, -totalDepth / 2)

for _, r in rows do
	for _, cell in r.cells do
		-- bounding box centre over the cell centre, pivot (bottom) on y = 0
		local centre = origin + Vector3.new(cell.x + cell.w / 2, 0, r.z + r.depth / 2)
		local offset = pivotOf(cell.copy).Position - cell.bbox.Position
		pivotTo(cell.copy, CFrame.new(centre.X + offset.X, 0, centre.Z + offset.Z))
		cell.copy.Parent = sheet

		local board = Instance.new("Part")
		board.Name = cell.name .. "Label"
		board.Anchored = true
		board.CanCollide = false
		board.Size = Vector3.new(cell.w, 1.2, 0.1)
		board.CFrame = CFrame.new(centre.X, 0.5, origin.Z + r.z - LABEL_DEPTH / 2) * CFrame.Angles(math.rad(60), 0, 0)
		board.Color = Color3.fromRGB(24, 22, 20)
		board.Material = Enum.Material.SmoothPlastic
		board.TopSurface = Enum.SurfaceType.Smooth
		board.BottomSurface = Enum.SurfaceType.Smooth
		board.Parent = labels
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(math.floor(cell.w * 50), 60)
		gui.LightInfluence = 0
		gui.Parent = board
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Text = cell.name
		text.TextColor3 = Color3.fromRGB(235, 225, 205)
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.Parent = gui
	end
end
sheet.WorldPivot = CFrame.new()
emit("AllProps", sheet, "sheet", nil)

---------------------------------------------------------------- house

local function groundAt(pos: Vector2): CFrame
	return CFrame.new(pos.X, Terrain.groundY(pos.X, pos.Y), pos.Y)
end

-- built into an empty folder, then its ground point moved to the origin
local houseFolder = Instance.new("Folder")
local house = House.build(houseFolder).model
house.Parent = nil
house.WorldPivot = groundAt(Config.Sites.House.pos)
pivotTo(house, CFrame.new())
emit("House", house, "house", nil)

---------------------------------------------------------------- sites

-- site folder -> the Config.Sites entry whose ground point becomes the
-- origin. Highway and Signs are spread over the whole map, so they keep
-- their world positions (pivot at the world origin).
local SITE_ANCHORS = {
	TruckClearing = "Truck",
	Barn = "Barn",
	HunterCamp = "Camp",
	Trailer = "Trailer",
	Cemetery = "Cemetery",
	RangerStation = "Station",
	LookoutTower = "Tower",
	ToolShed = "Shed",
	Helipad = "Helipad",
}

local sitesFolder = Instance.new("Folder")
Sites.build(sitesFolder)
for _, folder in sitesFolder.Sites:GetChildren() do
	local site = folder
	if not folder:IsA("Model") then
		-- a Folder has no pivot; carry the contents over to a Model
		site = Instance.new("Model")
		site.Name = folder.Name
		for k, v in rawget(folder, "__attrs") do
			site:SetAttribute(k, v)
		end
		for tag in rawget(folder, "__tags") do
			rawget(site, "__tags")[tag] = true
		end
		for _, child in folder:GetChildren() do
			child.Parent = site
		end
	end
	local anchor = SITE_ANCHORS[site.Name]
	if anchor then
		site.WorldPivot = groundAt(Config.Sites[anchor].pos)
		pivotTo(site, CFrame.new())
	else
		site.WorldPivot = CFrame.new()
		print("<<<LOG " .. site.Name .. " keeps its world position>>>")
	end
	emit("Site_" .. site.Name, site, "site", nil)
end

local notes = {}
for k in dropped do
	table.insert(notes, k)
end
table.sort(notes)
for _, k in notes do
	print("<<<LOG not exported: " .. k .. ">>>")
end

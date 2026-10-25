--!strict
-- Loads ForgeGUI meshes with InsertService, normalises their size and pivot,
-- and falls back to procedural props when a mesh cannot be loaded.
--
-- Priority for every model name:
--   1. ServerStorage.CustomModels[name]  (models you imported in Studio,
--      e.g. the Blender exports in assets/blender)
--   2. Assets.Models[name] mesh id loaded with InsertService
--   3. Props[name] procedural builder

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Props = require(script.Parent.Parent.World.Props)
local Util = require(ReplicatedStorage.Shared.Util)

local AssetService = {}

local templates = Instance.new("Folder")
templates.Name = "Templates"
templates.Parent = ServerStorage

-- Sizes for custom models / procedural props that have no mesh spec.
local DEFAULT_SPECS: { [string]: Assets.ModelSpec } = {
	Flashlight = { id = 0, length = 1.1 },
	Battery = { id = 0, length = 0.5 },
	Bandage = { id = 0, length = 0.6 },
	HouseKey = { id = 0, length = 0.6 },
	Fuse = { id = 0, length = 0.65 },
	GasCan = { id = 0, height = 2 },
	Cleaver = { id = 0, height = 1.8 },
	Chainsaw = { id = 0, length = 4 },
	Lantern = { id = 0, height = 1.1 },
	Generator = { id = 0, length = 3.8 },
	Radio = { id = 0, length = 2 },
	Helicopter = { id = 0, length = 26 },
	SackMask = { id = 0, height = 1.5 },
	DeadTree = { id = 0, height = 26 },
}

local loaded: { [string]: Model } = {}
local sourceOf: { [string]: string } = {}

local function clean(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
end

local function normalize(model: Model, spec: Assets.ModelSpec)
	clean(model)
	local _, size = model:GetBoundingBox()
	local scale = 1
	if spec.height and size.Y > 0 then
		scale = spec.height / size.Y
	elseif spec.length then
		local longest = math.max(size.X, size.Z)
		if longest > 0 then
			scale = spec.length / longest
		end
	end
	if scale == scale and scale > 0 and scale < 1e4 and math.abs(scale - 1) > 1e-3 then
		model:ScaleTo(model:GetScale() * scale)
	end
	if spec.yaw and spec.yaw ~= 0 then
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(spec.yaw), 0))
	end
	-- pivot = bottom centre, axis aligned, at the origin
	local cf, newSize = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(cf.Position - Vector3.new(0, newSize.Y / 2, 0))
	model:PivotTo(CFrame.new())
end

local function loadMesh(name: string, spec: Assets.ModelSpec): Model?
	if spec.id <= 0 then
		return nil
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(spec.id)
	end)
	if not ok or not result then
		warn(string.format("[AssetService] %s (%d) failed to load, using procedural fallback: %s", name, spec.id, tostring(result)))
		return nil
	end
	local container = result :: Model
	local children = container:GetChildren()
	local model: Model
	if #children == 1 and children[1]:IsA("Model") then
		model = children[1] :: Model
		model.Parent = nil
		container:Destroy()
	else
		model = container
	end
	model.Name = name
	normalize(model, spec)
	return model
end

local function fromCustom(name: string): Model?
	local folder = ServerStorage:FindFirstChild("CustomModels")
	local custom = folder and folder:FindFirstChild(name)
	if not custom then
		return nil
	end
	local model: Model
	if custom:IsA("Model") then
		model = custom:Clone()
	elseif custom:IsA("BasePart") then
		model = Instance.new("Model")
		custom:Clone().Parent = model
	else
		return nil
	end
	model.Name = name
	local spec = Assets.Models[name] or DEFAULT_SPECS[name]
	if spec then
		normalize(model, spec)
	else
		normalize(model, { id = 0 })
	end
	return model
end

-- Load every mesh in parallel. Call once at server start.
function AssetService.preload()
	local pending = 0
	for name, spec in Assets.Models do
		pending += 1
		task.spawn(function()
			local model = fromCustom(name)
			local source = "custom"
			if not model then
				model = loadMesh(name, spec)
				source = "mesh"
			end
			if model then
				model.Parent = templates
				loaded[name] = model
				sourceOf[name] = source
			end
			pending -= 1
		end)
	end
	-- custom-only overrides for props without a mesh id
	for name in DEFAULT_SPECS do
		if not loaded[name] then
			local model = fromCustom(name)
			if model then
				model.Parent = templates
				loaded[name] = model
				sourceOf[name] = "custom"
			end
		end
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 45 do
		task.wait(0.1)
	end
	local report = {}
	for name, source in sourceOf do
		table.insert(report, name .. "=" .. source)
	end
	table.sort(report)
	print("[AssetService] loaded: " .. table.concat(report, ", "))
end

function AssetService.hasMesh(name: string): boolean
	return (loaded[name] :: Model?) ~= nil
end

local fallbackRng = Util.rng(1234)

-- Returns a fresh copy of the named model (mesh or procedural). `rng` is used
-- by procedural builders that vary their shape.
function AssetService.create(name: string, rng: Util.Rng?): Model
	local template = loaded[name]
	if template then
		return template:Clone()
	end
	local builder = (Props :: any)[name]
	if typeof(builder) == "function" then
		return builder(rng or fallbackRng)
	end
	warn("[AssetService] no model or builder for " .. name)
	local m = Instance.new("Model")
	m.Name = name
	local p = Instance.new("Part")
	p.Size = Vector3.new(1, 1, 1)
	p.Anchored = true
	p.CFrame = CFrame.new(0, 0.5, 0)
	p.Parent = m
	m.WorldPivot = CFrame.new()
	return m
end

function AssetService.spawn(name: string, cf: CFrame, parent: Instance, rng: Util.Rng?): Model
	local m = AssetService.create(name, rng)
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

-- Copies item models into ReplicatedStorage so the client can show them in
-- the view model and inventory previews. Adds to (and replaces in) the folder
-- the lobby published for the store, when Studio turns the lobby into the game.
function AssetService.publishItemModels(names: { string })
	local folder = ReplicatedStorage:FindFirstChild("ItemModels") or Instance.new("Folder")
	folder.Name = "ItemModels"
	for _, name in names do
		local old = folder:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		local m = AssetService.create(name)
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
			elseif p:IsA("ProximityPrompt") then
				p:Destroy()
			end
		end
		m.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

return AssetService

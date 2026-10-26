--!strict
-- Swaps the Blender models (tools/blender/build_props.py, build_buildings.py)
-- in for the procedural stand-ins the server places.
--
-- The meshes ship as uploaded mesh assets: tools/blender/export_combined.py
-- packs them into one .glb that is imported once in Studio, and
-- tools/roblox/harvest_meshes.luau files the parts under
-- ReplicatedStorage.MeshAssets.<MeshName>, positioned around the origin each
-- mesh was modelled at. (Building them at runtime with EditableMesh is not
-- an option: a client may only hold a handful of those.)
--
-- The server tags stand-ins with "BlenderMesh" and a "Mesh" attribute. This
-- module hides the stand-in parts locally (LocalTransparencyModifier) and
-- shows the mesh in their place: fitted to the stand-in's size (FIT_AXIS),
-- unscaled at its pivot (MeshExact, buildings), or at a given scale
-- (MeshScale, the cannibals' body parts). SkipMesh turns a stand-in off. Collisions, prompts and gameplay stay on the
-- server parts, so a mesh that has not been imported yet simply leaves the
-- procedural prop visible.

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshCatalog"))

local MeshLibrary = {}

-- Which axis of the stand-in's bounding box the mesh is scaled to match.
local FIT_AXIS: { [string]: string } = {
	SackMask = "X",
	Flashlight = "X",
	HouseKey = "X",
	Fuse = "X",
	Battery = "X",
	Note = "X",
	BodyBag = "X",
	Campfire = "X",
	Chainsaw = "Z",
	Helicopter = "Z",
	Bandage = "Max",
	-- farmhouse furniture with parts sticking up (stove pipe, tap, cushions)
	Sofa = "X",
	Stove = "X",
	Bathtub = "X",
	DiningTable = "X",
	CoffeeTable = "X",
	KitchenTable = "X",
	Toilet = "Z",
	KidsBed = "Z",
	ToyChest = "X",
	BathroomSink = "X",
}

type Template = { model: Model, size: Vector3 }

local templates: { [string]: Template | false } = {}

---------------------------------------------------------------- templates

local function buildTemplate(name: string): Template?
	local store = ReplicatedStorage:FindFirstChild("MeshAssets")
	local source = store and store:FindFirstChild(name)
	if not source then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	for _, original in source:GetChildren() do
		if original:IsA("MeshPart") then
			local part = original:Clone()
			-- parts are "<MeshName>_<material>"; the palette names the Roblox material
			-- (a material too big for one mesh comes as "<material>_2", "_3"...)
			local key = string.sub(part.Name, #name + 2)
			local entry = MeshCatalog[key] or MeshCatalog[(string.gsub(key, "_%d+$", ""))]
			if entry then
				local ok, material = pcall(function()
					return (Enum.Material :: any)[entry.material]
				end)
				if ok and material then
					part.Material = material
				end
				part.Transparency = entry.transparency
			end
			part.Color = Color3.new(1, 1, 1) -- vertex colours carry the look
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = part.Transparency < 0.5
			part.Parent = model
		end
	end
	if #model:GetChildren() == 0 then
		return nil
	end
	model.WorldPivot = CFrame.new()
	return { model = model, size = model:GetExtentsSize() }
end

function MeshLibrary.template(name: string): Template?
	local cached = templates[name]
	if cached == false then
		return nil
	elseif cached ~= nil then
		return cached :: Template
	end
	local result = buildTemplate(name)
	templates[name] = result or false
	return result
end

-- Whether the Blender meshes have been imported into this place.
function MeshLibrary.available(): boolean
	return ReplicatedStorage:FindFirstChild("MeshAssets") ~= nil
end

---------------------------------------------------------------- upgrading stand-ins

local function largestPart(root: Instance): BasePart?
	local best: BasePart? = nil
	local bestVolume = -1
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "BlenderVisual" then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestVolume then
				bestVolume = v
				best = d
			end
		end
	end
	return best
end

local function axisValue(v: Vector3, axis: string): number
	if axis == "X" then
		return v.X
	elseif axis == "Z" then
		return v.Z
	elseif axis == "Max" then
		return math.max(v.X, v.Y, v.Z)
	end
	return v.Y
end

local connections: { [Instance]: { RBXScriptConnection } } = {}

local function setHidden(target: Instance, hidden: boolean)
	if target:GetAttribute("MeshBaked") then
		-- a building's baked parts (Build.bake): only those, not the stand-ins,
		-- lights and pickups around them
		for _, d in target:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Baked") then
				d.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
		return
	end
	local function apply(part: BasePart)
		if part:FindFirstAncestor("BlenderVisual") then
			return
		end
		local keep = part:FindFirstAncestorWhichIsA("Model")
		if keep and keep ~= target and keep:GetAttribute("KeepVisible") then
			return
		end
		if part:GetAttribute("KeepVisible") then
			return
		end
		part.LocalTransparencyModifier = if hidden then 1 else 0
	end
	if target:IsA("BasePart") then
		apply(target)
	end
	for _, d in target:GetDescendants() do
		if d:IsA("BasePart") then
			apply(d)
		end
	end
end

function MeshLibrary.remove(target: Instance)
	local visual = target:FindFirstChild("BlenderVisual")
	if visual then
		visual:Destroy()
	end
	local list = connections[target]
	if list then
		for _, c in list do
			c:Disconnect()
		end
		connections[target] = nil
	end
	setHidden(target, false)
end

-- Replace a tagged stand-in (Model or BasePart) with its Blender mesh.
function MeshLibrary.upgrade(target: Instance): Model?
	local name = target:GetAttribute("Mesh")
	if typeof(name) ~= "string" or target:GetAttribute("SkipMesh") then
		return nil
	end
	local template = MeshLibrary.template(name)
	if not template then
		return nil
	end
	MeshLibrary.remove(target)

	local targetCF: CFrame
	local targetSize: Vector3
	if target:IsA("Model") then
		targetCF = target:GetPivot()
		local _, size = target:GetBoundingBox()
		targetSize = size
	elseif target:IsA("BasePart") then
		targetCF = target.CFrame
		targetSize = target.Size
	else
		return nil
	end

	local visual = template.model:Clone()
	visual.Name = "BlenderVisual"
	local axis = FIT_AXIS[name] or "Y"
	local scale = axisValue(targetSize, axis) / math.max(axisValue(template.size, axis), 1e-3)
	if target:GetAttribute("MeshExact") then
		-- buildings are modelled at size around the stand-in's pivot
		scale = 1
	end
	local fixed = target:GetAttribute("MeshScale")
	if typeof(fixed) == "number" then
		-- body parts are modelled at rig scale 1 around the part's centre
		scale = fixed
	end
	if scale > 0.05 and scale < 50 and math.abs(scale - 1) > 1e-3 then
		visual:ScaleTo(scale)
	end
	visual:PivotTo(targetCF)

	local anchor = if target:IsA("BasePart") then target else largestPart(target)
	local list = {}
	if anchor and not anchor.Anchored then
		-- stand-in is welded to something that moves (a cannibal's hand)
		for _, p in visual:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = anchor
				weld.Part1 = p
				weld.Parent = p
			end
		end
	elseif anchor then
		-- anchored stand-ins can still be moved (the helicopter, held items):
		-- keep the visual where it sits relative to the anchor
		local offset = anchor.CFrame:ToObjectSpace(visual:GetPivot())
		local a: BasePart = anchor
		table.insert(list, a:GetPropertyChangedSignal("CFrame"):Connect(function()
			if visual.Parent then
				visual:PivotTo(a.CFrame * offset)
			end
		end))
	end
	visual.Parent = target
	setHidden(target, true)
	if target:GetAttribute("MeshHidden") then
		-- put away (CannibalSkins hides a monster's weapon): stay hidden
		for _, p in visual:GetDescendants() do
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = 1
			end
		end
	end
	connections[target] = list
	return visual
end

function MeshLibrary.init()
	local function onTagged(inst: Instance)
		-- only things in the world; item templates are upgraded on demand
		if not inst:IsDescendantOf(workspace) then
			return
		end
		task.defer(function()
			MeshLibrary.upgrade(inst)
		end)
		inst:GetAttributeChangedSignal("Mesh"):Connect(function()
			MeshLibrary.upgrade(inst)
		end)
	end
	CollectionService:GetInstanceAddedSignal("BlenderMesh"):Connect(onTagged)
	CollectionService:GetInstanceRemovedSignal("BlenderMesh"):Connect(function(inst)
		connections[inst] = nil
	end)
	-- fetch the meshes in the background so they don't pop in one by one
	task.spawn(function()
		local store = ReplicatedStorage:FindFirstChild("MeshAssets")
		if store then
			pcall(function()
				ContentProvider:PreloadAsync({ store })
			end)
		end
	end)
	-- swap what's already there a batch a frame, buildings first, so the
	-- menu doesn't hitch and the houses don't wait behind every rock
	task.spawn(function()
		local tagged = CollectionService:GetTagged("BlenderMesh")
		table.sort(tagged, function(a, b)
			return (a:GetAttribute("MeshExact") == true) and not (b:GetAttribute("MeshExact") == true)
		end)
		for i, inst in tagged do
			onTagged(inst)
			if i % 12 == 0 then
				task.wait()
			end
		end
	end)
end

return MeshLibrary

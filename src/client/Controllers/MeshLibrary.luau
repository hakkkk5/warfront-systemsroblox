--!strict
-- Builds the Blender props (tools/blender/build_props.py -> Shared.Meshes)
-- into MeshParts at runtime with EditableMesh, and swaps them in for the
-- procedural stand-ins the server places.
--
-- The server tags stand-ins with "BlenderMesh" and a "Mesh" attribute. This
-- module hides the stand-in parts locally (LocalTransparencyModifier) and
-- shows the Blender mesh in their place. Collisions, prompts and gameplay
-- stay on the server parts, so if EditableMesh is unavailable (e.g. "Allow
-- Mesh / Image APIs" is off in Game Settings > Security) nothing breaks: the
-- procedural props simply stay visible.

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshesFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Meshes")

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
}

type Template = { model: Model, size: Vector3, pivot: string }

local templates: { [string]: Template | false } = {}
local keepAlive: { EditableMesh } = {}
local disabled = false

---------------------------------------------------------------- base64

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local decodeMap: { [number]: number } = {}
for i = 1, #ALPHABET do
	decodeMap[string.byte(ALPHABET, i)] = i - 1
end

local function decode(s: string): buffer
	local len = #s
	local padding = 0
	if string.sub(s, -2) == "==" then
		padding = 2
	elseif string.sub(s, -1) == "=" then
		padding = 1
	end
	local outLen = (len // 4) * 3 - padding
	local out = buffer.create(outLen)
	local o = 0
	for i = 1, len, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local n = bit32.lshift(decodeMap[a] or 0, 18)
			+ bit32.lshift(decodeMap[b] or 0, 12)
			+ bit32.lshift(decodeMap[c] or 0, 6)
			+ (decodeMap[d] or 0)
		if o < outLen then
			buffer.writeu8(out, o, bit32.rshift(n, 16))
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, bit32.band(bit32.rshift(n, 8), 255))
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, bit32.band(n, 255))
		end
		o += 3
	end
	return out
end

---------------------------------------------------------------- mesh building

type PartData = {
	material: string,
	transparency: number,
	min: Vector3,
	max: Vector3,
	vertexCount: number,
	triangleCount: number,
	vertices: string,
	indices: string,
}

type MeshData = { name: string, pivot: string, parts: { PartData } }

local function buildPart(data: PartData): MeshPart
	local mesh = AssetService:CreateEditableMesh({})
	table.insert(keepAlive, mesh)
	local vb = decode(data.vertices)
	local ib = decode(data.indices)
	local lo, hi = data.min, data.max
	local span = hi - lo
	local count = data.vertexCount
	local vids = table.create(count)
	local nids = table.create(count)
	local cids = table.create(count)
	local uids = table.create(count)
	for i = 0, count - 1 do
		local off = i * 16
		local px = lo.X + buffer.readu16(vb, off) / 65535 * span.X
		local py = lo.Y + buffer.readu16(vb, off + 2) / 65535 * span.Y
		local pz = lo.Z + buffer.readu16(vb, off + 4) / 65535 * span.Z
		local n = Vector3.new(buffer.readi8(vb, off + 6), buffer.readi8(vb, off + 7), buffer.readi8(vb, off + 8))
		if n.Magnitude < 1e-3 then
			n = Vector3.yAxis
		end
		local color = Color3.fromRGB(buffer.readu8(vb, off + 9), buffer.readu8(vb, off + 10), buffer.readu8(vb, off + 11))
		local u = buffer.readu16(vb, off + 12) / 65535 * 64
		local v = buffer.readu16(vb, off + 14) / 65535 * 64
		vids[i + 1] = mesh:AddVertex(Vector3.new(px, py, pz))
		nids[i + 1] = mesh:AddNormal(n.Unit)
		cids[i + 1] = mesh:AddColor(color, 1)
		uids[i + 1] = mesh:AddUV(Vector2.new(u, v))
	end
	for t = 0, data.triangleCount - 1 do
		local a = buffer.readu16(ib, t * 6) + 1
		local b = buffer.readu16(ib, t * 6 + 2) + 1
		local c = buffer.readu16(ib, t * 6 + 4) + 1
		local face = mesh:AddTriangle(vids[a], vids[b], vids[c])
		mesh:SetFaceNormals(face, { nids[a], nids[b], nids[c] })
		mesh:SetFaceColors(face, { cids[a], cids[b], cids[c] })
		mesh:SetFaceUVs(face, { uids[a], uids[b], uids[c] })
	end

	local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
	local ok, material = pcall(function()
		return (Enum.Material :: any)[data.material]
	end)
	part.Material = if ok and material then material else Enum.Material.SmoothPlastic
	part.Transparency = data.transparency
	part.Color = Color3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = data.transparency < 0.5
	part.CFrame = CFrame.new((lo + hi) / 2)
	return part
end

local function buildTemplate(name: string): Template?
	local moduleScript = MeshesFolder:FindFirstChild(name)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil
	end
	local data = require(moduleScript) :: any
	local model = Instance.new("Model")
	model.Name = name
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, partData in (data :: MeshData).parts do
		local part = buildPart(partData)
		part.Parent = model
		lo = lo:Min(partData.min)
		hi = hi:Max(partData.max)
	end
	model.WorldPivot = CFrame.new()
	return { model = model, size = hi - lo, pivot = (data :: MeshData).pivot }
end

function MeshLibrary.template(name: string): Template?
	if disabled then
		return nil
	end
	local cached = templates[name]
	if cached == false then
		return nil
	elseif cached ~= nil then
		return cached :: Template
	end
	local ok, result = pcall(buildTemplate, name)
	if not ok then
		warn("[MeshLibrary] EditableMesh unavailable, keeping procedural props: " .. tostring(result))
		disabled = true
		templates[name] = false
		return nil
	end
	templates[name] = result or false
	return result
end

function MeshLibrary.available(): boolean
	return not disabled
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
	if typeof(name) ~= "string" then
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
		-- anchored stand-ins can still be moved by the server (helicopter)
		table.insert(list, anchor:GetPropertyChangedSignal("CFrame"):Connect(function()
			if visual.Parent then
				local cf = if target:IsA("BasePart") then target.CFrame else (target :: Model):GetPivot()
				visual:PivotTo(cf)
			end
		end))
	end
	visual.Parent = target
	setHidden(target, true)
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
	-- build lazily across a few frames so the menu doesn't hitch
	task.spawn(function()
		for _, inst in CollectionService:GetTagged("BlenderMesh") do
			onTagged(inst)
			task.wait()
		end
	end)
end

return MeshLibrary

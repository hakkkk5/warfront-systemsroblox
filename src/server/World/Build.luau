--!strict
-- Part construction helpers used by every world builder.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Shared.Util)

local Build = {}

export type Opening = {
	at: number, -- centre along the wall, in the wall's axis coordinate
	width: number,
	bottom: number, -- height of the sill above the wall base (0 for doors)
	top: number, -- height of the lintel above the wall base
}

local function apply(inst: Instance, extra: { [string]: any }?)
	if extra then
		for key, value in extra do
			(inst :: any)[key] = value
		end
	end
end

function Build.part(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- nothing listens to .Touched on world parts; skipping touch pairs saves physics time
	p.CanTouch = false
	apply(p, extra)
	p.Parent = parent
	return p
end

-- Cylinder whose axis runs along the CFrame's X axis.
function Build.cylinder(
	parent: Instance,
	length: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): Part
	local p = Build.part(parent, Vector3.new(length, diameter, diameter), cf, color, material, extra)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Vertical cylinder centred at cf.
function Build.post(
	parent: Instance,
	height: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): Part
	return Build.cylinder(parent, height, diameter, cf * CFrame.Angles(0, 0, math.rad(90)), color, material, extra)
end

function Build.ball(
	parent: Instance,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): Part
	local p = Build.part(parent, Vector3.new(diameter, diameter, diameter), cf, color, material, extra)
	p.Shape = Enum.PartType.Ball
	return p
end

function Build.wedge(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	apply(w, extra)
	w.Parent = parent
	return w
end

function Build.model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Holds the parts a Blender building exterior replaces (roof wedges, flat
-- porch roofs, box posts; tools/blender/build_buildings.py). Build them into
-- it, then call Build.markStandIn with the building's origin: clients hide
-- these and place the mesh there unscaled. The parts keep the collisions.
function Build.standIn(parent: Instance, meshName: string): Model
	return Build.model(parent, meshName)
end

function Build.markStandIn(model: Model, origin: CFrame)
	-- set last: a pivotless model re-centres when its first part arrives
	model.WorldPivot = origin
	model:SetAttribute("Mesh", model.Name)
	model:SetAttribute("MeshExact", true)
	CollectionService:AddTag(model, "BlenderMesh")
end

-- Plain blocks, wedges and trusses; not unions or parts with a mesh of their own.
local BAKEABLE: { [string]: boolean } = { Part = true, WedgePart = true, CornerWedgePart = true, TrussPart = true }

local function bakeable(part: BasePart, group: Instance): boolean
	if not BAKEABLE[part.ClassName] or part.Transparency >= 0.99 or part.Material == Enum.Material.Neon then
		return false
	end
	if part:GetAttribute("KeepVisible") then
		return false
	end
	for _, c in part:GetChildren() do
		if c:IsA("Light") or c:IsA("Fire") or c:IsA("Smoke") or c:IsA("ParticleEmitter") or c:IsA("Decal") or c:IsA("SurfaceGui") or c:IsA("DataModelMesh") then
			return false
		end
	end
	local a = part.Parent
	while a and a ~= group do
		if CollectionService:HasTag(a, "BlenderMesh") or a:GetAttribute("KeepVisible") then
			return false
		end
		a = a.Parent
	end
	return a == group
end

-- Bakes a building's plain parts (floors, walls, stairs, box furniture) into
-- one Blender mesh (tools/blender/build_house_parts.py, modelled from these
-- very parts as measured in Studio). Marks every visible, non-glowing part
-- under `group` that isn't inside a stand-in or a KeepVisible model "Baked"
-- and tags the group: clients hide just those parts and show the mesh at
-- `origin`. Call it once the building is done; later parts stay as they are.
function Build.bake(group: Model, meshName: string, origin: CFrame): number
	local count = 0
	for _, d in group:GetDescendants() do
		if d:IsA("BasePart") and bakeable(d, group) then
			d:SetAttribute("Baked", true)
			count += 1
		end
	end
	group.WorldPivot = origin
	group:SetAttribute("Mesh", meshName)
	group:SetAttribute("MeshExact", true)
	group:SetAttribute("MeshBaked", true)
	CollectionService:AddTag(group, "BlenderMesh")
	return count
end

function Build.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Axis aligned wall in the local space of `origin`, from a to b (XZ), with
-- door / window openings cut out of it.
function Build.wall(
	parent: Instance,
	origin: CFrame,
	a: Vector2,
	b: Vector2,
	y0: number,
	height: number,
	thickness: number,
	openings: { Opening },
	color: Color3,
	material: Enum.Material
)
	local alongX = math.abs(b.Y - a.Y) < 1e-3
	local s = if alongX then math.min(a.X, b.X) else math.min(a.Y, b.Y)
	local e = if alongX then math.max(a.X, b.X) else math.max(a.Y, b.Y)
	local fixed = if alongX then a.Y else a.X

	local function segment(from: number, to: number, yb: number, yt: number)
		if to - from < 0.05 or yt - yb < 0.05 then
			return
		end
		local mid = (from + to) / 2
		local len = to - from
		local h = yt - yb
		local pos = if alongX
			then Vector3.new(mid, y0 + (yb + yt) / 2, fixed)
			else Vector3.new(fixed, y0 + (yb + yt) / 2, mid)
		local size = if alongX then Vector3.new(len, h, thickness) else Vector3.new(thickness, h, len)
		Build.part(parent, size, origin * CFrame.new(pos), color, material)
	end

	local sorted = table.clone(openings)
	table.sort(sorted, function(x, y)
		return x.at < y.at
	end)

	local cursor = s
	for _, o in sorted do
		local os = o.at - o.width / 2
		local oe = o.at + o.width / 2
		segment(cursor, os, 0, height)
		segment(os, oe, 0, o.bottom)
		segment(os, oe, o.top, height)
		cursor = oe
	end
	segment(cursor, e, 0, height)
end

-- A hanging light bulb with a warm point light. Tagged lights flicker on the
-- client.
function Build.bulb(parent: Instance, cf: CFrame, color: Color3, brightness: number, range: number, flicker: boolean): Part
	local cord = Build.part(parent, Vector3.new(0.08, 1.6, 0.08), cf * CFrame.new(0, 0.9, 0), Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic, {
		CanCollide = false,
		CastShadow = false,
	})
	cord.Name = "Cord"
	local bulb = Build.ball(parent, 0.45, cf, Color3.fromRGB(255, 220, 160), Enum.Material.Neon, {
		CanCollide = false,
		CastShadow = false,
	})
	bulb.Name = "Bulb"
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = true
	light.Parent = bulb
	if flicker then
		CollectionService:AddTag(bulb, "FlickerLight")
	end
	return bulb
end

-- Candle with a tiny flame that flickers client side.
function Build.candle(parent: Instance, cf: CFrame, height: number?)
	local h = height or 0.6
	Build.post(parent, h, 0.22, cf * CFrame.new(0, h / 2, 0), Color3.fromRGB(230, 220, 190), Enum.Material.SmoothPlastic, {
		CanCollide = false,
	})
	local flame = Build.part(parent, Vector3.new(0.1, 0.22, 0.1), cf * CFrame.new(0, h + 0.12, 0), Color3.fromRGB(255, 170, 60), Enum.Material.Neon, {
		CanCollide = false,
		CastShadow = false,
	})
	flame.Name = "Flame"
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 70)
	light.Brightness = 0.9
	light.Range = 9
	light.Shadows = false
	light.Parent = flame
	CollectionService:AddTag(flame, "Candle")
end

-- Thin glossy dark red decal-like stain lying on a surface.
function Build.stain(parent: Instance, cf: CFrame, size: Vector2, rng: Util.Rng)
	local color = Color3.fromRGB(rng:NextInteger(60, 90), rng:NextInteger(4, 12), rng:NextInteger(4, 10))
	Build.part(parent, Vector3.new(size.X, 0.05, size.Y), cf, color, Enum.Material.Glass, {
		CanCollide = false,
		CastShadow = false,
		Reflectance = 0.15,
		Transparency = 0.05,
	})
	-- smaller satellite drops
	for _ = 1, rng:NextInteger(2, 5) do
		local offset = Vector3.new(rng:NextNumber(-1, 1) * size.X, 0, rng:NextNumber(-1, 1) * size.Y)
		local d = rng:NextNumber(0.15, 0.5)
		Build.part(parent, Vector3.new(d, 0.05, d * rng:NextNumber(0.6, 1.4)), cf * CFrame.new(offset) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), color, Enum.Material.Glass, {
			CanCollide = false,
			CastShadow = false,
			Reflectance = 0.15,
		})
	end
end

function Build.tag(inst: Instance, tag: string)
	CollectionService:AddTag(inst, tag)
end

-- Fire + smoke + light on a part (campfires, the burning truck).
function Build.fire(part: BasePart, size: number, withSmoke: boolean)
	local fire = Instance.new("Fire")
	fire.Size = size
	fire.Heat = size * 1.4
	fire.Color = Color3.fromRGB(255, 120, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 40, 10)
	fire.Parent = part
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 130, 60)
	light.Brightness = 2
	light.Range = size * 3.5
	light.Shadows = true
	light.Parent = part
	Build.tag(part, "FireLight")
	if withSmoke then
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(40, 38, 36)
		smoke.Opacity = 0.18
		smoke.RiseVelocity = 6
		smoke.Size = size * 0.8
		smoke.Parent = part
	end
end

return Build

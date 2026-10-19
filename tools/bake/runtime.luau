-- Minimal Roblox runtime for running the world builders outside Roblox
-- (used by tools/bake/bake.py). Implements just enough of the engine API:
-- datatypes with real math, an instance tree with properties, attributes and
-- tags, services, and a terrain that records WriteVoxels calls.

local runtime = {}

local function typed(t, name)
	t.__type = name
	return t
end

local rawtypeof = typeof
function typeof(v)
	if type(v) == "table" and rawget(v, "__type") then
		return rawget(v, "__type")
	end
	return rawtypeof(v)
end

---------------------------------------------------------------- Vector3
Vector3 = {}
local V3 = {}
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return Vector3.new(0, 0, 0)
		end
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return Vector3[k]
end
function Vector3.new(x, y, z)
	return setmetatable(typed({ X = x or 0, Y = y or 0, Z = z or 0 }, "Vector3"), V3)
end
V3.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return Vector3.new(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return Vector3.new(a.X / b, a.Y / b, a.Z / b)
	end
	return Vector3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__unm = function(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return string.format("%g, %g, %g", a.X, a.Y, a.Z)
end
function Vector3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vector3.Cross(a, b)
	return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vector3.Lerp(a, b, t)
	return a + (b - a) * t
end
function Vector3.Min(a, b)
	return Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function Vector3.Max(a, b)
	return Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
Vector3.xAxis = Vector3.new(1, 0, 0)
Vector3.yAxis = Vector3.new(0, 1, 0)
Vector3.zAxis = Vector3.new(0, 0, 1)

---------------------------------------------------------------- Vector2
Vector2 = {}
local V2 = {}
V2.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		if m == 0 then
			return Vector2.new(0, 0)
		end
		return Vector2.new(v.X / m, v.Y / m)
	end
	return Vector2[k]
end
function Vector2.new(x, y)
	return setmetatable(typed({ X = x or 0, Y = y or 0 }, "Vector2"), V2)
end
V2.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return Vector2.new(b.X * a, b.Y * a)
	elseif type(b) == "number" then
		return Vector2.new(a.X * b, a.Y * b)
	end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	return Vector2.new(a.X / b, a.Y / b)
end
V2.__unm = function(a)
	return Vector2.new(-a.X, -a.Y)
end
function Vector2.Lerp(a, b, t)
	return a + (b - a) * t
end
function Vector2.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end

---------------------------------------------------------------- CFrame
CFrame = {}
local CF = {}
local function cf(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return setmetatable(typed({
		X = x, Y = y, Z = z,
		r00 = r00, r01 = r01, r02 = r02,
		r10 = r10, r11 = r11, r12 = r12,
		r20 = r20, r21 = r21, r22 = r22,
	}, "CFrame"), CF)
end
CF.__index = function(c, k)
	if k == "Position" or k == "p" then
		return Vector3.new(c.X, c.Y, c.Z)
	elseif k == "LookVector" then
		return Vector3.new(-c.r02, -c.r12, -c.r22)
	elseif k == "RightVector" then
		return Vector3.new(c.r00, c.r10, c.r20)
	elseif k == "UpVector" then
		return Vector3.new(c.r01, c.r11, c.r21)
	elseif k == "Rotation" then
		return cf(0, 0, 0, c.r00, c.r01, c.r02, c.r10, c.r11, c.r12, c.r20, c.r21, c.r22)
	end
	return CFrame[k]
end
local function mulPoint(c, v)
	return Vector3.new(
		c.r00 * v.X + c.r01 * v.Y + c.r02 * v.Z + c.X,
		c.r10 * v.X + c.r11 * v.Y + c.r12 * v.Z + c.Y,
		c.r20 * v.X + c.r21 * v.Y + c.r22 * v.Z + c.Z
	)
end
CF.__mul = function(a, b)
	if typeof(b) == "Vector3" then
		return mulPoint(a, b)
	end
	return cf(
		a.r00 * b.X + a.r01 * b.Y + a.r02 * b.Z + a.X,
		a.r10 * b.X + a.r11 * b.Y + a.r12 * b.Z + a.Y,
		a.r20 * b.X + a.r21 * b.Y + a.r22 * b.Z + a.Z,
		a.r00 * b.r00 + a.r01 * b.r10 + a.r02 * b.r20,
		a.r00 * b.r01 + a.r01 * b.r11 + a.r02 * b.r21,
		a.r00 * b.r02 + a.r01 * b.r12 + a.r02 * b.r22,
		a.r10 * b.r00 + a.r11 * b.r10 + a.r12 * b.r20,
		a.r10 * b.r01 + a.r11 * b.r11 + a.r12 * b.r21,
		a.r10 * b.r02 + a.r11 * b.r12 + a.r12 * b.r22,
		a.r20 * b.r00 + a.r21 * b.r10 + a.r22 * b.r20,
		a.r20 * b.r01 + a.r21 * b.r11 + a.r22 * b.r21,
		a.r20 * b.r02 + a.r21 * b.r12 + a.r22 * b.r22
	)
end
CF.__add = function(a, v)
	return cf(a.X + v.X, a.Y + v.Y, a.Z + v.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
CF.__sub = function(a, v)
	return cf(a.X - v.X, a.Y - v.Y, a.Z - v.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
function CFrame.new(a, b, c, ...)
	if a == nil then
		return cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	if typeof(a) == "Vector3" then
		if b ~= nil then
			return CFrame.lookAt(a, b)
		end
		return cf(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	local rest = { ... }
	if #rest == 9 then
		return cf(a, b, c, rest[1], rest[2], rest[3], rest[4], rest[5], rest[6], rest[7], rest[8], rest[9])
	end
	return cf(a, b or 0, c or 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local X = cf(0, 0, 0, 1, 0, 0, 0, cx, -sx, 0, sx, cx)
	local Y = cf(0, 0, 0, cy, 0, sy, 0, 1, 0, -sy, 0, cy)
	local Z = cf(0, 0, 0, cz, -sz, 0, sz, cz, 0, 0, 0, 1)
	return X * Y * Z
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromMatrix(pos, right, up, back)
	back = back or right:Cross(up)
	return cf(pos.X, pos.Y, pos.Z, right.X, up.X, back.X, right.Y, up.Y, back.Y, right.Z, up.Z, back.Z)
end
function CFrame.lookAt(at, target, up)
	up = up or Vector3.new(0, 1, 0)
	local look = (target - at)
	if look.Magnitude < 1e-9 then
		return CFrame.new(at)
	end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(Vector3.new(0, 0, 1))
	end
	right = right.Unit
	local up2 = right:Cross(look).Unit
	return cf(at.X, at.Y, at.Z, right.X, up2.X, -look.X, right.Y, up2.Y, -look.Y, right.Z, up2.Z, -look.Z)
end
function CFrame.Inverse(c)
	-- transpose rotation, rotate negated position
	local r00, r01, r02 = c.r00, c.r10, c.r20
	local r10, r11, r12 = c.r01, c.r11, c.r21
	local r20, r21, r22 = c.r02, c.r12, c.r22
	return cf(
		-(r00 * c.X + r01 * c.Y + r02 * c.Z),
		-(r10 * c.X + r11 * c.Y + r12 * c.Z),
		-(r20 * c.X + r21 * c.Y + r22 * c.Z),
		r00, r01, r02, r10, r11, r12, r20, r21, r22
	)
end
function CFrame.ToObjectSpace(a, b)
	return a:Inverse() * b
end
function CFrame.ToWorldSpace(a, b)
	return a * b
end
function CFrame.PointToObjectSpace(a, v)
	return a:Inverse() * v
end
function CFrame.PointToWorldSpace(a, v)
	return a * v
end
function CFrame.VectorToWorldSpace(a, v)
	return a.Rotation * v
end
function CFrame.Lerp(a, b, t)
	local p = a.Position:Lerp(b.Position, t)
	local r = if t < 0.5 then a.Rotation else b.Rotation
	return r + p
end
function CFrame.GetComponents(c)
	return c.X, c.Y, c.Z, c.r00, c.r01, c.r02, c.r10, c.r11, c.r12, c.r20, c.r21, c.r22
end
CFrame.identity = CFrame.new()

---------------------------------------------------------------- Color3 and friends
Color3 = {}
local C3 = { __index = function(_, k)
	return Color3[k]
end }
function Color3.new(r, g, b)
	return setmetatable(typed({ R = r or 0, G = g or 0, B = b or 0 }, "Color3"), C3)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local m = i % 6
	if m == 0 then
		return Color3.new(v, t, p)
	elseif m == 1 then
		return Color3.new(q, v, p)
	elseif m == 2 then
		return Color3.new(p, v, t)
	elseif m == 3 then
		return Color3.new(p, q, v)
	elseif m == 4 then
		return Color3.new(t, p, v)
	end
	return Color3.new(v, p, q)
end
function Color3.Lerp(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

UDim = {}
function UDim.new(s, o)
	return typed({ Scale = s or 0, Offset = o or 0 }, "UDim")
end
UDim2 = {}
function UDim2.new(sx, ox, sy, oy)
	return typed({ X = UDim.new(sx, ox), Y = UDim.new(sy, oy) }, "UDim2")
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end

local function opaque(name)
	return { new = function(...)
		return typed({ args = { ... } }, name)
	end }
end
NumberSequence = opaque("NumberSequence")
NumberSequenceKeypoint = opaque("NumberSequenceKeypoint")
ColorSequence = opaque("ColorSequence")
ColorSequenceKeypoint = opaque("ColorSequenceKeypoint")
NumberRange = opaque("NumberRange")
TweenInfo = opaque("TweenInfo")
Region3 = opaque("Region3")
RaycastParams = { new = function()
	return { FilterDescendantsInstances = {}, FilterType = nil, IgnoreWater = false }
end }
Random = { new = function(seed)
	local state = math.floor(seed or 1)
	local r = {}
	local function nxt()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	function r.NextNumber(_, a, b)
		local u = nxt()
		if a and b then
			return a + (b - a) * u
		end
		return u
	end
	function r.NextInteger(_, a, b)
		return a + math.floor(nxt() * (b - a + 1))
	end
	return r
end }

-- Enum.<Type>.<Item>
local enumCache = {}
Enum = setmetatable({}, { __index = function(_, typeName)
	local items = enumCache[typeName]
	if not items then
		items = setmetatable({}, { __index = function(t, itemName)
			local item = typed({ Name = itemName, EnumType = typeName }, "EnumItem")
			rawset(t, itemName, item)
			return item
		end })
		enumCache[typeName] = items
	end
	return items
end })

---------------------------------------------------------------- signals / tasks
local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
		Once = function()
			return { Disconnect = function() end }
		end,
		Wait = function() end,
	}
end

task = {}
-- background loops (AI, story watcher) park forever on their first wait;
-- the main bake thread never yields
local spawned = setmetatable({}, { __mode = "k" })
function task.wait(_)
	local co = coroutine.running()
	if co and spawned[co] then
		coroutine.yield()
	end
	return 0
end
function task.spawn(f, ...)
	local co = coroutine.create(f)
	spawned[co] = true
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		error(err, 0)
	end
	return co
end
task.defer = task.spawn
function task.delay(_, _f) end
function warn(...)
	runtime.warnings = (runtime.warnings or 0) + 1
end

---------------------------------------------------------------- instances
local IS_A = {
	Part = { "Part", "FormFactorPart", "BasePart", "PVInstance" },
	WedgePart = { "WedgePart", "FormFactorPart", "BasePart", "PVInstance" },
	TrussPart = { "TrussPart", "BasePart", "PVInstance" },
	MeshPart = { "MeshPart", "BasePart", "PVInstance" },
	Model = { "Model", "PVInstance" },
	Workspace = { "Workspace", "Model", "PVInstance" },
	PointLight = { "PointLight", "Light" },
	SpotLight = { "SpotLight", "Light" },
	SurfaceLight = { "SurfaceLight", "Light" },
	SurfaceGui = { "SurfaceGui", "LayerCollector", "GuiBase2d" },
	BillboardGui = { "BillboardGui", "LayerCollector", "GuiBase2d" },
	TextLabel = { "TextLabel", "GuiObject", "GuiBase2d" },
	ModuleScript = { "ModuleScript", "LuaSourceContainer" },
	Script = { "Script", "BaseScript", "LuaSourceContainer" },
	NumberValue = { "NumberValue", "ValueBase" },
	Motor6D = { "Motor6D", "JointInstance" },
	Weld = { "Weld", "JointInstance" },
	WeldConstraint = { "WeldConstraint" },
	Humanoid = { "Humanoid" },
}

local DEFAULTS = {
	BasePart = function()
		return {
			Size = Vector3.new(4, 1, 2),
			CFrame = CFrame.new(),
			Color = Color3.fromRGB(163, 162, 165),
			Transparency = 0,
			Anchored = false,
			CanCollide = true,
		}
	end,
	Model = function()
		return { WorldPivot = CFrame.new() }
	end,
}

local Instance_ = {}
local IMT = {}
local methods = {}

-- joints keep their Part1 attached to Part0 like the engine does
local JOINTS = { Motor6D = true, Weld = true, WeldConstraint = true }
local jointsByPart0 = setmetatable({}, { __mode = "k" })
local propagate = true
local function snap(joint)
	local props = rawget(joint, "__props")
	local p0, p1 = props.Part0, props.Part1
	if not p0 or not p1 then
		return
	end
	if rawget(joint, "__class") == "WeldConstraint" then
		if props.__offset then
			p1.CFrame = p0.CFrame * props.__offset
		end
	else
		p1.CFrame = p0.CFrame * (props.C0 or CFrame.new()) * (props.C1 or CFrame.new()):Inverse()
	end
end

local function isA(inst, className)
	if className == "Instance" then
		return true
	end
	local list = IS_A[rawget(inst, "__class")]
	if list then
		return table.find(list, className) ~= nil
	end
	return rawget(inst, "__class") == className
end

IMT.__index = function(inst, k)
	if k == "ClassName" then
		return rawget(inst, "__class")
	elseif k == "Parent" then
		return rawget(inst, "__parent")
	elseif k == "Name" then
		return rawget(inst, "__props").Name or rawget(inst, "__class")
	elseif k == "Position" and isA(inst, "BasePart") then
		return rawget(inst, "__props").CFrame.Position
	elseif k == "Orientation" then
		return Vector3.new(0, 0, 0)
	end
	local m = methods[k]
	if m then
		return m
	end
	local props = rawget(inst, "__props")
	local v = props[k]
	if v ~= nil then
		return v
	end
	local children = rawget(inst, "__children")
	for _, c in children do
		if c.Name == k then
			return c
		end
	end
	if string.match(k, "^%u") and (string.find(k, "Changed") or string.find(k, "Triggered") or string.find(k, "Began") or string.find(k, "Ended") or string.find(k, "Added") or string.find(k, "Removing") or string.find(k, "Destroying") or k == "Died" or k == "Heartbeat" or k == "Activated" or k == "Completed" or k == "OnServerEvent" or k == "OnClientEvent" or k == "Touched") then
		return signal()
	end
	return nil
end

IMT.__newindex = function(inst, k, v)
	if k == "Parent" then
		local old = rawget(inst, "__parent")
		if old then
			local list = rawget(old, "__children")
			local i = table.find(list, inst)
			if i then
				table.remove(list, i)
			end
		end
		rawset(inst, "__parent", v)
		if v then
			table.insert(rawget(v, "__children"), inst)
		end
		return
	elseif k == "Position" and isA(inst, "BasePart") then
		local c = rawget(inst, "__props").CFrame
		inst.CFrame = c.Rotation + v
		return
	elseif k == "CFrame" and isA(inst, "BasePart") then
		rawget(inst, "__props").CFrame = v
		if propagate then
			local list = jointsByPart0[inst]
			if list then
				for _, joint in list do
					snap(joint)
				end
			end
		end
		return
	elseif JOINTS[rawget(inst, "__class")] and (k == "Part0" or k == "Part1" or k == "C0" or k == "C1") then
		local props = rawget(inst, "__props")
		props[k] = v
		if k == "Part0" and v then
			jointsByPart0[v] = jointsByPart0[v] or {}
			table.insert(jointsByPart0[v], inst)
		end
		if props.Part0 and props.Part1 then
			if rawget(inst, "__class") == "WeldConstraint" then
				props.__offset = props.Part0.CFrame:Inverse() * props.Part1.CFrame
			else
				snap(inst)
			end
		end
		return
	end
	rawget(inst, "__props")[k] = v
end
IMT.__tostring = function(inst)
	return inst.Name
end

function Instance_.new(className, parent)
	local props = {}
	for base, make in DEFAULTS do
		local list = IS_A[className]
		if className == base or (list and table.find(list, base)) then
			for k, v in make() do
				props[k] = v
			end
		end
	end
	local inst = setmetatable(typed({
		__class = className,
		__props = props,
		__children = {},
		__parent = nil,
		__attrs = {},
		__tags = {},
		__explicit = {},
	}, "Instance"), IMT)
	if parent then
		inst.Parent = parent
	end
	return inst
end
Instance = Instance_

function methods.IsA(inst, className)
	return isA(inst, className)
end
function methods.GetChildren(inst)
	return table.clone(rawget(inst, "__children"))
end
function methods.GetDescendants(inst)
	local out = {}
	local function walk(i)
		for _, c in rawget(i, "__children") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(inst)
	return out
end
function methods.FindFirstChild(inst, name, recursive)
	for _, c in rawget(inst, "__children") do
		if c.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in rawget(inst, "__children") do
			local found = c:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
methods.WaitForChild = methods.FindFirstChild
function methods.FindFirstChildOfClass(inst, className)
	for _, c in rawget(inst, "__children") do
		if c.ClassName == className then
			return c
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(inst, className)
	for _, c in rawget(inst, "__children") do
		if isA(c, className) then
			return c
		end
	end
	return nil
end
function methods.FindFirstAncestor(inst, name)
	local p = rawget(inst, "__parent")
	while p do
		if p.Name == name then
			return p
		end
		p = rawget(p, "__parent")
	end
	return nil
end
function methods.FindFirstAncestorWhichIsA(inst, className)
	local p = rawget(inst, "__parent")
	while p do
		if isA(p, className) then
			return p
		end
		p = rawget(p, "__parent")
	end
	return nil
end
function methods.IsDescendantOf(inst, ancestor)
	local p = rawget(inst, "__parent")
	while p do
		if p == ancestor then
			return true
		end
		p = rawget(p, "__parent")
	end
	return false
end
function methods.Destroy(inst)
	inst.Parent = nil
	rawset(inst, "__destroyed", true)
end
function methods.ClearAllChildren(inst)
	for _, c in table.clone(rawget(inst, "__children")) do
		c:Destroy()
	end
end
function methods.Clone(inst)
	local copy = Instance_.new(rawget(inst, "__class"))
	for k, v in rawget(inst, "__props") do
		rawget(copy, "__props")[k] = v
	end
	for k, v in rawget(inst, "__attrs") do
		rawget(copy, "__attrs")[k] = v
	end
	for k, v in rawget(inst, "__tags") do
		rawget(copy, "__tags")[k] = v
	end
	for _, c in rawget(inst, "__children") do
		c:Clone().Parent = copy
	end
	return copy
end
function methods.SetAttribute(inst, k, v)
	rawget(inst, "__attrs")[k] = v
end
function methods.GetAttribute(inst, k)
	return rawget(inst, "__attrs")[k]
end
function methods.GetAttributeChangedSignal()
	return signal()
end
function methods.GetPropertyChangedSignal()
	return signal()
end
function methods.GetFullName(inst)
	local names = {}
	local p = inst
	while p do
		table.insert(names, 1, p.Name)
		p = rawget(p, "__parent")
	end
	return table.concat(names, ".")
end

-- PVInstance
local function parts(inst)
	local out = {}
	if isA(inst, "BasePart") then
		table.insert(out, inst)
	end
	for _, d in inst:GetDescendants() do
		if isA(d, "BasePart") then
			table.insert(out, d)
		end
	end
	return out
end
function methods.GetPivot(inst)
	if isA(inst, "BasePart") then
		return inst.CFrame
	end
	local primary = rawget(inst, "__props").PrimaryPart
	if primary then
		return primary.CFrame
	end
	return rawget(inst, "__props").WorldPivot or CFrame.new()
end
function methods.PivotTo(inst, target)
	if isA(inst, "BasePart") then
		inst.CFrame = target
		return
	end
	local delta = target * inst:GetPivot():Inverse()
	propagate = false
	for _, p in parts(inst) do
		p.CFrame = delta * p.CFrame
	end
	propagate = true
	rawget(inst, "__props").WorldPivot = target
end
function methods.GetBoundingBox(inst)
	local pivot = inst:GetPivot()
	local rot = pivot.Rotation
	local inv = rot:Inverse()
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	local any = false
	for _, p in parts(inst) do
		any = true
		local s = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = inv * (p.CFrame * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz))
					lo = lo:Min(corner)
					hi = hi:Max(corner)
				end
			end
		end
	end
	if not any then
		return pivot, Vector3.new(0, 0, 0)
	end
	local center = rot * ((lo + hi) / 2)
	return rot + center, hi - lo
end
function methods.GetExtentsSize(inst)
	local _, size = inst:GetBoundingBox()
	return size
end
function methods.GetScale()
	return 1
end
function methods.ScaleTo()
	error("ScaleTo is not supported by the bake runtime")
end

-- Terrain
runtime.voxelWrites = {}
runtime.materialColors = {}
function methods.Clear() end
function methods.SetMaterialColor(_, material, color)
	runtime.materialColors[material.Name] = color
end
function methods.WriteVoxels(_, region, resolution, materials, occupancy)
	table.insert(runtime.voxelWrites, { region = region.args, res = resolution, materials = materials, occupancy = occupancy })
end
function methods.Raycast()
	return nil
end

-- Humanoid / Animator / misc
function methods.LoadAnimation()
	return { Play = function() end, Stop = function() end, AdjustSpeed = function() end }
end
function methods.MoveTo() end
function methods.ChangeState() end
function methods.SetNetworkOwner() end
function methods.ApplyAngularImpulse() end
function methods.FireServer() end
function methods.FireClient() end
function methods.FireAllClients() end

---------------------------------------------------------------- services
local dataModel = Instance_.new("DataModel")
local services = {}
local function service(name, className)
	local s = Instance_.new(className or name)
	s.Name = name
	s.Parent = dataModel
	services[name] = s
	return s
end
workspace = service("Workspace")
local terrain = Instance_.new("Terrain")
terrain.Name = "Terrain"
terrain.Parent = workspace
service("ReplicatedStorage")
service("ServerStorage")
service("ServerScriptService")
service("Lighting")
service("SoundService")
service("StarterPlayer")
local players = service("Players")
local collection = service("CollectionService")
local runService = service("RunService")
local insert = service("InsertService")
local tween = service("TweenService")
local pathfinding = service("PathfindingService")
service("PhysicsService")
service("TeleportService")
service("ProximityPromptService")
service("UserInputService")
service("ContextActionService")

function collection.AddTag(_, inst, tag)
	rawget(inst, "__tags")[tag] = true
end
function collection.HasTag(_, inst, tag)
	return rawget(inst, "__tags")[tag] == true
end
function collection.GetTagged()
	return {}
end
function runService.IsServer()
	return true
end
function runService.IsClient()
	return false
end
function runService.IsStudio()
	return true
end
function runService.IsRunning()
	return false
end
function insert.LoadAsset()
	error("assets cannot be loaded while baking")
end
function tween.Create()
	return { Play = function() end, Cancel = function() end, Completed = signal() }
end
function pathfinding.CreatePath()
	return { ComputeAsync = function() end, Status = nil, GetWaypoints = function()
		return {}
	end }
end
function players.GetPlayers()
	return {}
end
function players.CreateHumanoidModelFromDescription()
	error("no avatar service while baking")
end
game = dataModel
function methods.GetService(_, name)
	return services[name] or service(name)
end
runtime.services = services
runtime.game = dataModel

---------------------------------------------------------------- modules
-- bake.py registers each ModuleScript with runtime.module(path, loader)
local loaders = {}
local cache = {}
function runtime.module(path, className, loader)
	local segments = string.split(path, "/")
	local parent = dataModel
	for i, seg in segments do
		local existing = parent:FindFirstChild(seg)
		if not existing then
			local cls = if i == #segments then className else "Folder"
			if parent == dataModel then
				existing = services[seg] or service(seg)
			else
				existing = Instance_.new(cls)
				existing.Name = seg
				existing.Parent = parent
			end
		elseif i == #segments and className == "ModuleScript" then
			rawset(existing, "__class", "ModuleScript")
		end
		parent = existing
	end
	loaders[parent] = loader
end

local rawrequire = require
function require(target)
	if type(target) ~= "table" then
		return rawrequire(target)
	end
	if cache[target] ~= nil then
		return cache[target]
	end
	local loader = loaders[target]
	if not loader then
		error("no module registered for " .. target:GetFullName())
	end
	local result = loader(target)
	cache[target] = result
	return result
end

return runtime

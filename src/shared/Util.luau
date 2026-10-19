--!strict
-- Small helpers shared by server and client code.

local TweenService = game:GetService("TweenService")

local Util = {}

-- Instance.new with a property table. Parent is applied last so the instance
-- is fully configured before it replicates.
function Util.create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Util.tween(
	inst: Instance,
	duration: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(inst, info, goal)
	tween:Play()
	return tween
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

function Util.smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

function Util.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Distance from point p to segment ab on the XZ plane, plus the segment
-- parameter of the closest point.
function Util.segmentDistance2D(px: number, pz: number, ax: number, az: number, bx: number, bz: number): (number, number)
	local dx, dz = bx - ax, bz - az
	local lenSq = dx * dx + dz * dz
	local t = 0
	if lenSq > 0 then
		t = math.clamp(((px - ax) * dx + (pz - az) * dz) / lenSq, 0, 1)
	end
	local cx, cz = ax + dx * t, az + dz * t
	local ex, ez = px - cx, pz - cz
	return math.sqrt(ex * ex + ez * ez), t
end

-- Closest point on a polyline of Vector2s. Returns distance, closest point
-- and distance travelled along the line to that point.
function Util.polylineClosest(points: { Vector2 }, p: Vector2): (number, Vector2, number)
	local best, bestPoint, bestAlong = math.huge, points[1], 0
	local travelled = 0
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local d, t = Util.segmentDistance2D(p.X, p.Y, a.X, a.Y, b.X, b.Y)
		local segLen = (b - a).Magnitude
		if d < best then
			best = d
			bestPoint = a:Lerp(b, t)
			bestAlong = travelled + segLen * t
		end
		travelled += segLen
	end
	return best, bestPoint, bestAlong
end

function Util.polylineLength(points: { Vector2 }): number
	local total = 0
	for i = 1, #points - 1 do
		total += (points[i + 1] - points[i]).Magnitude
	end
	return total
end

-- Point and tangent at a distance along a polyline.
function Util.polylineSample(points: { Vector2 }, along: number): (Vector2, Vector2)
	local remaining = along
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local segLen = (b - a).Magnitude
		if remaining <= segLen or i == #points - 1 then
			local t = if segLen > 0 then math.clamp(remaining / segLen, 0, 1) else 0
			return a:Lerp(b, t), (b - a).Unit
		end
		remaining -= segLen
	end
	return points[#points], Vector2.new(0, 1)
end

function Util.shuffle<T>(list: { T }, rng: Random): { T }
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function Util.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Every BasePart in a model (or the instance itself if it is a part).
function Util.parts(root: Instance): { BasePart }
	local list = {}
	if root:IsA("BasePart") then
		table.insert(list, root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

function Util.setModelProperty(root: Instance, property: string, value: any)
	for _, p in Util.parts(root) do
		(p :: any)[property] = value
	end
end

return Util

--!strict
-- The farmhouse's rooms are SCALE times wider and deeper than the plan the
-- code was written against (same storey heights, same doors and windows).
-- Everything that places something in the house keeps using the original
-- plan's house-local numbers and maps them here, so the whole game moves
-- with the bigger rooms: World/House.luau and HouseWings.luau, the chores,
-- clues, cellar, lights and hiding spots, and the cutscenes on the client.
-- tools/blender/house_layout.py mirrors this for the Blender meshes.
--
-- Per axis, the plan's wall lines move out by SCALE. Anything within NEAR
-- studs of a wall line keeps its distance to that wall (so furniture stays
-- against the walls and a doorway keeps its width); the middle of each room
-- stretches to take up the extra space.
--
-- On the server the house also moves its furniture as whole pieces
-- (World/House.luau) and registers them here; `place` then keeps anything
-- placed on a piece of furniture (a key on a nightstand, candles on the
-- table) on that same piece.

local HouseLayout = {}

HouseLayout.SCALE = 1.5
HouseLayout.NEAR = 3

-- the original plan's wall lines, house-local
local LINES_X = { -68, -32, -5, 5, 32, 68 }
local LINES_Z = { -24, 0, 24 }

local function map(v: number, lines: { number }): number
	local K = HouseLayout.SCALE
	local n = #lines
	if v <= lines[1] then
		return lines[1] * K + (v - lines[1])
	elseif v >= lines[n] then
		return lines[n] * K + (v - lines[n])
	end
	for i = 1, n - 1 do
		local a, b = lines[i], lines[i + 1]
		if v <= b then
			local d = math.min(HouseLayout.NEAR, (b - a) / 2)
			if v <= a + d then
				return a * K + (v - a)
			elseif v >= b - d then
				return b * K + (v - b)
			end
			local t = (v - (a + d)) / ((b - d) - (a + d))
			return (a * K + d) + t * ((b * K - d) - (a * K + d))
		end
	end
	return v
end

-- the inverse: where a spot of the bigger house was on the plan
local function unmap(w: number, lines: { number }): number
	local K = HouseLayout.SCALE
	local n = #lines
	if w <= lines[1] * K then
		return lines[1] + (w - lines[1] * K)
	elseif w >= lines[n] * K then
		return lines[n] + (w - lines[n] * K)
	end
	for i = 1, n - 1 do
		local a, b = lines[i], lines[i + 1]
		if w <= b * K then
			local d = math.min(HouseLayout.NEAR, (b - a) / 2)
			if w <= a * K + d then
				return a + (w - a * K)
			elseif w >= b * K - d then
				return b + (w - b * K)
			end
			local t = (w - (a * K + d)) / ((b * K - d) - (a * K + d))
			return (a + d) + t * ((b - d) - (a + d))
		end
	end
	return w
end

-- A house-local point of the bigger house, back on the plan (for checks
-- like "is the player in the kitchen" written against the plan's numbers).
function HouseLayout.unmap(v: Vector3): Vector3
	return Vector3.new(unmap(v.X, LINES_X), v.Y, unmap(v.Z, LINES_Z))
end

function HouseLayout.x(v: number): number
	return map(v, LINES_X)
end

function HouseLayout.z(v: number): number
	return map(v, LINES_Z)
end

-- A point of the original plan, in the bigger house (house-local).
function HouseLayout.at(x: number, y: number, z: number): Vector3
	return Vector3.new(map(x, LINES_X), y, map(z, LINES_Z))
end

function HouseLayout.point(v: Vector3): Vector3
	return HouseLayout.at(v.X, v.Y, v.Z)
end

-- Moves a house-local CFrame to its spot in the bigger house; keeps its turn.
function HouseLayout.cframe(cf: CFrame): CFrame
	return cf.Rotation + HouseLayout.point(cf.Position)
end

-- An axis-aligned box of the plan that runs with the rooms (a floor, a
-- ceiling, a skirting board, a beam): along each horizontal axis where it is
-- at least 4 studs long its ends are mapped, so it stretches; shorter sides
-- keep their size. Returns the new size and centre.
function HouseLayout.span(size: Vector3, center: Vector3): (Vector3, Vector3)
	local function along(c: number, s: number, f: (number) -> number): (number, number)
		if s >= 4 then
			local lo, hi = f(c - s / 2), f(c + s / 2)
			return (lo + hi) / 2, hi - lo
		end
		return f(c), s
	end
	local cx, sx = along(center.X, size.X, HouseLayout.x)
	local cz, sz = along(center.Z, size.Z, HouseLayout.z)
	return Vector3.new(sx, size.Y, sz), Vector3.new(cx, center.Y, cz)
end

-- `span` for a box turned about Y by a multiple of 90 degrees.
function HouseLayout.spanCF(size: Vector3, cf: CFrame): (Vector3, CFrame)
	local swapped = math.abs(cf.RightVector.Z) > 0.7
	local world = if swapped then Vector3.new(size.Z, size.Y, size.X) else size
	local s, c = HouseLayout.span(world, cf.Position)
	return if swapped then Vector3.new(s.Z, s.Y, s.X) else s, cf.Rotation + c
end

---------------------------------------------------------------- furniture pieces (server)

export type Piece = { lo: Vector3, hi: Vector3, offset: Vector3 }

local pieces: { Piece } = {}

-- How far a piece of furniture spanning lo..hi (house-local, original plan)
-- moves: along each axis by its edge against a wall if it stands against
-- one, otherwise by its centre.
function HouseLayout.offsetFor(lo: Vector3, hi: Vector3): Vector3
	local function along(a: number, b: number, lines: { number }): number
		local near = HouseLayout.NEAR
		for _, line in lines do
			if math.abs(a - line) < near then
				return map(a, lines) - a
			end
		end
		for _, line in lines do
			if math.abs(b - line) < near then
				return map(b, lines) - b
			end
		end
		local c = (a + b) / 2
		return map(c, lines) - c
	end
	return Vector3.new(along(lo.X, hi.X, LINES_X), 0, along(lo.Z, hi.Z, LINES_Z))
end

function HouseLayout.register(list: { Piece })
	pieces = list
end

-- Like `at`, but a point on (or in) a registered piece of furniture moves
-- with that piece.
function HouseLayout.place(v: Vector3): Vector3
	local best: Piece? = nil
	local bestArea = math.huge
	for _, p in pieces do
		if v.X >= p.lo.X - 0.6 and v.X <= p.hi.X + 0.6 and v.Z >= p.lo.Z - 0.6 and v.Z <= p.hi.Z + 0.6 and v.Y >= p.lo.Y - 0.5 and v.Y <= p.hi.Y + 4 then
			local area = (p.hi.X - p.lo.X) * (p.hi.Z - p.lo.Z)
			if area < bestArea then
				best = p
				bestArea = area
			end
		end
	end
	if best then
		return v + best.offset
	end
	return HouseLayout.point(v)
end

function HouseLayout.placeCFrame(cf: CFrame): CFrame
	return cf.Rotation + HouseLayout.place(cf.Position)
end

return HouseLayout

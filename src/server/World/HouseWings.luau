--!strict
-- The farmhouse's two wings and the attic, added either side of the original
-- house (House.luau) so it is about three times the size, with loops to run
-- around in a chase:
--
--   west wing (x -68..-32): parlor (ground N), mudroom + back stairs
--                           (ground S), Grandma's room (upper N), sewing
--                           room (upper S)
--   east wing (x 32..68):   sunroom (ground N), workshop with the crafting
--                           bench (ground S), guest room (upper N), storage
--                           room with a ladder into the wing loft (upper S)
--   attic (over the core):  hatch and ladder from the upstairs hall, and a
--                           crawl hole through the east gable into the wing
--                           loft
--
-- House-local coordinates as in House.luau (ground floor y = 0, upper floor
-- y = 13, ceiling slab top y = 25, front door facing -Z). Furniture reuses
-- the Blender meshes of the main house (MeshLibrary stand-ins) with the same
-- collision boxes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)
local Util = require(ReplicatedStorage.Shared.Util)
local AssetService = require(script.Parent.Parent.Systems.AssetService)
local Doors = require(script.Parent.Parent.Systems.Doors)
local Hiding = require(script.Parent.Parent.Systems.Hiding)

local HouseWings = {}

type Opening = Build.Opening

export type Ctx = {
	O: CFrame,
	U: number,
	model: Model,
	structure: Model,
	furniture: Model,
	lights: Model,
	shell: Model,
	rng: Util.Rng,
	foundation: number,
	wall: (a: Vector2, b: Vector2, y0: number, h: number, openings: { Opening }, color: Color3?, mat: Enum.Material?) -> (),
	exterior: (a: Vector2, b: Vector2, y0: number, h: number, openings: { Opening }) -> (),
	windowFill: (cf: CFrame, boarded: boolean) -> (),
	door: (at: number) -> Opening,
	window: (at: number) -> Opening,
}

export type Info = {
	groundPatrol: { Vector3 },
	upperPatrol: { Vector3 },
	keySpots: { CFrame },
	crowbarSpots: { CFrame },
	spots: { [string]: CFrame },
	workbench: CFrame, -- top centre of the crafting bench, its -Z the front
	recordPlayer: BasePart,
	radio: BasePart,
	attic: Vector3,
}

local rgb = Color3.fromRGB
local M = Enum.Material
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local FLOOR = rgb(70, 50, 34)
local TRIM = rgb(60, 44, 32)
local WOOD = rgb(80, 60, 44)
local WALLPAPER_W = rgb(108, 98, 84)
local WALLPAPER_E = rgb(98, 104, 92)

-- Collision boxes of the shared Blender furniture, in the item's own frame
-- (pivot at the floor centre, -Z the front): { size, offset }
local FURNITURE: { [string]: { { Vector3 } } } = {
	Bed = {
		{ Vector3.new(7, 1.4, 9), Vector3.new(0, 1.4, 0) },
		{ Vector3.new(6.6, 0.8, 8.6), Vector3.new(0, 2.5, 0) },
		{ Vector3.new(7, 5, 0.6), Vector3.new(0, 2.5, 4.6) },
		{ Vector3.new(2.6, 0.7, 1.6), Vector3.new(0, 3.2, 3.5) },
	},
	Nightstand = { { Vector3.new(2, 2.4, 2), Vector3.new(0, 1.2, 0) } },
	Bookshelf = { { Vector3.new(6, 9, 1.4), Vector3.new(0, 4.5, 0) } },
	Dresser = {
		{ Vector3.new(6, 3.4, 2), Vector3.new(0, 1.7, 0) },
		{ Vector3.new(4, 4, 0.2), Vector3.new(0, 5.6, 0.8) },
	},
	Sofa = {
		{ Vector3.new(9, 1.6, 4), Vector3.new(0, 1.3, 0) },
		{ Vector3.new(9, 3.6, 1.4), Vector3.new(0, 2.3, 1.5) },
		{ Vector3.new(1.2, 2.6, 4), Vector3.new(-4.9, 1.8, 0) },
		{ Vector3.new(1.2, 2.6, 4), Vector3.new(4.9, 1.8, 0) },
	},
	CoffeeTable = {
		{ Vector3.new(5, 0.3, 3), Vector3.new(0, 1.8, 0) },
		{ Vector3.new(0.3, 1.6, 2.6), Vector3.new(-2, 0.85, 0) },
		{ Vector3.new(0.3, 1.6, 2.6), Vector3.new(2, 0.85, 0) },
	},
	KitchenTable = {
		{ Vector3.new(8, 0.5, 4), Vector3.new(0, 3, 0) },
		{ Vector3.new(0.5, 2.8, 0.5), Vector3.new(-3.5, 1.4, -1.5) },
		{ Vector3.new(0.5, 2.8, 0.5), Vector3.new(3.5, 1.4, -1.5) },
		{ Vector3.new(0.5, 2.8, 0.5), Vector3.new(-3.5, 1.4, 1.5) },
		{ Vector3.new(0.5, 2.8, 0.5), Vector3.new(3.5, 1.4, 1.5) },
	},
	KitchenCounter = {
		{ Vector3.new(4, 3.4, 2.6), Vector3.new(0, 1.7, 0) },
		{ Vector3.new(4.05, 0.3, 2.8), Vector3.new(0, 3.5, -0.1) },
	},
	GrandfatherClock = { { Vector3.new(2.2, 8, 1.4), Vector3.new(0, 4, 0) } },
	ChinaHutch = { { Vector3.new(7, 8, 2.5), Vector3.new(0, 4, 0) } },
	ToyChest = { { Vector3.new(4, 2.2, 2.4), Vector3.new(0, 1.1, 0) } },
	KidsBed = {
		{ Vector3.new(4, 1.6, 7), Vector3.new(0, 0.8, 0) },
		{ Vector3.new(3.6, 0.6, 6.6), Vector3.new(0, 1.9, 0) },
	},
}

function HouseWings.build(ctx: Ctx): Info
	local O, U, rng = ctx.O, ctx.U, ctx.rng
	local structure, furniture, lights, shell = ctx.structure, ctx.furniture, ctx.lights, ctx.shell
	local wall, exterior, door, window = ctx.wall, ctx.exterior, ctx.door, ctx.window

	local function L(x: number, y: number, z: number): CFrame
		return O * CF(x, y, z)
	end
	local function at(x: number, y: number, z: number): Vector3
		return L(x, y, z).Position
	end
	local function box(p: Instance, size: Vector3, x: number, y: number, z: number, color: Color3, mat: Enum.Material, extra: { [string]: any }?): Part
		return Build.part(p, size, L(x, y, z), color, mat, extra)
	end
	local function boxCF(p: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, extra: { [string]: any }?): Part
		return Build.part(p, size, O * cf, color, mat, extra)
	end
	local noCollide = { CanCollide = false, CastShadow = false }

	-- A Blender furniture stand-in with its collision boxes. Returns the
	-- model and its pivot (house-local).
	local function piece(meshName: string, x: number, y: number, z: number, yawDeg: number, color: Color3, mat: Enum.Material): (Model, CFrame)
		local pivot = CF(x, y, z) * ANG(0, rad(yawDeg), 0)
		local m = Instance.new("Model")
		m.Name = meshName
		m.WorldPivot = O * pivot
		m:SetAttribute("Mesh", meshName)
		m.Parent = furniture
		Build.tag(m, "BlenderMesh")
		for _, spec in FURNITURE[meshName] :: { { Vector3 } } do
			boxCF(m, spec[1], pivot * CF(spec[2]), color, mat)
		end
		return m, pivot
	end

	-- A wardrobe you can hide in; the doors face the item's -Z.
	local function hideWardrobe(x: number, y: number, z: number, yawDeg: number, label: string)
		local pivot = CF(x, y, z) * ANG(0, rad(yawDeg), 0)
		local m = Instance.new("Model")
		m.Name = "Wardrobe"
		m.WorldPivot = O * pivot
		m:SetAttribute("Mesh", "Wardrobe")
		m.Parent = furniture
		Build.tag(m, "BlenderMesh")
		local body = boxCF(m, Vector3.new(6, 9, 3), pivot * CF(0, 4.5, 0), rgb(64, 46, 32), M.Wood)
		body.Name = label
		body.CanCollide = false
		for _, dx in { -1.45, 1.45 } do
			boxCF(m, Vector3.new(2.8, 8.6, 0.2), pivot * CF(dx, 4.5, -1.55), rgb(54, 38, 28), M.WoodPlanks, { CanCollide = false })
		end
		Hiding.add(body, O * pivot * CF(0, 3, 0.1), O * pivot * CF(0, 3, -4.4), label)
	end

	local function rug(x: number, y: number, z: number, w: number, d: number, color: Color3)
		box(furniture, Vector3.new(w, 0.05, d), x, y + 0.03, z, color, M.Carpet, { CanCollide = false })
	end

	local function painting(cf: CFrame, w: number, h: number, canvas: Color3)
		boxCF(furniture, Vector3.new(w + 0.5, h + 0.5, 0.2), cf, TRIM, M.Wood, noCollide)
		boxCF(furniture, Vector3.new(w, h, 0.05), cf * CF(0, 0, -0.12), canvas, M.Fabric, noCollide)
	end

	local function truss(x: number, y0: number, z: number, height: number)
		local t = Instance.new("TrussPart")
		t.Anchored = true
		t.Size = Vector3.new(2, height, 2)
		t.CFrame = L(x, y0 + height / 2, z)
		t.Color = rgb(96, 74, 52)
		t.Material = M.Wood
		t.Parent = structure
	end

	local fh = ctx.foundation + 6
	local stone = rgb(70, 66, 62)
	for _, side in { -1, 1 } do
		local cx = side * 50.25
		--------------------------------------------------------- foundation, floors, ceilings
		box(structure, Vector3.new(36.5, fh, 49), cx, -fh / 2, 0, stone, M.Cobblestone)
		-- ground floors: parlor / sunroom (north), mudroom / workshop (south)
		box(structure, Vector3.new(36, 0.4, 24), side * 50, -0.2, -12, if side < 0 then FLOOR else rgb(150, 140, 120), if side < 0 then M.WoodPlanks else M.CeramicTiles)
		box(structure, Vector3.new(36, 0.4, 24), side * 50, -0.2, 12, if side < 0 then rgb(84, 80, 76) else rgb(90, 86, 80), if side < 0 then M.Slate else M.Concrete)
	end
	-- upper floors: the west one has the back stairwell (x -67.5..-62.5, z 6..20)
	box(structure, Vector3.new(36, 1, 30), -50, 12.5, -9, FLOOR, M.WoodPlanks)
	box(structure, Vector3.new(30.5, 1, 18), -47.25, 12.5, 15, FLOOR, M.WoodPlanks)
	box(structure, Vector3.new(5.5, 1, 4), -65.25, 12.5, 22, FLOOR, M.WoodPlanks)
	box(structure, Vector3.new(36, 1, 48), 50, 12.5, 0, FLOOR, M.WoodPlanks)
	-- ceilings / loft floors; the east one has the loft hatch (x 58..62, z 1..5)
	local ceiling = rgb(80, 70, 58)
	box(structure, Vector3.new(36, 1, 48), -50, 24.5, 0, ceiling, M.WoodPlanks)
	box(structure, Vector3.new(26, 1, 48), 45, 24.5, 0, ceiling, M.WoodPlanks)
	box(structure, Vector3.new(6, 1, 48), 65, 24.5, 0, ceiling, M.WoodPlanks)
	box(structure, Vector3.new(4, 1, 25), 60, 24.5, -11.5, ceiling, M.WoodPlanks)
	box(structure, Vector3.new(4, 1, 19), 60, 24.5, 14.5, ceiling, M.WoodPlanks)

	------------------------------------------------------------ walls
	for _, side in { -1, 1 } do
		local inner, outer = side * 32.5, side * 68.5
		local a, b = math.min(inner, outer), math.max(inner, outer)
		-- front and back, ground and upper
		exterior(Vector2.new(a, -24), Vector2.new(b, -24), 0, 12, { window(side * 42), window(side * 58) })
		exterior(Vector2.new(a, -24), Vector2.new(b, -24), 13, 11, { window(side * 42), window(side * 58) })
		exterior(Vector2.new(a, 24), Vector2.new(b, 24), 0, 12, { window(side * 45), window(side * 57) })
		exterior(Vector2.new(a, 24), Vector2.new(b, 24), 13, 11, { window(side * 50) })
		-- end walls
		exterior(Vector2.new(side * 68, -24), Vector2.new(side * 68, 24), 0, 12, if side < 0 then { window(-12) } else { window(-12), window(14) })
		exterior(Vector2.new(side * 68, -24), Vector2.new(side * 68, 24), 13, 11, { window(-12), window(12) })
		-- the wall between the north and south rooms
		local ia, ib = math.min(side * 33, side * 67.5), math.max(side * 33, side * 67.5)
		wall(Vector2.new(ia, 0), Vector2.new(ib, 0), 0, 12, { door(side * 50) }, if side < 0 then WALLPAPER_W else WALLPAPER_E)
		wall(Vector2.new(ia, 0), Vector2.new(ib, 0), 13, 11, { door(side * 45) }, if side < 0 then WALLPAPER_W else WALLPAPER_E)
	end
	-- glass, frames and curtains in the new windows
	for _, side in { -1, 1 } do
		for _, x in { 42, 58 } do
			ctx.windowFill(CF(side * x, 6.25, -24), side > 0 and x == 58)
			ctx.windowFill(CF(side * x, 19.25, -24), side < 0 and x == 42)
		end
		for _, x in { 45, 57 } do
			ctx.windowFill(CF(side * x, 6.25, 24) * ANG(0, math.pi, 0), x == 57)
		end
		ctx.windowFill(CF(side * 50, 19.25, 24) * ANG(0, math.pi, 0), side > 0)
		local face = if side < 0 then rad(90) else rad(-90)
		ctx.windowFill(CF(side * 68, 6.25, -12) * ANG(0, face, 0), side > 0)
		if side > 0 then
			ctx.windowFill(CF(side * 68, 6.25, 14) * ANG(0, face, 0), true)
		end
		ctx.windowFill(CF(side * 68, 19.25, -12) * ANG(0, face, 0), false)
		ctx.windowFill(CF(side * 68, 19.25, 12) * ANG(0, face, 0), side < 0)
	end

	------------------------------------------------------------ roofs, gables, attic
	-- wing roofs sit lower than the main one (ridge at y 33 against 36)
	local roofColor = rgb(44, 40, 38)
	for _, side in { -1, 1 } do
		Build.wedge(shell, Vector3.new(39, 8, 26.5), L(side * 50.5, 29, -12.75), roofColor, M.RoofShingles)
		Build.wedge(shell, Vector3.new(39, 8, 26.5), L(side * 50.5, 29, 12.75) * ANG(0, math.pi, 0), roofColor, M.RoofShingles)
		box(shell, Vector3.new(39, 0.6, 1.2), side * 50.5, 33.1, 0, rgb(34, 30, 28), M.Wood)
		-- wing end gables (inside face) and their siding
		Build.wedge(structure, Vector3.new(1, 8, 24), L(side * 68, 29, -12), rgb(96, 84, 70), M.Plaster)
		Build.wedge(structure, Vector3.new(1, 8, 24), L(side * 68, 29, 12) * ANG(0, math.pi, 0), rgb(96, 84, 70), M.Plaster)
		Build.wedge(shell, Vector3.new(0.2, 8, 24), L(side * 68.6, 29, -12), rgb(104, 92, 78), M.WoodPlanks)
		Build.wedge(shell, Vector3.new(0.2, 8, 24), L(side * 68.6, 29, 12) * ANG(0, math.pi, 0), rgb(104, 92, 78), M.WoodPlanks)
	end
	-- the main house's gables close the attic; the east one has a crawl hole
	-- (z -2..2, y 25..30.5) into the east wing loft
	local gable = rgb(90, 80, 66)
	local slope = 11 / 26
	Build.wedge(structure, Vector3.new(1, 11, 26), L(-32.5, 30.5, -13), gable, M.WoodPlanks)
	Build.wedge(structure, Vector3.new(1, 11, 26), L(-32.5, 30.5, 13) * ANG(0, math.pi, 0), gable, M.WoodPlanks)
	local h24 = slope * 24
	Build.wedge(structure, Vector3.new(1, h24, 24), L(32.5, 25 + h24 / 2, -14), gable, M.WoodPlanks)
	Build.wedge(structure, Vector3.new(1, h24, 24), L(32.5, 25 + h24 / 2, 14) * ANG(0, math.pi, 0), gable, M.WoodPlanks)
	box(structure, Vector3.new(1, 4.8, 4), 32.5, 32.9, 0, gable, M.WoodPlanks)
	for _, dz in { -2.2, 2.2 } do
		box(structure, Vector3.new(1.2, 5.6, 0.4), 32.5, 27.8, dz, TRIM, M.Wood, noCollide)
	end
	-- attic: floorboards are the ceiling slab; a ladder up from the upstairs
	-- hall (hatch x 0.5..4.5, z -6..-2, where the roof is high) and one into
	-- the east loft
	truss(2.5, 13, -1, 14)
	truss(60, 13, 6, 14)
	box(structure, Vector3.new(4.6, 0.3, 0.4), 2.5, 25.15, -6.2, TRIM, M.Wood, noCollide)
	box(structure, Vector3.new(4.6, 0.3, 0.4), 60, 25.15, 0.8, TRIM, M.Wood, noCollide)
	-- rafters
	for i = -6, 6 do
		local x = i * 5
		for _, s in { -1, 1 } do
			boxCF(structure, Vector3.new(0.5, 0.6, 28.5), CF(x, 30.3, s * 12.7) * ANG(s * math.atan(slope), 0, 0), rgb(58, 44, 32), M.Wood, noCollide)
		end
	end
	Build.bulb(lights, L(0, 33.5, 0), rgb(255, 170, 110), 0.25, 18, true)
	Build.bulb(lights, L(-20, 32.5, 2), rgb(255, 150, 90), 0.15, 14, true)

	------------------------------------------------------------ doors
	local function hingeZ(x: number, zc: number, y0: number): CFrame
		return L(x, y0, zc - 2.4) * ANG(0, -math.pi / 2, 0)
	end
	local function hingeX(xc: number, z: number, y0: number): CFrame
		return L(xc - 2.4, y0, z)
	end
	local model = ctx.model
	Doors.create(model, hingeZ(-32, -13.75, 0), 4.8, 9, { name = "ParlorDoor", swing = -1 })
	Doors.create(model, hingeX(-50, 0, 0), 4.8, 9, { name = "MudroomDoor", swing = 1, color = rgb(84, 70, 56) })
	Doors.create(model, hingeZ(-32, -15, U), 4.8, 9, { name = "GrandmaDoor", swing = -1, color = rgb(96, 80, 70) })
	Doors.create(model, hingeX(-45, 0, U), 4.8, 9, { name = "SewingDoor", swing = -1 })
	Doors.create(model, hingeZ(32, 20.5, 0), 4.8, 9, { name = "WorkshopDoor", swing = 1, color = rgb(70, 60, 50) })
	Doors.create(model, hingeZ(32, -17, U), 4.8, 9, { name = "GuestDoor", swing = 1 })
	Doors.create(model, hingeZ(32, 3, U), 4.8, 9, { name = "StorageDoor", swing = 1, color = rgb(76, 62, 50) })
	Doors.create(model, hingeX(50, 0, 0), 4.8, 9, { name = "SunroomDoor", swing = -1, color = rgb(180, 176, 160) })

	------------------------------------------------------------ back stairs (west wing, up toward +z)
	local steps = 13
	local run = 14 / steps
	for i = 1, steps do
		local z0 = 6 + (i - 1) * run
		box(structure, Vector3.new(5, i, run), -65, i / 2, z0 + run / 2, rgb(66, 48, 34), M.WoodPlanks)
	end
	box(structure, Vector3.new(0.3, 0.3, 14), -62.4, U + 3.2, 13, TRIM, M.Wood)
	box(structure, Vector3.new(5, 0.3, 0.3), -65, U + 3.2, 6, TRIM, M.Wood)
	for _, z in { 6.2, 9.5, 13, 16.5, 19.8 } do
		box(structure, Vector3.new(0.25, 3.2, 0.25), -62.4, U + 1.6, z, TRIM, M.Wood)
	end
	Build.part(structure, Vector3.new(0.3, 0.3, 19), L(-62.4, 6.5 + 3, 13) * ANG(-math.atan2(13, 14), 0, 0), TRIM, M.Wood)

	------------------------------------------------------------ parlor (west, ground north)
	local lamp = rgb(255, 180, 110)
	Build.bulb(lights, L(-50, 10.5, -12), lamp, 0.45, 18, true)
	rug(-54, 0, -11, 14, 10, rgb(70, 40, 52))
	piece("Sofa", -55, 0, -7, 0, rgb(56, 36, 30), M.Leather)
	piece("CoffeeTable", -55, 0, -12.5, 0, TRIM, M.Wood)
	piece("Bookshelf", -66.7, 0, -20, -90, TRIM, M.Wood)
	piece("Bookshelf", -66.7, 0, -4, -90, TRIM, M.Wood)
	piece("GrandfatherClock", -35, 0, -22.6, 180, rgb(58, 40, 28), M.Wood)
	-- upright piano against the north wall, keys yellowed, one stool
	box(furniture, Vector3.new(8, 6, 2.4), -50, 3, -22.4, rgb(36, 24, 18), M.Wood)
	box(furniture, Vector3.new(7.2, 0.3, 1.2), -50, 3.4, -20.8, rgb(220, 208, 170), M.SmoothPlastic)
	for i = 0, 11 do
		box(furniture, Vector3.new(0.18, 0.12, 0.7), -53.2 + i * 0.6, 3.6, -20.95, rgb(16, 14, 12), M.SmoothPlastic, noCollide)
	end
	box(furniture, Vector3.new(3, 0.4, 1.4), -50, 2.1, -18.6, rgb(40, 28, 20), M.Leather)
	for _, dx in { -1.2, 1.2 } do
		box(furniture, Vector3.new(0.3, 1.9, 1), -50 + dx, 0.95, -18.6, rgb(36, 24, 18), M.Wood)
	end
	for i = 0, 2 do
		Build.candle(furniture, L(-52.5 + i * 2.5, 6.05, -22.6), 0.4 + i * 0.15)
	end
	painting(CF(-58, 7.5, -23.35) * ANG(0, math.pi, 0), 4, 5, rgb(60, 50, 40))
	painting(CF(-42, 7, -23.35) * ANG(0, math.pi, 0), 3, 3.6, rgb(50, 56, 48))
	-- the record player (Distractions: plays and draws the family to it)
	box(furniture, Vector3.new(3, 2.6, 2.2), -38, 1.3, -4, TRIM, M.Wood)
	local recordPlayer = box(furniture, Vector3.new(1.8, 0.5, 1.6), -38, 2.85, -4, rgb(110, 70, 40), M.Wood)
	recordPlayer.Name = "RecordPlayer"
	Build.post(furniture, 0.05, 1.3, L(-38, 3.13, -4), rgb(20, 20, 20), M.SmoothPlastic)
	boxCF(furniture, Vector3.new(0.6, 1.4, 0.6), CF(-37.3, 3.9, -3.5) * ANG(rad(-30), 0, rad(20)), rgb(180, 150, 70), M.Metal, noCollide)
	-- deer skulls watching from above the bookshelves
	for _, z in { -20, -4 } do
		local mount = Instance.new("Model")
		mount.Name = "DeerSkull"
		mount.WorldPivot = L(-67.2, 9.7, z) * ANG(0, rad(-90), 0)
		mount:SetAttribute("Mesh", "DeerSkull")
		mount.Parent = furniture
		Build.tag(mount, "BlenderMesh")
		box(mount, Vector3.new(0.8, 1.6, 1.2), -67.2, 10.5, z, rgb(214, 206, 190), M.SmoothPlastic, { CanCollide = false })
	end

	------------------------------------------------------------ mudroom (west, ground south)
	Build.bulb(lights, L(-46, 10.5, 12), rgb(255, 196, 140), 0.35, 16, true)
	-- coat hooks with coats that are not the family's sizes
	box(furniture, Vector3.new(10, 0.3, 0.4), -44, 7.5, 23.3, TRIM, M.Wood, noCollide)
	for i = 0, 5 do
		local hue = rng:NextNumber()
		box(furniture, Vector3.new(1.4, 3.8, 0.6), -48.5 + i * 1.8, 5.4, 23, Color3.fromHSV(hue, 0.35, 0.35), M.Fabric, noCollide)
	end
	-- boots, far too many pairs
	for i = 0, 9 do
		box(furniture, Vector3.new(0.7, 0.9, 1.3), -49 + i * 1.1, 0.45, 21.6 - (i % 2) * 0.3, rgb(46 + i * 4, 34, 26), M.Leather, noCollide)
	end
	-- wash tub, mangle and a chest freezer
	box(furniture, Vector3.new(3.6, 3.4, 3), -36, 1.7, 21.8, rgb(200, 200, 196), M.Metal)
	box(furniture, Vector3.new(3, 0.3, 2.4), -36, 3.5, 21.8, rgb(40, 30, 24), M.Glass, { Transparency = 0.2 })
	box(furniture, Vector3.new(6, 3.2, 2.8), -41, 1.6, 4.2, rgb(214, 210, 200), M.Metal)
	box(furniture, Vector3.new(6.1, 0.2, 2.9), -41, 3.3, 4.2, rgb(190, 186, 176), M.Metal)
	Build.stain(furniture, L(-41, 0.05, 6.5), Vector2.new(1.4, 1.1), rng)
	hideWardrobe(-56, 0, 21.8, 0, "Closet")

	------------------------------------------------------------ Grandma's room (west, upper north)
	Build.bulb(lights, L(-50, U + 9.5, -12), rgb(255, 170, 110), 0.3, 16, true)
	rug(-52, U, -12, 12, 9, rgb(80, 60, 70))
	piece("Bed", -56, U, -18.6, 180, WOOD, M.Wood)
	piece("Nightstand", -61.2, U, -22, 180, TRIM, M.Wood)
	piece("Nightstand", -50.8, U, -22, 180, TRIM, M.Wood)
	piece("Dresser", -40, U, -22.6, 180, TRIM, M.Wood)
	hideWardrobe(-66, U, -6, -90, "Wardrobe")
	-- Grandma, in her chair by the window. She hasn't moved in a long time.
	local rocker = Props.Chair(false)
	rocker:PivotTo(L(-60, U, -6) * ANG(0, rad(140), 0))
	rocker.Parent = furniture
	local grandma = Build.model(furniture, "Grandma")
	local seat = L(-60, U, -6) * ANG(0, rad(140), 0)
	Build.part(grandma, Vector3.new(1.8, 2.6, 1.2), seat * CF(0, 3.9, 0.1), rgb(70, 60, 74), M.Fabric)
	Build.part(grandma, Vector3.new(2.6, 0.8, 1.6), seat * CF(0, 2.9, -0.6), rgb(70, 60, 74), M.Fabric)
	Build.ball(grandma, 1.15, seat * CF(0, 5.7, 0.05), rgb(150, 136, 112), M.SmoothPlastic)
	Build.part(grandma, Vector3.new(1.3, 0.5, 1.3), seat * CF(0, 6.2, 0.2), rgb(190, 190, 186), M.Fabric)
	for _, s in { -1, 1 } do
		Build.part(grandma, Vector3.new(0.22, 0.22, 0.05), seat * CF(s * 0.22, 5.75, -0.55), rgb(8, 6, 6), M.SmoothPlastic)
		Build.part(grandma, Vector3.new(0.35, 1.8, 0.35), seat * CF(s * 0.9, 3.6, -0.5) * ANG(rad(-60), 0, 0), rgb(150, 136, 112), M.SmoothPlastic)
	end
	for _, p in grandma:GetChildren() do
		if p:IsA("BasePart") then
			p.CanCollide = false
		end
	end
	painting(CF(-67.3, U + 6, 8) * ANG(0, rad(-90), 0), 3, 4, rgb(70, 40, 40))

	------------------------------------------------------------ sewing room (west, upper south)
	Build.bulb(lights, L(-46, U + 9.5, 12), rgb(255, 210, 160), 0.4, 16, true)
	-- a big cutting table covered in patterns, the machine at the end
	box(furniture, Vector3.new(10, 0.4, 4.4), -46, U + 3.1, 12, rgb(110, 84, 58), M.Wood)
	for _, x in { -50.5, -41.5 } do
		for _, z in { 10.2, 13.8 } do
			box(furniture, Vector3.new(0.5, 2.9, 0.5), x, U + 1.45, z, rgb(110, 84, 58), M.Wood)
		end
	end
	for i = 0, 3 do
		boxCF(furniture, Vector3.new(2.2, 0.03, 1.6), CF(-49 + i * 2.2, U + 3.33, 12 + rng:NextNumber(-1, 1)) * ANG(0, rng:NextNumber(-0.4, 0.4), 0), rgb(222, 206, 176), M.SmoothPlastic, noCollide)
	end
	box(furniture, Vector3.new(2.2, 1.4, 1), -42.5, U + 4, 12, rgb(30, 30, 32), M.Metal)
	box(furniture, Vector3.new(0.6, 1.8, 0.8), -41.8, U + 4.3, 12, rgb(30, 30, 32), M.Metal)
	-- dress forms wearing something that isn't fabric
	for i = 0, 2 do
		local x, z = -56 + i * 4.5, 21
		Build.post(furniture, 3, 0.25, L(x, U + 1.5, z), rgb(40, 40, 40), M.Metal)
		box(furniture, Vector3.new(2, 0.3, 2), x, U + 0.15, z, rgb(40, 40, 40), M.Metal)
		box(furniture, Vector3.new(1.9, 3, 1.2), x, U + 4.5, z, rgb(196, 156, 132), M.Leather)
		Build.ball(furniture, 0.9, L(x, U + 6.4, z), rgb(40, 40, 40), M.Metal)
		for _, s in { -1, 1 } do
			box(furniture, Vector3.new(0.05, 2.6, 0.08), x + s * 0.4, U + 4.5, z - 0.62, rgb(80, 20, 18), M.SmoothPlastic, noCollide)
		end
	end
	-- bolts of cloth
	for i = 0, 5 do
		Build.cylinder(furniture, 4, 0.9, L(-35, U + 0.45 + (i // 3) * 0.9, 6 - (i % 3) * 1) * ANG(0, 0, rad(90)), Color3.fromHSV(rng:NextNumber(), 0.3, 0.45), M.Fabric)
	end
	hideWardrobe(-34.6, U, 20.5, 90, "Wardrobe")

	------------------------------------------------------------ sunroom (east, ground north)
	Build.bulb(lights, L(50, 10.5, -12), rgb(220, 230, 255), 0.25, 18, true)
	-- dead plants in pots everywhere
	for i = 0, 7 do
		local x = 36 + (i % 4) * 9 + rng:NextNumber(-1, 1)
		local z = if i < 4 then -21.5 else -2.5
		Build.post(furniture, 1.6, 1.4, L(x, 0.8, z), rgb(140, 70, 50), M.Slate)
		for k = 0, 2 do
			boxCF(furniture, Vector3.new(0.15, 3 + rng:NextNumber(0, 2), 0.15), CF(x, 3, z) * ANG(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6), rng:NextNumber(-0.5, 0.5)) * CF(0, 0.8 + k * 0.2, 0), rgb(70, 56, 40), M.Wood, noCollide)
		end
	end
	piece("KitchenTable", 50, 0, -12, 0, rgb(120, 100, 70), M.Wood)
	for i, a in { 0, 180 } do
		local chair = Props.Chair(false)
		chair:PivotTo(L(50 + (if i == 1 then -5.5 else 5.5), 0, -12) * ANG(0, rad(a + 90), 0))
		chair.Parent = furniture
	end
	-- the tea is still in the cups
	for i = 0, 3 do
		Build.post(furniture, 0.5, 0.5, L(47.5 + i * 1.7, 3.5, -12 + (i % 2) * 0.8), rgb(220, 216, 206), M.SmoothPlastic)
	end
	-- birdcage on a stand, full of finger bones
	Build.post(furniture, 5, 0.2, L(64, 2.5, -20), rgb(60, 56, 50), M.Metal)
	Build.ball(furniture, 2.2, L(64, 6, -20), rgb(150, 130, 60), M.Metal, { Transparency = 0.55 })
	-- Mama's shrine: candles around a photo
	box(furniture, Vector3.new(4, 3, 2), 65.4, 1.5, -6, TRIM, M.Wood)
	painting(CF(67.3, 5.3, -6) * ANG(0, rad(90), 0), 1.6, 2, rgb(110, 100, 90))
	for i = 0, 4 do
		Build.candle(furniture, L(64.8, 3, -7.4 + i * 0.7), 0.3 + (i % 3) * 0.2)
	end
	-- the radio (Distractions: tuned loud, it draws the family over)
	box(furniture, Vector3.new(3, 2.4, 2), 35, 1.2, -14, TRIM, M.Wood)
	local radio = box(furniture, Vector3.new(2, 1.3, 1.1), 35, 3.05, -14, rgb(90, 62, 40), M.Wood)
	radio.Name = "Radio"
	box(furniture, Vector3.new(0.05, 0.8, 0.9), 34.0, 3.05, -14, rgb(200, 180, 120), M.Fabric, noCollide)

	------------------------------------------------------------ workshop (east, ground south)
	Build.bulb(lights, L(50, 10.5, 12), rgb(255, 200, 150), 0.55, 20, true)
	-- the crafting bench along the back wall, vise and pegboard over it
	local benchTop = CF(56, 3.5, 21.6)
	box(furniture, Vector3.new(10, 0.5, 3.4), 56, 3.25, 21.6, rgb(96, 72, 48), M.Wood)
	for _, dx in { -4.6, 4.6 } do
		box(furniture, Vector3.new(0.6, 3, 3), 56 + dx, 1.5, 21.6, rgb(96, 72, 48), M.Wood)
	end
	box(furniture, Vector3.new(9, 0.3, 2.8), 56, 1, 21.6, rgb(84, 62, 44), M.Wood)
	box(furniture, Vector3.new(1, 0.8, 1.2), 52, 3.9, 21, rgb(60, 70, 80), M.Metal)
	box(furniture, Vector3.new(10, 5, 0.3), 56, 7, 23.3, rgb(150, 120, 80), M.Wood, noCollide)
	for i = 0, 7 do
		local x = 52 + i * 1.1
		boxCF(furniture, Vector3.new(0.2, 1.4 + (i % 3) * 0.4, 0.15), CF(x, 7.2, 23.05) * ANG(0, 0, rad((i % 2) * 10 - 5)), rgb(130, 130, 136), M.Metal, noCollide)
	end
	-- smoking racks with what's being cured on them
	local hooks = AssetService.create("MeatHooks", rng)
	local _, hookSize = hooks:GetBoundingBox()
	hooks:PivotTo(L(42, 12 - hookSize.Y, 12) * ANG(0, rad(90), 0))
	hooks.Parent = furniture
	for i = 0, 2 do
		local barrel = Props.Barrel(rng)
		barrel:PivotTo(L(40 + i * 2.6, 0, 22))
		barrel.Parent = furniture
	end
	-- sawhorse with a half-cut plank
	for _, dx in { -1.6, 1.6 } do
		boxCF(furniture, Vector3.new(0.3, 3, 2), CF(60 + dx, 1.5, 8), rgb(110, 84, 58), M.Wood)
	end
	box(furniture, Vector3.new(4.2, 0.3, 0.5), 60, 3.1, 8, rgb(110, 84, 58), M.Wood)
	box(furniture, Vector3.new(8, 0.25, 1), 60, 3.4, 8, rgb(150, 120, 84), M.WoodPlanks)
	Build.stain(furniture, L(44, 0.05, 14), Vector2.new(2, 1.6), rng)

	------------------------------------------------------------ guest room (east, upper north)
	Build.bulb(lights, L(50, U + 9.5, -12), rgb(255, 180, 120), 0.35, 16, true)
	piece("Bed", 56, U, -18.6, 180, WOOD, M.Wood)
	piece("Nightstand", 61.2, U, -22, 180, TRIM, M.Wood)
	hideWardrobe(66, U, -5, 90, "Wardrobe")
	-- the last guest's suitcase, still packed, on a luggage rack
	box(furniture, Vector3.new(3.4, 0.3, 2.2), 42, U + 1.9, -20, TRIM, M.Wood)
	for _, dx in { -1.5, 1.5 } do
		box(furniture, Vector3.new(0.25, 1.9, 2), 42 + dx, U + 0.95, -20, TRIM, M.Wood)
	end
	box(furniture, Vector3.new(3, 1.2, 2), 42, U + 2.65, -20, rgb(90, 40, 34), M.Leather)
	rug(52, U, -11, 10, 7, rgb(60, 70, 80))
	Build.stain(furniture, L(55, U + 3.0, -17), Vector2.new(1.4, 1.8), rng)

	------------------------------------------------------------ storage room (east, upper south)
	Build.bulb(lights, L(46, U + 9.5, 12), rgb(255, 170, 110), 0.25, 14, true)
	for i = 0, 11 do
		local x = 36 + (i % 4) * 4.5 + rng:NextNumber(-0.6, 0.6)
		local z = 14 + (i // 4) * 3.2
		local s = rng:NextNumber(2, 3.2)
		boxCF(furniture, Vector3.new(s, s * 0.8, s), CF(x, U + s * 0.4, z) * ANG(0, rng:NextNumber(-0.3, 0.3), 0), rgb(150, 120, 84), M.Cardboard)
	end
	-- old furniture under sheets
	for i, x in { 52, 58 } do
		box(furniture, Vector3.new(4, 4 + i, 3), x, U + (4 + i) / 2, 21.5, rgb(206, 202, 194), M.Fabric)
	end
	piece("ToyChest", 64, U, 21.6, 0, rgb(140, 60, 50), M.Wood)
	piece("KidsBed", 42, U, 4.5, 90, rgb(110, 90, 70), M.Wood)

	------------------------------------------------------------ attic & loft contents
	local attic = rgb(70, 56, 44)
	for i = 0, 4 do
		local x = -26 + i * 11 + rng:NextNumber(-1.5, 1.5)
		local z = if i % 2 == 0 then -7 else 7
		box(furniture, Vector3.new(4, 2.2, 2.4), x, 26.1, z, attic, M.Wood)
		box(furniture, Vector3.new(4.1, 0.25, 2.5), x, 27.3, z, rgb(96, 74, 52), M.Metal)
	end
	-- an old crib and a rocking horse by the chimney
	for _, dx in { -1.6, 1.6 } do
		box(furniture, Vector3.new(0.3, 3, 4.6), -24 + dx, 26.5, -2, rgb(200, 196, 186), M.Wood)
	end
	box(furniture, Vector3.new(3.4, 0.3, 4.6), -24, 26.2, -2, rgb(200, 196, 186), M.Wood)
	box(furniture, Vector3.new(3.6, 1.6, 1), 14, 26.8, 3, rgb(150, 60, 50), M.Wood)
	box(furniture, Vector3.new(1, 0.9, 1.4), 15.6, 27.7, 3, rgb(150, 60, 50), M.Wood)
	-- sheets hanging from the rafters
	for i = 0, 3 do
		boxCF(furniture, Vector3.new(4, 5, 0.06), CF(-8 + i * 8, 29.5, rng:NextNumber(-4, 4)) * ANG(0, rng:NextNumber(-0.4, 0.4), 0), rgb(214, 208, 196), M.Fabric, { CanCollide = false, Transparency = 0.15 })
	end
	-- the east loft: low and tight, junk along the eaves
	for i = 0, 3 do
		box(furniture, Vector3.new(3, 1.6, 2.4), 38 + i * 7, 25.8, (i % 2) * 2 - 6, rgb(150, 120, 84), M.Cardboard)
	end
	Build.bulb(lights, L(50, 31.5, 0), rgb(255, 150, 90), 0.12, 12, true)

	------------------------------------------------------------ gameplay data
	return {
		groundPatrol = {
			at(-48, 0, -12),
			at(-60, 0, -14),
			at(-46, 0, 12),
			at(-56, 0, 6),
			at(48, 0, -10),
			at(60, 0, -6),
			at(46, 0, 12),
			at(58, 0, 14),
		},
		upperPatrol = {
			at(-48, U, -12),
			at(-60, U, -12),
			at(-50, U, 8),
			at(48, U, -12),
			at(58, U, -8),
			at(48, U, 8),
		},
		keySpots = {
			L(-61.2, U + 2.45, -22) * ANG(0, rad(20), 0), -- Grandma's nightstand
			L(-48, U + 3.35, 12.6) * ANG(0, rad(-40), 0), -- under the sewing patterns
			L(42, U + 3.3, -20) * ANG(0, rad(80), 0), -- the guest's suitcase
			L(-41, 3.45, 4.2) * ANG(0, rad(15), 0), -- on the chest freezer
			L(-26, 27.4, -7) * ANG(0, rad(60), 0), -- attic trunk
			L(-50, 6.05, -22.2) * ANG(0, rad(5), 0), -- on top of the piano
			L(52, 26.65, -6) * ANG(0, rad(-30), 0), -- east loft box
		},
		crowbarSpots = {
			L(58, 3.55, 21.2) * ANG(0, rad(10), 0), -- the workshop bench
			L(-44, 0.2, 19.6) * ANG(0, rad(80), 0), -- among the boots
			L(46, U + 0.2, 6.5) * ANG(0, rad(-30), 0), -- storage room floor
			L(4, 25.2, 8) * ANG(0, rad(40), 0), -- attic boards
			L(62, 0.2, -16) * ANG(0, rad(110), 0), -- sunroom, behind the plants
			L(-62, U + 0.2, 14) * ANG(0, rad(60), 0), -- by the back stairs
		},
		spots = {
			BatteryParlor = L(-55, 2.08, -12.5),
			BandageMudroom = L(-36, 3.75, 21.2),
			BatteryGuest = L(61.2, U + 2.45, -22),
			SyringeWorkshop = L(60, 3.6, 21.4) * ANG(0, rad(30), 0),
			NotePiano = L(-50, 3.6, -20.6) * ANG(0, rad(-8), 0),
			NoteGuest = L(42, U + 3.3, -19.4) * ANG(0, rad(12), 0),
			NoteSewing = L(-44, U + 3.35, 11) * ANG(0, rad(30), 0),
			NoteAttic = L(14, 27.65, 3) * ANG(0, rad(-20), 0),
		},
		workbench = O * benchTop,
		recordPlayer = recordPlayer,
		radio = radio,
		attic = at(0, 25.5, 0),
	}
end

return HouseWings

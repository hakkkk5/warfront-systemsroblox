--!strict
-- The cannibal family's farmhouse: two floors, an attic, the cellar, two wings
-- (HouseWings: sixteen rooms in all), a porch, and the
-- slaughter room where the player wakes up.
--
-- Local layout (origin = centre of the ground floor, floor top at y = 0,
-- front door faces -Z / north):
--   ground floor: living room (NW), dining room (NE), kitchen (SW),
--                 slaughter room (SE), hallway + stairs in the middle
--   upper floor:  master bedroom (NW), kid's room (NE), bathroom (SW),
--                 trophy room (SE)
--
-- The numbers below are the original, smaller plan; the rooms are built
-- HouseLayout.SCALE times as wide and deep. Walls, floors and fixtures go
-- straight into the bigger house (S, span, fixture); the furniture is laid
-- out on the plan (L, box) and then moved into the bigger rooms piece by
-- piece (settle), so it stays against its walls and in one piece.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HouseLayout = require(ReplicatedStorage.Shared.HouseLayout)
local Build = require(script.Parent.Build)
local Util = require(ReplicatedStorage.Shared.Util)
local Props = require(script.Parent.Props)
local Terrain = require(script.Parent.Terrain)
local AssetService = require(script.Parent.Parent.Systems.AssetService)
local Doors = require(script.Parent.Parent.Systems.Doors)
local Hiding = require(script.Parent.Parent.Systems.Hiding)
local HouseWings = require(script.Parent.HouseWings)

local House = {}

export type Info = {
	origin: CFrame,
	model: Model,
	chairSeat: CFrame, -- where the tied-up player sits, facing the table
	chairEye: CFrame,
	chair: Model,
	tableTop: CFrame,
	body: Model,
	knifeSpot: CFrame,
	knife: Model?,
	slaughterDoor: Doors.Door,
	frontDoor: Doors.Door,
	padlock: Model,
	spawnInside: CFrame,
	spawnPorch: CFrame,
	groundPatrol: { Vector3 },
	upperPatrol: { Vector3 },
	keySpots: { CFrame },
	crowbarSpots: { CFrame },
	spots: { [string]: CFrame },
	actors: { [string]: CFrame },
	center: Vector3,
	workbench: CFrame,
	recordPlayer: BasePart,
	radio: BasePart,
	attic: Vector3,
	polaroidSpots: { [string]: CFrame },
	junkSpots: { CFrame },
}

local rgb = Color3.fromRGB
local M = Enum.Material
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local WALL = rgb(118, 104, 86)
local WALL_DIRTY = rgb(96, 84, 70)
local TRIM = rgb(60, 44, 32)
local FLOOR = rgb(70, 50, 34)
local EXTERIOR = rgb(104, 92, 78)

function House.build(parent: Instance): Info
	local site = Config.Sites.House
	local groundY = Terrain.siteY("House")
	local foundation = Config.House.Foundation
	local O = CF(site.pos.X, groundY + foundation, site.pos.Y)
	local rng = Util.rng(Config.Map.Seed + 11)

	local model = Build.model(parent, "CannibalHouse")
	local structure = Build.model(model, "Structure")
	local furniture = Build.model(model, "Furniture")
	local lights = Build.model(model, "Lights")

	local function L(x: number, y: number, z: number): CFrame
		return O * CF(x, y, z)
	end
	local function box(p: Instance, size: Vector3, x: number, y: number, z: number, color: Color3, mat: Enum.Material, extra: { [string]: any }?): Part
		return Build.part(p, size, L(x, y, z), color, mat, extra)
	end
	local function boxCF(p: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, extra: { [string]: any }?): Part
		return Build.part(p, size, O * cf, color, mat, extra)
	end
	-- the bigger house: a point of the plan where it ended up
	local HL = HouseLayout
	local function S(x: number, y: number, z: number): CFrame
		return O * CF(HL.at(x, y, z))
	end
	-- a fixture (window frame, trim, cobweb) keeps its size
	local function fixture(p: Instance, size: Vector3, x: number, y: number, z: number, color: Color3, mat: Enum.Material, extra: { [string]: any }?): Part
		return Build.part(p, size, S(x, y, z), color, mat, extra)
	end
	-- floors, ceilings and long runs stretch with the rooms
	local function span(p: Instance, size: Vector3, x: number, y: number, z: number, color: Color3, mat: Enum.Material, extra: { [string]: any }?): Part
		local s, c = HL.span(size, Vector3.new(x, y, z))
		return Build.part(p, s, O * CF(c), color, mat, extra)
	end
	local function spanWedge(p: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): WedgePart
		local s, c = HL.spanCF(size, cf)
		return Build.wedge(p, s, O * c, color, mat)
	end
	-- a box between two corners already in the bigger house (x0 < x1, z0 < z1)
	local function rect(p: Instance, x0: number, x1: number, z0: number, z1: number, y: number, h: number, color: Color3, mat: Enum.Material)
		if x1 - x0 > 0.05 and z1 - z0 > 0.05 then
			Build.part(p, Vector3.new(x1 - x0, h, z1 - z0), O * CF((x0 + x1) / 2, y, (z0 + z1) / 2), color, mat)
		end
	end
	-- Hiding spots and the like wait until the furniture has moved
	local later: { () -> () } = {}
	-- a CFrame of the plan in the bigger house, moving with the furniture it
	-- is on (once the furniture has settled)
	local function moved(cf: CFrame): CFrame
		return O * HL.placeCFrame(O:ToObjectSpace(cf))
	end
	-- A group of box furniture that clients swap for the Blender model of the
	-- same name (MeshLibrary; tools/blender/build_props.py). The boxes keep
	-- the collisions. pivot: floor centre, house-local, its -Z the front.
	local function standIn(meshName: string, x: number, y: number, z: number, yawDeg: number): Model
		local m = Instance.new("Model")
		m.Name = meshName
		m.WorldPivot = L(x, y, z) * ANG(0, rad(yawDeg), 0)
		m:SetAttribute("Mesh", meshName)
		m.Parent = furniture
		Build.tag(m, "BlenderMesh")
		return m
	end

	------------------------------------------------------------ foundation & floors
	-- foundation, solid except for the cellar under the kitchen (x -30..-6,
	-- z 1..23; Cellar.luau builds the room)
	local fh = foundation + 6
	local stone = rgb(70, 66, 62)
	span(structure, Vector3.new(39, fh, 50), 13.5, -fh / 2, 0, stone, M.Cobblestone)
	span(structure, Vector3.new(27, fh, 26), -19.5, -fh / 2, -12, stone, M.Cobblestone)
	span(structure, Vector3.new(3, fh, 24), -31.5, -fh / 2, 13, stone, M.Cobblestone)
	span(structure, Vector3.new(24, fh, 2), -18, -fh / 2, 24, stone, M.Cobblestone)
	-- ground floor rooms
	span(structure, Vector3.new(27, 0.4, 24), -18.5, -0.2, -12, FLOOR, M.WoodPlanks) -- living
	span(structure, Vector3.new(27, 0.4, 24), 18.5, -0.2, -12, FLOOR, M.WoodPlanks) -- dining
	-- kitchen, with the 4 x 4 hole under the cellar hatch
	local tiles = rgb(150, 140, 120)
	local kh = HL.at(-10, 0, 9)
	local kx0, kx1, kz0, kz1 = HL.x(-32), HL.x(-5), HL.z(0), HL.z(24)
	rect(structure, kx0, kh.X - 2, kz0, kz1, -0.2, 0.4, tiles, M.CeramicTiles)
	rect(structure, kh.X + 2, kx1, kz0, kz1, -0.2, 0.4, tiles, M.CeramicTiles)
	rect(structure, kh.X - 2, kh.X + 2, kz0, kh.Z - 2, -0.2, 0.4, tiles, M.CeramicTiles)
	rect(structure, kh.X - 2, kh.X + 2, kh.Z + 2, kz1, -0.2, 0.4, tiles, M.CeramicTiles)
	span(structure, Vector3.new(27, 0.4, 24), 18.5, -0.2, 12, rgb(90, 86, 80), M.Concrete) -- slaughter
	span(structure, Vector3.new(10, 0.4, 48), 0, -0.2, 0, rgb(62, 44, 30), M.WoodPlanks) -- hall
	-- the main stairs stand free in the middle of the hall, 6 wide, facing
	-- you as you come in the front door and rising toward the back to a
	-- landing; the upper floor has a well over them, walkways either side
	local stairX0, stairX1 = -3, 3
	local stairBack = HL.z(24) - 8
	local stairFront = stairBack - 13 * 1.7
	local wx0, wx1, wz0, wz1 = HL.x(-32), HL.x(32), HL.z(-24), HL.z(24)
	local hallX0, hallX1, midZ = HL.x(-5), HL.x(5), HL.z(0)
	rect(structure, wx0, wx1, wz0, midZ, 12.5, 1, FLOOR, M.WoodPlanks)
	rect(structure, wx0, hallX0, midZ, wz1, 12.5, 1, rgb(150, 150, 145), M.CeramicTiles) -- bathroom
	rect(structure, hallX1, wx1, midZ, wz1, 12.5, 1, FLOOR, M.WoodPlanks) -- trophy room
	rect(structure, hallX0, stairX0, midZ, wz1, 12.5, 1, FLOOR, M.WoodPlanks)
	rect(structure, stairX1, hallX1, midZ, wz1, 12.5, 1, FLOOR, M.WoodPlanks)
	rect(structure, stairX0, stairX1, midZ, stairFront, 12.5, 1, FLOOR, M.WoodPlanks)
	rect(structure, stairX0, stairX1, stairBack, wz1, 12.5, 1, FLOOR, M.WoodPlanks) -- the landing
	-- upper ceiling / attic floor, with the 4 x 4 attic hatch over the
	-- upstairs hall (HouseWings puts the ladder under it)
	local ceiling = rgb(80, 70, 58)
	local ah = HL.at(2.5, 0, -4)
	rect(structure, wx0, ah.X - 2, wz0, wz1, 24.5, 1, ceiling, M.WoodPlanks)
	rect(structure, ah.X + 2, wx1, wz0, wz1, 24.5, 1, ceiling, M.WoodPlanks)
	rect(structure, ah.X - 2, ah.X + 2, wz0, ah.Z - 2, 24.5, 1, ceiling, M.WoodPlanks)
	rect(structure, ah.X - 2, ah.X + 2, ah.Z + 2, wz1, 24.5, 1, ceiling, M.WoodPlanks)

	------------------------------------------------------------ roof
	-- roof, chimney and the porch roof and posts stand in for the Blender
	-- exterior (tools/blender/build_buildings.py), which also adds the trim,
	-- gutters and gable siding; these parts keep the collisions
	-- (XL: the exterior with the wings; the old mesh no longer fits)
	local shell = Build.standIn(structure, "FarmhouseExteriorXL")
	local roofColor = rgb(44, 40, 38)
	spanWedge(shell, Vector3.new(69, 11, 27), CF(0, 30.5, -12.5), roofColor, M.RoofShingles)
	spanWedge(shell, Vector3.new(69, 11, 27), CF(0, 30.5, 12.5) * ANG(0, math.pi, 0), roofColor, M.RoofShingles)
	span(shell, Vector3.new(69, 0.6, 1.2), 0, 36.1, 0, rgb(34, 30, 28), M.Wood)
	-- chimney over the living room fireplace
	fixture(shell, Vector3.new(4, 18, 4), -30, 28, -12, rgb(96, 50, 40), M.Brick)
	local chimneyTop = fixture(shell, Vector3.new(4.4, 0.6, 4.4), -30, 37.3, -12, rgb(70, 66, 62), M.Concrete)
	local smoke = Instance.new("Smoke")
	smoke.Color = rgb(60, 58, 56)
	smoke.Opacity = 0.12
	smoke.RiseVelocity = 5
	smoke.Size = 3
	smoke.Parent = chimneyTop

	------------------------------------------------------------ walls
	local function window(at: number): Build.Opening
		return { at = at, width = 4, bottom = 4, top = 8.5 }
	end
	local function door(at: number): Build.Opening
		return { at = at, width = 5, bottom = 0, top = 9 }
	end
	-- walls take the plan's ends and openings: the ends move with the rooms,
	-- doors and windows keep their width
	local function planned(a: Vector2, b: Vector2, openings: { Build.Opening }): (Vector2, Vector2, { Build.Opening })
		local alongX = math.abs(b.Y - a.Y) < 1e-3
		local moved = {}
		for _, o in openings do
			table.insert(moved, { at = if alongX then HL.x(o.at) else HL.z(o.at), width = o.width, bottom = o.bottom, top = o.top })
		end
		return Vector2.new(HL.x(a.X), HL.z(a.Y)), Vector2.new(HL.x(b.X), HL.z(b.Y)), moved
	end
	local function wall(a: Vector2, b: Vector2, y0: number, h: number, openings: { Build.Opening }, color: Color3?, mat: Enum.Material?)
		local ma, mb, mo = planned(a, b, openings)
		Build.wall(structure, O, ma, mb, y0, h, 1, mo, color or WALL, mat or M.Plaster)
	end
	local function exterior(a: Vector2, b: Vector2, y0: number, h: number, openings: { Build.Opening })
		-- weathered siding outside, plaster inside; the siding layer stands in
		-- for the Blender clapboard (FarmhouseExterior) and is hidden under it
		local alongX = math.abs(b.Y - a.Y) < 1e-3
		local outward = if alongX then Vector2.new(0, if a.Y < 0 then -0.6 else 0.6) else Vector2.new(if a.X < 0 then -0.6 else 0.6, 0)
		local ma, mb, mo = planned(a, b, openings)
		Build.wall(structure, O, ma, mb, y0, h, 1, mo, WALL_DIRTY, M.Plaster)
		Build.wall(shell, O, ma + outward, mb + outward, y0, h, 0.2, mo, EXTERIOR, M.WoodPlanks)
	end

	-- ground floor exterior
	exterior(Vector2.new(-32.5, -24), Vector2.new(32.5, -24), 0, 12, { door(0), window(-20), window(-12), window(12), window(22) })
	exterior(Vector2.new(-32.5, 24), Vector2.new(32.5, 24), 0, 12, { { at = 2.5, width = 4.6, bottom = 0, top = 9 }, window(-20), window(20) })
	-- the old end walls open into the wings (HouseWings)
	wall(Vector2.new(-32, -24), Vector2.new(-32, 24), 0, 12, { door(-13.75), door(8.9) }, WALL_DIRTY)
	wall(Vector2.new(32, -24), Vector2.new(32, 24), 0, 12, { door(-8), door(20.5) }, WALL_DIRTY)
	-- upper floor exterior
	exterior(Vector2.new(-32.5, -24), Vector2.new(32.5, -24), 13, 11, { window(-20), window(-12), window(12), window(22) })
	exterior(Vector2.new(-32.5, 24), Vector2.new(32.5, 24), 13, 11, { window(-18), window(18) })
	wall(Vector2.new(-32, -24), Vector2.new(-32, 24), 13, 11, { door(-15), door(14) }, WALL_DIRTY)
	wall(Vector2.new(32, -24), Vector2.new(32, 24), 13, 11, { door(-17), door(3) }, WALL_DIRTY)

	-- ground floor interior
	wall(Vector2.new(-5, -23.5), Vector2.new(-5, 0), 0, 12, { door(-11.5) })
	wall(Vector2.new(5, -23.5), Vector2.new(5, 0), 0, 12, { door(-11.5) })
	wall(Vector2.new(-31.5, 0), Vector2.new(-5.5, 0), 0, 12, { { at = -18, width = 5, bottom = 0, top = 9.5 } })
	wall(Vector2.new(5.5, 0), Vector2.new(31.5, 0), 0, 12, {}, rgb(84, 76, 66))
	wall(Vector2.new(-5, 0), Vector2.new(-5, 23.5), 0, 12, { door(4.5) })
	wall(Vector2.new(5, 0), Vector2.new(5, 23.5), 0, 12, { door(16.5) }, rgb(84, 76, 66))
	-- upper floor interior
	wall(Vector2.new(-5, -23.5), Vector2.new(-5, 0), 13, 11, { door(-5.5) })
	wall(Vector2.new(5, -23.5), Vector2.new(5, 0), 13, 11, { door(-5.5) }, rgb(96, 110, 120))
	wall(Vector2.new(-31.5, 0), Vector2.new(-5.5, 0), 13, 11, {})
	wall(Vector2.new(5.5, 0), Vector2.new(31.5, 0), 13, 11, {})
	wall(Vector2.new(-5, 0), Vector2.new(-5, 23.5), 13, 11, { door(4.5) })
	wall(Vector2.new(5, 0), Vector2.new(5, 23.5), 13, 11, { door(4.5) })

	-- skirting boards along the hallway
	for _, x in { -4.4, 4.4 } do
		span(structure, Vector3.new(0.2, 0.6, 47), x, 0.3, 0, TRIM, M.Wood, { CanCollide = false })
	end

	------------------------------------------------------------ windows (glass + boards)
	-- cf: the window's centre on the plan; everything is placed around it
	-- once it has moved
	local function windowFill(planCF: CFrame, boarded: boolean)
		local cf = HL.cframe(planCF)
		boxCF(structure, Vector3.new(4, 4.5, 0.15), cf, rgb(40, 50, 56), M.Glass, { Transparency = 0.55, Reflectance = 0.2 })
		boxCF(structure, Vector3.new(4.4, 0.3, 0.6), cf * CF(0, -2.35, 0), TRIM, M.Wood)
		-- frame, cross bars and a torn curtain on the inside (+Z here)
		local noCollide = { CanCollide = false, CastShadow = false }
		boxCF(structure, Vector3.new(4.6, 0.35, 0.5), cf * CF(0, 2.35, 0), TRIM, M.Wood, noCollide)
		for _, x in { -2.15, 2.15 } do
			boxCF(structure, Vector3.new(0.3, 4.9, 0.5), cf * CF(x, 0, 0), TRIM, M.Wood, noCollide)
		end
		boxCF(structure, Vector3.new(0.12, 4.4, 0.18), cf, TRIM, M.Wood, noCollide)
		boxCF(structure, Vector3.new(3.9, 0.12, 0.18), cf, TRIM, M.Wood, noCollide)
		boxCF(structure, Vector3.new(5, 0.12, 0.12), cf * CF(0, 2.75, 0.55), rgb(70, 66, 60), M.Metal, noCollide)
		local cloth = Color3.fromHSV(rng:NextNumber(0.02, 0.1), 0.35, rng:NextNumber(0.3, 0.45))
		for _, side in { -1, 1 } do
			local width = rng:NextNumber(0.9, 1.5)
			local length = rng:NextNumber(3.2, 4.8)
			boxCF(structure, Vector3.new(width, length, 0.06), cf * CF(side * (2.4 - width / 2), 2.7 - length / 2, 0.62) * ANG(0, 0, rad(rng:NextNumber(-3, 3))), cloth, M.Fabric, { CanCollide = false, Transparency = 0.1 })
		end
		-- boards over the outside: part of the stand-in shell, so they go when
		-- the Blender exterior shows (they poked through its siding)
		if boarded then
			for i = -1, 1 do
				boxCF(shell, Vector3.new(4.8, 0.7, 0.25), cf * CF(0, i * 1.4, -0.45) * ANG(0, 0, rad(rng:NextNumber(-14, 14))), rgb(92, 72, 52), M.WoodPlanks)
			end
		end
	end
	for _, x in { -20, -12, 12, 22 } do
		windowFill(CF(x, 6.25, -24), x > 0)
		windowFill(CF(x, 19.25, -24), true)
	end
	windowFill(CF(-20, 6.25, 24) * ANG(0, math.pi, 0), false)
	windowFill(CF(20, 6.25, 24) * ANG(0, math.pi, 0), true)
	windowFill(CF(-18, 19.25, 24) * ANG(0, math.pi, 0), true)
	windowFill(CF(18, 19.25, 24) * ANG(0, math.pi, 0), false)

	------------------------------------------------------------ wings and attic
	local wings = HouseWings.build({
		O = O,
		U = 13,
		model = model,
		structure = structure,
		furniture = furniture,
		lights = lights,
		shell = shell,
		rng = rng,
		foundation = foundation,
		wall = wall,
		exterior = exterior,
		windowFill = windowFill,
		door = door,
		window = window,
		later = function(fn: () -> ())
			table.insert(later, fn)
		end,
		moved = moved,
	})

	------------------------------------------------------------ stairs
	-- free-standing in the middle of the hall (x stairX0..stairX1), from the
	-- foot (stairFront) up toward the back to the landing (stairBack), with a
	-- banister on both sides; the hall runs past them on either side
	local steps = 13
	local run = (stairBack - stairFront) / steps
	local stairW = stairX1 - stairX0
	local stairMid = (stairX0 + stairX1) / 2
	for i = 1, steps do
		local z0 = stairFront + (i - 1) * run
		Build.part(structure, Vector3.new(stairW, i, run), O * CF(stairMid, i / 2, z0 + run / 2), rgb(66, 48, 34), M.WoodPlanks)
	end
	local function rail(a: Vector3, b: Vector3)
		Build.part(structure, Vector3.new(0.3, 0.3, (b - a).Magnitude), O * CFrame.lookAt((a + b) / 2, b), TRIM, M.Wood)
	end
	local function post(x: number, y: number, z: number, h: number)
		Build.part(structure, Vector3.new(0.25, h, 0.25), O * CF(x, y + h / 2, z), TRIM, M.Wood)
	end
	for _, x in { stairX0 + 0.15, stairX1 - 0.15 } do
		-- banister up the flight, newel post at the foot
		rail(Vector3.new(x, 1 + 3, stairFront + run / 2), Vector3.new(x, steps + 3, stairBack - run / 2))
		post(x, 0, stairFront + 0.2, 4.2)
		for i = 1, steps, 2 do
			post(x, i, stairFront + (i - 0.5) * run, 3)
		end
		-- and on along the well upstairs
		rail(Vector3.new(x, 16.2, stairFront - 0.15), Vector3.new(x, 16.2, stairBack))
		local z = stairFront + 0.2
		while z < stairBack - 0.4 do
			post(x, 13, z, 3.2)
			z += 2.6
		end
	end
	rail(Vector3.new(stairX0, 16.2, stairFront - 0.15), Vector3.new(stairX1, 16.2, stairFront - 0.15))

	------------------------------------------------------------ doors
	-- hinges for the doorways of the plan, in the bigger house: the doorway
	-- centre moves, the door keeps its width
	local function hingeZ(x: number, zc: number, y0: number): CFrame
		return O * CF(HL.x(x), y0, HL.z(zc) - 2.4) * ANG(0, -math.pi / 2, 0)
	end
	local function hingeX(xc: number, z: number, y0: number): CFrame
		return O * CF(HL.x(xc) - 2.4, y0, HL.z(z))
	end
	Doors.create(model, hingeZ(-5, -11.5, 0), 4.8, 9, { name = "LivingDoor", swing = -1 })
	Doors.create(model, hingeZ(5, -11.5, 0), 4.8, 9, { name = "DiningDoor", swing = 1 })
	Doors.create(model, hingeZ(-5, 4.5, 0), 4.8, 9, { name = "KitchenDoor", swing = -1 })
	local slaughterDoor = Doors.create(model, hingeZ(5, 16.5, 0), 4.8, 9, {
		name = "SlaughterDoor",
		swing = 1,
		color = rgb(60, 44, 34),
	})
	Doors.create(model, hingeZ(-5, -5.5, 13), 4.8, 9, { name = "MasterDoor", swing = -1 })
	Doors.create(model, hingeZ(5, -5.5, 13), 4.8, 9, { name = "KidsDoor", swing = 1, color = rgb(120, 110, 96) })
	Doors.create(model, hingeZ(-5, 4.5, 13), 4.8, 9, { name = "BathroomDoor", swing = -1 })
	Doors.create(model, hingeZ(5, 4.5, 13), 4.8, 9, { name = "TrophyDoor", swing = 1 })
	local backDoorX = HL.x(2.5)
	Doors.create(model, O * CF(backDoorX - 2.3, 0, HL.z(24)), 4.4, 9, { name = "BackDoor", barred = true })
	-- planks nailed across the back door
	for i = 0, 2 do
		Build.part(structure, Vector3.new(5.6, 0.6, 0.3), O * CF(backDoorX - 0.1, 2.5 + i * 2.4, HL.z(23.4)), rgb(92, 72, 52), M.WoodPlanks, { CanCollide = false })
	end

	local frontDoor = Doors.create(model, hingeX(0, -24, 0), 4.8, 9, {
		name = "FrontDoor",
		swing = -1,
		locked = true,
		keyItem = "HouseKey",
		lockedText = "A heavy chain and padlock hold it shut. I need the key.",
		color = rgb(66, 40, 30),
	})
	-- chain + padlock across the front door (removed when unlocked)
	local padlock = Build.model(model, "Padlock")
	local frontAt = O * CF(HL.at(0, 0, -24))
	for i = -6, 6 do
		Build.part(padlock, Vector3.new(0.35, 0.2, 0.2), frontAt * CF(i * 0.4, 4.5 - math.abs(i) * 0.05, -0.6) * ANG(0, 0, if i % 2 == 0 then 0 else rad(90)), rgb(90, 86, 80), M.Metal, { CanCollide = false })
	end
	Build.part(padlock, Vector3.new(0.7, 0.8, 0.35), frontAt * CF(0, 4.1, -0.75), rgb(130, 110, 70), M.Metal, { CanCollide = false })

	------------------------------------------------------------ porch & exterior
	span(structure, Vector3.new(20, 1, 9), 0, -0.5, -29, rgb(76, 60, 44), M.WoodPlanks)
	for i = 1, 3 do
		span(structure, Vector3.new(8, foundation * (1 - i / 4) + 0.2, 1.4), 0, -foundation + (foundation * (1 - i / 4)) / 2 - 0.4, -33 - i * 1.2, rgb(70, 56, 40), M.WoodPlanks)
	end
	for _, x in { -9.5, 9.5 } do
		fixture(shell, Vector3.new(0.6, 11, 0.6), x, 5.5, -33, TRIM, M.Wood)
	end
	span(shell, Vector3.new(21, 0.6, 10), 0, 11.3, -29, rgb(52, 46, 42), M.RoofShingles)
	Build.markStandIn(shell, O)
	Build.bulb(lights, S(0, 9.8, -26.5), rgb(255, 196, 130), 0.9, 16, true)
	local porchChair = Props.Chair(false)
	porchChair:PivotTo(L(-6, 0, -28) * ANG(0, rad(200), 0))
	porchChair.Parent = furniture
	-- skulls on stakes along the driveway
	for i = 0, 3 do
		local side = if i % 2 == 0 then -1 else 1
		local x = site.pos.X + HL.x(side * 9)
		local z = site.pos.Y + HL.z(-44 - i * 12)
		local gy = Terrain.groundY(x, z)
		Build.post(structure, 6, 0.4, CF(x, gy + 3, z), rgb(70, 54, 40), M.Wood)
		Build.ball(structure, 1.1, CF(x, gy + 6.4, z), rgb(220, 214, 196), M.SmoothPlastic)
		Build.part(structure, Vector3.new(0.3, 0.25, 0.1), CF(x - 0.22, gy + 6.5, z - 0.5), rgb(10, 10, 10), M.SmoothPlastic)
		Build.part(structure, Vector3.new(0.3, 0.25, 0.1), CF(x + 0.22, gy + 6.5, z - 0.5), rgb(10, 10, 10), M.SmoothPlastic)
	end
	-- wood pile and chopping block by the west wing
	for i = 0, 8 do
		Build.cylinder(furniture, 4, 0.9, L(-72, -foundation + 0.45 + (i // 3) * 0.85, -14 + (i % 3) * 0.95) * ANG(0, rad(90), 0), rgb(84, 62, 44), M.Wood)
	end
	Build.post(furniture, 2, 2, L(-73, -foundation + 1, -6), rgb(78, 58, 42), M.Wood)

	------------------------------------------------------------ detailing
	local trimOnly = { CanCollide = false, CastShadow = false }
	-- exposed ceiling beams in the ground floor rooms and the hall
	for _, room in { { -18.5, -12 }, { 18.5, -12 }, { -18.5, 12 }, { 18.5, 12 } } do
		for i = -2, 2 do
			span(structure, Vector3.new(0.9, 0.9, 23), room[1] + i * 5.2, 11.55, room[2], rgb(52, 38, 28), M.Wood, trimOnly)
		end
	end
	for i = -4, 4 do
		local z = HL.z(i * 5.4)
		if z < stairFront - 1 or z > stairBack + 1 then -- not across the stair well
			span(structure, Vector3.new(9, 0.7, 0.7), 0, 11.65, i * 5.4, rgb(52, 38, 28), M.Wood, trimOnly)
		end
	end
	-- skirting along every room wall, and a chair rail at waist height
	for _, wallRun in {
		{ Vector2.new(-31.4, -23.4), Vector2.new(-5.6, -23.4) },
		{ Vector2.new(5.6, -23.4), Vector2.new(31.4, -23.4) },
		{ Vector2.new(-31.4, 23.4), Vector2.new(-5.6, 23.4) },
		{ Vector2.new(5.6, 23.4), Vector2.new(31.4, 23.4) },
	} do
		local a = Vector2.new(HL.x(wallRun[1].X), HL.z(wallRun[1].Y))
		local b = Vector2.new(HL.x(wallRun[2].X), HL.z(wallRun[2].Y))
		local mid = (a + b) / 2
		local length = (b - a).Magnitude
		for _, y in { 0.3, 13.3 } do
			boxCF(structure, Vector3.new(length, 0.6, 0.15), CF(mid.X, y, mid.Y), TRIM, M.Wood, trimOnly)
		end
		boxCF(structure, Vector3.new(length, 0.25, 0.18), CF(mid.X, 3.4, mid.Y), TRIM, M.Wood, trimOnly)
	end
	-- along the end walls, broken at the doorways into the wings
	local wingDoors: { [string]: { number } } = {
		["-1,0"] = { -13.75, 8.9 },
		["-1,13"] = { -15, 14 },
		["1,0"] = { -8, 20.5 },
		["1,13"] = { -17, 3 },
	}
	for _, side in { -1, 1 } do
		for _, y0 in { 0, 13 } do
			local cuts = wingDoors[side .. "," .. y0]
			for _, stretch in { { -23.4, -0.6 }, { 0.6, 23.4 } } do
				-- (in the bigger house: the doorways keep their width)
				local from = HL.z(stretch[1])
				local segments: { { number } } = {}
				for _, d in cuts do
					if d - 2.7 > stretch[1] and d + 2.7 < stretch[2] then
						table.insert(segments, { from, HL.z(d) - 2.7 })
						from = HL.z(d) + 2.7
					end
				end
				table.insert(segments, { from, HL.z(stretch[2]) })
				local x = HL.x(side * 31.4)
				for _, s in segments do
					local z1, z2 = s[1], s[2]
					boxCF(structure, Vector3.new(0.15, 0.6, z2 - z1), CF(x, y0 + 0.3, (z1 + z2) / 2), TRIM, M.Wood, trimOnly)
					if y0 == 0 then
						boxCF(structure, Vector3.new(0.18, 0.25, z2 - z1), CF(x, 3.4, (z1 + z2) / 2), TRIM, M.Wood, trimOnly)
					end
				end
			end
		end
	end
	-- casings around the interior doorways, both sides of the wall
	for _, d in {
		{ -5, -11.5, 0 }, { 5, -11.5, 0 }, { -5, 4.5, 0 }, { 5, 16.5, 0 },
		{ -5, -5.5, 13 }, { 5, -5.5, 13 }, { -5, 4.5, 13 }, { 5, 4.5, 13 },
	} do
		local x, z, y0 = HL.x(d[1]), HL.z(d[2]), d[3]
		for _, side in { -0.62, 0.62 } do
			boxCF(structure, Vector3.new(0.18, 0.5, 6), CF(x + side, y0 + 9.25, z), TRIM, M.Wood, trimOnly)
			for _, dz in { -2.75, 2.75 } do
				boxCF(structure, Vector3.new(0.18, 9.2, 0.5), CF(x + side, y0 + 4.6, z + dz), TRIM, M.Wood, trimOnly)
			end
		end
	end
	-- cobwebs in the upper corners
	for _, c in { { -31, -23 }, { 31, -23 }, { -31, 23 }, { 31, 23 }, { -6, -23 }, { 6, 23 } } do
		for _, y in { 11.2, 23.6 } do
			boxCF(structure, Vector3.new(2.6, 2.6, 0.03), HL.cframe(CF(c[1], y, c[2]) * ANG(0, rad(if c[1] * c[2] > 0 then 45 else -45), rad(45))), rgb(200, 200, 196), M.SmoothPlastic, {
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
				Transparency = 0.82,
			})
		end
	end
	-- shutters beside the front windows, one hanging off its hinge (shell: gone
	-- under the Blender exterior, which has its own window trim)
	for i, x in { -20, -12, 12, 22 } do
		for _, side in { -1, 1 } do
			local hanging = i == 2 and side == 1
			local cf = CF(HL.x(x) + side * 3.1, 6.25, HL.z(-24.9)) * (if hanging then CF(0, -0.8, -0.3) * ANG(0, 0, rad(-14)) else CFrame.identity)
			boxCF(shell, Vector3.new(1.9, 5.2, 0.2), cf, rgb(40, 52, 44), M.WoodPlanks, trimOnly)
		end
	end
	-- porch railing
	for _, x in { -9.5, 9.5 } do
		fixture(structure, Vector3.new(0.3, 0.3, 8.6), x, 3, -29, TRIM, M.Wood)
		for k = 0, 6 do
			fixture(structure, Vector3.new(0.2, 3, 0.2), x, 1.5, -25.4 - k * 1.2, TRIM, M.Wood, trimOnly)
		end
	end
	for _, x in { -7, 7 } do
		span(structure, Vector3.new(5, 0.3, 0.3), x, 3, -33.3, TRIM, M.Wood)
	end

	-- Blender dressing for the rooms (tools/blender/build_interiors.py):
	-- wallpaper, wainscot, tiles, crown moulding, the stair runner, blood.
	-- It only adds to the walls, so each stand-in holds a hidden anchor.
	-- (v2: with the doorways into the wings and the wing rooms)
	for _, meshName in { "FarmhouseInteriorGround2", "FarmhouseInteriorUpper2" } do
		local dressing = Build.standIn(structure, meshName)
		Build.part(dressing, Vector3.new(0.2, 0.2, 0.2), L(0, 0.1, 0), WALL, M.SmoothPlastic, {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		Build.markStandIn(dressing, O)
	end

	------------------------------------------------------------ lights
	Build.bulb(lights, S(0, 10.5, -14), rgb(255, 180, 110), 0.6, 18, true)
	Build.bulb(lights, S(2.5, 10.5, 14), rgb(255, 170, 100), 0.45, 14, true)
	Build.bulb(lights, S(18, 10, 10), rgb(255, 70, 50), 1.1, 26, true) -- slaughter room red bulb
	Build.bulb(lights, S(-18, 10.5, 12), rgb(255, 190, 120), 0.5, 18, false)
	Build.bulb(lights, S(0, 22.5, -10), rgb(255, 180, 110), 0.4, 16, true)
	Build.bulb(lights, S(-18, 22.5, 12), rgb(220, 230, 255), 0.5, 16, true) -- bathroom
	Build.bulb(lights, S(18, 22.5, 12), rgb(255, 160, 90), 0.35, 16, false)

	------------------------------------------------------------ living room (NW)
	-- stone fireplace with a low fire
	local fireplace = standIn("Fireplace", -30.4, 0, -6, -90)
	box(fireplace, Vector3.new(2.5, 8, 8), -30.6, 4, -6, rgb(96, 50, 40), M.Brick)
	box(fireplace, Vector3.new(1.2, 3.4, 4.2), -29.6, 1.7, -6, rgb(16, 12, 10), M.Slate)
	box(fireplace, Vector3.new(3.2, 0.5, 9), -30, 8.2, -6, TRIM, M.Wood)
	local hearth = box(furniture, Vector3.new(1, 0.4, 2.4), -29.8, 0.4, -6, rgb(255, 110, 40), M.Neon, { Transparency = 0.3 })
	Build.fire(hearth, 2.2, false)
	Build.candle(furniture, L(-29.6, 8.45, -9), 0.7)
	Build.candle(furniture, L(-29.6, 8.45, -3), 0.5)
	-- tufted leather sofa facing the fire
	local leather = rgb(56, 36, 30)
	local sofa = standIn("Sofa", -19.8, 0, -6, 90)
	box(sofa, Vector3.new(4, 1.6, 9), -20, 1.3, -6, leather, M.Leather)
	box(sofa, Vector3.new(1.4, 3.6, 9), -18.3, 2.3, -6, leather, M.Leather)
	box(sofa, Vector3.new(4, 2.6, 1.2), -20, 1.8, -10.9, leather, M.Leather)
	box(sofa, Vector3.new(4, 2.6, 1.2), -20, 1.8, -1.1, leather, M.Leather)
	-- coffee table
	local coffeeTable = standIn("CoffeeTable", -25, 0, -6, 90)
	box(coffeeTable, Vector3.new(3, 0.3, 5), -25, 1.8, -6, TRIM, M.Wood)
	for _, dz in { -2, 2 } do
		box(coffeeTable, Vector3.new(2.6, 1.6, 0.3), -25, 0.85, -6 + dz, TRIM, M.Wood)
	end
	-- rug
	box(furniture, Vector3.new(12, 0.05, 10), -24, 0.03, -6, rgb(90, 30, 28), M.Carpet, { CanCollide = false })
	Build.stain(furniture, L(-23, 0.07, -4), Vector2.new(1.8, 1.2), rng)
	-- old CRT television showing static
	box(furniture, Vector3.new(3, 2.2, 3.5), -8, 1.1, -20, TRIM, M.Wood)
	box(furniture, Vector3.new(2.6, 2.4, 2.8), -8, 3.4, -20, rgb(30, 28, 26), M.Plastic)
	local screen = box(furniture, Vector3.new(0.1, 1.8, 2.1), -9.35, 3.45, -20, rgb(160, 170, 175), M.Neon, { Transparency = 0.35 })
	Build.tag(screen, "TVStatic")
	local tvLight = Instance.new("SurfaceLight")
	tvLight.Face = Enum.NormalId.Left
	tvLight.Color = rgb(170, 190, 220)
	tvLight.Brightness = 0.8
	tvLight.Range = 14
	tvLight.Angle = 100
	tvLight.Parent = screen
	-- rocking chair and deer skulls on the wall
	local rocker = Props.Chair(false)
	rocker:PivotTo(L(-26, 0, -19) * ANG(0, rad(35), 0))
	rocker.Parent = furniture
	for i = 0, 2 do
		local x = -26 + i * 7
		local mount = standIn("DeerSkull", x, 7.7, -23.2, 180)
		box(mount, Vector3.new(1.2, 1.6, 0.8), x, 8.5, -23.2, rgb(214, 206, 190), M.SmoothPlastic)
		for _, s in { -1, 1 } do
			box(mount, Vector3.new(0.2, 2.4, 0.2), x + s * 0.9, 9.8, -23.1, rgb(190, 176, 150), M.SmoothPlastic, { CanCollide = false })
			box(mount, Vector3.new(0.8, 0.2, 0.2), x + s * 1.3, 10.6, -23.1, rgb(190, 176, 150), M.SmoothPlastic, { CanCollide = false })
		end
	end
	-- bookshelf on the west wall, clear of the parlor doorway
	local bookshelf = standIn("Bookshelf", -31, 0, -20.5, -90)
	box(bookshelf, Vector3.new(1.4, 9, 6), -31, 4.5, -20.5, TRIM, M.Wood)

	------------------------------------------------------------ dining room (NE): the family table
	local tableWood = rgb(70, 46, 30)
	local diningTable = standIn("DiningTable", 19, 0, -12, 0)
	box(diningTable, Vector3.new(16, 0.6, 5), 19, 3.2, -12, tableWood, M.Wood)
	for _, x in { 12, 26 } do
		for _, z in { -14, -10 } do
			box(diningTable, Vector3.new(0.6, 2.9, 0.6), x, 1.45, z, tableWood, M.Wood)
		end
	end
	for i = 0, 2 do
		for _, side in { -1, 1 } do
			local chair = Props.Chair(false)
			chair:PivotTo(L(14 + i * 5, 0, -12 + side * 4) * ANG(0, if side < 0 then 0 else math.pi, 0))
			chair.Parent = furniture
		end
	end
	for i = 0, 4 do
		local x = 12.5 + i * 3.2
		Build.post(furniture, 0.1, 1.5, L(x, 3.55, -12 + (if i % 2 == 0 then -1.3 else 1.3)), rgb(200, 196, 186), M.SmoothPlastic)
		box(furniture, Vector3.new(0.9, 0.4, 0.6), x, 3.75, -12 + (if i % 2 == 0 then -1.3 else 1.3), rgb(110, 30, 24), M.SmoothPlastic, { CanCollide = false })
		Build.candle(furniture, L(x + 1.5, 3.5, -12), 0.5 + rng:NextNumber() * 0.4)
	end
	-- covered platter and bones in the middle
	Build.ball(furniture, 2.2, L(19, 3.6, -12), rgb(160, 160, 155), M.Metal)
	for i = 0, 5 do
		box(furniture, Vector3.new(0.9, 0.2, 0.2), 15 + i, 3.6, -11 + (i % 2) * 0.6, rgb(225, 218, 200), M.SmoothPlastic, { CanCollide = false })
	end
	Build.stain(furniture, L(22, 3.53, -12.5), Vector2.new(1.5, 1), rng)
	local hutch = standIn("ChinaHutch", 30.6, 0, -18, 90)
	box(hutch, Vector3.new(2.5, 8, 7), 30.6, 4, -18, TRIM, M.Wood) -- china hutch
	box(hutch, Vector3.new(0.2, 4, 6), 29.3, 5.5, -18, rgb(40, 50, 56), M.Glass, { Transparency = 0.4 })
	Build.bulb(lights, S(19, 10, -12), rgb(255, 180, 110), 0.5, 16, true)

	------------------------------------------------------------ kitchen (SW)
	-- counters along the back wall (the stove takes the last spot)
	for i = 0, 4 do
		local x = -29 + i * 4
		local counter = standIn("KitchenCounter", x, 0, 22.4, 0)
		box(counter, Vector3.new(4, 3.4, 2.6), x, 1.7, 22.4, rgb(98, 82, 64), M.Wood)
		box(counter, Vector3.new(4.05, 0.3, 2.8), x, 3.5, 22.3, rgb(170, 166, 156), M.Marble)
	end
	box(furniture, Vector3.new(3, 0.4, 1.8), -17, 3.67, 22.4, rgb(140, 140, 145), M.Metal) -- sink
	local stove = standIn("Stove", -9, 0, 22.2, 0)
	box(stove, Vector3.new(4, 3.6, 3), -9, 1.8, 22.2, rgb(30, 30, 30), M.Metal) -- stove
	for _, dx in { -1, 1 } do
		Build.post(stove, 0.1, 1, L(-9 + dx, 3.65, 22), rgb(60, 60, 60), M.Metal)
	end
	local pot = Build.post(furniture, 1.2, 1.6, L(-9, 4.3, 22), rgb(70, 70, 72), M.Metal)
	local steam = Instance.new("Smoke")
	steam.Color = rgb(200, 200, 200)
	steam.Opacity = 0.05
	steam.RiseVelocity = 2
	steam.Size = 0.8
	steam.Parent = pot
	local fridge = standIn("Fridge", -30, 0, 4, -90)
	box(fridge, Vector3.new(3.4, 8, 3), -30, 4, 4, rgb(200, 196, 180), M.Metal) -- fridge
	-- jars of "preserves" on a shelf
	box(furniture, Vector3.new(8, 0.3, 1.4), -20, 7, 23.2, TRIM, M.Wood)
	for i = 0, 5 do
		Build.post(furniture, 0.9, 0.7, L(-23.5 + i * 1.3, 7.6, 23.1), rgb(120, 30, 26), M.Glass, { Transparency = 0.25 })
	end
	-- kitchen table with a cutting board
	local kitchenTable = standIn("KitchenTable", -18, 0, 12, 0)
	box(kitchenTable, Vector3.new(8, 0.5, 4), -18, 3, 12, rgb(100, 76, 50), M.Wood)
	for _, x in { -21.5, -14.5 } do
		for _, z in { 10.5, 13.5 } do
			box(kitchenTable, Vector3.new(0.5, 2.8, 0.5), x, 1.4, z, rgb(100, 76, 50), M.Wood)
		end
	end
	box(kitchenTable, Vector3.new(2.5, 0.2, 1.6), -18, 3.35, 12, rgb(160, 120, 80), M.Wood)
	Build.stain(furniture, L(-18, 3.47, 12), Vector2.new(0.9, 0.6), rng)
	-- pantry (hiding spot)
	local pantry = box(furniture, Vector3.new(3, 9, 5.5), -30.4, 4.5, 15, rgb(90, 70, 50), M.WoodPlanks)
	pantry.Name = "Pantry"
	box(furniture, Vector3.new(0.2, 8.4, 2.4), -28.85, 4.4, 13.7, rgb(74, 56, 40), M.Wood, { CanCollide = false })
	box(furniture, Vector3.new(0.2, 8.4, 2.4), -28.85, 4.4, 16.3, rgb(74, 56, 40), M.Wood, { CanCollide = false })
	pantry.CanCollide = false
	table.insert(later, function()
		Hiding.add(pantry, moved(L(-30.3, 3, 15) * ANG(0, rad(-90), 0)), moved(L(-26, 3, 15) * ANG(0, rad(-90), 0)), "Pantry")
	end)

	------------------------------------------------------------ slaughter room (SE)
	local tableCF = L(17, 0, 9)
	local butcherTable = AssetService.spawn("ButcherTable", tableCF, furniture, rng)
	local _, tableSize = butcherTable:GetBoundingBox()
	local tableTop = tableCF * CF(0, tableSize.Y, 0)
	local body = Props.BodyBag(rng)
	body:PivotTo(tableCF * CF(0, math.min(tableSize.Y, 3.6) - 0.2, 0))
	body.Name = "Victim"
	body.Parent = furniture

	local hooks = AssetService.create("MeatHooks", rng)
	local _, hookSize = hooks:GetBoundingBox()
	hooks:PivotTo(L(12, 12 - hookSize.Y, 21))
	hooks.Parent = furniture
	local hooks2 = AssetService.create("MeatHooks", rng)
	hooks2:PivotTo(L(24, 12 - hookSize.Y, 3) * ANG(0, rad(90), 0))
	hooks2.Parent = furniture

	local cage = Props.Cage()
	cage:PivotTo(L(28.5, 0, 4.5))
	cage.Parent = furniture
	for i = 0, 1 do
		local bag = Props.BodyBag(rng)
		bag:PivotTo(L(9, i * 1.4, 3 + i * 0.3) * ANG(0, rad(80 + i * 15), 0))
		bag.Parent = furniture
	end
	for i = 0, 2 do
		local barrel = Props.Barrel(rng)
		barrel:PivotTo(L(7.5 + i * 2.6, 0, 22.5))
		barrel.Parent = furniture
	end
	-- floor drain and pooled blood
	Build.post(furniture, 0.06, 1.4, L(17, 0.03, 13.5), rgb(30, 30, 30), M.DiamondPlate, { CanCollide = false })
	Build.stain(furniture, L(17, 0.04, 12), Vector2.new(3.5, 2.4), rng)
	Build.stain(furniture, L(12, 0.04, 6), Vector2.new(1.6, 2.2), rng)
	Build.stain(furniture, L(23, 0.04, 15), Vector2.new(1.2, 1), rng)
	-- shelf on the east wall (flashlight sits here)
	for _, y in { 3, 5.6, 8.2 } do
		box(furniture, Vector3.new(1.8, 0.25, 7), 30.9, y, 14, TRIM, M.Wood)
	end
	box(furniture, Vector3.new(0.3, 8.5, 0.3), 30.9, 4.25, 10.6, TRIM, M.Wood)
	box(furniture, Vector3.new(0.3, 8.5, 0.3), 30.9, 4.25, 17.4, TRIM, M.Wood)
	-- saws hanging on the wall
	for i = 0, 2 do
		box(furniture, Vector3.new(0.1, 0.6, 2.2), 31.3, 7 + i * 0.1, 3 + i * 2.6, rgb(150, 150, 150), M.Metal, { CanCollide = false })
	end
	-- the chair the player is tied to, facing the table
	local chairPos = L(25.5, 0, 19.5).Position
	local chairCF = CFrame.lookAt(chairPos, Vector3.new(tableCF.Position.X, chairPos.Y, tableCF.Position.Z))
	local chair = Props.Chair(true)
	chair.Name = "CaptiveChair"
	chair:PivotTo(chairCF)
	chair.Parent = furniture
	-- small side table with the knife
	local sideCF = chairCF * CF(2.3, 0, 0.4)
	Build.part(furniture, Vector3.new(1.6, 0.2, 1.6), sideCF * CF(0, 2.7, 0), TRIM, M.Wood)
	Build.post(furniture, 2.6, 0.3, sideCF * CF(0, 1.3, 0), TRIM, M.Wood)
	local knifeSpot = sideCF * CF(0, 2.82, 0) * ANG(0, rad(70), 0)
	local knife = AssetService.spawn("HuntingKnife", knifeSpot, furniture, rng)

	------------------------------------------------------------ master bedroom (NW, upstairs)
	local U = 13
	local bed = standIn("Bed", -24, U, -18.6, 180)
	box(bed, Vector3.new(7, 1.4, 9), -24, U + 1.4, -18.5, rgb(80, 60, 44), M.Wood)
	box(bed, Vector3.new(6.6, 0.8, 8.6), -24, U + 2.5, -18.5, rgb(170, 160, 140), M.Fabric)
	box(bed, Vector3.new(7, 5, 0.6), -24, U + 2.5, -23.2, rgb(70, 50, 36), M.Wood)
	box(bed, Vector3.new(2.6, 0.7, 1.6), -24, U + 3.2, -22, rgb(190, 186, 170), M.Fabric)
	Build.stain(furniture, L(-23.5, U + 2.95, -17), Vector2.new(1.6, 2), rng)
	for _, x in { -29.2, -18.8 } do
		local nightstand = standIn("Nightstand", x, U, -22, 180)
		box(nightstand, Vector3.new(2, 2.4, 2), x, U + 1.2, -22, TRIM, M.Wood)
	end
	Build.candle(furniture, L(-18.8, U + 2.4, -22.3), 0.5)
	-- wardrobe (hiding spot)
	local wardrobeModel = standIn("Wardrobe", -30.4, U, -6, -90)
	local wardrobe = box(wardrobeModel, Vector3.new(3, 9, 6), -30.4, U + 4.5, -6, rgb(64, 46, 32), M.Wood)
	wardrobe.Name = "Wardrobe"
	wardrobe.CanCollide = false
	box(wardrobeModel, Vector3.new(0.2, 8.6, 2.8), -28.85, U + 4.5, -7.45, rgb(54, 38, 28), M.WoodPlanks, { CanCollide = false })
	box(wardrobeModel, Vector3.new(0.2, 8.6, 2.8), -28.85, U + 4.5, -4.55, rgb(54, 38, 28), M.WoodPlanks, { CanCollide = false })
	table.insert(later, function()
		Hiding.add(wardrobe, moved(L(-30.3, U + 3, -6) * ANG(0, rad(-90), 0)), moved(L(-26, U + 3, -6) * ANG(0, rad(-90), 0)), "Wardrobe")
	end)
	-- dresser with a cracked mirror
	local dresser = standIn("Dresser", -12, U, -22.6, 180)
	box(dresser, Vector3.new(6, 3.4, 2), -12, U + 1.7, -22.6, TRIM, M.Wood)
	box(dresser, Vector3.new(4, 4, 0.2), -12, U + 5.6, -23.4, rgb(160, 170, 175), M.Glass, { Reflectance = 0.5 })

	------------------------------------------------------------ kid's room (NE, upstairs)
	local kidsBed = standIn("KidsBed", 27.5, U, -10, 0)
	box(kidsBed, Vector3.new(4, 1.6, 7), 27.5, U + 0.8, -10, rgb(110, 90, 70), M.Wood)
	box(kidsBed, Vector3.new(3.6, 0.6, 6.6), 27.5, U + 1.9, -10, rgb(140, 150, 170), M.Fabric)
	local chestModel = standIn("ToyChest", 26, U, -22, 180)
	local toyChest = box(chestModel, Vector3.new(4, 2.2, 2.4), 26, U + 1.1, -22, rgb(140, 60, 50), M.Wood)
	toyChest.Name = "ToyChest"
	-- a row of dolls watching the door
	for i = 0, 4 do
		local x = 10 + i * 2.2
		local doll = standIn("Doll", x, U + 1.35, -23.1, 180)
		Build.ball(doll, 0.9, L(x, U + 2.9, -23.1), rgb(230, 210, 196), M.SmoothPlastic)
		box(doll, Vector3.new(0.9, 1.4, 0.6), x, U + 1.95, -23.1, rgb(120 + i * 20, 80, 90), M.Fabric)
		box(doll, Vector3.new(0.12, 0.12, 0.05), x - 0.18, U + 3, -23.55, rgb(0, 0, 0), M.SmoothPlastic)
		box(doll, Vector3.new(0.12, 0.12, 0.05), x + 0.18, U + 3, -23.55, rgb(0, 0, 0), M.SmoothPlastic)
	end
	box(furniture, Vector3.new(11.5, 0.3, 1.4), 14.4, U + 1.2, -23.1, TRIM, M.Wood)
	local nightLight = box(furniture, Vector3.new(0.6, 0.6, 0.2), 30, U + 1.5, -1, rgb(120, 160, 255), M.Neon)
	local nl = Instance.new("PointLight")
	nl.Color = rgb(110, 140, 255)
	nl.Brightness = 0.6
	nl.Range = 12
	nl.Parent = nightLight
	-- the kid's closet wears the Blender wardrobe
	local closetModel = standIn("Wardrobe", 30.4, U, -4, 90)
	local closet = box(closetModel, Vector3.new(3, 9, 5), 30.4, U + 4.5, -4, rgb(200, 190, 170), M.Wood)
	closet.Name = "Closet"
	closet.CanCollide = false
	box(closetModel, Vector3.new(0.2, 8.6, 4.6), 28.85, U + 4.4, -4, rgb(180, 170, 150), M.WoodPlanks, { CanCollide = false })
	table.insert(later, function()
		Hiding.add(closet, moved(L(30.3, U + 3, -4) * ANG(0, rad(90), 0)), moved(L(26, U + 3, -4) * ANG(0, rad(90), 0)), "Closet")
	end)

	------------------------------------------------------------ bathroom (SW, upstairs)
	local tub = standIn("Bathtub", -26, U, 21.6, 0)
	box(tub, Vector3.new(8, 2.6, 3.6), -26, U + 1.3, 21.6, rgb(220, 216, 206), M.Marble)
	-- the bath is full, and the water isn't water
	box(furniture, Vector3.new(7.2, 0.2, 2.8), -26, U + 2.1, 21.6, rgb(60, 14, 12), M.Glass, { Transparency = 0.1, Reflectance = 0.3 })
	box(standIn("Toilet", -9, U, 22, 0), Vector3.new(2, 2, 2.4), -9, U + 1, 22, rgb(220, 216, 206), M.Marble)
	box(standIn("BathroomSink", -31, U, 8, -90), Vector3.new(3, 3, 2), -31, U + 1.5, 8, rgb(200, 196, 186), M.Marble)
	box(furniture, Vector3.new(0.2, 3, 2.6), -31.4, U + 5.6, 8, rgb(150, 160, 165), M.Glass, { Reflectance = 0.5 })
	Build.stain(furniture, L(-20, U + 0.05, 15), Vector2.new(1.4, 2.4), rng)

	------------------------------------------------------------ trophy room (SE, upstairs)
	for i = 0, 2 do
		box(furniture, Vector3.new(1.6, 0.25, 14), 30.9, U + 2.5 + i * 2.6, 13, TRIM, M.Wood)
		for j = 0, 5 do
			local z = 7.5 + j * 2.2
			if (i + j) % 2 == 0 then
				Build.ball(furniture, 0.9, L(30.9, U + 3.1 + i * 2.6, z), rgb(220, 212, 196), M.SmoothPlastic)
			else
				Build.post(furniture, 1, 0.8, L(30.9, U + 3.15 + i * 2.6, z), rgb(110, 40, 30), M.Glass, { Transparency = 0.3 })
			end
		end
	end
	box(furniture, Vector3.new(6, 0.4, 3), 22, U + 3, 21.5, TRIM, M.Wood) -- desk
	for _, x in { 19.4, 24.6 } do
		box(furniture, Vector3.new(0.4, 2.8, 2.6), x, U + 1.4, 21.5, TRIM, M.Wood)
	end
	-- piles of the victims' belongings
	for i = 0, 7 do
		box(furniture, Vector3.new(rng:NextNumber(1, 2), rng:NextNumber(0.4, 1.2), rng:NextNumber(1, 1.8)), 10 + rng:NextNumber(0, 6), U + 0.4 + (i // 3) * 0.6, 20 + rng:NextNumber(0, 3), Color3.fromHSV(rng:NextNumber(), 0.4, 0.35), M.Fabric)
	end
	-- clothes rack
	box(furniture, Vector3.new(0.2, 0.2, 7), 9, U + 6.5, 12, rgb(90, 90, 90), M.Metal)
	for i = 0, 4 do
		box(furniture, Vector3.new(0.4, 3.6, 1.8), 9, U + 4.6, 9.5 + i * 1.3, Color3.fromHSV(rng:NextNumber(), 0.5, 0.4), M.Fabric, { CanCollide = false })
	end

	------------------------------------------------------------ ground floor hall
	-- a tall clock ticking by the front door
	local clock = standIn("GrandfatherClock", -3.75, 0, -17.5, -90)
	box(clock, Vector3.new(1.4, 8, 2.2), -3.75, 4, -17.5, rgb(58, 40, 28), M.Wood)

	------------------------------------------------------------ upstairs hall
	box(furniture, Vector3.new(0.2, 3.6, 2.6), -4.4, U + 6, -16, rgb(60, 50, 40), M.Wood)
	box(furniture, Vector3.new(0.1, 3, 2), -4.25, U + 6, -16, rgb(110, 90, 80), M.Fabric)

	------------------------------------------------------------ into the bigger rooms
	-- The furniture (here and in HouseWings) was laid out on the plan. Move
	-- each piece as a whole - a model, or loose parts that touch: a desk and
	-- its legs, a table with its chairs and candles - keeping pieces that
	-- stand against a wall against it (HouseLayout.offsetFor).
	do
		type Item = { roots: { Instance }, parts: { BasePart }, lo: Vector3, hi: Vector3, flat: boolean }
		local items: { Item } = {}
		for _, child in furniture:GetChildren() do
			local parts: { BasePart } = {}
			if child:IsA("BasePart") then
				table.insert(parts, child)
			end
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			if #parts > 0 then
				local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
				for _, p in parts do
					local cf = O:ToObjectSpace(p.CFrame)
					local s = p.Size / 2
					local e = Vector3.new(
						math.abs(cf.XVector.X) * s.X + math.abs(cf.YVector.X) * s.Y + math.abs(cf.ZVector.X) * s.Z,
						math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z,
						math.abs(cf.XVector.Z) * s.X + math.abs(cf.YVector.Z) * s.Y + math.abs(cf.ZVector.Z) * s.Z
					)
					lo = lo:Min(cf.Position - e)
					hi = hi:Max(cf.Position + e)
				end
				table.insert(items, { roots = { child }, parts = parts, lo = lo, hi = hi, flat = hi.Y - lo.Y <= 0.15 })
			end
		end
		-- pieces that touch (or nearly: chairs at a table) move together;
		-- rugs and stains on the floor don't tie anything to anything
		local link: { number } = {}
		for i = 1, #items do
			link[i] = i
		end
		local function find(i: number): number
			while link[i] ~= i do
				link[i] = link[link[i]]
				i = link[i]
			end
			return i
		end
		for i = 1, #items do
			local a = items[i]
			if not a.flat then
				for j = i + 1, #items do
					local b = items[j]
					if not b.flat
						and a.lo.X - 1 < b.hi.X and b.lo.X - 1 < a.hi.X
						and a.lo.Z - 1 < b.hi.Z and b.lo.Z - 1 < a.hi.Z
						and a.lo.Y - 0.1 < b.hi.Y and b.lo.Y - 0.1 < a.hi.Y
					then
						link[find(i)] = find(j)
					end
				end
			end
		end
		local groups: { [number]: { lo: Vector3, hi: Vector3, members: { Item } } } = {}
		for i, item in items do
			local r = find(i)
			local g = groups[r]
			if g then
				g.lo = g.lo:Min(item.lo)
				g.hi = g.hi:Max(item.hi)
				table.insert(g.members, item)
			else
				groups[r] = { lo = item.lo, hi = item.hi, members = { item } }
			end
		end
		local pieces: { HouseLayout.Piece } = {}
		for _, g in groups do
			local offset = HL.offsetFor(g.lo, g.hi)
			for _, item in g.members do
				local root = item.roots[1]
				if root:IsA("Model") then
					root:PivotTo(root:GetPivot() + offset)
				elseif root:IsA("BasePart") then
					root.CFrame += offset
				end
				table.insert(pieces, { lo = item.lo, hi = item.hi, offset = offset })
			end
		end
		HL.register(pieces)
	end
	for _, fn in later do
		fn()
	end

	------------------------------------------------------------ gameplay data
	local function at(x: number, y: number, z: number): Vector3
		return L(x, y, z).Position
	end

	local info: Info = {
		origin = O,
		model = model,
		chairSeat = chairCF * CF(0, 2.05, 0),
		chairEye = chairCF * CF(0, 4.6, -0.2),
		chair = chair,
		tableTop = tableTop,
		body = body,
		knifeSpot = knifeSpot,
		knife = knife,
		slaughterDoor = slaughterDoor,
		frontDoor = frontDoor,
		padlock = padlock,
		spawnInside = CFrame.lookAt(at(22, 3, 17), at(5, 3, 16.5)),
		spawnPorch = CFrame.lookAt(at(0, 3, -30), at(0, 3, -60)),
		groundPatrol = {
			at(0, 0, -18),
			at(-18, 0, -14),
			at(0, 0, -6),
			at(18, 0, -18),
			at(0, 0, -3),
			at(-16, 0, 8),
			at(2.5, 0, 10),
			at(15, 0, 17),
			at(2.5, 0, 20),
			at(0, 0, -12),
		},
		upperPatrol = {
			at(0, U, -16),
			at(-16, U, -12),
			at(0, U, -3),
			at(18, U, -14),
			at(1, U, 4),
			at(-17, U, 12),
			at(4, U, 5), -- beside the stair well
			at(17, U, 12),
			at(2.5, U, 18),
		},
		keySpots = {
			L(-29.2, U + 2.45, -22) * ANG(0, rad(30), 0),
			L(26, U + 2.25, -22) * ANG(0, rad(-20), 0),
			L(22.5, U + 3.25, 21.5) * ANG(0, rad(75), 0),
		},
		spots = {
			Flashlight = L(30.9, 3.15, 13) * ANG(0, rad(90), 0),
			Syringe = L(-31, U + 3.05, 8.5) * ANG(0, rad(20), 0),
			Bandage = L(-31, U + 3.05, 7.2),
			BatteryKitchen = L(-25, 3.68, 22.2),
			BatteryLiving = L(-25, 1.98, -6.5),
			NoteLedger = L(30.9, 5.75, 15.5) * ANG(0, rad(90), 0),
			NoteDiary = L(-25, 1.98, -5),
			NoteDrawing = L(14, U + 1.38, -23) * ANG(0, rad(10), 0),
			NoteClipping = L(21, U + 3.22, 21.4) * ANG(0, rad(-12), 0),
		},
		actors = {
			butcher = CFrame.lookAt(at(17, 0, 12.4), at(17, 0, 9)),
			brother = CFrame.lookAt(at(20.5, 0, 5.4), at(17, 0, 9)),
			exit = L(2.5, 0, 16.5),
			doorway = L(7, 0, 16.5),
		},
		center = O.Position,
		crowbarSpots = wings.crowbarSpots,
		workbench = wings.workbench,
		recordPlayer = wings.recordPlayer,
		radio = wings.radio,
		attic = wings.attic,
		polaroidSpots = wings.polaroidSpots,
		junkSpots = wings.junkSpots,
	}
	-- the wings join the patrols, and hide most of what you need to get out
	for _, p in wings.groundPatrol do
		table.insert(info.groundPatrol, p)
	end
	for _, p in wings.upperPatrol do
		table.insert(info.upperPatrol, p)
	end
	for _, cf in wings.keySpots do
		table.insert(info.keySpots, cf)
	end
	for name, cf in wings.spots do
		info.spots[name] = cf
	end

	-- the spots above are on the plan: move them into the bigger house, with
	-- whatever piece of furniture they sit on
	local function movedPoint(v: Vector3): Vector3
		return O * HL.place(O:PointToObjectSpace(v))
	end
	local function movedList<T>(list: { T }, fn: (T) -> T)
		for i, v in list do
			list[i] = fn(v)
		end
	end
	info.chairSeat = moved(info.chairSeat)
	info.chairEye = moved(info.chairEye)
	info.tableTop = moved(info.tableTop)
	info.knifeSpot = moved(info.knifeSpot)
	info.spawnInside = moved(info.spawnInside)
	info.spawnPorch = moved(info.spawnPorch)
	info.workbench = moved(info.workbench)
	info.attic = movedPoint(info.attic)
	movedList(info.groundPatrol, movedPoint)
	movedList(info.upperPatrol, movedPoint)
	movedList(info.keySpots, moved)
	movedList(info.crowbarSpots, moved)
	movedList(info.junkSpots, moved)
	for _, t in { info.spots, info.actors, info.polaroidSpots } do
		for name, cf in t do
			t[name] = moved(cf)
		end
	end

	-- the old box house: every plain floor, wall, stair and box of furniture
	-- is shown as its Blender remodel instead (the parts keep the collisions)
	if knife then
		knife:SetAttribute("KeepVisible", true)
	end
	Build.bake(structure, "FarmhouseStructure", O)
	Build.bake(furniture, "FarmhouseFurnish", O)
	return info
end

return House

--!strict
-- The last act's places (Systems/Finale runs the story there):
--
--   HeliCrash  where the rescue helicopter comes down, a drag trail leading
--              south through the trees
--   Plant      Hollow Meats, the family's meat plant by the highway: loading
--              bay, kill floor, office, generator room, cold storage (where
--              the pilot hangs), and a steel door out back into the old mine
--   Church     Pinecrest's church at the end of a dead Main Street: the
--              family's supper table before the altar, a bell tower, and the
--              crypt the mine tunnels come out in
--
-- The terrain is baked into the place without these, so their pads are
-- levelled and their trails painted here at runtime.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)
local Terrain = require(script.Parent.Terrain)
local AssetService = require(script.Parent.Parent.Systems.AssetService)
local Doors = require(script.Parent.Parent.Systems.Doors)
local Hiding = require(script.Parent.Parent.Systems.Hiding)

local FinaleSites = {}

export type Info = {
	crash: {
		center: CFrame,
		wreck: CFrame, -- where the helicopter ends up
		spawns: { CFrame },
		trail: { Vector3 },
	},
	plant: {
		origin: CFrame,
		gate: Vector3,
		breakers: { BasePart },
		keycardSpots: { CFrame },
		coldDoor: Doors.Door,
		pilot: Model,
		mineDoor: Doors.Door,
		minePortal: Vector3,
		lamps: { Light },
		patrol: { Vector3 },
		checkpoint: CFrame,
		bench: CFrame,
		junkSpots: { CFrame },
	},
	church: {
		origin: CFrame,
		cryptSpawns: { CFrame },
		cryptDoor: Doors.Door,
		cryptKeySpots: { CFrame },
		bell: BasePart,
		patrol: { Vector3 },
		checkpoint: CFrame,
		cruiser: CFrame,
		polaroid: CFrame,
		street: Vector3,
	},
}

local rgb = Color3.fromRGB
local M = Enum.Material
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local CONCRETE = rgb(120, 116, 108)
local BLOCK = rgb(104, 98, 90)
local STEEL = rgb(130, 134, 138)
local RUST = rgb(120, 70, 44)
local STONE = rgb(110, 104, 96)
local DARK_WOOD = rgb(58, 42, 30)

local noCollide = { CanCollide = false, CastShadow = false }

-- Levels a site's pad on the baked terrain; returns its centre on the ground.
local function pad(name: string): CFrame
	local site = Config.Sites[name]
	local x, z = site.pos.X, site.pos.Y
	local y = Terrain.groundY(x, z)
	local t = workspace.Terrain
	t:FillCylinder(CF(x, y - 5, z), 10, site.radius, M.Ground)
	t:FillCylinder(CF(x, y + 35, z), 70, site.radius - 2, M.Air)
	return CF(x, y, z)
end

-- Paints a trail or road onto the baked terrain.
local function paint(points: { Vector2 }, width: number, material: Enum.Material)
	local t = workspace.Terrain
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		local yaw = math.atan2(b.X - a.X, b.Y - a.Y)
		local steps = math.max(1, math.floor(length / 3))
		for s = 0, steps do
			local p = a:Lerp(b, s / steps)
			local y = Terrain.groundY(p.X, p.Y)
			t:FillBlock(CF(p.X, y - 1, p.Y) * ANG(0, yaw, 0), Vector3.new(width * 2, 2, 4), material)
		end
	end
end

local function lamp(parent: Instance, cf: CFrame, color: Color3, range: number, on: boolean): PointLight
	Build.part(parent, Vector3.new(1.6, 0.5, 1.6), cf, rgb(60, 60, 60), M.Metal, noCollide)
	local bulb = Build.part(parent, Vector3.new(1, 0.25, 1), cf * CF(0, -0.35, 0), color, if on then M.Neon else M.Glass, noCollide)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 1.4
	light.Shadows = true
	light.Enabled = on
	light.Parent = bulb
	bulb:SetAttribute("Lamp", true)
	return light
end

---------------------------------------------------------------- heli crash

local function buildCrash(world: Instance, rng: Util.Rng): any
	local C = pad("HeliCrash")
	local folder = Build.folder(world, "HeliCrash")
	local function L(x: number, y: number, z: number): CFrame
		return C * CF(x, y, z)
	end
	-- a scorched furrow, snapped trees, burning wreckage
	for i = 0, 7 do
		Build.part(folder, Vector3.new(6 + rng:NextNumber(0, 4), 0.2, 4), L(-14 + i * 4, 0.05, rng:NextNumber(-2, 2)) * ANG(0, rng:NextNumber(-0.3, 0.3), 0), rgb(30, 26, 24), M.Ground, noCollide)
	end
	for i = 0, 5 do
		local x, z = rng:NextNumber(-24, 24), rng:NextNumber(-24, 24)
		Build.cylinder(folder, rng:NextNumber(10, 18), rng:NextNumber(1.2, 2), L(x, 0.8, z) * ANG(0, rng:NextNumber(0, 6), rad(90)), rgb(70, 54, 40), M.Wood)
		Build.post(folder, rng:NextNumber(2, 5), 2, L(x + 4, 1.5, z - 2), rgb(70, 54, 40), M.Wood)
	end
	for i = 0, 9 do
		Build.part(folder, Vector3.new(rng:NextNumber(1, 4), rng:NextNumber(0.2, 0.6), rng:NextNumber(1, 3)), L(rng:NextNumber(-20, 20), 0.4, rng:NextNumber(-16, 16)) * ANG(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6), rng:NextNumber(-0.5, 0.5)), if i % 3 == 0 then rgb(200, 190, 60) else rgb(60, 64, 70), M.Metal)
	end
	local blaze = Build.part(folder, Vector3.new(3, 0.5, 3), L(8, 0.3, 5), rgb(255, 110, 40), M.Neon, { Transparency = 0.4, CanCollide = false })
	Build.fire(blaze, 7, true)
	-- the drag marks start at the wreck and lead off south
	local trail: { Vector3 } = {}
	local road: Config.Road? = nil
	for _, r in Config.Roads do
		if r.name == "DragTrail" then
			road = r
		end
	end
	if road then
		for i = 1, #road.points - 1 do
			local a, b = road.points[i], road.points[i + 1]
			local steps = math.floor((b - a).Magnitude / 7)
			for s = 0, steps - 1 do
				local p = a:Lerp(b, s / steps)
				local y = Terrain.groundY(p.X, p.Y)
				local pos = Vector3.new(p.X + rng:NextNumber(-0.6, 0.6), y + 0.05, p.Y)
				table.insert(trail, pos)
				Build.part(folder, Vector3.new(0.9, 0.05, 2.2), CF(pos) * ANG(0, math.atan2(b.X - a.X, b.Y - a.Y) + rng:NextNumber(-0.2, 0.2), 0), rgb(70, 8, 6), M.Glass, {
					CanCollide = false,
					CastShadow = false,
					Reflectance = 0.1,
				})
			end
		end
	end
	return {
		center = C,
		wreck = L(0, 3.2, 0) * ANG(rad(8), rad(35), rad(-24)),
		spawns = { L(-9, 3, -10), L(-12, 3, -6), L(-6, 3, -13), L(-14, 3, -12) },
		trail = trail,
	}
end

---------------------------------------------------------------- the plant

local function buildPlant(world: Instance, rng: Util.Rng): any
	local P = pad("Plant")
	local model = Build.model(world, "HollowMeats")
	local structure = Build.model(model, "Structure")
	local furniture = Build.model(model, "Furniture")
	local lights = Build.model(model, "Lights")
	local FY = 1
	local H = 16
	local function L(x: number, y: number, z: number): CFrame
		return P * CF(x, y, z)
	end
	local function box(p: Instance, size: Vector3, x: number, y: number, z: number, color: Color3, mat: Enum.Material, extra: { [string]: any }?): Part
		return Build.part(p, size, L(x, y, z), color, mat, extra)
	end
	local function wall(a: Vector2, b: Vector2, openings: { Build.Opening }, color: Color3, mat: Enum.Material, thick: number?)
		Build.wall(structure, P, a, b, FY, H, thick or 1.2, openings, color, mat)
	end
	local function door(at: number, w: number?, top: number?): Build.Opening
		return { at = at, width = w or 5, bottom = 0, top = top or 9 }
	end
	local function high(at: number): Build.Opening
		return { at = at, width = 6, bottom = 11, top = 14 }
	end

	-- slab, floor and roof
	box(structure, Vector3.new(76, 2, 52), 0, 0, 0, CONCRETE, M.Concrete)
	box(structure, Vector3.new(74, 1, 50), 0, FY + H + 0.5, 0, rgb(80, 76, 72), M.CorrodedMetal)
	for _, z in { -25.4, 25.4 } do
		box(structure, Vector3.new(76, 2, 0.8), 0, FY + H + 1.5, z, BLOCK, M.Concrete)
	end
	for _, x in { -37.4, 37.4 } do
		box(structure, Vector3.new(0.8, 2, 52), x, FY + H + 1.5, 0, BLOCK, M.Concrete)
	end
	-- outside walls: roll-up doors and a staff door in front, the mine door
	-- at the back, high windows along the kill floor
	wall(Vector2.new(-36.6, -24), Vector2.new(36.6, -24), { door(-20, 10, 10), door(4, 10, 10), door(28, 4.5, 8) }, BLOCK, M.Concrete)
	wall(Vector2.new(-36.6, 24), Vector2.new(36.6, 24), { door(-20, 5, 9), high(4), high(24) }, BLOCK, M.Concrete)
	wall(Vector2.new(-36, -24), Vector2.new(-36, 24), { high(-6), high(6), high(18) }, BLOCK, M.Concrete)
	wall(Vector2.new(36, -24), Vector2.new(36, 24), { { at = -6, width = 4, bottom = 4, top = 8 } }, BLOCK, M.Concrete)
	-- inside: loading bay | kill floor | corridor | office, generator, cold
	wall(Vector2.new(-35.4, -12), Vector2.new(35.4, -12), { door(-14, 8, 12), door(10.5, 4.5) }, rgb(150, 146, 136), M.Plaster, 0.8)
	wall(Vector2.new(8, -12), Vector2.new(8, 23.4), { door(6) }, rgb(150, 146, 136), M.Plaster, 0.8)
	wall(Vector2.new(13, -12), Vector2.new(13, 23.4), { door(-6), door(6), door(18) }, rgb(150, 146, 136), M.Plaster, 0.8)
	wall(Vector2.new(13.4, 0), Vector2.new(35.4, 0), {}, rgb(150, 146, 136), M.Plaster, 0.8)
	wall(Vector2.new(13.4, 12), Vector2.new(35.4, 12), {}, rgb(196, 214, 222), M.Plaster, 0.8)
	-- the roll-up doors stay down; the staff door hangs off its hinges
	for _, x in { -20, 4 } do
		box(structure, Vector3.new(10, 10, 0.4), x, FY + 5, -24.1, rgb(150, 150, 146), M.CorrodedMetal)
		for i = 0, 9 do
			box(structure, Vector3.new(10, 0.12, 0.5), x, FY + 0.6 + i, -24.3, rgb(120, 120, 116), M.Metal, noCollide)
		end
	end
	Build.part(structure, Vector3.new(4.3, 8, 0.3), L(30.6, FY + 0.3, -27) * ANG(rad(-88), 0, rad(6)), rgb(90, 96, 100), M.Metal)
	-- dock apron and the sign over it
	box(structure, Vector3.new(40, 1.2, 8), -8, FY - 0.4, -28.5, CONCRETE, M.Concrete)
	local sign = box(structure, Vector3.new(26, 4, 0.4), -8, FY + H + 4.2, -25.6, rgb(150, 30, 26), M.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 30
	gui.LightInfluence = 1
	gui.Parent = sign
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "HOLLOW MEATS - FAMILY BUTCHERS"
	text.TextScaled = true
	text.Font = Enum.Font.Bangers
	text.TextColor3 = rgb(236, 226, 200)
	text.Parent = gui
	for _, x in { -18, 2 } do
		Build.post(structure, 4, 0.3, L(x, FY + H + 2, -25.4), STEEL, M.Metal)
	end

	-- lights: dead until the breakers are thrown; red emergency lamps flicker
	local lamps: { Light } = {}
	for _, pos in { { -26, -18 }, { -6, -18 }, { 22, -18 }, { -26, 0 }, { -10, 0 }, { -26, 14 }, { -10, 14 }, { 2, 6 }, { 10.5, 0 }, { 24, -6 }, { 24, 6 }, { 24, 18 } } do
		table.insert(lamps, lamp(lights, L(pos[1], FY + H - 0.6, pos[2]), rgb(255, 236, 200), 26, false))
	end
	for _, pos in { { -30, -20 }, { -30, 20 }, { 10.5, 20 }, { 30, -20 } } do
		Build.bulb(lights, L(pos[1], FY + H - 1.5, pos[2]), rgb(255, 40, 30), 0.6, 18, true)
	end
	for _, l in lamps do
		l.Brightness = 1.6
	end

	-- loading bay: pallets, crates, a cage of lockers, the first breaker
	for i = 0, 5 do
		local crate = Props.Crate(rng)
		crate:PivotTo(L(-30 + i * 5 + rng:NextNumber(-1, 1), FY, -18 + (i % 2) * 4) * ANG(0, rng:NextNumber(-0.3, 0.3), 0))
		crate.Parent = furniture
	end
	for i = 0, 4 do
		box(furniture, Vector3.new(2, 7, 1.6), 22 + i * 2.1, FY + 3.5, -22.8, rgb(70, 90, 80), M.Metal)
	end
	local lockerBody = box(furniture, Vector3.new(3, 8, 2), 32.5, FY + 4, -22.6, rgb(70, 90, 80), M.Metal)
	lockerBody.Name = "Locker"
	lockerBody.CanCollide = false
	Hiding.add(lockerBody, L(32.5, FY + 3, -22.6) * ANG(0, math.pi, 0), L(32.5, FY + 3, -18.5) * ANG(0, math.pi, 0), "Locker")
	local breakers: { BasePart } = {}
	local function breaker(cf: CFrame): BasePart
		local panel = Build.part(furniture, Vector3.new(2.2, 3, 0.6), cf, rgb(90, 96, 100), M.Metal)
		Build.part(furniture, Vector3.new(0.3, 1.2, 0.3), cf * CF(0.5, 0.2, -0.4), rgb(200, 40, 30), M.SmoothPlastic, noCollide)
		panel.Name = "Breaker"
		table.insert(breakers, panel)
		return panel
	end
	breaker(L(-35.2, FY + 5, -18) * ANG(0, rad(-90), 0))

	-- kill floor: the rail, hooks, carcasses, steel tables, a closet
	for _, z in { 0, 12 } do
		box(structure, Vector3.new(42, 0.5, 0.5), -14, FY + 13, z, STEEL, M.Metal, noCollide)
		for i = 0, 3 do
			local hooks = AssetService.create("MeatHooks", rng)
			local _, size = hooks:GetBoundingBox()
			hooks:PivotTo(L(-30 + i * 10, FY + 13 - size.Y, z) * ANG(0, rad(90), 0))
			hooks.Parent = furniture
		end
		for i = 0, 5 do
			local x = -32 + i * 7 + rng:NextNumber(-1, 1)
			box(furniture, Vector3.new(0.15, 3, 0.15), x, FY + 11.5, z, STEEL, M.Metal, noCollide)
			box(furniture, Vector3.new(2.4, 5, 1.6), x, FY + 7.4, z, rgb(150, 70, 60), M.SmoothPlastic, { CanCollide = false })
			box(furniture, Vector3.new(2.2, 4.4, 0.2), x, FY + 7.4, z - 0.85, rgb(220, 200, 180), M.SmoothPlastic, noCollide)
		end
	end
	for i, x in { -26, -8 } do
		AssetService.spawn("ButcherTable", L(x, FY, 6) * ANG(0, rad(90), 0), furniture, rng)
		Build.stain(furniture, L(x + 1, FY + 0.05, 6 + i), Vector2.new(3, 2.2), rng)
	end
	for i = 0, 6 do
		Build.post(furniture, 0.06, 1.2, L(-30 + i * 6, FY + 0.03, 18), rgb(30, 30, 30), M.DiamondPlate, { CanCollide = false })
		Build.stain(furniture, L(-30 + i * 6 + rng:NextNumber(-2, 2), FY + 0.05, 18 + rng:NextNumber(-3, 1)), Vector2.new(2, 1.4), rng)
	end
	breaker(L(-35.2, FY + 5, 18) * ANG(0, rad(-90), 0))
	local closet = box(furniture, Vector3.new(5, 9, 3), -32, FY + 4.5, 21.8, rgb(90, 96, 100), M.Metal)
	closet.Name = "Closet"
	closet.CanCollide = false
	Hiding.add(closet, L(-32, FY + 3, 21.9), L(-32, FY + 3, 17.6), "Supply closet")

	-- office: desk, filing cabinets, the foreman's calendar
	box(furniture, Vector3.new(6, 0.4, 3), 24, FY + 3, -8, rgb(110, 84, 58), M.Wood)
	for _, dx in { -2.6, 2.6 } do
		box(furniture, Vector3.new(0.6, 3, 2.6), 24 + dx, FY + 1.5, -8, rgb(110, 84, 58), M.Wood)
	end
	for i = 0, 2 do
		box(furniture, Vector3.new(2, 5, 2.4), 34 - i * 2.2, FY + 2.5, -1.8, rgb(100, 104, 100), M.Metal)
	end
	local chair = Props.Chair(false)
	chair:PivotTo(L(24, FY, -5.5) * ANG(0, math.pi, 0))
	chair.Parent = furniture
	box(furniture, Vector3.new(4, 5, 0.1), 35.3, FY + 6, -9, rgb(230, 224, 210), M.SmoothPlastic, noCollide)

	-- generator room: the generator, fuel drums, the main breaker, a bench
	local generator = Props.Generator()
	generator:PivotTo(L(22, FY, 6))
	generator.Parent = furniture
	for i = 0, 2 do
		local barrel = Props.Barrel(rng)
		barrel:PivotTo(L(32, FY, 2 + i * 2.6))
		barrel.Parent = furniture
	end
	breaker(L(35.2, FY + 5, 9) * ANG(0, rad(90), 0))
	box(furniture, Vector3.new(8, 0.5, 3), 24, FY + 3.25, 10.4, rgb(96, 72, 48), M.Wood)
	for _, dx in { -3.6, 3.6 } do
		box(furniture, Vector3.new(0.6, 3, 2.8), 24 + dx, FY + 1.5, 10.4, rgb(96, 72, 48), M.Wood)
	end

	-- cold storage: frost, hanging meat, the pilot
	box(structure, Vector3.new(22, 0.2, 11.2), 24.4, FY + 0.1, 18, rgb(210, 226, 232), M.Ice, noCollide)
	for i = 0, 3 do
		local x = 17 + i * 5
		box(furniture, Vector3.new(0.15, 4, 0.15), x, FY + 13, 21, STEEL, M.Metal, noCollide)
		box(furniture, Vector3.new(2.4, 5.2, 1.6), x, FY + 8.4, 21, rgb(170, 90, 80), M.SmoothPlastic, { CanCollide = false })
	end
	local cold = Instance.new("PointLight")
	cold.Color = rgb(140, 190, 255)
	cold.Range = 20
	cold.Brightness = 0.8
	cold.Parent = box(lights, Vector3.new(1, 0.3, 1), 24, FY + H - 0.5, 18, rgb(160, 200, 255), M.Neon, noCollide)
	local pilot = Build.model(furniture, "Pilot")
	local hang = L(28, FY, 15.5)
	Build.part(pilot, Vector3.new(0.2, 4, 0.2), hang * CF(0, 12, 0), STEEL, M.Metal, noCollide)
	Build.part(pilot, Vector3.new(2, 2.6, 1), hang * CF(0, 7.6, 0), rgb(200, 110, 40), M.Fabric, noCollide)
	Build.ball(pilot, 1.15, hang * CF(0, 9.5, 0) * ANG(0.4, 0, 0), rgb(196, 160, 132), M.SmoothPlastic, noCollide)
	for _, s in { -1, 1 } do
		Build.part(pilot, Vector3.new(0.8, 2.8, 0.8), hang * CF(s * 0.5, 4.9, 0), rgb(200, 110, 40), M.Fabric, noCollide)
		Build.part(pilot, Vector3.new(0.6, 2.8, 0.6), hang * CF(s * 1.3, 9.6, 0) * ANG(0, 0, s * rad(170)), rgb(200, 110, 40), M.Fabric, noCollide)
	end
	Build.part(pilot, Vector3.new(1.4, 1.4, 1.4), hang * CF(0, 7.6, 0), rgb(255, 255, 255), M.SmoothPlastic, { Name = "PilotPrompt", Transparency = 1, CanCollide = false })

	-- doors
	local function hingeZ(x: number, zc: number): CFrame
		return L(x, FY, zc - 2.4) * ANG(0, -math.pi / 2, 0)
	end
	Doors.create(model, L(10.5 - 2.2, FY, -12), 4.4, 9, { name = "CorridorDoor", color = rgb(90, 96, 100) })
	Doors.create(model, hingeZ(8, 6), 4.8, 9, { name = "KillFloorDoor", color = rgb(90, 96, 100) })
	Doors.create(model, hingeZ(13, -6), 4.8, 9, { name = "OfficeDoor", swing = 1, color = rgb(110, 84, 58) })
	Doors.create(model, hingeZ(13, 6), 4.8, 9, { name = "GeneratorDoor", swing = 1, color = rgb(90, 96, 100) })
	local coldDoor = Doors.create(model, hingeZ(13, 18), 4.8, 9, {
		name = "ColdStorageDoor",
		swing = 1,
		locked = true,
		lockedText = "Cold storage. The lock is electric - no power, no way in.",
		color = rgb(196, 214, 222),
	})
	local mineDoor = Doors.create(model, L(-20 - 2.4, FY, 24), 4.8, 9, {
		name = "MineDoor",
		locked = true,
		keyItem = "Keycard",
		lockedText = "A steel door marked MINE ACCESS - AUTHORISED ONLY. There's a card reader.",
		color = RUST,
	})

	-- out back: the mine head against the hillside
	local portal = L(-20, FY, 36)
	for _, dx in { -3.5, 3.5 } do
		Build.part(structure, Vector3.new(1, 10, 1), portal * CF(dx, 5, 0), DARK_WOOD, M.Wood)
	end
	Build.part(structure, Vector3.new(9, 1, 1.2), portal * CF(0, 10, 0), DARK_WOOD, M.Wood)
	Build.part(structure, Vector3.new(8, 10, 1), portal * CF(0, 5, 2), rgb(8, 6, 6), M.SmoothPlastic)
	Build.part(structure, Vector3.new(8, 1.2, 12), portal * CF(0, -0.4, -5), rgb(70, 60, 50), M.WoodPlanks)
	for i = 0, 5 do
		Build.part(structure, Vector3.new(0.4, 0.3, 11), portal * CF(-1.6 + (i % 2) * 3.2, 0.3, -5), STEEL, M.Metal, noCollide)
	end
	local rocks = { { -8, 6 }, { 8, 6 }, { -10, 9 }, { 10, 9 } }
	for _, r in rocks do
		local rock = Props.Rock(rng)
		rock:PivotTo(portal * CF(r[1], 0, r[2]))
		rock.Parent = furniture
	end

	local function at(x: number, z: number): Vector3
		return L(x, FY, z).Position
	end
	return {
		origin = P,
		gate = L(0, FY, -34).Position,
		breakers = breakers,
		keycardSpots = {
			L(24.5, FY + 3.25, -8.4) * ANG(0, rad(20), 0), -- the foreman's desk
			L(-26, FY + 3.4, 6.5) * ANG(0, rad(70), 0), -- a butcher table
			L(22, FY + 3.55, 10.4) * ANG(0, rad(-10), 0), -- the generator room bench
			L(22, FY + 0.15, -21) * ANG(0, rad(40), 0), -- by the lockers
		},
		coldDoor = coldDoor,
		pilot = pilot,
		mineDoor = mineDoor,
		minePortal = portal.Position,
		lamps = lamps,
		patrol = { at(-26, -18), at(-6, -18), at(22, -18), at(-24, 6), at(-6, 6), at(-20, 18), at(10.5, 0), at(10.5, 16), at(24, -6), at(24, 6) },
		checkpoint = L(0, FY + 3, -34) * ANG(0, math.pi, 0),
		bench = L(24, FY + 3.5, 10.4),
		junkSpots = {
			L(-10, FY + 0.2, -19),
			L(25, FY + 3.25, -7.4),
			L(27, FY + 3.55, 10.6),
			L(31.5, FY + 3.3, 2),
			L(-30, FY + 0.2, 10),
		},
	}
end

---------------------------------------------------------------- the church

local function buildChurch(world: Instance, rng: Util.Rng): any
	local C = pad("Church")
	local model = Build.model(world, "PinecrestChurch")
	local structure = Build.model(model, "Structure")
	local furniture = Build.model(model, "Furniture")
	local lights = Build.model(model, "Lights")
	local CY = 1.5
	local WH = 18
	local function L(x: number, y: number, z: number): CFrame
		return C * CF(x, y, z)
	end
	local function box(p: Instance, size: Vector3, x: number, y: number, z: number, color: Color3, mat: Enum.Material, extra: { [string]: any }?): Part
		return Build.part(p, size, L(x, y, z), color, mat, extra)
	end
	local function wall(a: Vector2, b: Vector2, y0: number, h: number, openings: { Build.Opening }, color: Color3?, mat: Enum.Material?)
		Build.wall(structure, C, a, b, y0, h, 1.2, openings, color or STONE, mat or M.Slate)
	end
	local function gothic(at: number): Build.Opening
		return { at = at, width = 3, bottom = 6, top = 14 }
	end

	-- foundation, open under the crypt (x -10..10, z 4..18)
	local F = 3
	box(structure, Vector3.new(30, F, 27), 0, CY - F / 2, -9.5, STONE, M.Cobblestone)
	box(structure, Vector3.new(30, F, 5), 0, CY - F / 2, 20.5, STONE, M.Cobblestone)
	for _, x in { -12.5, 12.5 } do
		box(structure, Vector3.new(5, F, 14), x, CY - F / 2, 11, STONE, M.Cobblestone)
	end
	-- nave floor over the crypt, with the stairwell (x 6..9, z 4..12)
	local floor = rgb(80, 60, 44)
	box(structure, Vector3.new(16, 1, 14), -2, CY - 0.5, 11, floor, M.WoodPlanks)
	box(structure, Vector3.new(1, 1, 14), 9.5, CY - 0.5, 11, floor, M.WoodPlanks)
	box(structure, Vector3.new(3, 1, 6), 7.5, CY - 0.5, 15, floor, M.WoodPlanks)
	box(structure, Vector3.new(22, 0.2, 24), 0, CY + 0.1, -9, floor, M.WoodPlanks)

	-- nave walls, tall arched windows
	wall(Vector2.new(-12.6, 20), Vector2.new(12.6, 20), CY, WH, {})
	wall(Vector2.new(-12, -20), Vector2.new(-12, 20), CY, WH, { gothic(-12), gothic(-4), gothic(4), gothic(12) })
	wall(Vector2.new(12, -20), Vector2.new(12, 20), CY, WH, { gothic(-12), gothic(-4), gothic(4), gothic(12) })
	wall(Vector2.new(-12.6, -20), Vector2.new(12.6, -20), CY, WH, { { at = 0, width = 5, bottom = 0, top = 10 } })
	-- stained glass, mostly red
	for _, x in { -12, 12 } do
		for i, z in { -12, -4, 4, 12 } do
			local glass = if i % 2 == 0 then rgb(150, 20, 18) else rgb(120, 60, 140)
			box(structure, Vector3.new(0.2, 8, 3), x, CY + 10, z, glass, M.Glass, { Transparency = 0.25 })
		end
	end
	-- gable roof (ridge along Z) and the gable ends
	local roof = rgb(46, 40, 40)
	Build.wedge(structure, Vector3.new(44, 10, 13.5), L(6.75, CY + WH + 5, 0) * ANG(0, -math.pi / 2, 0), roof, M.Slate)
	Build.wedge(structure, Vector3.new(44, 10, 13.5), L(-6.75, CY + WH + 5, 0) * ANG(0, math.pi / 2, 0), roof, M.Slate)
	for _, z in { -20, 20 } do
		Build.wedge(structure, Vector3.new(1.2, 10, 12), L(6, CY + WH + 5, z) * ANG(0, -math.pi / 2, 0), STONE, M.Slate)
		Build.wedge(structure, Vector3.new(1.2, 10, 12), L(-6, CY + WH + 5, z) * ANG(0, math.pi / 2, 0), STONE, M.Slate)
	end
	box(structure, Vector3.new(24, 1, 40), 0, CY + WH + 0.5, 0, rgb(60, 48, 40), M.WoodPlanks)

	-- bell tower at the front: the main door, a ladder to the belfry
	local TH = 30
	wall(Vector2.new(-5.6, -28), Vector2.new(5.6, -28), CY, TH, { { at = 0, width = 4.6, bottom = 0, top = 9 } })
	wall(Vector2.new(-5, -28), Vector2.new(-5, -20), CY, TH, {})
	wall(Vector2.new(5, -28), Vector2.new(5, -20), CY, TH, {})
	-- belfry floor, open over the ladder (x 2.2..4.2, z -27..-25)
	local BY = CY + TH + 0.5
	box(structure, Vector3.new(7.7, 1, 9), -1.65, BY, -24, STONE, M.Slate)
	box(structure, Vector3.new(1.3, 1, 9), 4.85, BY, -24, STONE, M.Slate)
	box(structure, Vector3.new(2, 1, 5.5), 3.2, BY, -22.25, STONE, M.Slate)
	box(structure, Vector3.new(2, 1, 1.5), 3.2, BY, -27.75, STONE, M.Slate)
	Build.ladder(structure, Vector3.new(2, TH + 2, 2), L(3.2, CY + (TH + 2) / 2, -26), DARK_WOOD, M.Wood)
	-- belfry: open arches, the bell, a little spire
	for _, s in { -1, 1 } do
		box(structure, Vector3.new(1.2, 7, 1.2), s * 4.4, CY + TH + 4.5, -27.4, STONE, M.Slate)
		box(structure, Vector3.new(1.2, 7, 1.2), s * 4.4, CY + TH + 4.5, -20.6, STONE, M.Slate)
	end
	box(structure, Vector3.new(11, 1, 9), 0, CY + TH + 8.5, -24, STONE, M.Slate)
	for i = 0, 3 do
		local w = 8 - i * 2
		box(structure, Vector3.new(w, 3, w * 0.8), 0, CY + TH + 10.5 + i * 3, -24, roof, M.Slate)
	end
	box(structure, Vector3.new(0.4, 4, 0.4), 0, CY + TH + 24, -24, rgb(30, 28, 26), M.Metal)
	box(structure, Vector3.new(2.2, 0.4, 0.4), 0, CY + TH + 25, -24, rgb(30, 28, 26), M.Metal)
	local bell = Build.cylinder(structure, 3, 3.4, L(0, CY + TH + 5, -24) * ANG(0, 0, rad(90)), rgb(120, 90, 50), M.Metal)
	bell.Name = "Bell"
	Build.ball(structure, 0.9, L(0, CY + TH + 3.3, -24), rgb(80, 60, 40), M.Metal)
	box(structure, Vector3.new(0.3, 3, 0.3), 0, CY + TH + 7.5, -24, DARK_WOOD, M.Wood, noCollide)

	-- the pews, an aisle down the middle
	for i = 0, 7 do
		local z = -16 + i * 3.2
		for _, x in { -6.5, 6.5 } do
			box(furniture, Vector3.new(8, 0.5, 1.6), x, CY + 2, z, DARK_WOOD, M.Wood)
			box(furniture, Vector3.new(8, 2.4, 0.3), x, CY + 3.2, z + 0.8, DARK_WOOD, M.Wood)
			for _, dx in { -3.7, 3.7 } do
				box(furniture, Vector3.new(0.3, 2, 1.6), x + dx, CY + 1, z, DARK_WOOD, M.Wood)
			end
		end
	end
	-- the altar, and before it the family's supper table, laid
	box(furniture, Vector3.new(16, 1, 4), 0, CY + 0.5, 18, rgb(90, 70, 56), M.WoodPlanks)
	box(furniture, Vector3.new(6, 3.6, 2), 0, CY + 2.8, 18.6, rgb(200, 196, 186), M.Marble)
	box(furniture, Vector3.new(0.6, 8, 0.6), 0, CY + 9, 19.5, rgb(40, 30, 24), M.Wood)
	box(furniture, Vector3.new(4, 0.6, 0.6), 0, CY + 11, 19.5, rgb(40, 30, 24), M.Wood)
	box(furniture, Vector3.new(18, 0.5, 4), 0, CY + 3.2, 12, rgb(70, 46, 30), M.Wood)
	for _, x in { -8.4, 8.4 } do
		for _, z in { 10.4, 13.6 } do
			box(furniture, Vector3.new(0.5, 3, 0.5), x, CY + 1.5, z, rgb(70, 46, 30), M.Wood)
		end
	end
	box(furniture, Vector3.new(17, 0.05, 3.2), 0, CY + 3.48, 12, rgb(220, 214, 200), M.Fabric, noCollide)
	for i = 0, 6 do
		local x = -7.5 + i * 2.5
		Build.post(furniture, 0.1, 1.4, L(x, CY + 3.52, 11.2), rgb(200, 196, 186), M.SmoothPlastic)
		box(furniture, Vector3.new(0.8, 0.4, 0.6), x, CY + 3.72, 11.2, rgb(110, 26, 22), M.SmoothPlastic, noCollide)
		Build.candle(furniture, L(x + 1.2, CY + 3.48, 12.8), 0.6 + rng:NextNumber() * 0.6)
		local seat = Props.Chair(false)
		seat:PivotTo(L(x, CY, 9) * ANG(0, 0, 0))
		seat.Parent = furniture
	end
	Build.stain(furniture, L(2, CY + 3.5, 12), Vector2.new(2, 1.2), rng)
	for i = 0, 3 do
		Build.candle(furniture, L(-2.2 + i * 1.5, CY + 4.6, 18.6), 0.8 + i * 0.2)
	end
	Build.bulb(lights, L(0, CY + 14, 12), rgb(255, 170, 100), 0.35, 26, true)
	Build.bulb(lights, L(0, CY + 14, -8), rgb(255, 150, 90), 0.2, 22, true)
	-- hiding: a confessional booth by the side wall
	local booth = box(furniture, Vector3.new(4, 8, 3), -10, CY + 4, -18, DARK_WOOD, M.Wood)
	booth.Name = "Confessional"
	booth.CanCollide = false
	Hiding.add(booth, L(-10, CY + 3, -18.1) * ANG(0, math.pi, 0), L(-10, CY + 3, -14) * ANG(0, math.pi, 0), "Confessional")

	-- the crypt under the altar (x -10..10, z 4..18), with stairs up
	workspace.Terrain:FillBlock(L(0, CY - 7, 11), Vector3.new(22, 14, 16), M.Air)
	local cryptY = CY - 12
	box(structure, Vector3.new(21, 1, 15), 0, cryptY - 0.5, 11, rgb(70, 66, 62), M.Cobblestone)
	wall(Vector2.new(-10.6, 4), Vector2.new(10.6, 4), cryptY, 11.5, {}, rgb(76, 70, 64), M.Cobblestone)
	wall(Vector2.new(-10.6, 18), Vector2.new(10.6, 18), cryptY, 11.5, { { at = -6, width = 5, bottom = 0, top = 8 } }, rgb(76, 70, 64), M.Cobblestone)
	wall(Vector2.new(-10, 4), Vector2.new(-10, 18), cryptY, 11.5, {}, rgb(76, 70, 64), M.Cobblestone)
	wall(Vector2.new(10, 4), Vector2.new(10, 18), cryptY, 11.5, {}, rgb(76, 70, 64), M.Cobblestone)
	-- the mine tunnel comes in through the back wall: boards torn off it
	box(structure, Vector3.new(5, 8, 0.4), -6, cryptY + 4, 18.6, rgb(6, 5, 5), M.SmoothPlastic)
	for i = 0, 2 do
		box(furniture, Vector3.new(5.6, 0.6, 0.25), -6 + rng:NextNumber(-1, 1), cryptY + 0.3, 16 - i * 0.8, rgb(92, 72, 52), M.WoodPlanks)
	end
	local steps = 12
	local run = 8 / steps
	for i = 1, steps do
		box(structure, Vector3.new(3, i * (12 / steps), run), 7.5, cryptY + i * (12 / steps) / 2, 12 - (i - 0.5) * run, rgb(80, 74, 68), M.Slate)
	end
	-- coffins, bones, candles
	local cryptKeySpots: { CFrame } = {}
	for i = 0, 3 do
		local x = -7 + (i % 2) * 7
		local z = 7 + (i // 2) * 5
		box(furniture, Vector3.new(2.6, 1.6, 6), x, cryptY + 0.8, z, rgb(54, 40, 30), M.Wood)
		box(furniture, Vector3.new(2.8, 0.3, 6.2), x, cryptY + 1.75, z, rgb(64, 48, 36), M.Wood)
		table.insert(cryptKeySpots, L(x, cryptY + 1.92, z + rng:NextNumber(-1.5, 1.5)) * ANG(0, rng:NextNumber(0, 6), 0))
	end
	for i = 0, 5 do
		Build.candle(furniture, L(-9 + (i % 3) * 0.5, cryptY, 5 + i * 2), 0.5 + rng:NextNumber() * 0.4)
	end
	Build.bulb(lights, L(0, cryptY + 10, 11), rgb(255, 150, 80), 0.25, 16, true)
	local cryptDoor = Doors.create(model, L(7.5 - 1.5, cryptY, 12.7), 3, 7.5, {
		name = "CryptDoor",
		locked = true,
		keyItem = "CryptKey",
		lockedText = "An iron gate across the crypt stairs, padlocked. One of the coffins might have the key.",
		color = rgb(40, 40, 42),
	})
	Doors.create(model, L(-2.3, CY, -28), 4.6, 9, { name = "ChurchDoor", color = rgb(70, 40, 30) })

	-- graveyard round the sides and back
	for i = 0, 17 do
		local side = if i % 3 == 0 then -1 elseif i % 3 == 1 then 1 else 0
		local x = if side == 0 then rng:NextNumber(-14, 14) else side * rng:NextNumber(17, 26)
		local z = if side == 0 then rng:NextNumber(24, 34) else rng:NextNumber(-20, 22)
		local tilt = ANG(rng:NextNumber(-0.15, 0.15), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.15, 0.15))
		Build.part(furniture, Vector3.new(2.2, 3 + rng:NextNumber(0, 1.5), 0.6), L(x, 1.5, z) * tilt, rgb(120, 118, 112), M.Slate)
	end

	-- Main Street: what's left of Pinecrest (past the pad, on the real ground)
	local function ground(x: number, z: number): CFrame
		local p = L(x, 0, z).Position
		return CF(p.X, Terrain.groundY(p.X, p.Z), p.Z)
	end
	local signs = { "GENERAL STORE", "DINER", "SHERIFF", "PINECREST BANK" }
	for i = 0, 3 do
		local side = if i % 2 == 0 then -1 else 1
		local z = -48 - (i // 2) * 26
		local front = ground(side * 22, z)
		Build.part(structure, Vector3.new(16, 14, 18), front * CF(side * 4, 5, 0), rgb(96 + i * 6, 84, 74), M.WoodPlanks)
		Build.part(structure, Vector3.new(0.4, 2.4, 12), front * CF(side * -4.2, 13, 0), rgb(60, 50, 40), M.Wood)
		for _, dz in { -4, 4 } do
			Build.part(structure, Vector3.new(0.3, 4, 3), front * CF(side * -4.1, 4, dz), rgb(30, 30, 34), M.Glass, { Transparency = 0.2 })
			for k = -1, 1 do
				Build.part(structure, Vector3.new(0.3, 0.5, 3.6), front * CF(side * -4.3, 4 + k, dz) * ANG(rad(rng:NextNumber(-10, 10)), 0, 0), rgb(92, 72, 52), M.WoodPlanks, noCollide)
			end
		end
		local sign = Build.part(structure, Vector3.new(0.3, 2, 10), front * CF(side * -4.4, 13, 0), rgb(60, 50, 40), M.Wood)
		local sg = Instance.new("SurfaceGui")
		sg.Face = if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left
		sg.PixelsPerStud = 30
		sg.Parent = sign
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = signs[i + 1]
		label.TextScaled = true
		label.Font = Enum.Font.SpecialElite
		label.TextColor3 = rgb(210, 200, 170)
		label.Parent = sg
	end
	for i = 0, 3 do
		Build.post(structure, 12, 0.5, ground(9 * (if i % 2 == 0 then -1 else 1), -44 - i * 24) * CF(0, 6, 0), rgb(50, 50, 52), M.Metal)
	end

	local function at(x: number, z: number): Vector3
		if z < -60 then
			return ground(x, z).Position
		end
		return L(x, CY, z).Position
	end
	return {
		origin = C,
		cryptSpawns = { L(-6, cryptY + 3, 14) * ANG(0, math.pi, 0), L(-4, cryptY + 3, 13) * ANG(0, math.pi, 0), L(-8, cryptY + 3, 13), L(-5, cryptY + 3, 11) },
		cryptDoor = cryptDoor,
		cryptKeySpots = cryptKeySpots,
		bell = bell,
		patrol = { at(0, -10), at(0, 6), at(-8, 2), at(8, -12), at(0, -34), at(-20, 0), at(20, 10), at(0, 28), at(0, -60), at(0, -90) },
		checkpoint = L(0, CY + 3, -10),
		cruiser = ground(4, -104) * ANG(0, rad(170), 0),
		polaroid = L(1.4, CY + 4.62, 18.4) * ANG(0, rad(15), 0),
		street = at(0, -100),
	}
end

function FinaleSites.build(world: Instance): Info
	local rng = Util.rng(Config.Map.Seed + 77)
	-- trails first, so the pads cut their own ground over them cleanly
	for _, road in Config.Roads do
		if road.name == "DragTrail" or road.name == "PlantRoad" or road.name == "MainStreet" then
			paint(road.points, road.width, road.material)
		end
	end
	return {
		crash = buildCrash(world, rng),
		plant = buildPlant(world, rng),
		church = buildChurch(world, rng),
	}
end

return FinaleSites

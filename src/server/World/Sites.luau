--!strict
-- Every outdoor location: the crash, the broken-down truck, the barn, the
-- hunter's camp, the doctor's trailer, the cemetery, the ranger station with
-- its generator, the fire lookout, the tool shed and the helipad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)
local Terrain = require(script.Parent.Terrain)
local AssetService = require(script.Parent.Parent.Systems.AssetService)
local Doors = require(script.Parent.Parent.Systems.Doors)
local Hiding = require(script.Parent.Parent.Systems.Hiding)

local Sites = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local S = Config.Sites

export type Info = {
	sedan: Model,
	crashTree: CFrame,
	truck: Model,
	truckCF: CFrame,
	truckSlots: { [string]: BasePart },
	truckDoor: BasePart,
	spots: { [string]: CFrame },
	patrols: { [string]: { Vector3 } },
	checkpoints: { [string]: CFrame },
	surviveSpawns: { CFrame },
	station: {
		door: Doors.Door,
		radio: BasePart,
		fuseBox: BasePart,
		generator: Model,
		generatorPart: BasePart,
		lights: { Light },
		lamps: { BasePart },
		center: Vector3,
	},
	helipad: CFrame,
	helipadLights: { BasePart },
	wreck: CFrame,
}

local function ground(x: number, z: number, yaw: number?): CFrame
	return Terrain.groundCFrame(x, z, yaw)
end

local function siteCF(name: string, dx: number?, dz: number?, yaw: number?): CFrame
	local p = S[name].pos
	return ground(p.X + (dx or 0), p.Y + (dz or 0), yaw)
end

local function spawnProp(parent: Instance, builder: (Util.Rng) -> Model, cf: CFrame, rng: Util.Rng): Model
	local m = builder(rng)
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

local function lanternOn(parent: Instance, cf: CFrame)
	local l = Props.Lantern()
	l:PivotTo(cf)
	l.Parent = parent
	return l
end

local function sign(parent: Instance, text: string, x: number, z: number, faceToward: Vector2)
	local s = Props.Sign(text)
	local pos = ground(x, z).Position
	s:PivotTo(CFrame.lookAt(pos, Vector3.new(faceToward.X, pos.Y, faceToward.Y)))
	s.Parent = parent
end

local function invisible(parent: Instance, size: Vector3, cf: CFrame, name: string): Part
	local p = Build.part(parent, size, cf, rgb(255, 255, 255), M.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = true,
	})
	p.Name = name
	return p
end

---------------------------------------------------------------- simple walkable shell
-- mesh: the Blender exterior (build_buildings.py) that replaces the roof
type ShedOptions = { doorWidth: number?, holes: boolean?, windows: boolean?, roofColor: Color3?, mesh: string? }

-- Rectangular building with plank walls, a door gap on the front (-Z) wall and
-- a gable roof. Returns the local-to-world origin.
local function shed(
	parent: Instance,
	origin: CFrame,
	w: number,
	d: number,
	h: number,
	color: Color3,
	opts: ShedOptions?
)
	local o: ShedOptions = opts or {}
	local dw = o.doorWidth or 6
	Build.part(parent, Vector3.new(w, 1, d), origin * CF(0, -0.4, 0), rgb(70, 54, 40), M.WoodPlanks)
	local win: { Build.Opening } = if o.windows then { { at = -w / 4, width = 4, bottom = 4, top = 7.5 }, { at = w / 4, width = 4, bottom = 4, top = 7.5 } } else {}
	Build.wall(parent, origin, Vector2.new(-w / 2, -d / 2), Vector2.new(w / 2, -d / 2), 0, h, 0.8, { { at = 0, width = dw, bottom = 0, top = math.min(h - 1, 10) } }, color, M.WoodPlanks)
	Build.wall(parent, origin, Vector2.new(-w / 2, d / 2), Vector2.new(w / 2, d / 2), 0, h, 0.8, win, color, M.WoodPlanks)
	Build.wall(parent, origin, Vector2.new(-w / 2, -d / 2), Vector2.new(-w / 2, d / 2), 0, h, 0.8, win, color, M.WoodPlanks)
	Build.wall(parent, origin, Vector2.new(w / 2, -d / 2), Vector2.new(w / 2, d / 2), 0, h, 0.8, win, color, M.WoodPlanks)
	local roof = o.roofColor or rgb(48, 44, 40)
	local rh = w * 0.3
	local roofSize = Vector3.new(w + 2, rh, d / 2 + 1)
	local shell = if o.mesh then Build.standIn(parent, o.mesh) else nil
	local roofParent: Instance = shell or parent
	if o.holes then
		-- broken roof: only a few panels survive
		Build.wedge(roofParent, Vector3.new(w * 0.45, rh, d / 2 + 1), origin * CF(-w * 0.25, h + rh / 2, -d / 4 - 0.25), roof, M.CorrodedMetal)
		Build.wedge(roofParent, Vector3.new(w * 0.6, rh, d / 2 + 1), origin * CF(w * 0.18, h + rh / 2, d / 4 + 0.25) * ANG(0, math.pi, 0), roof, M.CorrodedMetal)
	else
		Build.wedge(roofParent, roofSize, origin * CF(0, h + rh / 2, -d / 4 - 0.25), roof, M.RoofShingles)
		Build.wedge(roofParent, roofSize, origin * CF(0, h + rh / 2, d / 4 + 0.25) * ANG(0, math.pi, 0), roof, M.RoofShingles)
	end
	if shell then
		Build.markStandIn(shell, origin)
	end
	-- foundation skirt so slopes never leave a gap underneath
	Build.part(parent, Vector3.new(w, 6, d), origin * CF(0, -3.9, 0), rgb(60, 56, 52), M.Cobblestone)
end

---------------------------------------------------------------- crash site & highway
local function buildHighway(parent: Instance, info: Info, rng: Util.Rng)
	local road = Config.Roads[1]
	local folder = Build.folder(parent, "Highway")
	local length = Util.polylineLength(road.points)
	-- dashed centre line and leaning power poles along the road
	local d = 0
	while d < length do
		local p, dir = Util.polylineSample(road.points, d)
		local yaw = math.atan2(-dir.X, -dir.Y)
		local cf = ground(p.X, p.Y, yaw)
		if math.abs(p.X) < 600 then
			Build.part(folder, Vector3.new(0.4, 0.05, 6), cf * CF(0, 0.08, 0), rgb(190, 170, 90), M.SmoothPlastic, {
				CanCollide = false,
				CastShadow = false,
				Transparency = 0.35,
			})
			if math.floor(d / 12) % 7 == 0 then
				local side = ground(p.X + dir.Y * 17, p.Y - dir.X * 17, yaw)
				local pole = Props.PowerPole()
				pole:PivotTo(side * ANG(rad(rng:NextNumber(-5, 5)), 0, rad(rng:NextNumber(-6, 6))))
				pole.Parent = folder
			end
		end
		d += 12
	end

	-- the crash: sedan wrapped around a big pine on the south shoulder
	local crash = S.Crash.pos
	local treeCF = ground(crash.X, crash.Y + 6)
	Build.post(folder, 40, 4.4, treeCF * CF(0, 18, 0), rgb(54, 40, 30), M.Wood).Name = "CrashTree"
	local pine = AssetService.create("PineTree", rng)
	pine:PivotTo(treeCF)
	pine.Parent = folder
	-- scraped bark where the car hit
	Build.part(folder, Vector3.new(4.6, 3, 1), treeCF * CF(0, 2.5, -2) , rgb(150, 120, 90), M.Wood, { CanCollide = false })
	info.crashTree = treeCF

	-- the car left the road heading south and wrapped its bonnet (-Z) around the tree
	local sedanCF = treeCF * CF(0.6, 0, -9.5) * ANG(0, math.pi + rad(8), 0)
	local sedan = AssetService.spawn("CrashedSedan", sedanCF, folder, rng)
	sedan.Name = "CrashedSedan"
	info.sedan = sedan
	local engineSmoke = invisible(folder, Vector3.new(2, 1, 2), sedanCF * CF(0, 3.2, -5), "Smoke")
	local smoke = Instance.new("Smoke")
	smoke.Color = rgb(70, 70, 70)
	smoke.Opacity = 0.25
	smoke.RiseVelocity = 4
	smoke.Size = 2
	smoke.Parent = engineSmoke
	-- blinking hazard lights at the rear
	for _, x in { -2.8, 2.8 } do
		local hazard = Build.part(folder, Vector3.new(0.6, 0.4, 0.3), sedanCF * CF(x, 3, 7.4), rgb(255, 150, 30), M.Neon, { CanCollide = false })
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 150, 40)
		light.Range = 12
		light.Brightness = 1.4
		light.Parent = hazard
		Build.tag(hazard, "Hazard")
	end
	-- skid marks behind the car (towards the road) and glass in front of it
	for i = 0, 5 do
		local t = sedanCF * CF(-1.6 + (i % 2) * 3.2, 0.05, 10 + (i // 2) * 9) * ANG(0, rad(-12 + i * 3), 0)
		Build.part(folder, Vector3.new(0.9, 0.05, 9), t, rgb(18, 18, 18), M.SmoothPlastic, { CanCollide = false, Transparency = 0.3 })
	end
	for _ = 1, 24 do
		Build.part(folder, Vector3.new(0.25, 0.05, 0.2), sedanCF * CF(rng:NextNumber(-5, 5), 0.06, rng:NextNumber(-9, -6)) * ANG(0, rng:NextNumber(0, 3), 0), rgb(190, 210, 210), M.Glass, {
			CanCollide = false,
			Transparency = 0.2,
		})
	end

	-- road blocks at both ends of the map
	for _, x in { -585, 585 } do
		local p = Vector2.new(x, 0)
		local _, cp = Util.polylineClosest(road.points, p)
		local cf = ground(cp.X, cp.Y, rad(90))
		for i = 0, 3 do
			Build.cylinder(folder, 36, 3, cf * CF(0, 1.5 + i * 2.4, (i % 2) * 2 - 1) * ANG(0, rad(rng:NextNumber(-8, 8)), 0), rgb(58, 44, 32), M.Wood)
		end
		local barrier = Build.part(folder, Vector3.new(0.5, 1.4, 20), cf * CF(4, 3.5, 0), rgb(200, 160, 40), M.SmoothPlastic)
		barrier.Name = "RoadClosed"
		local gui = Instance.new("SurfaceGui")
		gui.Face = if x < 0 then Enum.NormalId.Right else Enum.NormalId.Left
		gui.CanvasSize = Vector2.new(800, 60)
		gui.Parent = barrier
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "ROAD CLOSED - BRIDGE OUT"
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = rgb(20, 20, 20)
		label.Parent = gui
	end

	-- the family's mailbox at the end of their driveway
	local mailCF = ground(-172, -500, rad(180))
	Build.post(folder, 4, 0.4, mailCF * CF(0, 2, 0), rgb(70, 54, 40), M.Wood)
	Build.part(folder, Vector3.new(1.4, 1.2, 2.2), mailCF * CF(0, 4.4, 0), rgb(90, 90, 92), M.CorrodedMetal)
	sign(folder, "THE HOLLOW FAMILY", -160, -505, Vector2.new(-160, -530))
	-- where the logging road leaves the farm: point the way to the truck
	sign(folder, "LOGGING ROAD  >  CLEARING", -60, -250, Vector2.new(-90, -275))
end

---------------------------------------------------------------- truck clearing
local function buildTruck(parent: Instance, info: Info, rng: Util.Rng)
	local folder = Build.folder(parent, "TruckClearing")
	local site = S.Truck.pos
	local target = Config.DrivePath[2]
	local start = Config.DrivePath[1]
	local yaw = math.atan2(-(target.X - start.X), -(target.Y - start.Y))
	local truckCF = ground(start.X, start.Y, yaw)
	local truck = AssetService.spawn("PickupTruck", truckCF, folder, rng)
	truck.Name = "EscapeTruck"
	info.truck = truck
	info.truckCF = truckCF

	local slots: { [string]: BasePart } = {}
	slots.Engine = invisible(folder, Vector3.new(5, 3, 3), truckCF * CF(0, 4, -7.5), "EngineSlot")
	slots.CarBattery = invisible(folder, Vector3.new(2, 2, 2), truckCF * CF(-2.5, 4, -6), "BatterySlot")
	slots.SparkPlugs = invisible(folder, Vector3.new(2, 2, 2), truckCF * CF(2.5, 4, -6), "PlugSlot")
	slots.Tire = invisible(folder, Vector3.new(2, 3, 3), truckCF * CF(-4.2, 1.6, 5.8), "TireSlot")
	info.truckSlots = slots
	info.truckDoor = invisible(folder, Vector3.new(1, 4, 3.6), truckCF * CF(-3.8, 4.4, -0.6), "DriverDoor")

	-- jack under the missing wheel, toolbox, oil cans, a work lamp
	Build.part(folder, Vector3.new(1.2, 1.4, 2), truckCF * CF(-3.6, 0.7, 5.8), rgb(160, 30, 24), M.Metal)
	Build.part(folder, Vector3.new(3, 1.2, 1.4), truckCF * CF(-6, 0.6, -3) * ANG(0, 0.3, 0), rgb(150, 30, 26), M.Metal).Name = "Toolbox"
	for i = 0, 2 do
		Build.post(folder, 1.6, 1.1, truckCF * CF(6 + i * 1.3, 0.8, 3 - i * 0.6), rgb(60, 70, 80), M.CorrodedMetal)
	end
	local lampCF = truckCF * CF(-7, 0, -6)
	Build.post(folder, 5, 0.25, lampCF * CF(0, 2.5, 0), rgb(40, 40, 40), M.Metal)
	local lamp = Build.part(folder, Vector3.new(1, 0.8, 0.8), lampCF * CF(0, 5.2, 0.3) * ANG(rad(-35), 0, 0), rgb(255, 230, 180), M.Neon)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Back
	spot.Angle = 70
	spot.Range = 34
	spot.Brightness = 2.2
	spot.Color = rgb(255, 214, 160)
	spot.Shadows = true
	spot.Parent = lamp
	Build.tag(lamp, "FlickerLight")
	sign(folder, "HOLLOW RIDGE LOGGING CO.", site.X - 24, site.Y - 30, site)
	for i = 0, 5 do
		Build.cylinder(folder, 14, 2.2, ground(site.X + 22, site.Y + 18 + i * 0.1) * CF(0, 1.1 + (i // 3) * 2, (i % 3) * 2.3) * ANG(0, rad(90), 0), rgb(84, 62, 44), M.Wood)
	end

	info.patrols.Butcher = {
		ground(site.X - 20, site.Y + 40).Position,
		ground(122, 52).Position,
		ground(S.Camp.pos.X + 18, S.Camp.pos.Y - 10).Position,
		ground(20, 60).Position,
		ground(40, -120).Position,
		ground(site.X - 40, site.Y - 30).Position,
	}
	info.checkpoints.Repair = CFrame.lookAt(ground(site.X - 14, site.Y - 18).Position + Vector3.new(0, 3, 0), truckCF.Position + Vector3.new(0, 3, 0))
end

---------------------------------------------------------------- barn
local function buildBarn(parent: Instance, info: Info, rng: Util.Rng)
	local folder = Build.folder(parent, "Barn")
	local origin = siteCF("Barn", 0, 0, rad(20))
	origin = origin + Vector3.new(0, 0.5, 0)
	shed(folder, origin, 30, 40, 16, rgb(96, 40, 32), { doorWidth = 12, holes = true, mesh = "BarnExterior" })
	-- hay, stalls, chains, the engine on a hoist
	for i = 0, 5 do
		Build.part(folder, Vector3.new(4, 2.4, 2.6), origin * CF(-11 + (i % 3) * 4.2, 1.2 + (i // 3) * 2.4, 16), rgb(170, 140, 70), M.Grass)
	end
	for i = 0, 2 do
		Build.part(folder, Vector3.new(0.6, 5, 10), origin * CF(6, 2.5, -6 + i * 10), rgb(80, 60, 44), M.WoodPlanks)
	end
	Build.part(folder, Vector3.new(8, 0.6, 4), origin * CF(-6, 3, -4), rgb(84, 62, 44), M.Wood).Name = "Workbench"
	for _, x in { -9.6, -2.4 } do
		Build.part(folder, Vector3.new(0.6, 3, 3.4), origin * CF(x, 1.5, -4), rgb(84, 62, 44), M.Wood)
	end
	-- A-frame hoist with chain over the engine
	for _, z in { -7, -1 } do
		Build.part(folder, Vector3.new(0.6, 11, 0.6), origin * CF(-9, 5, z) * ANG(0, 0, rad(12)), rgb(70, 70, 72), M.Metal)
		Build.part(folder, Vector3.new(0.6, 11, 0.6), origin * CF(-3, 5, z) * ANG(0, 0, rad(-12)), rgb(70, 70, 72), M.Metal)
	end
	Build.part(folder, Vector3.new(0.6, 0.6, 7), origin * CF(-6, 10.4, -4), rgb(70, 70, 72), M.Metal)
	for i = 0, 8 do
		Build.part(folder, Vector3.new(0.12, 0.5, 0.25), origin * CF(-6, 9.8 - i * 0.55, -4) * ANG(0, if i % 2 == 0 then 0 else rad(90), 0), rgb(90, 86, 80), M.Metal, { CanCollide = false })
	end
	info.spots.Engine = origin * CF(-6, 3.3, -4)
	info.spots.NoteBarn = origin * CF(-8.5, 3.32, -2.6) * ANG(0, rad(20), 0)
	info.spots.BarnBattery = origin * CF(-3, 3.32, -5)
	lanternOn(folder, origin * CF(-2.6, 3.3, -3.2))
	for _ = 1, 4 do
		spawnProp(folder, Props.Crate, origin * CF(rng:NextNumber(4, 12), 0, rng:NextNumber(-16, 14)) * ANG(0, rng:NextNumber(0, 3), 0), rng)
	end
	spawnProp(folder, Props.Barrel, origin * CF(12, 0, -15), rng)
	for i = 0, 3 do
		Build.post(folder, 6, 0.4, origin * CF(-14 + i * 0.5, 3, 18) * ANG(rad(-20), 0, rad(i * 5)), rgb(110, 90, 60), M.Wood)
	end
end

---------------------------------------------------------------- hunter's camp
local function buildCamp(parent: Instance, info: Info, rng: Util.Rng)
	local folder = Build.folder(parent, "HunterCamp")
	local origin = siteCF("Camp")
	spawnProp(folder, function()
		return Props.Campfire()
	end, origin, rng)
	spawnProp(folder, function()
		return Props.Tent()
	end, origin * CF(-11, 0, 5) * ANG(0, rad(70), 0), rng)
	spawnProp(folder, function()
		return Props.Tent()
	end, origin * CF(9, 0, 9) * ANG(0, rad(-40), 0), rng)
	for i = 0, 2 do
		local a = i * 2.1 + 0.4
		Build.cylinder(folder, 5, 1.2, origin * CF(math.cos(a) * 5.5, 0.6, math.sin(a) * 5.5) * ANG(0, -a + math.pi / 2, 0), rgb(76, 58, 42), M.Wood)
	end
	-- tarp lean-to hiding the car battery
	local tarp = origin * CF(2, 0, -11)
	for _, x in { -4, 4 } do
		Build.post(folder, 5, 0.3, tarp * CF(x, 2.5, -2), rgb(70, 54, 40), M.Wood)
	end
	Build.part(folder, Vector3.new(9, 0.15, 6), tarp * CF(0, 3.6, 0) * ANG(rad(-25), 0, 0), rgb(40, 70, 90), M.Fabric)
	info.spots.CarBattery = tarp * CF(0, 0, 0)
	info.spots.NoteCamp = origin * CF(4.5, 1.25, 3.6) * ANG(0, rad(30), 0)
	info.spots.CampBandage = origin * CF(-4, 1.25, -4)
	-- a deer strung up on a tripod
	for i = 0, 2 do
		local a = i * 2.09
		Build.part(folder, Vector3.new(0.35, 11, 0.35), origin * CF(14 + math.cos(a) * 2.2, 5, -6 + math.sin(a) * 2.2) * ANG(math.sin(a) * 0.2, 0, -math.cos(a) * 0.2), rgb(70, 54, 40), M.Wood)
	end
	local carcass = Props.BodyBag(rng)
	carcass:PivotTo(origin * CF(14, 3.2, -6) * ANG(0, 0, rad(90)))
	carcass.Parent = folder
	lanternOn(folder, origin * CF(-3, 0, 6))
	for _ = 1, 3 do
		spawnProp(folder, Props.Crate, origin * CF(rng:NextNumber(-14, -8), 0, rng:NextNumber(-12, -6)) * ANG(0, rng:NextNumber(0, 3), 0), rng)
	end
end

---------------------------------------------------------------- doctor's trailer
local function buildTrailer(parent: Instance, info: Info, rng: Util.Rng)
	local folder = Build.folder(parent, "Trailer")
	local origin = siteCF("Trailer", 0, 0, rad(-25)) + Vector3.new(0, 2.4, 0)
	local w, d, h = 10, 26, 8
	local paint = rgb(196, 190, 170)
	Build.part(folder, Vector3.new(w, 0.6, d), origin * CF(0, -0.3, 0), rgb(80, 74, 66), M.WoodPlanks)
	-- the flat roof stands in for the Blender camper shell (build_buildings.py)
	local shell = Build.standIn(folder, "TrailerExterior")
	Build.part(shell, Vector3.new(w + 0.4, 0.5, d + 0.4), origin * CF(0, h + 0.25, 0), paint, M.Metal)
	Build.markStandIn(shell, origin)
	Build.wall(folder, origin, Vector2.new(-w / 2, -d / 2), Vector2.new(w / 2, -d / 2), 0, h, 0.4, { { at = 0, width = 4, bottom = 3, top = 6 } }, paint, M.Metal)
	Build.wall(folder, origin, Vector2.new(-w / 2, d / 2), Vector2.new(w / 2, d / 2), 0, h, 0.4, {}, paint, M.Metal)
	Build.wall(folder, origin, Vector2.new(-w / 2, -d / 2), Vector2.new(-w / 2, d / 2), 0, h, 0.4, { { at = -6, width = 4, bottom = 3.5, top = 6.5 }, { at = 6, width = 4, bottom = 3.5, top = 6.5 } }, paint, M.Metal)
	Build.wall(folder, origin, Vector2.new(w / 2, -d / 2), Vector2.new(w / 2, d / 2), 0, h, 0.4, { { at = 2, width = 3.6, bottom = 0, top = 7 }, { at = -8, width = 4, bottom = 3.5, top = 6.5 } }, paint, M.Metal)
	Build.part(folder, Vector3.new(w + 0.5, 1, d + 0.5), origin * CF(0, 1.2, 0), rgb(120, 60, 40), M.Metal, { CanCollide = false })
	-- steps, wheels, hitch
	for i = 1, 3 do
		Build.part(folder, Vector3.new(2, 0.4, 3.4), origin * CF(w / 2 + 0.6 + i * 0.9, -i * 0.8, 2), rgb(90, 90, 90), M.DiamondPlate)
	end
	for _, z in { -4, 4 } do
		Build.cylinder(folder, 1.2, 3.2, origin * CF(-w / 2 - 0.2, -1, z), rgb(24, 24, 24), M.Rubber)
		Build.cylinder(folder, 1.2, 3.2, origin * CF(w / 2 + 0.2, -1, z), rgb(24, 24, 24), M.Rubber)
	end
	Build.part(folder, Vector3.new(0.6, 0.6, 5), origin * CF(0, -1.4, -d / 2 - 2.5), rgb(60, 60, 60), M.Metal)
	Build.part(folder, Vector3.new(w + 0.6, 4, d - 2), origin * CF(0, -2.4, 0), rgb(44, 40, 36), M.Metal)
	-- interior: table, benches, bed, counter, medicine cabinet
	Build.part(folder, Vector3.new(4, 0.3, 3), origin * CF(-2.5, 2.8, -8), rgb(170, 160, 140), M.SmoothPlastic).Name = "Table"
	Build.part(folder, Vector3.new(0.4, 2.8, 0.4), origin * CF(-2.5, 1.4, -8), rgb(120, 120, 120), M.Metal)
	for _, z in { -11, -5 } do
		Build.part(folder, Vector3.new(4, 1.8, 1.6), origin * CF(-2.8, 0.9, z), rgb(110, 70, 50), M.Fabric)
	end
	Build.part(folder, Vector3.new(8, 1.6, 6), origin * CF(0, 0.8, 9.5), rgb(120, 110, 100), M.Fabric)
	Build.stain(folder, origin * CF(1, 1.65, 9), Vector2.new(1.5, 1.2), rng)
	for i = 0, 2 do
		Build.part(folder, Vector3.new(2.6, 3, 3), origin * CF(-3.4, 1.5, 1 + i * 3), rgb(150, 140, 120), M.Wood)
	end
	Build.part(folder, Vector3.new(2.6, 0.2, 9), origin * CF(-3.4, 3.1, 4), rgb(180, 176, 168), M.Marble)
	Build.part(folder, Vector3.new(1.2, 3, 3), origin * CF(-4.3, 5.5, 4), rgb(220, 220, 220), M.Metal).Name = "MedCabinet"
	Build.bulb(folder, origin * CF(0, h - 1.5, -2), rgb(220, 235, 255), 0.6, 18, true)
	info.spots.SparkPlugs = origin * CF(-3.4, 3.22, 2.2)
	info.spots.Syringe1 = origin * CF(-2.8, 2.96, -8.3) * ANG(0, rad(30), 0)
	info.spots.Syringe2 = origin * CF(-2.0, 2.96, -7.4) * ANG(0, rad(-60), 0)
	info.spots.NoteDoctor = origin * CF(-3.4, 3.22, 5.8) * ANG(0, rad(80), 0)
	info.spots.TrailerBattery = origin * CF(-3.6, 3.22, 7)
	-- hiding spot: the trailer's closet
	local closet = Build.part(folder, Vector3.new(3, 7, 3), origin * CF(3.2, 3.5, 11), rgb(150, 140, 120), M.Wood, { CanCollide = false })
	Hiding.add(closet, origin * CF(3.2, 3, 11) * ANG(0, math.pi, 0), origin * CF(3.2, 3, 7.5) * ANG(0, math.pi, 0), "Closet")

	info.patrols.Hunter = {
		siteCF("Barn", 22, 22).Position,
		ground(-300, 45).Position,
		siteCF("Trailer", 22, -18).Position,
		ground(-120, 125).Position,
		ground(-190, -20).Position,
		ground(-255, -190).Position,
	}
end

---------------------------------------------------------------- cemetery
local function buildCemetery(parent: Instance, info: Info, rng: Util.Rng)
	local folder = Build.folder(parent, "Cemetery")
	local origin = siteCF("Cemetery", 0, 0, rad(10))
	for row = 0, 3 do
		for col = 0, 4 do
			if rng:NextNumber() > 0.12 then
				local cf = origin * CF(-16 + col * 8 + rng:NextNumber(-1, 1), 0, -14 + row * 9) * ANG(0, rad(rng:NextNumber(-6, 6)), 0)
				spawnProp(folder, Props.Gravestone, cf, rng)
			end
		end
	end
	-- fence around the plot with a gap for the gate
	for i = -3, 3 do
		for _, z in { -22, 22 } do
			if not (z == -22 and i == 0) then
				local f = Props.FenceSegment()
				f:PivotTo(origin * CF(i * 8.2, 0, z) * ANG(0, 0, rad(rng:NextNumber(-4, 4))))
				f.Parent = folder
			end
		end
	end
	for i = -2, 2 do
		for _, x in { -29, 29 } do
			local f = Props.FenceSegment()
			f:PivotTo(origin * CF(x, 0, i * 8.4) * ANG(0, rad(90), rad(rng:NextNumber(-4, 4))))
			f.Parent = folder
		end
	end
	-- stone crypt with the spare wheel leaning on it
	local crypt = origin * CF(18, 0, 14)
	Build.part(folder, Vector3.new(10, 8, 8), crypt * CF(0, 4, 0), rgb(90, 90, 88), M.Slate)
	Build.wedge(folder, Vector3.new(10.6, 2.4, 4.3), crypt * CF(0, 9.2, -2.1), rgb(70, 70, 68), M.Slate)
	Build.wedge(folder, Vector3.new(10.6, 2.4, 4.3), crypt * CF(0, 9.2, 2.1) * ANG(0, math.pi, 0), rgb(70, 70, 68), M.Slate)
	Build.part(folder, Vector3.new(3, 5.5, 0.4), crypt * CF(0, 2.75, -4.1), rgb(30, 30, 30), M.Metal)
	info.spots.Tire = crypt * CF(-5.6, 0, -2) * ANG(0, rad(90), rad(8))
	-- an open grave and a shovel
	Build.part(folder, Vector3.new(3, 0.2, 6), origin * CF(-12, 0.05, 12), rgb(20, 16, 12), M.Mud, { CanCollide = false })
	Build.part(folder, Vector3.new(3.6, 1.2, 2), origin * CF(-12, 0.6, 16.5), rgb(52, 40, 30), M.Mud)
	Build.part(folder, Vector3.new(0.2, 5, 0.2), origin * CF(-9.5, 1.8, 15) * ANG(rad(25), 0, 0), rgb(80, 60, 40), M.Wood)
	Build.part(folder, Vector3.new(1, 1.3, 0.1), origin * CF(-9.5, 0.2, 13.9) * ANG(rad(25), 0, 0), rgb(110, 110, 110), M.Metal)
	spawnProp(folder, Props.DeadTree, origin * CF(-22, 0, -8), rng)
	local post = origin * CF(0, 0, -23.5)
	Build.post(folder, 7, 0.4, post * CF(3, 3.5, 0), rgb(70, 54, 40), M.Wood)
	lanternOn(folder, post * CF(3, 7, 0))
	sign(folder, "HOLLOW CREEK CEMETERY", S.Cemetery.pos.X - 6, S.Cemetery.pos.Y - 30, S.Cemetery.pos)

	info.patrols.Scavenger = {
		(origin * CF(0, 0, -30)).Position,
		ground(250, -165).Position,
		ground(240, -40).Position,
		ground(300, 40).Position,
		ground(205, -205).Position,
	}
end

---------------------------------------------------------------- ranger station, tower, shed, helipad
local function buildStation(parent: Instance, info: Info, rng: Util.Rng)
	local folder = Build.folder(parent, "RangerStation")
	local site = S.Station.pos
	local origin = siteCF("Station", 0, 0, rad(200)) + Vector3.new(0, 1, 0)
	local w, d, h = 40, 28, 11
	local logColor = rgb(92, 66, 44)
	Build.part(folder, Vector3.new(w + 1, 8, d + 1), origin * CF(0, -4.4, 0), rgb(70, 66, 62), M.Cobblestone)
	Build.part(folder, Vector3.new(w, 0.5, d), origin * CF(0, -0.25, 0), rgb(110, 86, 60), M.WoodPlanks)
	Build.part(folder, Vector3.new(w + 2, 0.6, d + 2), origin * CF(0, h + 0.3, 0), rgb(70, 60, 50), M.WoodPlanks)
	local function win(at: number): Build.Opening
		return { at = at, width = 4, bottom = 3.5, top = 7.5 }
	end
	Build.wall(folder, origin, Vector2.new(-w / 2, -d / 2), Vector2.new(w / 2, -d / 2), 0, h, 1, { { at = 0, width = 5, bottom = 0, top = 9 }, win(-12), win(12) }, logColor, M.Wood)
	Build.wall(folder, origin, Vector2.new(-w / 2, d / 2), Vector2.new(w / 2, d / 2), 0, h, 1, { win(-12), win(8) }, logColor, M.Wood)
	Build.wall(folder, origin, Vector2.new(-w / 2, -d / 2), Vector2.new(-w / 2, d / 2), 0, h, 1, { win(0) }, logColor, M.Wood)
	Build.wall(folder, origin, Vector2.new(w / 2, -d / 2), Vector2.new(w / 2, d / 2), 0, h, 1, { win(-4) }, logColor, M.Wood)
	-- interior walls: office (west), bunk room (east), utility (north-east)
	Build.wall(folder, origin, Vector2.new(-8, -d / 2), Vector2.new(-8, d / 2), 0, h, 0.6, { { at = -4, width = 5, bottom = 0, top = 9 } }, rgb(120, 100, 76), M.WoodPlanks)
	Build.wall(folder, origin, Vector2.new(8, -d / 2), Vector2.new(8, d / 2), 0, h, 0.6, { { at = -4, width = 5, bottom = 0, top = 9 } }, rgb(120, 100, 76), M.WoodPlanks)
	Build.wall(folder, origin, Vector2.new(8, 4), Vector2.new(w / 2, 4), 0, h, 0.6, { { at = 12, width = 5, bottom = 0, top = 9 } }, rgb(120, 100, 76), M.WoodPlanks)
	-- roof, porch roof and posts: stand-ins for the Blender log-cabin exterior
	-- (build_buildings.py), which also lays logs over the walls
	local shell = Build.standIn(folder, "RangerStationExterior")
	Build.wedge(shell, Vector3.new(w + 4, 7, d / 2 + 2), origin * CF(0, h + 4, -d / 4 - 0.5), rgb(54, 66, 52), M.CorrodedMetal)
	Build.wedge(shell, Vector3.new(w + 4, 7, d / 2 + 2), origin * CF(0, h + 4, d / 4 + 0.5) * ANG(0, math.pi, 0), rgb(54, 66, 52), M.CorrodedMetal)
	-- porch
	Build.part(folder, Vector3.new(18, 0.6, 7), origin * CF(0, -0.3, -d / 2 - 3.5), rgb(100, 78, 54), M.WoodPlanks)
	for _, x in { -8.5, 8.5 } do
		Build.part(shell, Vector3.new(0.6, 10, 0.6), origin * CF(x, 5, -d / 2 - 6.5), rgb(70, 54, 40), M.Wood)
	end
	Build.part(shell, Vector3.new(19, 0.6, 8), origin * CF(0, 10.2, -d / 2 - 3.5), rgb(54, 66, 52), M.CorrodedMetal)
	Build.markStandIn(shell, origin)
	sign(folder, "PINECREST RANGER STATION", site.X + 0, site.Y + 0, site)
	local door = Doors.create(folder, origin * CF(-2.4, 0, -d / 2), 4.8, 9, { name = "StationDoor", swing = -1, color = rgb(60, 80, 60) })

	-- office: radio desk, map board, filing cabinets
	local desk = origin * CF(-16, 0, 8)
	Build.part(folder, Vector3.new(7, 0.4, 3.4), desk * CF(0, 3.2, 0), rgb(110, 84, 56), M.Wood)
	for _, x in { -3.2, 3.2 } do
		Build.part(folder, Vector3.new(0.4, 3, 3.2), desk * CF(x, 1.5, 0), rgb(110, 84, 56), M.Wood)
	end
	local radio = Props.Radio()
	radio:PivotTo(desk * CF(0, 3.4, 0.4) * ANG(0, math.pi, 0))
	radio.Parent = folder
	local radioPart = invisible(folder, Vector3.new(2.4, 1.6, 1.6), desk * CF(0, 4.2, 0.4), "RadioPrompt")
	Build.part(folder, Vector3.new(8, 5, 0.2), origin * CF(-14, 6, d / 2 - 0.7), rgb(200, 190, 160), M.Fabric).Name = "MapBoard"
	for i = 0, 1 do
		Build.part(folder, Vector3.new(2.2, 5, 2.6), origin * CF(-w / 2 + 1.6, 2.5, -6 + i * 2.8), rgb(80, 90, 80), M.Metal)
	end
	info.spots.NoteRanger = desk * CF(2.2, 3.42, -0.4) * ANG(0, rad(15), 0)
	info.spots.StationBattery = desk * CF(-2.4, 3.42, -0.3)

	-- bunk room: beds and lockers you can hide in
	for i = 0, 1 do
		Build.part(folder, Vector3.new(4, 1.4, 8), origin * CF(14 - i * 6, 1.2, -9), rgb(70, 80, 70), M.Fabric)
	end
	for i = 0, 1 do
		local locker = Build.part(folder, Vector3.new(2.6, 7, 2.4), origin * CF(18.4, 3.5, -3 - i * 2.8), rgb(70, 90, 80), M.Metal, { CanCollide = false })
		Hiding.add(locker, origin * CF(18.6, 3, -3 - i * 2.8) * ANG(0, rad(90), 0), origin * CF(14.5, 3, -3 - i * 2.8) * ANG(0, rad(90), 0), "Locker")
	end
	info.spots.StationBandage = origin * CF(14, 2.0, -9)

	-- utility room: fuse box
	local fuseBox = Build.part(folder, Vector3.new(0.6, 3, 2.4), origin * CF(w / 2 - 0.9, 5, 9), rgb(110, 110, 104), M.Metal)
	fuseBox.Name = "FuseBox"
	Build.part(folder, Vector3.new(0.2, 0.4, 0.4), origin * CF(w / 2 - 1.25, 5.8, 9.6), rgb(150, 20, 20), M.Neon).Name = "FuseLamp"

	-- lights that come on with the power
	local lights: { Light } = {}
	local lamps: { BasePart } = {}
	for _, p in { Vector3.new(-14, 10.2, 0), Vector3.new(0, 10.2, 0), Vector3.new(14, 10.2, -6), Vector3.new(14, 10.2, 9), Vector3.new(0, 9.6, -d / 2 - 3.5) } do
		local lamp = Build.part(folder, Vector3.new(1.4, 0.3, 1.4), origin * CF(p), rgb(60, 60, 60), M.Glass)
		local light = Instance.new("PointLight")
		light.Range = 22
		light.Brightness = 1.6
		light.Color = rgb(255, 228, 190)
		light.Shadows = p.X == 0 and p.Z == 0 -- one shadow caster is plenty in a small room
		light.Enabled = false
		light.Parent = lamp
		table.insert(lights, light)
		table.insert(lamps, lamp)
	end

	-- generator behind the station
	local genCF = origin * CF(-8, 0, d / 2 + 8)
	Build.part(folder, Vector3.new(10, 1, 8), genCF * CF(0, -0.3, 0), rgb(120, 120, 116), M.Concrete)
	local generator = Props.Generator()
	generator:PivotTo(genCF * CF(0, 0.2, 0))
	generator.Parent = folder
	local genPart = invisible(folder, Vector3.new(4, 3, 3), genCF * CF(0, 1.6, 0), "GeneratorPrompt")

	info.station = {
		door = door,
		radio = radioPart,
		fuseBox = fuseBox,
		generator = generator,
		generatorPart = genPart,
		lights = lights,
		lamps = lamps,
		center = origin.Position,
	}
	info.checkpoints.Station = CFrame.lookAt((origin * CF(0, 3, 4)).Position, (origin * CF(0, 3, -10)).Position)
	info.checkpoints.StationOutside = origin * CF(0, 3, -d / 2 - 12) * ANG(0, math.pi, 0)

	-- ranger jeep on blocks
	local jeep = origin * CF(24, 0, -24) * ANG(0, rad(30), 0)
	Build.part(folder, Vector3.new(6, 3, 11), jeep * CF(0, 3, 0), rgb(60, 80, 60), M.CorrodedMetal)
	Build.part(folder, Vector3.new(6, 2.6, 4), jeep * CF(0, 5.6, 1), rgb(60, 80, 60), M.CorrodedMetal)
	for _, x in { -2.5, 2.5 } do
		for _, z in { -3.5, 3.5 } do
			Build.part(folder, Vector3.new(1.4, 1.6, 1.4), jeep * CF(x, 0.8, z), rgb(90, 90, 90), M.Concrete)
		end
	end

	-- patrol loop and wave spawn points around the station
	local loop = {}
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		table.insert(loop, ground(site.X + math.cos(a) * 48, site.Y + math.sin(a) * 48).Position)
	end
	info.patrols.Station = loop
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + 0.4
		table.insert(info.surviveSpawns, ground(site.X + math.cos(a) * 95, site.Y + math.sin(a) * 95))
	end
end

local function buildTower(parent: Instance, info: Info)
	local folder = Build.folder(parent, "LookoutTower")
	local base = siteCF("Tower")
	local h = 30
	local legColor = rgb(84, 64, 46)
	for _, x in { -5, 5 } do
		for _, z in { -5, 5 } do
			Build.part(folder, Vector3.new(1, h, 1), base * CF(x, h / 2, z), legColor, M.Wood)
		end
	end
	for level = 0, 2 do
		local y = 4 + level * 9
		for _, side in { -5, 5 } do
			Build.part(folder, Vector3.new(10, 0.5, 0.5), base * CF(0, y, side) * ANG(0, 0, rad(38)), legColor, M.Wood)
			Build.part(folder, Vector3.new(0.5, 0.5, 10), base * CF(side, y, 0) * ANG(rad(38), 0, 0), legColor, M.Wood)
		end
	end
	Build.part(folder, Vector3.new(13, 0.8, 13), base * CF(0, h, 0), rgb(100, 78, 54), M.WoodPlanks)
	-- trapdoor gap where the ladder arrives
	for _, x in { -6.2, 6.2 } do
		Build.part(folder, Vector3.new(0.4, 3.4, 13), base * CF(x, h + 2.1, 0), legColor, M.Wood)
	end
	Build.part(folder, Vector3.new(13, 3.4, 0.4), base * CF(0, h + 2.1, 6.2), legColor, M.Wood)
	Build.part(folder, Vector3.new(8, 3.4, 0.4), base * CF(-2.5, h + 2.1, -6.2), legColor, M.Wood)
	-- flat cab roof: stand-in for the Blender hipped tin roof
	local roof = Build.standIn(folder, "LookoutTowerRoof")
	Build.part(roof, Vector3.new(14, 0.6, 14), base * CF(0, h + 8.5, 0), rgb(54, 66, 52), M.CorrodedMetal)
	Build.markStandIn(roof, base)
	for _, x in { -6, 6 } do
		for _, z in { -6, 6 } do
			Build.part(folder, Vector3.new(0.4, 8, 0.4), base * CF(x, h + 4.5, z), legColor, M.Wood)
		end
	end
	Build.ladder(folder, Vector3.new(2, h + 2, 2), base * CF(4, (h + 2) / 2, -6.6), rgb(70, 70, 72), M.Metal)
	Build.part(folder, Vector3.new(3, 2, 2), base * CF(-3, h + 1.4, 3), rgb(150, 30, 26), M.Metal).Name = "Toolbox"
	info.spots.Fuse = base * CF(-3, h + 2.45, 3) * ANG(0, rad(20), 0)
	lanternOn(folder, base * CF(2, h + 0.4, 3))
end

local function buildToolShed(parent: Instance, info: Info, rng: Util.Rng)
	local folder = Build.folder(parent, "ToolShed")
	local origin = siteCF("Shed", 0, 0, rad(150)) + Vector3.new(0, 0.5, 0)
	shed(folder, origin, 12, 10, 9, rgb(84, 70, 54), { doorWidth = 4.5, mesh = "ToolShedExterior" })
	Build.part(folder, Vector3.new(10, 0.4, 2.4), origin * CF(0, 3, 3.4), rgb(100, 76, 50), M.Wood)
	for i = 0, 3 do
		Build.part(folder, Vector3.new(0.2, 3.2, 0.3), origin * CF(-4 + i * 2.4, 6, 4.5), rgb(120, 120, 120), M.Metal, { CanCollide = false })
	end
	info.spots.GasCan = origin * CF(-3, 0, 2)
	spawnProp(folder, Props.Barrel, origin * CF(4, 0, 2.4), rng)
end

local function buildHelipad(parent: Instance, info: Info)
	local folder = Build.folder(parent, "Helipad")
	local cf = siteCF("Helipad")
	Build.cylinder(folder, 1, 40, cf * CF(0, 0.2, 0) * ANG(0, 0, rad(90)), rgb(110, 110, 108), M.Concrete)
	Build.cylinder(folder, 6, 39.6, cf * CF(0, -2.8, 0) * ANG(0, 0, rad(90)), rgb(90, 90, 88), M.Concrete)
	local white = rgb(220, 220, 214)
	Build.part(folder, Vector3.new(2, 0.1, 14), cf * CF(-5, 0.72, 0), white, M.SmoothPlastic, { CanCollide = false })
	Build.part(folder, Vector3.new(2, 0.1, 14), cf * CF(5, 0.72, 0), white, M.SmoothPlastic, { CanCollide = false })
	Build.part(folder, Vector3.new(8, 0.1, 2), cf * CF(0, 0.72, 0), white, M.SmoothPlastic, { CanCollide = false })
	local lights: { BasePart } = {}
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local lamp = Build.part(folder, Vector3.new(0.6, 0.4, 0.6), cf * CF(math.cos(a) * 19, 0.9, math.sin(a) * 19), rgb(40, 50, 40), M.Glass)
		local light = Instance.new("PointLight")
		light.Color = rgb(120, 255, 140)
		light.Range = 8
		light.Brightness = 2
		light.Enabled = false
		light.Parent = lamp
		table.insert(lights, lamp)
	end
	-- windsock
	Build.post(folder, 14, 0.4, cf * CF(24, 7, 0), rgb(200, 200, 200), M.Metal)
	Build.cylinder(folder, 4, 1.2, cf * CF(26, 13.4, 0) * ANG(0, 0, rad(-12)), rgb(230, 110, 40), M.Fabric, { CanCollide = false })
	info.helipad = cf
	info.helipadLights = lights
end

---------------------------------------------------------------- signs and scattered dressing
local function buildSigns(parent: Instance)
	local folder = Build.folder(parent, "Signs")
	sign(folder, "<- RANGER STN 2 MI", 205, -20, S.Truck.pos)
	sign(folder, "CAMP ->", 140, 0, S.Truck.pos)
	sign(folder, "CEMETERY ->", 200, -90, S.Truck.pos)
	sign(folder, "TRESPASSERS WILL BE EATEN", -112, -392, Vector2.new(-150, -420))
	sign(folder, "KEEP OUT", -60, -240, S.House.pos)
end

function Sites.build(parent: Instance): Info
	local rng = Util.rng(Config.Map.Seed + 77)
	local info: Info = {
		patrols = {},
		spots = {},
		checkpoints = {},
		surviveSpawns = {},
		truckSlots = {},
	} :: any
	local root = Build.folder(parent, "Sites")
	buildHighway(root, info, rng)
	buildTruck(root, info, rng)
	buildBarn(root, info, rng)
	buildCamp(root, info, rng)
	buildTrailer(root, info, rng)
	buildCemetery(root, info, rng)
	buildStation(root, info, rng)
	buildTower(root, info)
	buildToolShed(root, info, rng)
	buildHelipad(root, info)
	buildSigns(root)

	info.wreck = siteCF("Wreck")
	info.checkpoints.Hunt = info.wreck * CF(-8, 3, 6)
	return info
end

return Sites

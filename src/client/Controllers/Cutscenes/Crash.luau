--!strict
-- Crash (~58 s), shot from outside like a film: you at the wheel on a late
-- food run with friends in the storm, a pickup with its lights off rolls out
-- of the dark and T-bones the car into a pine. Michel and Jason come down the
-- road with a lantern, find you slumped over the wheel, and Michel carries
-- you up the driveway. Lightning shows the farmhouse - far too big - with a
-- figure at an upstairs window that is gone on the next flash.
-- data: { sedan: Model, tree: CFrame, house: CFrame, truck: Model?, truckCF: CFrame? }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local CameraController = require(script.Parent.Parent.CameraController)
local Effects = require(script.Parent.Parent.Effects)
local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local Stage = require(script.Parent.Stage)
local Cast = require(script.Parent.Cast)

local rgb = Color3.fromRGB
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local UP = Vector3.yAxis
local at = Stage.at
local sleep = Stage.sleep
local groundY = Stage.groundY

-- The other players in the car, or stand-ins when playing alone.
local function friendNames(): (string, string)
	local names: { string } = {}
	for _, plr in Players:GetPlayers() do
		if plr ~= Players.LocalPlayer then
			table.insert(names, plr.DisplayName)
		end
	end
	return names[1] or "Sam", names[2] or "Riley"
end

-- A torch in the actor's right hand, shining down the arm.
local function flashlight(actor: Cast.Actor)
	local hand = actor.model:FindFirstChild("RightHand") or actor.model:FindFirstChild("Right Arm")
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local cf = hand.CFrame * CF(0, -hand.Size.Y / 2 - 0.3, -0.1) * ANG(rad(-90), 0, 0)
	local tube = Stage.part(Vector3.new(0.32, 0.32, 1.1), cf, rgb(30, 30, 30), Enum.Material.Metal)
	local lens = Stage.part(Vector3.new(0.3, 0.3, 0.05), cf * CF(0, 0, -0.56), rgb(255, 245, 210), Enum.Material.Neon)
	local beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front
	beam.Range = 40
	beam.Angle = 38
	beam.Brightness = 2.6
	beam.Color = rgb(255, 240, 210)
	beam.Shadows = true
	beam.Parent = lens
	for _, p in { tube, lens } do
		p.Anchored = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = p
		weld.Parent = p
		p.Parent = actor.model
	end
end

return Stage.scene("Crash", function(data: any)
	local road = Config.Roads[1].points
	local site = Config.Sites.Crash.pos
	local tree = Stage.cf(data.tree, CF(site.X, groundY(site.X, site.Y + 6), site.Y + 6))
	local treePos = tree.Position
	local sedan = Stage.model(data.sedan)
	local passengerName, backName = friendNames()

	Stage.setBlack(1)
	Stage.letterbox(true, 0)
	Effects.setRain(true, true)
	Stage.blur(0)
	Stage.cut(Stage.camCFrame(), 60)

	-- where the car ends up: nose into the pine (the server's wreck spot)
	local carCF: CFrame
	if sedan then
		local pivot = sedan:GetPivot()
		local flatPivot = CFrame.lookAt(pivot.Position, pivot.Position + Util.flat(pivot.LookVector))
		carCF = if Util.flat(treePos - pivot.Position):Dot(pivot.LookVector) >= 0 then flatPivot else flatPivot * ANG(0, math.pi, 0)
		carCF = CF(carCF.X, groundY(carCF.X, carCF.Z, carCF.Y), carCF.Z) * carCF.Rotation
	else
		local base = Stage.ground(tree * Vector3.new(0.6, 0, -9.5))
		carCF = CFrame.lookAt(base, Vector3.new(treePos.X, base.Y, treePos.Z))
	end

	-- our own car plays the wreck too, so the server sedan stays hidden; its
	-- smoke, hazards and broken glass only show once we have crashed
	local wreckBits: { BasePart } = {}
	local wreckLights: { [Light]: number } = {}
	local wreckSmoke: { Smoke } = {}
	if sedan then
		Stage.hide(sedan)
		local center = sedan:GetPivot().Position
		local holder = sedan.Parent
		if holder then
			for _, child in holder:GetChildren() do
				if child:IsA("BasePart") and child.Size.Magnitude < 12 and (child.Position - center).Magnitude < 32 then
					table.insert(wreckBits, child)
					for _, e in child:GetDescendants() do
						if e:IsA("Light") then
							wreckLights[e] = e.Brightness
						elseif e:IsA("Smoke") then
							table.insert(wreckSmoke, e)
						end
					end
				end
			end
		end
	end
	local function showWreck(visible: boolean)
		for _, p in wreckBits do
			p.LocalTransparencyModifier = if visible then 0 else 1
		end
		for light, brightness in wreckLights do
			light.Brightness = if visible then brightness else 0
		end
		for _, s in wreckSmoke do
			s.Enabled = visible
		end
	end
	showWreck(false)
	Stage.cleanup(function()
		showWreck(true)
	end)

	---------------------------------------------------------------- the drive
	local T_HIT = 14
	local SPIN = 1.05
	local LANE = 4.6 -- car centre, right of the road's centre line
	local total = Util.polylineLength(road)
	local finalBase = Util.flat(carCF.Position)
	local _, _, finalAlong = Util.polylineClosest(road, Vector2.new(finalBase.X, finalBase.Z))
	local hitAlong = math.min(finalAlong + 22, total - 20)
	local SPEED = math.clamp((total - 12 - hitAlong) / T_HIT, 20, 50)
	local startAlong = hitAlong + SPEED * T_HIT

	-- car centre on the ground in the right-hand lane, and the travel direction
	local function lane(s: number): (Vector3, Vector3)
		local p = Util.polylineSample(road, s)
		local behind = Util.polylineSample(road, s + 9)
		local ahead = Util.polylineSample(road, math.max(s - 9, 0))
		local d2 = ahead - behind
		d2 = if d2.Magnitude > 1e-3 then d2.Unit else Vector2.new(-1, 0)
		local c2 = p + Vector2.new(-d2.Y, d2.X) * LANE
		return Vector3.new(c2.X, groundY(c2.X, c2.Y), c2.Y), Vector3.new(d2.X, 0, d2.Y)
	end

	local function carFrame(base: Vector3, dir: Vector3, roll: number): CFrame
		local f = base + dir * 5
		local b = base - dir * 5
		local pitch = math.atan2(groundY(f.X, f.Z, base.Y) - groundY(b.X, b.Z, base.Y), 10)
		return CFrame.lookAt(base, base + dir) * ANG(pitch, 0, roll)
	end

	local pHit, dir0 = lane(hitAlong)
	local rightV = dir0:Cross(UP)
	-- the truck comes from the side away from the tree and shoves the car into it
	local away = if (finalBase - Util.flat(pHit)):Dot(rightV) < 0 then rightV else -rightV
	local sideWord = if away:Dot(rightV) > 0 then "right" else "left"
	local sideSign = if away:Dot(rightV) > 0 then 1 else -1
	local finalDir = Util.flat(carCF.LookVector)
	finalDir = if finalDir.Magnitude > 1e-3 then finalDir.Unit else -away
	local spinAngle = math.atan2(dir0:Cross(finalDir).Y, dir0:Dot(finalDir))
	local shove = Stage.spline({ Util.flat(pHit), Util.flat(pHit) + dir0 * 8 - away * 6, finalBase })

	-- the family's pickup, dark until the last second
	local serverTruck = Stage.model(data.truck)
	local truckBody = Stage.cloneProp(serverTruck)
	local pivotOffset = CFrame.identity
	if truckBody and serverTruck then
		pivotOffset = Stage.cf(data.truckCF, serverTruck:GetPivot()):ToObjectSpace(serverTruck:GetPivot())
	end
	local truck = truckBody or Cast.simpleTruck()
	local HALF = 9.2
	local TRUCK_RUN = 4
	local TRUCK_DIST = 64
	local impactCenter = Util.flat(pHit) + away * (3.4 + HALF) + dir0 * 1.5
	local function truckAt(center: Vector3): CFrame
		local g = Stage.ground(center)
		return CFrame.lookAt(g, g - away)
	end
	local lamps: { { part: BasePart, offset: CFrame } } = {}
	local headLamps: { BasePart } = {}
	local headBeams: { SpotLight } = {}
	local tailLamps: { BasePart } = {}
	for _, x in { -2.6, 2.6 } do
		local lamp = Stage.part(Vector3.new(1.1, 0.7, 0.2), CFrame.identity, rgb(70, 70, 66), Enum.Material.Glass, { Transparency = 0.3 })
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Range = 70
		beam.Angle = 75
		beam.Brightness = 0
		beam.Color = rgb(255, 244, 214)
		beam.Shadows = true
		beam.Parent = lamp
		table.insert(headLamps, lamp)
		table.insert(headBeams, beam)
		table.insert(lamps, { part = lamp :: BasePart, offset = CF(x, 3.5, -HALF - 0.1) })
		local tail = Stage.part(Vector3.new(0.8, 0.6, 0.2), CFrame.identity, rgb(70, 14, 14), Enum.Material.Glass, { Transparency = 0.3 })
		table.insert(tailLamps, tail)
		table.insert(lamps, { part = tail :: BasePart, offset = CF(x * 1.08, 3.3, HALF + 0.1) })
	end
	local function placeTruck(cf: CFrame)
		truck:PivotTo(cf * pivotOffset)
		for _, l in lamps do
			l.part.CFrame = cf * l.offset
		end
	end
	local function headlights(on: boolean)
		for _, lamp in headLamps do
			lamp.Material = if on then Enum.Material.Neon else Enum.Material.Glass
			lamp.Color = if on then rgb(255, 248, 226) else rgb(70, 70, 66)
		end
		for _, beam in headBeams do
			beam.Brightness = if on then 7 else 0
		end
	end
	local function taillights(on: boolean)
		for _, lamp in tailLamps do
			lamp.Material = if on then Enum.Material.Neon else Enum.Material.Glass
			lamp.Color = if on then rgb(200, 20, 16) else rgb(70, 14, 14)
		end
	end
	local function truckPose(t: number): CFrame
		if t < T_HIT - TRUCK_RUN then
			return truckAt(impactCenter + away * TRUCK_DIST)
		elseif t < T_HIT then
			local u = (t - (T_HIT - TRUCK_RUN)) / TRUCK_RUN
			return truckAt(impactCenter + away * TRUCK_DIST * (1 - u * u))
		end
		return truckAt(impactCenter - away * 3 * Stage.smooth(math.min((t - T_HIT) / 0.5, 1)))
	end
	placeTruck(truckPose(0))

	-- the car and the three of you in it
	local car = Cast.simpleCar(rgb(44, 58, 92))
	local me = Cast.me(CFrame.identity)
	local passenger = Cast.friend(1, CFrame.identity)
	local backSeat = Cast.friend(2, CFrame.identity)
	Cast.sit(me, 1.1)
	Cast.sit(passenger, 0.4)
	Cast.sit(backSeat, 0.4)
	local riders = {
		{ actor = me, seat = Cast.CAR_DRIVER },
		{ actor = passenger, seat = Cast.CAR_PASSENGER },
		{ actor = backSeat, seat = Cast.CAR_BACK },
	}
	local doorAngle = 0
	local function placeAll(cf: CFrame)
		Cast.placeCar(car, cf, doorAngle)
		for _, r in riders do
			r.actor.root.CFrame = cf * r.seat * CF(0, Cast.seatLift(r.actor), 0)
		end
	end

	Stage.resetClock()
	local elapsed = 0
	local crashed = false
	local startSpot, startDir = lane(startAlong)
	local carNow = carFrame(startSpot, startDir, 0)
	local shot = 1
	-- shot 1: the roadside, the car coming through the rain
	local roadside, roadsideDir = lane(startAlong - SPEED * 4.6)
	local roadsideCam = roadside + roadsideDir:Cross(UP) * 13 + UP * 2.2
	-- shot 4: across the road from the impact, wide enough for the spin
	local impactCam = Util.flat(pHit) + dir0 * 2 - away * 24 + UP * (pHit.Y + 3.5)
	Stage.track(function(dt)
		elapsed += dt
		local spot, dir, roll = pHit, dir0, 0
		if elapsed < T_HIT then
			spot, dir = lane(startAlong - SPEED * elapsed)
		else
			local u = math.clamp((elapsed - T_HIT) / SPIN, 0, 1)
			local p = Stage.splineAt(shove, 1 - (1 - u) ^ 2)
			spot = Vector3.new(p.X, groundY(p.X, p.Z), p.Z)
			dir = CFrame.fromAxisAngle(UP, spinAngle * (1 - (1 - u) ^ 3)):VectorToWorldSpace(dir0)
			roll = math.sin(u * math.pi) * 0.16 * sideSign
			if u >= 1 then
				crashed = true
			end
		end
		carNow = carFrame(spot, dir, roll)
		placeAll(carNow)
		local pose = truckPose(elapsed)
		placeTruck(pose)
		if shot == 1 then
			return CFrame.lookAt(roadsideCam, carNow.Position + UP * 2.5)
		elseif shot == 2 then
			-- on the dashboard, looking back at you and your friends
			local cam = carNow * CF(0.1, 4.5, -2.1)
			return CFrame.lookAt(cam.Position, (carNow * CF(-0.3, 4.1, 1.8)).Position, carNow.UpVector)
		elseif shot == 3 then
			-- from the back seat, out through the windscreen and the side window
			local cam = carNow * CF(-0.6, 5, 3.4)
			return CFrame.lookAt(cam.Position, (carNow * CF(2.6 * sideSign, 4.2, -6)).Position, carNow.UpVector)
		end
		return CFrame.lookAt(impactCam, carNow.Position + UP * 2)
	end)

	Stage.sway(0.2)
	Stage.zoom(48, 0)
	Stage.fadeTo(0, 2.2)
	at(0.9)
	HUD.subtitle(passengerName, "Okay, I'm officially starving. How far's the McDonald's?", 3.4)
	at(4.2)
	shot = 2
	Stage.zoom(68, 0)
	HUD.subtitle("You", "Sign said twelve miles. Twenty minutes, tops.", 3)
	at(5.6)
	Cast.pose(passenger, "neck", Cast.neck(passenger, 0, 0.5, 0), 0.6) -- turns to you
	at(7.4)
	Cast.pose(backSeat, "waist", Cast.waist(backSeat, 0.25), 0.6) -- leans forward between the seats
	HUD.subtitle(backName, "Twenty minutes? In THIS storm? We're gonna die out here for nuggets.", 3.6)
	at(9.6)
	Cast.pose(passenger, "neck", CFrame.identity, 0.5)
	at(10)
	shot = 3
	Stage.zoom(70, 0)
	HUD.subtitle(passengerName, "Worth it. Totally worth it.", 1.4)
	at(T_HIT - 3.2)
	HUD.subtitle(passengerName, "…hey. What's that? On the " .. sideWord .. "—", 1.7)
	Cast.pose(passenger, "neck", Cast.neck(passenger, 0, -0.9 * sideSign, 0), 0.5)
	at(T_HIT - 2.6)
	Effects.lightning() -- a dark pickup, rolling at you with no lights
	at(T_HIT - 1.7)
	shot = 4
	Stage.zoom(52, 0)
	HUD.subtitle(backName, "IT'S NOT STOPPING!", 1.4)
	at(T_HIT - 0.5)
	headlights(true)
	Stage.sfx("EngineStart", nil, impactCenter, 1, 1.1)
	at(T_HIT)
	-- the T-bone
	Effects.flash(Color3.new(1, 1, 1), 0.4)
	CameraController.shake(2.4, 1.8)
	Stage.sfx("Crash", "Impact", carNow.Position, 1, 0.75)
	Stage.sfx("Scream", nil, carNow.Position, 0.5, 1.15)
	headlights(false)
	for _, g in car.glass do
		g.Color = rgb(200, 210, 214)
		g.Transparency = 0.45
	end
	local deadline = os.clock() + SPIN + 1.5
	while not crashed and os.clock() < deadline do
		sleep(0)
	end

	-- the pine: white flash, hard shake, black
	Stage.flashWhite(0.45)
	Effects.flash(Color3.new(1, 1, 1), 0.9)
	CameraController.shake(3.6, 1.3)
	Stage.sfx("Crash", "Impact", carNow.Position, 1, 0.5)
	sleep(0.16)
	Stage.setBlack(1)
	Stage.stopCamera()
	Stage.sway(0)
	Stage.blur(14)
	sleep(1.6)

	---------------------------------------------------------------- the wreck
	-- crumpled bonnet, dead lights, the three of you slumped where you sat
	for _, l in car.headlights do
		l.Enabled = false
	end
	for _, lamp in car.lamps do
		lamp.Material = Enum.Material.Glass
		lamp.Color = rgb(60, 60, 58)
	end
	local wreckCF = carCF
	placeAll(wreckCF)
	for _, p in car.hood do
		p.CFrame = p.CFrame * CF(0, 0.4, 0.8) * ANG(rad(16), rad(4), rad(-5))
	end
	Cast.pose(me, "neck", Cast.neck(me, -0.7, 0.2, 0.25), 0)
	Cast.pose(me, "waist", Cast.waist(me, 0.55), 0)
	Cast.pose(me, "rightShoulder", Cast.arm(me, true, 0.9, 0.1), 0)
	Cast.pose(me, "leftShoulder", Cast.arm(me, false, 0.2, 0.2), 0)
	Cast.pose(passenger, "neck", Cast.neck(passenger, -0.6, -0.3, -0.4), 0)
	Cast.pose(backSeat, "neck", Cast.neck(backSeat, -0.5, 0.2, 0.3), 0)
	showWreck(true)
	local truckStop = truckPose(T_HIT + 1)
	placeTruck(truckStop)
	taillights(true)
	local _, roadPoint = Util.polylineClosest(road, Vector2.new(wreckCF.X, wreckCF.Z))
	local side = if (Vector3.new(roadPoint.X, wreckCF.Y, roadPoint.Y) - wreckCF.Position):Dot(wreckCF.RightVector) >= 0 then 1 else -1

	local smokePart = Stage.part(Vector3.one, wreckCF * CF(0, 3.2, -5.6), rgb(0, 0, 0), nil, { Transparency = 1 })
	local smoke = Instance.new("Smoke")
	smoke.Color = rgb(90, 90, 94)
	smoke.Opacity = 0.18
	smoke.RiseVelocity = 3
	smoke.Size = 3.5
	smoke.Parent = smokePart
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(rgb(255, 170, 70))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.12)
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Speed = NumberRange.new(6, 12)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.Rate = 0
	sparks.Parent = smokePart
	-- the hazards still blink
	local hazards = true
	Stage.go(function()
		while hazards do
			for _, lamp in car.lamps do
				lamp.Material = Enum.Material.Neon
				lamp.Color = rgb(255, 160, 40)
			end
			sleep(0.5)
			for _, lamp in car.lamps do
				lamp.Material = Enum.Material.Glass
				lamp.Color = rgb(60, 60, 58)
			end
			sleep(0.5)
		end
	end)

	Stage.cut(CFrame.lookAt(wreckCF * Vector3.new(side * 14, 2.6, 3), wreckCF * Vector3.new(0, 2.6, -2.5)), 55)
	Stage.blurTo(2, 2.5)
	Stage.fadeTo(0, 1.4)
	Stage.move(CFrame.lookAt(wreckCF * Vector3.new(side * 10.5, 2, 4), wreckCF * Vector3.new(0, 3, -1.5)), 3.6)
	Stage.later(1.6, function()
		sparks:Emit(14)
	end)
	sleep(3.4)

	-- reverse shot from beside the wreck: the pickup backs off into the rain
	local truckLook = truckStop.Position + UP * 3
	local lowEye = wreckCF * Vector3.new(side * 3.8, 2, 6.5)
	Stage.cut(CFrame.lookAt(lowEye, truckLook), 50)
	Stage.move(CFrame.lookAt(lowEye + UP * 0.3, truckLook + away * 10), 3.4)
	Stage.go(function()
		Stage.animate(3.4, function(a)
			placeTruck(truckAt(impactCenter - away * 3 + away * 24 * Stage.smooth(a)))
		end)
	end)
	Stage.later(1.2, Effects.lightning)
	sleep(2.6)
	Stage.fadeTo(1, 0.7)
	sleep(0.8)
	truck:Destroy()
	for _, l in lamps do
		l.part:Destroy()
	end

	---------------------------------------------------------------- the rescue
	-- Michel comes up from the road with a lantern, Jason behind with a torch
	local doorSpot = Stage.ground(wreckCF * Vector3.new(-4.6, 0, -0.4))
	local start = Stage.ground(wreckCF * Vector3.new(-6, 0, 18))
	local michel = Cast.actor("Michel", CFrame.lookAt(start, Vector3.new(doorSpot.X, start.Y, doorSpot.Z)), "HostTemplates")
	Cast.lantern(michel)
	local jasonStart = Stage.ground(wreckCF * Vector3.new(-9.5, 0, 22))
	local jasonSpot = Stage.ground(wreckCF * Vector3.new(-8.2, 0, 4.2))
	local jason = Cast.actor("Jason", CFrame.lookAt(jasonStart, jasonSpot), "HostTemplates")
	flashlight(jason)
	Stage.go(function()
		Cast.walk(michel, { doorSpot }, 3.7, { ground = true })
		Cast.face(michel, (wreckCF * CF(-1.45, 4, 0.7)).Position, 0.7)
	end)
	Stage.go(function()
		sleep(0.8)
		Cast.walk(jason, { jasonSpot }, 3.6, { ground = true })
		Cast.face(jason, (wreckCF * CF(-1.45, 4, 0.7)).Position, 0.8)
	end)

	-- low behind Michel as he comes up to the driver's door
	Stage.resetClock()
	Stage.blur(6)
	Stage.cut(CFrame.lookAt(wreckCF * Vector3.new(-12, 2.4, 13), wreckCF * Vector3.new(-2.5, 3.4, -0.5)), 50)
	Stage.move(CFrame.lookAt(wreckCF * Vector3.new(-10.5, 2.8, 9.5), wreckCF * Vector3.new(-2.5, 3.6, -0.5)), 7)
	Stage.fadeTo(0, 0.8)
	at(2)
	HUD.subtitle(backName, "…guys…? Is everyone okay…?", 2.6)
	at(4.4)
	HUD.subtitle("Michel", "Hello?! Anybody hurt in there?!", 2.4)
	at(7.2)
	-- through the driver's window: you, out cold over the wheel
	Stage.cut(CFrame.lookAt(wreckCF * Vector3.new(-7.2, 4.6, -3.4), wreckCF * Vector3.new(-1.45, 4, 0.8)), 46)
	Stage.move(CFrame.lookAt(wreckCF * Vector3.new(-6.6, 4.4, -2.6), wreckCF * Vector3.new(-1.45, 3.9, 0.8)), 4.6)
	at(7.6)
	-- the door opens
	Stage.go(function()
		Stage.animate(0.9, function(a)
			doorAngle = 1.15 * Stage.smooth(a)
			Cast.placeCar(car, wreckCF, doorAngle)
		end)
	end)
	Stage.sfx("DoorOpen", nil, wreckCF.Position, 0.8, 0.8)
	at(8)
	HUD.subtitle("Michel", "Easy… easy now. We've got you.", 2.8)
	Cast.pose(michel, "waist", Cast.waist(michel, 0.4), 0.9)
	Cast.pose(michel, "neck", Cast.neck(michel, -0.3, 0, 0), 0.9)
	at(8.6)
	Stage.go(function()
		local from = michel.root.CFrame
		local toward = Util.flat((wreckCF * CF(-1.45, 0, 0.7)).Position - from.Position)
		toward = if toward.Magnitude > 1e-3 then toward.Unit else Vector3.zero
		Stage.animate(1.2, function(a)
			michel.root.CFrame = from + toward * (1.3 * Stage.smooth(a))
		end)
	end)
	Cast.pose(michel, "rightShoulder", Cast.arm(michel, true, 1.35, 0.1), 1.1)
	Cast.pose(michel, "leftShoulder", Cast.arm(michel, false, 1.2, 0.1), 1.1)
	at(10.2)
	Cast.pose(jason, "rightShoulder", Cast.arm(jason, true, 1.2, 0), 0.6)
	HUD.subtitle("Jason", "Get them out. The house isn't far.", 2.6)
	at(12)
	Stage.fadeTo(1, 0.5)
	sleep(0.6)
	hazards = false
	Stage.stopCamera()
	car.model:Destroy()
	passenger.model:Destroy()
	backSeat.model:Destroy()

	---------------------------------------------------------------- the carry
	-- up the driveway in Michel's arms, Jason lighting the way; the camera
	-- walks alongside
	local driveway = Config.Roads[2].points
	local pts: { Vector2 } = {}
	for i = #driveway, 1, -1 do
		table.insert(pts, driveway[i])
	end
	local CARRY_START, CARRY_LEN, CARRY_TIME = 4, 30, 9.5
	Cast.stand(michel, 0)
	Cast.pose(michel, "rightShoulder", Cast.arm(michel, true, 1.45, 0.15), 0)
	Cast.pose(michel, "leftShoulder", Cast.arm(michel, false, 1.45, 0.15), 0)
	michel.model:SetAttribute("AnimLegsOnly", true)
	Cast.play(michel, "walk", 0.45)
	Cast.pose(jason, "rightShoulder", Cast.arm(jason, true, 0.35, 0), 0)
	Cast.play(jason, "walk", 0.45)
	-- you, limp across his arms: head lolling, one arm hanging
	Cast.still(me)
	for _, joint in { "rightHip", "leftHip", "waist" } do
		Cast.pose(me, joint, CFrame.identity, 0)
	end
	Cast.pose(me, "neck", Cast.neck(me, 0.5, 0, 0.2), 0)
	Cast.pose(me, "rightShoulder", Cast.arm(me, true, -1.3, 0), 0)
	Cast.pose(me, "leftShoulder", Cast.arm(me, false, 0.2, 0.1), 0)
	local carryElapsed = 0
	Stage.track(function(dt)
		carryElapsed += dt
		local prog = math.clamp(carryElapsed / CARRY_TIME, 0, 1)
		local stride = math.sin(carryElapsed * 7.2)
		local s = CARRY_START + CARRY_LEN * prog
		local p2 = Util.polylineSample(pts, s)
		local d2 = Util.polylineSample(pts, s + 3) - Util.polylineSample(pts, math.max(s - 3, 0))
		d2 = if d2.Magnitude > 1e-3 then d2.Unit else Vector2.new(0, 1)
		local d = Vector3.new(d2.X, 0, d2.Y)
		local mpos = Vector3.new(p2.X, groundY(p2.X, p2.Y), p2.Y) + UP * (michel.lift + math.abs(stride) * 0.06)
		local mcf = CFrame.lookAt(mpos, mpos + d)
		michel.root.CFrame = mcf
		-- face up across his arms, head to his left
		local held = mpos + d * 1.6 + UP * 0.6
		me.root.CFrame = CFrame.fromMatrix(held, -mcf.LookVector, -mcf.RightVector)
		local j2 = Util.polylineSample(pts, s + 7)
		local jpos = Vector3.new(j2.X, groundY(j2.X, j2.Y), j2.Y) + UP * jason.lift
		jason.root.CFrame = CFrame.lookAt(jpos, jpos + d)
		local camPos = mpos + mcf.RightVector * 7.5 + UP * 1.6 - d * 2.5
		return CFrame.lookAt(camPos, held + d * 1.5)
	end)
	Stage.blur(5)
	Stage.sway(0.4)
	Stage.zoom(55, 0)
	Stage.resetClock()
	Stage.fadeTo(0, 0.6)
	at(1.4)
	HUD.subtitle("Michel", "Shh… you're safe now.", 2.6)
	at(4.6)
	HUD.subtitle("Jason", "Your friends are right behind us. Don't you worry.", 3)
	at(7.4)
	HUD.subtitle("Michel", "Almost home.", 2)
	at(8.8)
	Stage.fadeTo(1, 0.4)
	sleep(0.5)
	Stage.stopCamera()
	jason.model:Destroy()
	michel.model:Destroy()
	me.model:Destroy()

	---------------------------------------------------------------- the house
	-- out of the dark in a lightning flash: the farmhouse, far bigger than a
	-- house out here should be, every window black but one. Someone stands
	-- at an upstairs window watching you being carried in, and on the next
	-- flash there's no one there.
	local house = Stage.cf(data.house, workspace.CurrentCamera.CFrame)
	local function HV(x: number, y: number, z: number): Vector3
		return house * Vector3.new(x, y, z)
	end
	local watcherFloor = house * CF(-12, 13, -22.4)
	local watcher = Cast.actor("Kin", CFrame.lookAt(watcherFloor.Position, watcherFloor.Position - house.LookVector))
	Cast.still(watcher)
	Cast.pose(watcher, "neck", Cast.neck(watcher, -0.1, 0, 0.12), 0)
	-- lamplight from just inside the glass, on the figure's front (from
	-- behind it only made a silhouette against a black room)
	local glow = Stage.part(Vector3.one, house * CF(-12, 19.5, -23.1), rgb(0, 0, 0), nil, { Transparency = 1 })
	local window = Instance.new("PointLight")
	window.Color = rgb(255, 150, 80)
	window.Range = 9
	window.Brightness = 1.8
	window.Parent = glow
	Stage.cut(CFrame.lookAt(HV(26, 3, -96), HV(0, 13, -22)), 52)
	Stage.move(CFrame.lookAt(HV(8, 5, -58), HV(-6, 15, -22)), 8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	Stage.blur(0)
	Stage.sway(0.3)
	Stage.resetClock()
	Stage.fadeTo(0, 1.4)
	at(1.3)
	Effects.lightning()
	at(2.6)
	HUD.subtitle("Jason", "(whispering) Mama's going to be so pleased.", 3)
	at(4.4)
	-- in close on the window... and then she's gone
	Stage.cut(CFrame.lookAt(HV(-10, 15, -44), HV(-12, 16.5, -23)), 34)
	Stage.move(CFrame.lookAt(HV(-11, 15.8, -38), HV(-12, 16.5, -23)), 3)
	at(6.2)
	Effects.lightning()
	watcher.model:Destroy()
	window.Brightness = 0
	at(7.4)
	Stage.sfx("Impact", nil, HV(0, 4, -24), 1, 0.55) -- the front door slams
	CameraController.shake(0.25, 3)
	Stage.fadeTo(1, 0.3)
	sleep(0.4)
	Stage.stopCamera()
	Stage.title("Hours later…", { font = Theme.Fonts.Type, size = 34, color = Theme.Colors.BoneDim, fadeIn = 1.2, hold = 1.8, fadeOut = 1 })
	sleep(4.2)
end)

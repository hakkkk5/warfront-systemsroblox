--!strict
-- Crash (~49 s): a late food run with friends in the storm. A pickup with its
-- lights off rolls out of the dark and T-bones the car into a pine. Through
-- blurred eyes two kind strangers, Michel and Jason, pull you out of the
-- wreck and carry you up the driveway to their farmhouse.
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

-- An extra part that rides along in the cockpit (eye space); returns its
-- item index so the pose can change later.
local function rider(cockpit: Cast.Cockpit, size: Vector3, base: CFrame, color: Color3, material: Enum.Material?): number
	local p = Stage.part(size, base, color, material)
	p.Parent = cockpit.model
	table.insert(cockpit.items, { part = p :: BasePart, base = base, group = "static" })
	table.insert(cockpit.parts, p)
	table.insert(cockpit.frames, base)
	return #cockpit.items
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
	local passenger, backSeat = friendNames()

	Stage.setBlack(1)
	Stage.letterbox(true, 0)
	Effects.setRain(true, true)
	Stage.blur(0)
	Stage.cut(Stage.camCFrame(), 72)

	-- where the car ends up: wrapped around the pine
	local carCF: CFrame
	local eyeCF: CFrame
	if sedan then
		local pivot = sedan:GetPivot()
		carCF = if Util.flat(treePos - pivot.Position):Dot(pivot.LookVector) >= 0 then pivot else pivot * ANG(0, math.pi, 0)
		local bbCF, bbSize = sedan:GetBoundingBox()
		local center = carCF:PointToObjectSpace(bbCF.Position)
		local bottom = center.Y - bbSize.Y / 2
		eyeCF = carCF * CF(center.X - 1.45, bottom + bbSize.Y * 0.8, center.Z + 0.3) * ANG(rad(-5), 0, rad(5))
	else
		local base = Stage.ground(tree * Vector3.new(0.6, 0, -9.5))
		carCF = CFrame.lookAt(base, Vector3.new(treePos.X, base.Y, treePos.Z))
		eyeCF = carCF * CF(-1.45, 4.1, 0) * ANG(rad(-5), 0, rad(5))
	end

	-- the finished wreck already sits by the tree: keep it out of the drive
	local wreckParts: { BasePart } = {}
	local wreckLights: { [Light]: number } = {}
	local wreckSmoke: { Smoke } = {}
	if sedan then
		local center = sedan:GetPivot().Position
		for _, d in sedan:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(wreckParts, d)
			end
		end
		local holder = sedan.Parent
		if holder then
			for _, child in holder:GetChildren() do
				if child:IsA("BasePart") and child.Size.Magnitude < 12 and (child.Position - center).Magnitude < 32 then
					table.insert(wreckParts, child)
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
		for _, p in wreckParts do
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

	-- the route: west along the highway, hit from the side, shoved into the tree
	local T_HIT = 14
	local SPIN = 1.05
	local LANE = 3.4
	local EYE = 3.9
	local total = Util.polylineLength(road)
	local finalBase = Util.flat(eyeCF.Position)
	local _, _, finalAlong = Util.polylineClosest(road, Vector2.new(finalBase.X, finalBase.Z))
	local hitAlong = math.min(finalAlong + 22, total - 20)
	local SPEED = math.clamp((total - 12 - hitAlong) / T_HIT, 20, 50)
	local startAlong = hitAlong + SPEED * T_HIT

	-- eye position on the ground in the right-hand lane, and the travel direction
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
		local f = base + dir * 4
		local b = base - dir * 4
		local pitch = math.atan2(groundY(f.X, f.Z, base.Y) - groundY(b.X, b.Z, base.Y), 8)
		local eye = base + UP * EYE
		return CFrame.lookAt(eye, eye + dir) * ANG(pitch, 0, roll)
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
	local impactCenter = Util.flat(pHit) + away * (4.6 + HALF) - dir0 * 2.4
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

	-- the car, with a friend riding shotgun
	local cockpit = Cast.buildCockpit(6.2, rgb(32, 40, 66))
	Cast.setGauges(cockpit, true)
	cockpit.speed = 0.6
	cockpit.rpm = 0.45
	local SEAT = 6.2 * 0.46
	local headItem = rider(cockpit, Vector3.new(1.1, 1.2, 1.1), CF(SEAT, -0.15, 0.2), rgb(224, 186, 152))
	local hairItem = rider(cockpit, Vector3.new(1.2, 0.4, 1.2), CF(SEAT, 0.5, 0.3), rgb(52, 36, 26), Enum.Material.Fabric)
	local bodyItem = rider(cockpit, Vector3.new(2, 2, 1.1), CF(SEAT, -1.8, 0.35), rgb(64, 84, 118), Enum.Material.Fabric)
	rider(cockpit, Vector3.new(1.5, 1.4, 0.4), CF(SEAT, 0.1, 1.15), rgb(30, 28, 27), Enum.Material.Leather)

	Stage.resetClock()
	local elapsed = 0
	local crashed = false
	local lurch = 0
	local glanceV = Stage.numberValue(0)
	Stage.track(function(dt)
		elapsed += dt
		local spot, dir, roll = pHit, dir0, 0
		if elapsed < T_HIT then
			spot, dir = lane(startAlong - SPEED * elapsed)
			cockpit.rpm = 0.45 + math.noise(elapsed * 2, 0.5) * 0.04
		else
			if lurch == 0 and not crashed then
				lurch = 1.4
			end
			local u = math.clamp((elapsed - T_HIT) / SPIN, 0, 1)
			local p = Stage.splineAt(shove, 1 - (1 - u) ^ 2)
			spot = Vector3.new(p.X, groundY(p.X, p.Z), p.Z)
			dir = CFrame.fromAxisAngle(UP, spinAngle * (1 - (1 - u) ^ 3)):VectorToWorldSpace(dir0)
			roll = math.sin(u * math.pi) * 0.16 * sideSign
			cockpit.steer = math.sin(elapsed * 22) * 0.6
			cockpit.speed = Util.lerp(0.55, 0, u)
			if u >= 1 and not crashed then
				crashed = true
				lurch = 1
			end
		end
		lurch = math.max(0, lurch - dt * 2.5)
		local frame = carFrame(spot, dir, roll)
		Cast.placeCockpit(cockpit, frame)
		local pose = truckPose(elapsed)
		placeTruck(pose)
		local eye = frame.Position
		local look = frame.LookVector
		if elapsed > T_HIT - 3.2 and elapsed < T_HIT then
			local toTruck = pose.Position + UP * 3 - eye
			look = look:Lerp(toTruck.Unit, Stage.smooth((elapsed - (T_HIT - 3.2)) / 1.4) * 0.6)
		end
		local cam = CFrame.lookAt(eye, eye + look, frame.UpVector) * ANG(0, glanceV.Value, 0)
		if lurch > 0 then
			cam = cam * CF(0.25 * lurch * sideSign, -0.15 * lurch, 0) * ANG(-0.2 * lurch, 0, 0.18 * lurch * sideSign)
		end
		return cam
	end)

	Stage.sway(0.25)
	Stage.fadeTo(0, 2.6)
	at(0.9)
	Util.tween(glanceV, 1, { Value = -1.2 })
	HUD.subtitle(passenger, "Okay, I'm officially starving. How far's the McDonald's?", 3.4)
	at(3.6)
	Util.tween(glanceV, 1, { Value = 0 })
	at(4.3)
	HUD.subtitle("You", "Sign said twelve miles. Twenty minutes, tops.", 3)
	at(7.4)
	HUD.subtitle(backSeat, "Twenty minutes? In THIS storm? We're gonna die out here for nuggets.", 3.6)
	at(10.2)
	HUD.subtitle(passenger, "Worth it. Totally worth it.", 1.4)
	at(T_HIT - 3.2)
	HUD.subtitle(passenger, "…hey. What's that? On the " .. sideWord .. "—", 1.7)
	at(T_HIT - 2.6)
	Effects.lightning() -- a dark pickup, rolling at you with no lights
	at(T_HIT - 1.5)
	HUD.subtitle(backSeat, "IT'S NOT STOPPING!", 1.4)
	at(T_HIT - 0.5)
	headlights(true)
	CameraController.shake(0.5, 3)
	Stage.sfx("EngineStart", nil, impactCenter, 1, 1.1)
	at(T_HIT)
	-- the T-bone
	Effects.flash(Color3.new(1, 1, 1), 0.5)
	CameraController.shake(3, 1.6)
	Stage.sfx("Crash", "Impact", nil, 1, 0.75)
	Stage.sfx("Scream", nil, nil, 0.45, 1.15)
	for _, p in cockpit.cracks do
		p.Transparency = 0.25
	end
	cockpit.glass.Transparency = 0.55
	headlights(false)
	local deadline = os.clock() + SPIN + 1.5
	while not crashed and os.clock() < deadline do
		sleep(0)
	end

	-- the pine: white flash, hard shake, black
	Stage.flashWhite(0.45)
	Effects.flash(Color3.new(1, 1, 1), 0.9)
	CameraController.shake(3.6, 1.3)
	Stage.sfx("Crash", "Impact", nil, 1, 0.5)
	sleep(0.16)
	Stage.setBlack(1)
	Stage.stopCamera()
	Stage.sway(0)
	cockpit.model.Parent = nil
	Stage.blur(22)
	Stage.zoom(70, 0)
	sleep(1.8)

	-- the wreck from outside: smoke, hazard lights, rain
	showWreck(true)
	local truckStop = truckPose(T_HIT + 1)
	placeTruck(truckStop)
	taillights(true)
	local _, roadPoint = Util.polylineClosest(road, Vector2.new(carCF.X, carCF.Z))
	local side = if (Vector3.new(roadPoint.X, carCF.Y, roadPoint.Y) - carCF.Position):Dot(carCF.RightVector) >= 0 then 1 else -1

	local smokePart = Stage.part(Vector3.one, carCF * CF(0, 3.4, -6), rgb(0, 0, 0), nil, { Transparency = 1 })
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

	Stage.cut(CFrame.lookAt(carCF * Vector3.new(side * 14, 2.4, 2), carCF * Vector3.new(0, 2.4, -2.5)), 55)
	Stage.blurTo(2, 2.5)
	Stage.fadeTo(0, 1.6)
	Stage.move(CFrame.lookAt(carCF * Vector3.new(side * 10.5, 1.9, 3), carCF * Vector3.new(0, 2.6, -2)), 3.6)
	Stage.later(1.6, function()
		sparks:Emit(14)
	end)
	sleep(3.4)

	-- reverse shot from beside the wreck: the pickup backs off into the rain
	local truckLook = truckStop.Position + UP * 3
	local lowEye = carCF * Vector3.new(side * 3.6, 2, 5.5)
	Stage.cut(CFrame.lookAt(lowEye, truckLook), 50)
	Stage.move(CFrame.lookAt(lowEye + UP * 0.3, truckLook + away * 10), 3.4)
	Stage.go(function()
		Stage.animate(3.4, function(a)
			placeTruck(truckAt(impactCenter - away * 3 + away * 24 * Stage.smooth(a)))
		end)
	end)
	Stage.later(1.2, Effects.lightning)
	sleep(2.6)
	Stage.fadeTo(1, 0.8)
	sleep(0.9)
	truck:Destroy()
	for _, l in lamps do
		l.part:Destroy()
	end

	-- inside the wreck: cracked glass, crumpled bonnet, flickering dash, blurred
	-- and blinking. The server sedan is hidden so any car model works here.
	Stage.hide(sedan)
	cockpit.model.Parent = Stage.folder()
	for _, item in cockpit.items do
		if table.find(cockpit.hood, item.part) then
			item.base = CF(0, 0.35, 0.6) * item.base * ANG(rad(14), rad(3), rad(-4))
		end
	end
	-- the friend in the passenger seat, slumped and out cold
	cockpit.items[headItem].base = CF(SEAT - 0.35, -0.75, -0.1) * ANG(rad(-25), 0, rad(28))
	cockpit.items[hairItem].base = CF(SEAT - 0.1, -0.2, -0.05) * ANG(rad(-25), 0, rad(28))
	cockpit.items[bodyItem].base = CF(SEAT - 0.1, -1.95, 0.2) * ANG(rad(-12), 0, rad(10))
	for _, l in cockpit.lights do
		l.Enabled = false
		local lamp = l.Parent
		if lamp and lamp:IsA("BasePart") then
			lamp.Material = Enum.Material.Glass
			lamp.Color = rgb(60, 60, 58)
		end
	end
	cockpit.steer = 0.35
	cockpit.speed = 0
	cockpit.rpm = 0
	Cast.setGauges(cockpit, false)
	Stage.eyes(0, 0)
	local doorV = Stage.numberValue(0)
	local yawV, pitchV, rollV = Stage.numberValue(0.15), Stage.numberValue(-0.42), Stage.numberValue(0.1)
	Stage.track(function()
		cockpit.door = doorV.Value
		Cast.placeCockpit(cockpit, eyeCF)
		return eyeCF * ANG(0, yawV.Value, 0) * ANG(pitchV.Value, 0, rollV.Value)
	end)
	Stage.zoom(70, 0)
	Stage.sway(1.4)
	Stage.blur(22)
	Stage.go(function()
		while true do
			Cast.setGauges(cockpit, math.random() < 0.35)
			sleep(0.08 + math.random() * 0.5)
		end
	end)

	-- Michel comes up from the road with a lantern, Jason behind him with a torch
	local doorSpot = eyeCF * Vector3.new(-3.3, 0, 0.5)
	local start = Stage.ground(carCF * Vector3.new(-4.5, 0, 17))
	local michel = Cast.actor("Michel", CFrame.lookAt(start, Vector3.new(doorSpot.X, start.Y, doorSpot.Z)), "HostTemplates")
	Cast.lantern(michel)
	local jasonStart = Stage.ground(carCF * Vector3.new(-8, 0, 21))
	local jasonSpot = Stage.ground(carCF * Vector3.new(-6.4, 0, 3.6))
	local jason = Cast.actor("Jason", CFrame.lookAt(jasonStart, jasonSpot), "HostTemplates")
	flashlight(jason)
	Stage.go(function()
		Cast.walk(michel, { doorSpot }, 3.7, { ground = true })
		Cast.face(michel, eyeCF.Position, 0.7)
	end)
	Stage.go(function()
		sleep(0.8)
		Cast.walk(jason, { jasonSpot }, 3.6, { ground = true })
		Cast.face(jason, eyeCF.Position, 0.8)
	end)

	Stage.resetClock()
	Stage.fadeTo(0, 0.3)
	at(0.7)
	Stage.eyes(0.3, 1.4)
	at(2)
	HUD.subtitle(backSeat, "…guys…? Is everyone okay…?", 2.6)
	at(2.6)
	Stage.eyes(0, 0.25)
	at(3.3)
	Stage.eyes(0.5, 0.8)
	Stage.blurTo(13, 3)
	at(4.4)
	HUD.subtitle("Michel", "Hello?! Anybody hurt in there?!", 2.4)
	at(5)
	-- head lolls toward the side window
	Util.tween(yawV, 2.2, { Value = 1.25 })
	Util.tween(pitchV, 2.2, { Value = -0.08 })
	Util.tween(rollV, 2.2, { Value = 0.05 })
	at(6.6)
	Stage.eyes(0, 0.22)
	at(7.1)
	Stage.eyes(0.6, 0.5)
	at(7.4)
	-- the door opens, the dome light comes on
	Util.tween(doorV, 0.9, { Value = -1.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	cockpit.dome.Enabled = true
	Stage.sfx("DoorOpen", nil, eyeCF.Position, 0.8, 0.8)
	at(7.9)
	HUD.subtitle("Michel", "Easy… easy now. We've got you.", 2.8)
	Cast.pose(michel, "waist", Cast.waist(michel, 0.4), 0.9)
	Cast.pose(michel, "neck", Cast.neck(michel, -0.3, 0, 0), 0.9)
	at(8.6)
	-- he reaches in, gently
	Stage.go(function()
		local from = michel.root.CFrame
		local toward = Util.flat(eyeCF.Position - from.Position)
		toward = if toward.Magnitude > 1e-3 then toward.Unit else Vector3.zero
		Stage.animate(1.2, function(a)
			michel.root.CFrame = from + toward * (1.2 * Stage.smooth(a))
		end)
	end)
	Cast.pose(michel, "rightShoulder", Cast.arm(michel, true, 1.35, 0.1), 1.1)
	Stage.zoom(58, 1.4)
	Util.tween(yawV, 1.2, { Value = 1.1 })
	at(10.2)
	Cast.pose(jason, "rightShoulder", Cast.arm(jason, true, 1.2, 0), 0.6)
	HUD.subtitle("Jason", "Get them out. The house isn't far.", 2.6)
	at(11.6)
	Stage.eyes(0, 0.5)
	sleep(0.5)
	Stage.fadeTo(1, 0.2)
	sleep(0.25)
	Stage.stopCamera()
	cockpit.model:Destroy()
	michel.model:Destroy()

	-- carried up the driveway in Michel's arms, Jason lighting the way
	local driveway = Config.Roads[2].points
	local pts: { Vector2 } = {}
	for i = #driveway, 1, -1 do
		table.insert(pts, driveway[i])
	end
	local CARRY_START, CARRY_LEN, CARRY_TIME = 4, 30, 9
	local thetaV = Stage.numberValue(1.15)
	Cast.pose(jason, "rightShoulder", Cast.arm(jason, true, 0.35, 0), 0)
	Cast.play(jason, "walk", 0.5)
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
		local pos = Vector3.new(p2.X, groundY(p2.X, p2.Y) + 4.3 + math.abs(stride) * 0.08, p2.Y)
		local th = thetaV.Value
		local look = d * math.cos(th) + UP * math.sin(th)
		local up = UP * math.cos(th) - d * math.sin(th)
		local j2 = Util.polylineSample(pts, s + 6.5)
		local jpos = Vector3.new(j2.X, groundY(j2.X, j2.Y), j2.Y) + UP * jason.lift
		jason.root.CFrame = CFrame.lookAt(jpos, jpos + d)
		return CFrame.lookAt(pos, pos + look, up) * ANG(stride * 0.012, 0, math.sin(carryElapsed * 3.6) * 0.035)
	end)
	Stage.resetClock()
	Stage.eyes(0, 0)
	Stage.blur(14)
	Stage.sway(0.6)
	Stage.zoom(70, 0)
	Stage.fadeTo(0, 0.6)
	at(0.6)
	Stage.eyes(0.45, 1.2)
	at(1.4)
	HUD.subtitle("Michel", "Shh… you're safe now.", 2.6)
	at(3.2)
	Stage.eyes(0, 0.3)
	at(3.7)
	Stage.eyes(0.55, 0.6)
	Util.tween(thetaV, 1.8, { Value = 0.3 })
	at(4.8)
	HUD.subtitle("Jason", "Your friends are right behind us. Don't you worry.", 3)
	at(7.3)
	HUD.subtitle("Michel", "Almost home.", 2)
	Stage.eyes(0, 1)
	at(8.6)
	Stage.fadeTo(1, 0.3)
	sleep(0.4)
	Stage.stopCamera()
	jason.model:Destroy()
	Stage.title("Hours later…", { font = Theme.Fonts.Type, size = 34, color = Theme.Colors.BoneDim, fadeIn = 1.2, hold = 1.8, fadeOut = 1 })
	sleep(4.2)
end)

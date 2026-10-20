--!strict
-- Crash (~40 s): night drive on the highway in heavy rain, a figure in the
-- headlights by the log, the swerve into the tree, the wreck from outside,
-- the Butcher at the driver's door, then dragged down the driveway.
-- data: { sedan: Model, tree: CFrame, trapLog: CFrame, house: CFrame }

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

return Stage.scene("Crash", function(data: any)
	local road = Config.Roads[1].points
	local site = Config.Sites.Crash.pos
	local tree = Stage.cf(data.tree, CF(site.X, groundY(site.X, site.Y + 6), site.Y + 6))
	local logCF = Stage.cf(data.trapLog, CF(site.X + 36, groundY(site.X + 36, site.Y - 12), site.Y - 12) * ANG(0, rad(78), 0))
	local sedan = Stage.model(data.sedan)
	local treePos = tree.Position

	Stage.setBlack(1)
	Stage.letterbox(true, 0)
	Effects.setRain(true, true)
	Stage.blur(0)
	Stage.cut(Stage.camCFrame(), 72)

	-- the route: west along the highway toward the log, then the swerve
	local SPEED = 60
	local LANE = 3.4
	local EYE = 3.9
	local APPROACH = 6.4
	local _, _, logAlong = Util.polylineClosest(road, Vector2.new(logCF.X, logCF.Z))
	local swerveAlong = logAlong + 34
	local startAlong = swerveAlong + SPEED * APPROACH

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

	local function carFrame(base: Vector3, dir: Vector3, yaw: number, roll: number): CFrame
		local f = base + dir * 4
		local b = base - dir * 4
		local pitch = math.atan2(groundY(f.X, f.Z, base.Y) - groundY(b.X, b.Z, base.Y), 8)
		local eye = base + UP * EYE
		return CFrame.lookAt(eye, eye + dir) * ANG(0, yaw, 0) * ANG(pitch, 0, roll)
	end

	-- swerve around the end of the log nearest the tree, then into the tree
	local p0, dir0 = lane(swerveAlong)
	local axis = logCF.RightVector
	local endA, endB = logCF.Position + axis * 15, logCF.Position - axis * 15
	local logEnd = if (endA - treePos).Magnitude < (endB - treePos).Magnitude then endA else endB
	local outward = Util.flat(logEnd - logCF.Position)
	outward = if outward.Magnitude > 1e-3 then outward.Unit else Vector3.new(0, 0, 1)
	local around = Util.flat(logEnd) + outward * 7.5
	local inDir = Util.flat(treePos) - around
	inDir = if inDir.Magnitude > 1e-3 then inDir.Unit else dir0
	local contact = Util.flat(treePos) - inDir * 8.6 - Vector3.new(-inDir.Z, 0, inDir.X) * 1.45
	local turn = if dir0:Cross(inDir).Y >= 0 then 1 else -1 -- 1 = swerving left
	local toAround = Util.flat(around - p0)
	local mid = Util.flat(p0) + dir0 * 14 + (if toAround.Magnitude > 1e-3 then toAround.Unit else dir0) * 2.5
	local swerve = Stage.spline({ Util.flat(p0), mid, around, contact })
	local V1 = 40
	local swerveTime = 2 * swerve.total / (SPEED + V1)
	local decel = (V1 - SPEED) / swerveTime

	-- the figure in the headlights, lantern raised
	local figurePos = lane(logAlong) - dir0 * 2.6
	local figure = Cast.actor("Hunter", CFrame.lookAt(figurePos, figurePos - dir0))
	Cast.play(figure, "idle")
	Cast.pose(figure, "leftShoulder", Cast.arm(figure, false, 1.05, 0.1), 0)
	Cast.pose(figure, "neck", Cast.neck(figure, -0.05, 0, 0.22), 0)
	local figureHead = figurePos + UP * 5.4

	local cockpit = Cast.buildCockpit(6.2, rgb(32, 40, 66))
	Cast.setGauges(cockpit, true)
	cockpit.speed = 0.62
	cockpit.rpm = 0.45

	Stage.resetClock()
	local elapsed = 0
	local crashed = false
	local lurch = 0
	Stage.track(function(dt)
		elapsed += dt
		local spot, dir, yaw, roll = p0, dir0, 0, 0
		if elapsed < APPROACH then
			spot, dir = lane(startAlong - SPEED * elapsed)
			cockpit.rpm = 0.45 + math.noise(elapsed * 2, 0.5) * 0.04
		else
			local t = elapsed - APPROACH
			local s = math.min(SPEED * t + 0.5 * decel * t * t, swerve.total)
			local prog = if swerve.total > 0 then s / swerve.total else 1
			local pos = Stage.splineAt(swerve, prog)
			local d = Stage.splineAt(swerve, math.min(prog + 0.03, 1)) - Stage.splineAt(swerve, math.max(prog - 0.03, 0))
			dir = if d.Magnitude > 1e-3 then d.Unit else dir0
			spot = Vector3.new(pos.X, groundY(pos.X, pos.Z), pos.Z)
			local slide = math.sin(prog * math.pi)
			yaw = turn * slide * 0.4
			roll = -turn * slide * 0.08
			cockpit.steer = -turn * math.min(1, prog * 3)
			cockpit.speed = Util.lerp(0.62, 0.42, prog)
			cockpit.rpm = 0.8
			if prog >= 1 and not crashed then
				crashed = true
				lurch = 1
			end
		end
		lurch = math.max(0, lurch - dt * 2.5)
		local frame = carFrame(spot, dir, yaw, roll)
		Cast.placeCockpit(cockpit, frame)
		local eye = frame.Position
		local toFigure = figureHead - eye
		local k = if elapsed < APPROACH + 0.6 then Stage.smooth((110 - toFigure.Magnitude) / 80) * 0.35 else 0
		local look = frame.LookVector:Lerp(toFigure.Unit, k)
		local cam = CFrame.lookAt(eye, eye + look, frame.UpVector) * ANG(0, -yaw * 0.45, 0)
		if lurch > 0 then
			cam = cam * CF(0, -0.2 * lurch, -0.5 * lurch) * ANG(-0.35 * lurch, 0, 0.1 * lurch)
		end
		return cam
	end)

	Stage.sway(0.25)
	Stage.fadeTo(0, 2.6)
	at(0.9)
	HUD.subtitle("You", "Two more hours to Pinecrest… and not one gas station out here.", 3.6)
	at(2.8)
	Effects.lightning()
	at(4.5)
	HUD.subtitle("You", "Wait… is someone standing in the road?!", 2.2)
	Stage.zoom(60, 1.6)
	at(APPROACH)
	CameraController.shake(1.1, 2.5)
	HUD.subtitle("You", "WHOA—!", 1.6)
	Stage.sfx("Whoosh", nil, nil, 0.6, 0.6)
	Stage.go(function()
		Cast.face(figure, Util.flat(treePos) + UP * figurePos.Y, 1.4)
	end)
	local deadline = os.clock() + swerveTime + 1.5
	while not crashed and os.clock() < deadline do
		sleep(0)
	end

	-- impact: white flash, hard shake, black
	Stage.flashWhite(0.45)
	Effects.flash(Color3.new(1, 1, 1), 0.9)
	CameraController.shake(3.6, 1.3)
	Stage.sfx("Crash", "Impact", nil, 1, 0.5)
	sleep(0.16)
	Stage.setBlack(1)
	Stage.stopCamera()
	Stage.sway(0)
	figure.model:Destroy()
	cockpit.model.Parent = nil
	Stage.blur(22)
	Stage.zoom(70, 0)
	sleep(1.8)

	-- the wreck from outside: smoke, hazard lights, rain
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
		local base = Stage.ground(contact)
		carCF = CFrame.lookAt(base, Vector3.new(treePos.X, base.Y, treePos.Z))
		eyeCF = carCF * CF(-1.45, 4.1, 0) * ANG(rad(-5), 0, rad(5))
	end
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
	Stage.fadeTo(0, 2)
	Stage.move(CFrame.lookAt(carCF * Vector3.new(side * 9.5, 1.7, 3), carCF * Vector3.new(0, 2.6, -2)), 6.6)
	Stage.later(2.4, function()
		sparks:Emit(14)
	end)
	Stage.later(3.4, Effects.lightning)
	sleep(5.3)
	Stage.fadeTo(1, 1.2)
	sleep(1.3)

	-- inside the wreck: cracked glass, crumpled bonnet, flickering dash, blurred
	-- and blinking. The server sedan is hidden so any car model works here.
	Stage.hide(sedan)
	cockpit.model.Parent = Stage.folder()
	for _, item in cockpit.items do
		if table.find(cockpit.hood, item.part) then
			item.base = CF(0, 0.35, 0.6) * item.base * ANG(rad(14), rad(3), rad(-4))
		end
	end
	for _, l in cockpit.lights do
		l.Enabled = false
		local lamp = l.Parent
		if lamp and lamp:IsA("BasePart") then
			lamp.Material = Enum.Material.Glass
			lamp.Color = rgb(60, 60, 58)
		end
	end
	for _, p in cockpit.cracks do
		p.Transparency = 0.25
	end
	cockpit.glass.Transparency = 0.55
	cockpit.glass.Color = rgb(205, 212, 216)
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

	-- the Butcher walks up from behind the car to the driver's door
	local doorSpot = eyeCF * Vector3.new(-3.3, 0, 0.5)
	local start = Stage.ground(carCF * Vector3.new(-4.5, 0, 17))
	local butcher = Cast.actor("Butcher", CFrame.lookAt(start, Vector3.new(doorSpot.X, start.Y, doorSpot.Z)))
	Stage.go(function()
		Cast.walk(butcher, { doorSpot }, 3.7, { ground = true })
		Cast.face(butcher, eyeCF.Position, 0.7)
	end)

	Stage.resetClock()
	Stage.fadeTo(0, 0.3)
	at(0.7)
	Stage.eyes(0.3, 1.4)
	at(2.5)
	Stage.eyes(0, 0.25)
	at(3.25)
	Stage.eyes(0.5, 0.8)
	Stage.blurTo(13, 3)
	at(3.4)
	-- head lolls toward the side window
	Util.tween(yawV, 2.2, { Value = 1.25 })
	Util.tween(pitchV, 2.2, { Value = -0.08 })
	Util.tween(rollV, 2.2, { Value = 0.05 })
	at(6.2)
	Cast.pose(butcher, "waist", Cast.waist(butcher, 0.45), 0.9)
	Cast.pose(butcher, "neck", Cast.neck(butcher, -0.35, 0, 0.15), 0.9)
	at(6.6)
	Stage.eyes(0, 0.22)
	at(7.1)
	Stage.eyes(0.6, 0.5)
	at(7.4)
	-- the door opens, the dome light comes on
	Util.tween(doorV, 0.9, { Value = -1.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	cockpit.dome.Enabled = true
	Stage.sfx("DoorOpen", nil, eyeCF.Position, 0.8, 0.8)
	at(7.8)
	HUD.subtitle("You", "…no… stop…", 2.8)
	at(8.2)
	-- he reaches in
	Stage.go(function()
		local from = butcher.root.CFrame
		local toward = Util.flat(eyeCF.Position - from.Position)
		toward = if toward.Magnitude > 1e-3 then toward.Unit else Vector3.zero
		Stage.animate(1.2, function(a)
			butcher.root.CFrame = from + toward * (1.5 * Stage.smooth(a))
		end)
	end)
	Cast.pose(butcher, "leftShoulder", Cast.arm(butcher, false, 1.45, -0.15), 1.1)
	Stage.zoom(56, 1.4)
	Util.tween(yawV, 1.2, { Value = 1.1 })
	Util.tween(rollV, 1.2, { Value = -0.1 })
	at(9.4)
	Stage.eyes(0, 0.35)
	sleep(0.35)
	Stage.fadeTo(1, 0.15)
	sleep(0.2)
	Stage.stopCamera()
	cockpit.model:Destroy()

	-- dragged by the ankles down the driveway, looking up at the trees
	local driveway = Config.Roads[2].points
	local pts: { Vector2 } = {}
	for i = #driveway, 1, -1 do
		table.insert(pts, driveway[i])
	end
	local DRAG_START, DRAG_LEN, DRAG_TIME = 5, 24, 8
	local thetaV = Stage.numberValue(1.2)
	Cast.pose(butcher, "neck", CFrame.identity, 0)
	Cast.pose(butcher, "waist", Cast.waist(butcher, 0.12), 0)
	Cast.pose(butcher, "leftShoulder", Cast.arm(butcher, false, -0.45, 0.15), 0)
	Cast.pose(butcher, "rightShoulder", Cast.arm(butcher, true, -0.45, 0.15), 0)
	Cast.play(butcher, "walk", 0.38)
	local dragElapsed = 0
	Stage.track(function(dt)
		dragElapsed += dt
		local prog = math.clamp(dragElapsed / DRAG_TIME, 0, 1)
		local tug = math.sin(prog * math.pi * 14)
		local s = DRAG_START + DRAG_LEN * (prog + tug * 0.012)
		local p2 = Util.polylineSample(pts, s)
		local d2 = Util.polylineSample(pts, s + 3) - Util.polylineSample(pts, math.max(s - 3, 0))
		d2 = if d2.Magnitude > 1e-3 then d2.Unit else Vector2.new(0, 1)
		local d = Vector3.new(d2.X, 0, d2.Y)
		local pos = Vector3.new(p2.X, groundY(p2.X, p2.Y) + 0.85, p2.Y)
		local th = thetaV.Value
		local look = d * math.cos(th) + UP * math.sin(th)
		local up = UP * math.cos(th) - d * math.sin(th)
		local b2 = Util.polylineSample(pts, s + 5.4)
		local bpos = Vector3.new(b2.X, groundY(b2.X, b2.Y), b2.Y) + UP * butcher.lift
		butcher.root.CFrame = CFrame.lookAt(bpos, bpos + d)
		return CFrame.lookAt(pos, pos + look, up) * ANG(tug * 0.015, 0, math.sin(dragElapsed * 0.9) * 0.06)
	end)
	Stage.resetClock()
	Stage.eyes(0, 0)
	Stage.blur(14)
	Stage.sway(0.6)
	Stage.zoom(70, 0)
	Stage.fadeTo(0, 0.6)
	at(0.5)
	Stage.eyes(0.45, 1.2)
	at(1.8)
	Util.tween(thetaV, 1.4, { Value = 1.02 })
	at(2.6)
	Stage.eyes(0, 0.3)
	at(3.1)
	Stage.eyes(0.55, 0.6)
	at(3.5)
	Util.tween(thetaV, 1.6, { Value = 0.36 })
	at(4)
	HUD.subtitle("You", "…please…", 2.6)
	at(6.3)
	Util.tween(thetaV, 1.4, { Value = 0.9 })
	at(7)
	Stage.eyes(0, 0.9)
	at(7.9)
	Stage.fadeTo(1, 0.3)
	sleep(0.4)
	Stage.stopCamera()
	butcher.model:Destroy()
	Stage.title("Hours later…", { font = Theme.Fonts.Type, size = 34, color = Theme.Colors.BoneDim, fadeIn = 1.2, hold = 1.8, fadeOut = 1 })
	sleep(4.2)
end)

--!strict
-- Local actors and vehicles for the scenes: cannibal clones with joint
-- posing (works on R15 and R6 rigs), hand-moved walking, the cleaver chop,
-- lanterns, a driver's-eye car cockpit and simple stand-in vehicles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Shared.Util)
local CameraController = require(script.Parent.Parent.CameraController)
local Stage = require(script.Parent.Stage)

local Cast = {}

local rgb = Color3.fromRGB
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local UP = Vector3.yAxis
local part = Stage.part

local ANIMS: { [string]: { [string]: string } } = {
	R15 = {
		idle = "rbxassetid://507766666",
		walk = "rbxassetid://507777826",
		slash = "rbxassetid://522635514",
	},
	R6 = {
		idle = "rbxassetid://180435571",
		walk = "rbxassetid://180426354",
		slash = "rbxassetid://129967390",
	},
}

local JOINTS: { [string]: { string } } = {
	rightShoulder = { "RightShoulder", "Right Shoulder" },
	leftShoulder = { "LeftShoulder", "Left Shoulder" },
	neck = { "Neck" },
	waist = { "Waist", "RootJoint" },
}

---------------------------------------------------------------- actors

export type Actor = {
	model: Model,
	root: BasePart,
	lift: number, -- root height above the floor
	r15: boolean,
	tracks: { [string]: AnimationTrack },
	motors: { [string]: Motor6D },
	rest: { [string]: CFrame },
}

-- Stand-in used if the server templates never arrive.
local function fallbackFigure(): Model
	local m = Instance.new("Model")
	m.Name = "Figure"
	local root = part(Vector3.new(2, 2, 1), CF(0, 3, 0), rgb(0, 0, 0), nil, { Transparency = 1, Name = "HumanoidRootPart" })
	root.Parent = m
	local function limb(size: Vector3, cf: CFrame, color: Color3, name: string)
		local p = part(size, cf, color, Enum.Material.Fabric, { Name = name })
		p.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = m
	end
	limb(Vector3.new(2, 2, 1), CF(0, 3, 0), rgb(84, 70, 56), "Torso")
	limb(Vector3.new(0.9, 2, 0.9), CF(-0.5, 1, 0), rgb(44, 42, 40), "Left Leg")
	limb(Vector3.new(0.9, 2, 0.9), CF(0.5, 1, 0), rgb(44, 42, 40), "Right Leg")
	limb(Vector3.new(0.9, 2, 0.9), CF(-1.5, 3, 0), rgb(196, 162, 140), "Left Arm")
	limb(Vector3.new(0.9, 2, 0.9), CF(1.5, 3, 0), rgb(196, 162, 140), "Right Arm")
	limb(Vector3.new(1.3, 1.4, 1.3), CF(0, 4.75, 0), rgb(138, 112, 78), "Head")
	m.PrimaryPart = root
	return m
end

-- Local clone of a cannibal standing on floorCF (feet level). The root is
-- anchored and moved by hand; animations and joint poses do the rest.
function Cast.actor(kind: string, floorCF: CFrame): Actor
	local templates = ReplicatedStorage:FindFirstChild("CannibalTemplates") or ReplicatedStorage:WaitForChild("CannibalTemplates", 5)
	local template = templates and templates:FindFirstChild(kind)
	local model = if template and template:IsA("Model") then template:Clone() else fallbackFigure()
	local found = model:FindFirstChild("HumanoidRootPart")
	if not (found and found:IsA("BasePart")) then
		model:Destroy()
		model = fallbackFigure()
		found = model:FindFirstChild("HumanoidRootPart")
	end
	local root = found :: BasePart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = d == root
		end
	end

	local bbCF, bbSize = model:GetBoundingBox()
	local lift = root.Position.Y - (bbCF.Position.Y - bbSize.Y / 2)
	local look = Util.flat(floorCF.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local rootPos = floorCF.Position + UP * lift
	model:PivotTo(CFrame.lookAt(rootPos, rootPos + look) * root.CFrame:ToObjectSpace(model:GetPivot()))

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local r15 = false
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		pcall(function()
			(humanoid :: any).EvaluateStateMachine = false
		end)
		r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	end
	model.Parent = Stage.folder()

	local tracks: { [string]: AnimationTrack } = {}
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			local created = Instance.new("Animator")
			created.Parent = humanoid
			animator = created
		end
		for name, id in ANIMS[if r15 then "R15" else "R6"] do
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, loaded = pcall(function()
				return (animator :: Animator):LoadAnimation(anim)
			end)
			if ok and loaded then
				loaded.Priority = if name == "slash"
					then Enum.AnimationPriority.Action
					elseif name == "walk" then Enum.AnimationPriority.Movement
					else Enum.AnimationPriority.Idle
				loaded.Looped = name ~= "slash"
				tracks[name] = loaded
			end
		end
	end

	local motors: { [string]: Motor6D } = {}
	local rest: { [string]: CFrame } = {}
	for key, names in JOINTS do
		for _, n in names do
			local m = model:FindFirstChild(n, true)
			if m and m:IsA("Motor6D") then
				motors[key] = m
				rest[key] = m.C0
				break
			end
		end
	end

	return { model = model, root = root, lift = lift, r15 = r15, tracks = tracks, motors = motors, rest = rest }
end

function Cast.play(actor: Actor, name: string, speed: number?)
	local chosen = actor.tracks[name]
	if not chosen then
		return
	end
	for other, t in actor.tracks do
		if other ~= name and other ~= "slash" and t.IsPlaying then
			t:Stop(0.25)
		end
	end
	if not chosen.IsPlaying then
		chosen:Play(0.25)
	end
	chosen:AdjustSpeed(speed or 1)
end

-- Joint offsets that read the same on R15 and R6 rigs.
-- raise > 0 lifts the arm forward, out > 0 swings it away from the body.
function Cast.arm(actor: Actor, right: boolean, raise: number, out: number?): CFrame
	local o = out or 0
	if actor.r15 then
		return ANG(raise, 0, if right then o else -o)
	end
	return ANG(-o, 0, if right then raise else -raise)
end

-- pitch > 0 looks up, yaw > 0 turns left
function Cast.neck(actor: Actor, pitch: number, yaw: number, roll: number): CFrame
	if actor.r15 then
		return ANG(pitch, yaw, roll)
	end
	return ANG(-pitch, roll, yaw)
end

-- lean > 0 bends forward
function Cast.waist(actor: Actor, lean: number, twist: number?): CFrame
	if actor.r15 then
		return ANG(-lean, twist or 0, 0)
	end
	return ANG(lean, 0, twist or 0)
end

function Cast.pose(actor: Actor, joint: string, offset: CFrame, duration: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local motor = actor.motors[joint]
	if not motor then
		return
	end
	local target = actor.rest[joint] * offset
	if duration <= 0 then
		motor.C0 = target
	else
		Util.tween(motor, duration, { C0 = target }, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.InOut)
	end
end

function Cast.head(actor: Actor): Vector3
	local head = actor.model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return actor.root.Position + UP * 2
end

-- Turns the actor in place to face a point (yields).
function Cast.face(actor: Actor, point: Vector3, duration: number)
	local from = actor.root.CFrame
	local pos = from.Position
	local flat = Vector3.new(point.X, pos.Y, point.Z)
	if (flat - pos).Magnitude < 0.05 then
		return
	end
	local to = CFrame.lookAt(pos, flat)
	Stage.animate(duration, function(a)
		actor.root.CFrame = from:Lerp(to, Stage.smooth(a))
	end)
end

export type WalkOptions = { ground: boolean?, onPoint: ((index: number) -> ())?, anim: number? }

-- Walks through floor-level points at a fixed speed (yields).
function Cast.walk(actor: Actor, points: { Vector3 }, speed: number, opts: WalkOptions?)
	local o: WalkOptions = opts or {}
	Cast.play(actor, "walk", o.anim or math.clamp(speed / 11, 0.35, 1.6))
	local pos = actor.root.Position - UP * actor.lift
	local heading = Util.flat(actor.root.CFrame.LookVector)
	heading = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.new(0, 0, -1)
	for i, target in points do
		local goal = if o.ground then Stage.ground(target) else target
		while true do
			local dt = task.wait()
			Stage.check()
			local delta = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
			local dist = delta.Magnitude
			local step = speed * dt
			local dir = if dist > 1e-3 then delta / dist else heading
			if dist <= step then
				pos = goal
			else
				pos += dir * step
				local y = if o.ground then Stage.groundY(pos.X, pos.Z, pos.Y) else Util.lerp(pos.Y, goal.Y, math.min(1, step / dist))
				pos = Vector3.new(pos.X, y, pos.Z)
			end
			local blended = heading:Lerp(dir, math.min(1, dt * 7))
			if blended.Magnitude > 1e-3 then
				heading = blended.Unit
			end
			local rootPos = pos + UP * actor.lift
			actor.root.CFrame = CFrame.lookAt(rootPos, rootPos + heading)
			if dist <= step then
				break
			end
		end
		if o.onPoint then
			o.onPoint(i)
		end
	end
	Cast.play(actor, "idle")
end

-- Shoulders shaking with laughter (yields).
function Cast.laugh(actor: Actor, duration: number)
	local t = 0
	Stage.animate(duration, function(_, dt)
		t += dt
		local k = math.sin(t * 24) * 0.5 + 0.5
		Cast.pose(actor, "waist", Cast.waist(actor, 0.08 + k * 0.07), 0)
		Cast.pose(actor, "neck", Cast.neck(actor, 0.14 * k - 0.04, 0, 0), 0)
	end)
	Cast.pose(actor, "waist", CFrame.identity, 0.3)
	Cast.pose(actor, "neck", CFrame.identity, 0.3)
end

-- One cleaver swing down onto the table (yields, about 1.3 s).
function Cast.chop(actor: Actor, target: Vector3)
	Cast.pose(actor, "rightShoulder", Cast.arm(actor, true, 2.9, 0.15), 0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Cast.pose(actor, "waist", Cast.waist(actor, -0.1), 0.42)
	Stage.sleep(0.46)
	Cast.pose(actor, "rightShoulder", Cast.arm(actor, true, 0.55, 0.05), 0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Cast.pose(actor, "waist", Cast.waist(actor, 0.3), 0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Stage.sleep(0.11)
	Stage.sfx("Chop", "Impact", target, 0.9, 0.62 + math.random() * 0.1)
	CameraController.shake(0.3, 6)
	Stage.sleep(0.32)
	Cast.pose(actor, "rightShoulder", Cast.arm(actor, true, 0.25, 0), 0.5)
	Cast.pose(actor, "waist", Cast.waist(actor, 0.12), 0.5)
	Stage.sleep(0.5)
end

-- A lit lantern welded into the actor's left hand.
function Cast.lantern(actor: Actor)
	local hand = actor.model:FindFirstChild("LeftHand") or actor.model:FindFirstChild("Left Arm")
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local base = hand.CFrame * CF(0, -hand.Size.Y / 2 - 0.85, 0)
	local metal = rgb(40, 40, 36)
	local glass = part(Vector3.new(0.45, 0.6, 0.45), base, rgb(255, 180, 100), Enum.Material.Neon, { Transparency = 0.25 })
	local pieces = {
		glass,
		part(Vector3.new(0.6, 0.15, 0.6), base * CF(0, 0.37, 0), metal, Enum.Material.Metal),
		part(Vector3.new(0.6, 0.15, 0.6), base * CF(0, -0.37, 0), metal, Enum.Material.Metal),
		part(Vector3.new(0.05, 0.45, 0.05), base * CF(0, 0.65, 0), metal, Enum.Material.Metal),
	}
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 160, 80)
	light.Brightness = 1.6
	light.Range = 16
	light.Shadows = true
	light.Parent = glass
	for _, p in pieces do
		p.Anchored = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = p
		weld.Parent = p
		p.Parent = actor.model
	end
end

---------------------------------------------------------------- vehicles

type CockpitItem = { part: BasePart, base: CFrame, group: string }

-- Driver's-eye car interior. Every part is placed relative to the eye each
-- frame; groups let the wheel, door and needles move.
export type Cockpit = {
	model: Model,
	items: { CockpitItem },
	parts: { BasePart },
	frames: { CFrame },
	anchors: { [string]: CFrame },
	gauges: { BasePart },
	warnings: { BasePart },
	warningColors: { Color3 },
	lights: { SpotLight },
	hood: { BasePart },
	cracks: { BasePart },
	glass: BasePart,
	glow: PointLight,
	dome: PointLight,
	steer: number,
	speed: number,
	rpm: number,
	door: number,
}

-- hood: paint colour for a bonnet with headlights in front of the dash
function Cast.buildCockpit(width: number, hoodPaint: Color3): Cockpit
	local model = Instance.new("Model")
	model.Name = "Cockpit"
	model.Parent = Stage.folder()
	local items: { CockpitItem } = {}
	local cx = width * 0.23 -- car centre, right of the driver's eye
	local lx, rx = cx - width / 2 + 0.25, cx + width / 2 - 0.25
	local dash = rgb(26, 24, 23)
	local trim = rgb(40, 37, 34)
	local frameColor = rgb(34, 32, 30)
	local anchors: { [string]: CFrame } = {
		wheel = CF(0, -1.2, -1.45) * ANG(rad(-25), 0, 0),
		door = CF(lx - 0.1, 0, -1.6),
		speed = CF(-0.42, -1, -1.855),
		rpm = CF(0.42, -1, -1.855),
	}

	local function add(group: string, size: Vector3, base: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
		local p = part(size, base, color, material, props)
		p.Parent = model
		table.insert(items, { part = p :: BasePart, base = base, group = group })
		return p
	end
	local function beam(a: Vector3, b: Vector3, thickness: number)
		add("static", Vector3.new(thickness, thickness, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), frameColor)
	end
	local function doorPart(size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?, props: { [string]: any }?)
		add("door", size, CF(pos - anchors.door.Position), color, material, props)
	end

	-- dashboard, gauges and warning lamps
	add("static", Vector3.new(width - 0.5, 0.95, 1.3), CF(cx, -1.32, -2.55), dash)
	add("static", Vector3.new(width - 0.5, 0.14, 1.6), CF(cx, -0.82, -2.6) * ANG(rad(-6), 0, 0), trim, Enum.Material.Leather)
	local visor = add("static", Vector3.new(1.9, 0.12, 0.5), CF(0, -0.68, -1.95), dash)
	local gauges: { BasePart } = {}
	for _, x in { -0.42, 0.42 } do
		table.insert(gauges, add("static", Vector3.new(0.04, 0.5, 0.5), CF(x, -1, -1.88) * ANG(0, rad(90), 0), rgb(25, 45, 35), Enum.Material.Neon, {
			Shape = Enum.PartType.Cylinder,
			Transparency = 0.5,
		}))
	end
	for _, group in { "speed", "rpm" } do
		add(group, Vector3.new(0.035, 0.2, 0.02), CF(0, 0.08, 0), rgb(255, 110, 40), Enum.Material.Neon)
	end
	local warnings: { BasePart } = {}
	local warningColors = { rgb(255, 40, 30), rgb(255, 170, 40), rgb(255, 40, 30) }
	for i = 1, 3 do
		table.insert(warnings, add("static", Vector3.new(0.09, 0.07, 0.02), CF(-0.12 + (i - 1) * 0.12, -0.9, -1.87), rgb(40, 14, 12)))
	end
	local glow = Instance.new("PointLight")
	glow.Range = 3.5
	glow.Brightness = 0.6
	glow.Color = rgb(120, 220, 170)
	glow.Enabled = false
	glow.Parent = visor

	-- steering wheel (rim segments, hub, spokes) and column
	local rimRadius = 0.72
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		add("wheel", Vector3.new(2 * math.pi * rimRadius / 14 + 0.03, 0.11, 0.13), ANG(0, 0, a) * CF(0, rimRadius, 0), rgb(22, 21, 20), Enum.Material.Leather)
	end
	add("wheel", Vector3.new(0.44, 0.34, 0.16), CF(0, -0.05, -0.02), rgb(30, 29, 28))
	for _, side in { -1, 1 } do
		add("wheel", Vector3.new(0.6, 0.09, 0.07), CF(side * 0.42, -0.08, 0), trim)
	end
	add("static", Vector3.new(0.22, 0.22, 0.9), CF(0, -1.42, -1.9) * ANG(rad(-25), 0, 0), dash)

	-- pillars, roof and windscreen
	beam(Vector3.new(lx, -0.85, -2), Vector3.new(lx + 0.1, 1.02, -0.95), 0.24)
	beam(Vector3.new(rx, -0.85, -2), Vector3.new(rx - 0.1, 1.02, -0.95), 0.24)
	beam(Vector3.new(lx + 0.1, 1.02, -0.95), Vector3.new(rx - 0.1, 1.02, -0.95), 0.2)
	beam(Vector3.new(lx - 0.05, -0.5, 1.7), Vector3.new(lx + 0.05, 1.02, 1.55), 0.26)
	beam(Vector3.new(rx + 0.05, -0.5, 1.7), Vector3.new(rx - 0.05, 1.02, 1.55), 0.26)
	local roof = add("static", Vector3.new(width - 0.3, 0.14, 3.4), CF(cx, 1.02, 0.75), rgb(64, 60, 55), Enum.Material.Fabric)
	local glassCF = CF(cx, 0.085, -1.48) * ANG(rad(29), 0, 0)
	local glass = add("static", Vector3.new(rx - lx, 2.14, 0.03), glassCF, rgb(160, 180, 190), Enum.Material.Glass, { Transparency = 0.9 })
	local cracks: { BasePart } = {}
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + 0.3
		local len = 0.5 + (i % 3) * 0.3
		table.insert(cracks, add("static", Vector3.new(0.02, len, 0.01), glassCF * CF(1.2, 0.2, 0.03) * ANG(0, 0, a) * CF(0, len / 2, 0), rgb(225, 230, 235), Enum.Material.SmoothPlastic, {
			Transparency = 1,
		}))
	end
	local dome = Instance.new("PointLight")
	dome.Range = 7
	dome.Brightness = 1.1
	dome.Color = rgb(255, 214, 160)
	dome.Shadows = true
	dome.Enabled = false
	dome.Parent = roof

	-- doors: the driver's door swings on its front edge
	local doorColor = rgb(48, 44, 40)
	local sideGlass = rgb(150, 170, 180)
	doorPart(Vector3.new(0.16, 1.45, 3.2), Vector3.new(lx - 0.1, -1.1, 0), doorColor, Enum.Material.Leather)
	doorPart(Vector3.new(0.3, 0.1, 3.2), Vector3.new(lx - 0.05, -0.35, 0), frameColor)
	doorPart(Vector3.new(0.03, 1.2, 3), Vector3.new(lx - 0.12, 0.35, 0.05), sideGlass, Enum.Material.Glass, { Transparency = 0.88 })
	add("static", Vector3.new(0.16, 1.45, 3.2), CF(rx + 0.1, -1.1, 0), doorColor, Enum.Material.Leather)
	add("static", Vector3.new(0.3, 0.1, 3.2), CF(rx + 0.05, -0.35, 0), frameColor)
	add("static", Vector3.new(0.03, 1.2, 3), CF(rx + 0.12, 0.35, 0.05), sideGlass, Enum.Material.Glass, { Transparency = 0.88 })

	-- console, mirror, a cardboard pine air freshener
	add("static", Vector3.new(0.9, 0.5, 2.6), CF(cx, -1.8, -0.6), dash)
	add("static", Vector3.new(0.85, 0.24, 0.06), CF(cx, 0.72, -1.05) * ANG(rad(8), rad(-12), 0), rgb(20, 20, 20))
	add("static", Vector3.new(0.16, 0.24, 0.02), CF(cx, 0.42, -1.08), rgb(40, 120, 60))

	-- bonnet and headlights
	local hood: { BasePart } = {
		add("static", Vector3.new(width - 0.4, 0.25, 4.6), CF(cx, -1.62, -4.6) * ANG(rad(-5), 0, 0), hoodPaint, Enum.Material.Metal),
		add("static", Vector3.new(width, 0.9, 0.35), CF(cx, -2, -6.95), hoodPaint, Enum.Material.Metal),
	}
	local lights: { SpotLight } = {}
	for _, x in { cx - width * 0.36, cx + width * 0.36 } do
		local lamp = add("static", Vector3.new(0.9, 0.32, 0.08), CF(x, -1.9, -7.15), rgb(255, 244, 220), Enum.Material.Neon)
		table.insert(hood, lamp)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 50
		spot.Range = 70
		spot.Brightness = 5
		spot.Shadows = true
		spot.Color = rgb(255, 238, 210)
		spot.Parent = lamp
		table.insert(lights, spot)
	end

	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for i, item in items do
		parts[i] = item.part
		frames[i] = item.base
	end
	return {
		model = model,
		items = items,
		parts = parts,
		frames = frames,
		anchors = anchors,
		gauges = gauges,
		warnings = warnings,
		warningColors = warningColors,
		lights = lights,
		hood = hood,
		cracks = cracks,
		glass = glass,
		glow = glow,
		dome = dome,
		steer = 0,
		speed = 0,
		rpm = 0,
		door = 0,
	}
end

function Cast.placeCockpit(c: Cockpit, eye: CFrame)
	local groups: { [string]: CFrame } = {
		static = eye,
		wheel = eye * c.anchors.wheel * ANG(0, 0, -c.steer * 1.5),
		door = eye * c.anchors.door * ANG(0, c.door, 0),
		speed = eye * c.anchors.speed * ANG(0, 0, 2.3 - math.clamp(c.speed, 0, 1) * 4.4),
		rpm = eye * c.anchors.rpm * ANG(0, 0, 2.3 - math.clamp(c.rpm, 0, 1) * 4.4),
	}
	for i, item in c.items do
		c.frames[i] = groups[item.group] * item.base
	end
	workspace:BulkMoveTo(c.parts, c.frames, Enum.BulkMoveMode.FireCFrameChanged)
end

function Cast.setGauges(c: Cockpit, on: boolean)
	for _, g in c.gauges do
		g.Color = if on then rgb(110, 230, 170) else rgb(25, 45, 35)
		g.Transparency = if on then 0.2 else 0.5
	end
	c.glow.Enabled = on
end

function Cast.setWarnings(c: Cockpit, on: boolean)
	for i, w in c.warnings do
		w.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		w.Color = if on then c.warningColors[i] else rgb(40, 14, 12)
	end
end

-- Stand-in truck if the server one is missing (front faces -Z, pivot at the
-- bottom centre like Props.PickupTruck).
function Cast.simpleTruck(): Model
	local m = Instance.new("Model")
	m.Name = "PickupTruck"
	local paint = rgb(122, 40, 32)
	local function add(size: Vector3, cf: CFrame, color: Color3, name: string?)
		local p = part(size, cf, color, Enum.Material.CorrodedMetal, { Name = name or "Part" })
		p.Parent = m
	end
	add(Vector3.new(6.6, 1.2, 17), CF(0, 2, 0), rgb(30, 28, 26))
	add(Vector3.new(7, 2.2, 6.2), CF(0, 3.5, -5.4), paint, "Hood")
	add(Vector3.new(7, 4.4, 4.2), CF(0, 4.6, -0.4), paint, "Cab")
	add(Vector3.new(7, 0.3, 4.4), CF(0, 6.9, -0.4), paint)
	add(Vector3.new(7, 2.6, 7.4), CF(0, 3.4, 6.2), rgb(96, 58, 36))
	for _, z in { -5.6, 5.8 } do
		for _, x in { -3.4, 3.4 } do
			add(Vector3.new(1.1, 3.2, 3.2), CF(x, 1.6, z), rgb(24, 24, 24))
		end
	end
	m.WorldPivot = CFrame.new()
	m.Parent = Stage.folder()
	return m
end

-- Stand-in rescue helicopter (same layout as Props.Helicopter).
function Cast.simpleHelicopter(): Model
	local m = Instance.new("Model")
	m.Name = "Helicopter"
	local whiteColor = rgb(225, 225, 220)
	local function add(parent: Instance, size: Vector3, cf: CFrame, color: Color3)
		local p = part(size, cf, color, Enum.Material.Metal)
		p.Parent = parent
	end
	add(m, Vector3.new(7, 6, 14), CF(0, 5, 0), whiteColor)
	add(m, Vector3.new(7.05, 1.2, 14), CF(0, 4, 0), rgb(180, 30, 30))
	add(m, Vector3.new(1.6, 1.6, 16), CF(0, 6.5, 14), whiteColor)
	add(m, Vector3.new(0.4, 4, 2.4), CF(0.8, 8, 21.5), rgb(180, 30, 30))
	for _, x in { -3.6, 3.6 } do
		add(m, Vector3.new(0.4, 0.4, 13), CF(x, 0.3, 0), rgb(50, 50, 50))
	end
	local rotor = Instance.new("Model")
	rotor.Name = "Rotor"
	rotor.Parent = m
	for i = 0, 3 do
		add(rotor, Vector3.new(1.2, 0.2, 19), CF(0, 9.7, 0) * ANG(0, i * math.pi / 2, 0) * CF(0, 0, 9.5), rgb(30, 30, 30))
	end
	m.WorldPivot = CFrame.new()
	m.Parent = Stage.folder()
	return m
end

-- Cabin interior around the left side door, so the door shot has a frame.
function Cast.addCabin(heli: Model, pivot: CFrame)
	local metal = rgb(52, 54, 58)
	local function add(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
		local p = part(size, pivot * offset, color, material or Enum.Material.Metal)
		p.Parent = heli
	end
	add(Vector3.new(6.4, 0.2, 9), CF(0, 2.25, 0.5), rgb(40, 42, 44), Enum.Material.DiamondPlate)
	add(Vector3.new(6.4, 0.2, 9), CF(0, 7.85, 0.5), rgb(70, 72, 74), Enum.Material.Fabric)
	add(Vector3.new(0.3, 0.3, 5.2), CF(-3.3, 7.7, 0.5), metal)
	add(Vector3.new(0.3, 0.3, 5.2), CF(-3.3, 2.5, 0.5), metal)
	add(Vector3.new(0.3, 5.5, 0.3), CF(-3.3, 5.1, -2.1), metal)
	add(Vector3.new(0.3, 5.5, 0.3), CF(-3.3, 5.1, 3.1), metal)
	add(Vector3.new(0.2, 5.4, 9), CF(3.2, 5, 0.5), rgb(80, 82, 84))
	add(Vector3.new(0.08, 1.6, 0.08), CF(-2.7, 7, 1.2), rgb(200, 120, 40), Enum.Material.Fabric)
	add(Vector3.new(2.2, 1.1, 1.8), CF(1.6, 2.9, 2.2), rgb(60, 66, 58), Enum.Material.Fabric)
end

return Cast

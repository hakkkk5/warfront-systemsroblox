--!strict
-- WakeUp (~50 s): blinking awake tied to the chair, the Butcher chopping and
-- the Brother laughing at the table, the dialogue, the two leaving through
-- the slaughter-room door, then the knife sawing through the ropes.
-- data: { eye, seat, tableTop, butcher, brother, exit, doorway: CFrame,
--         knife: Model?, chair: Model, body: Model }

local CameraController = require(script.Parent.Parent.CameraController)
local Effects = require(script.Parent.Parent.Effects)
local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local Util = require(game:GetService("ReplicatedStorage").Shared.Util)
local Stage = require(script.Parent.Stage)
local Cast = require(script.Parent.Cast)

local rgb = Color3.fromRGB
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local UP = Vector3.yAxis
local at = Stage.at
local sleep = Stage.sleep
local part = Stage.part

-- Splits a cut rope into pieces that drop to the floor.
local function snapRope(rope: BasePart)
	local size = rope.Size
	local count = if size.X > 0.8 then 2 else 1
	for i = 1, count do
		local offset = if count == 2 then (if i == 1 then -1 else 1) * size.X / 4 else 0
		local piece = part(
			Vector3.new(if count == 2 then size.X / 2 - 0.04 else size.X, size.Y, size.Z),
			rope.CFrame * CF(offset, 0, 0),
			rope.Color,
			rope.Material
		)
		piece.Anchored = false
		piece.CanCollide = true
		piece.AssemblyLinearVelocity = rope.CFrame.RightVector * (math.sign(offset) * 3) + Vector3.new(0, 1.5, 0)
	end
	rope:Destroy()
end

local function moveModel(model: Model, from: CFrame, to: CFrame, duration: number)
	Stage.animate(duration, function(a)
		model:PivotTo(from:Lerp(to, Stage.smooth(a)))
	end)
end

-- Saws the knife back and forth along a world axis (yields).
local function saw(model: Model, base: CFrame, axis: Vector3, duration: number)
	local t = 0
	local strokes = 0
	Stage.animate(duration, function(_, dt)
		t += dt
		model:PivotTo(base + axis * math.sin(t * math.pi * 6.4))
		local n = math.floor(t * 6.4)
		if n ~= strokes then
			strokes = n
			CameraController.shake(0.1, 8)
			Stage.sfx("RopeCut", "Whoosh", base.Position, 0.18, 1.8)
		end
	end)
	model:PivotTo(base)
end

local function simpleKnife(): Model
	local m = Instance.new("Model")
	m.Name = "HuntingKnife"
	part(Vector3.new(0.8, 0.04, 0.16), CF(0.35, 0.04, 0), rgb(180, 180, 185), Enum.Material.Metal).Parent = m
	part(Vector3.new(0.5, 0.12, 0.14), CF(-0.35, 0.04, 0), rgb(70, 46, 30), Enum.Material.Wood).Parent = m
	m.WorldPivot = CFrame.new()
	m.Parent = Stage.folder()
	return m
end

return Stage.scene("WakeUp", function(data: any)
	local camera = workspace.CurrentCamera
	local eye = Stage.cf(data.eye, camera.CFrame)
	local seat = Stage.cf(data.seat, eye * CF(0, -2.55, 0.2))
	local chairCF = seat * CF(0, -2.05, 0)
	local tableTop = Stage.cf(data.tableTop, eye * CF(0, -1.1, -14))
	local doorway = Stage.cf(data.doorway, chairCF * CF(-18, 0, 3))
	local exit = Stage.cf(data.exit, doorway * CF(-4.5, 0, 0))
	local eyePos = eye.Position
	local eyeLocal = chairCF:PointToObjectSpace(eyePos)
	local tablePos = tableTop.Position

	-- house frame (axis aligned; doorway = L(7, 0, 16.5), exit = L(2.5, 0, 16.5))
	local xAxis = doorway.Position - exit.Position
	local houseCF = if xAxis.Magnitude > 0.5
		then CFrame.fromMatrix(doorway.Position, xAxis.Unit, UP) * CF(-7, 0, -16.5)
		else CF(doorway.Position) * CF(-7, 0, -16.5)
	local function H(x: number, z: number): Vector3
		return (houseCF * CF(x, 0, z)).Position
	end

	Effects.setRain(false) -- indoors
	Stage.letterbox(true, 0)
	Stage.setBlack(1)
	Stage.eyes(0, 0)
	Stage.blur(28)
	Stage.sway(0.55)
	Stage.cut(CFrame.lookAt(eyePos, eyePos + eye.LookVector * 5 - UP * 3.6), 70)

	-- the slaughter room door swings locally (closed again at the end)
	local chair = Stage.model(data.chair)
	local doorModel: Instance? = nil
	if chair then
		local houseModel = chair:FindFirstAncestorWhichIsA("Model")
		doorModel = if houseModel then houseModel:FindFirstChild("SlaughterDoor", true) else nil
	end
	doorModel = doorModel or workspace:FindFirstChild("SlaughterDoor", true)
	local doorParts: { { part: BasePart, cf: CFrame } } = {}
	if doorModel then
		for _, d in doorModel:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(doorParts, { part = d, cf = d.CFrame })
			end
		end
	end
	local hinge = CF(H(5, 14.1))
	local doorAngle = Stage.numberValue(0)
	Stage.connect(doorAngle:GetPropertyChangedSignal("Value"):Connect(function()
		local rot = hinge * ANG(0, doorAngle.Value, 0) * hinge:Inverse()
		for _, e in doorParts do
			e.part.CFrame = rot * e.cf
		end
	end))
	Stage.cleanup(function()
		for _, e in doorParts do
			if e.part.Parent then
				e.part.CFrame = e.cf
			end
		end
	end)

	-- ropes: hide the server ones and cut local copies one by one
	local ropes: { BasePart } = {}
	if chair then
		for _, d in chair:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Rope" then
				table.insert(ropes, d)
			end
		end
		if chair:GetAttribute("Mesh") == "ChairRopes" then
			-- local only: show the rope-less Blender chair, the ropes are our copies
			chair:SetAttribute("Mesh", "Chair")
		end
	end
	local copies: { BasePart } = {}
	for _, r in ropes do
		table.insert(copies, part(r.Size, r.CFrame, r.Color, r.Material))
		Stage.hide(r, true)
	end
	if #copies == 0 then
		local ropeColor = rgb(170, 150, 110)
		for _, y in { 2.6, 3.4 } do
			table.insert(copies, part(Vector3.new(2.3, 0.18, 0.18), chairCF * CF(0, y, 1.08), ropeColor, Enum.Material.Fabric))
		end
		for _, x in { -0.95, 0.95 } do
			table.insert(copies, part(Vector3.new(0.3, 0.16, 0.3), chairCF * CF(x, 0.5, -0.95), ropeColor, Enum.Material.Fabric))
		end
	end
	Stage.later(0.25, function()
		for _, r in ropes do
			r.LocalTransparencyModifier = 1
		end
	end)
	local wrists: { BasePart } = {}
	local ankles: { { rope: BasePart, x: number } } = {}
	for _, r in copies do
		local rel = chairCF:PointToObjectSpace(r.Position)
		if rel.Y > 1.5 then
			table.insert(wrists, r)
		else
			table.insert(ankles, { rope = r, x = rel.X })
		end
	end
	table.sort(ankles, function(a, b)
		return a.x > b.x
	end)

	-- the knife on the side table
	local serverKnife = Stage.model(data.knife)
	local knifeRest = if serverKnife then serverKnife:GetPivot() else chairCF * CF(2.3, 2.82, 0.4) * ANG(0, rad(70), 0)
	local knife = Stage.cloneProp(serverKnife) or Stage.itemModel("HuntingKnife") or simpleKnife()
	Stage.hide(serverKnife, true)
	knife:PivotTo(knifeRest)
	local grip = part(Vector3.new(0.42, 0.3, 0.34), knifeRest * CF(-0.38, 0.06, 0), rgb(214, 178, 150), nil, { Transparency = 1 })
	grip.Parent = knife

	-- a bare bulb over the table
	local pivot = Vector3.new(tablePos.X, houseCF.Y + 11.8, tablePos.Z)
	local bulb = part(Vector3.new(0.45, 0.6, 0.45), CF(pivot - UP * 3), rgb(255, 214, 160), Enum.Material.Neon)
	local cord = part(Vector3.new(0.06, 3, 0.06), CF(pivot - UP * 1.5), rgb(20, 20, 20))
	local bulbLight = Instance.new("PointLight")
	bulbLight.Range = 24
	bulbLight.Brightness = 1.2
	bulbLight.Color = rgb(255, 190, 130)
	bulbLight.Shadows = true
	bulbLight.Parent = bulb
	local swing, swingStart, flickerUntil = 0, 0, 0
	Stage.go(function()
		while true do
			local now = os.clock()
			local t = now - swingStart
			local angle = swing * math.exp(-t / 2.6) * math.sin(t * 2.4)
			local rot = CF(pivot) * ANG(angle, 0, angle * 0.4)
			cord.CFrame = rot * CF(0, -1.5, 0)
			bulb.CFrame = rot * CF(0, -3, 0)
			bulbLight.Brightness = if now < flickerUntil
				then (if math.random() < 0.3 then 0.1 else 1.3)
				else 1.2 + math.noise(now * 3) * 0.08
			sleep(0)
		end
	end)

	-- the family
	local butcher = Cast.actor("Butcher", Stage.cf(data.butcher, CFrame.lookAt(H(17, 12.4), H(17, 9))))
	local brother = Cast.actor("Brother", Stage.cf(data.brother, CFrame.lookAt(H(20.5, 5.4), H(17, 9))))
	Cast.play(butcher, "idle")
	Cast.play(brother, "idle")

	-- the camera is the captive's head: it turns toward a focus point
	local offsetV = Instance.new("Vector3Value")
	offsetV.Parent = Stage.folder()
	local rollV = Stage.numberValue(0.06)
	local focus = eyePos + eye.LookVector * 5 - UP * 3.6
	local focusFn: () -> Vector3 = function()
		return eyePos + eye.LookVector * 5 - UP * 3.6
	end
	local rate = 1.2
	local function lookAt(fn: () -> Vector3, r: number)
		focusFn = fn
		rate = r
	end
	Stage.track(function(dt)
		focus = focus:Lerp(focusFn(), 1 - math.exp(-rate * dt))
		local p = chairCF * (eyeLocal + offsetV.Value)
		return CFrame.lookAt(p, focus) * ANG(0, 0, rollV.Value)
	end)
	local function butcherHead(): Vector3
		return Cast.head(butcher)
	end
	local function brotherHead(): Vector3
		return Cast.head(brother)
	end
	local doorFocus = H(5, 16.5) + UP * 4.5
	local function atDoor(): Vector3
		return doorFocus
	end

	Stage.resetClock()
	local chopping = true
	Stage.go(function()
		sleep(0.6)
		while chopping do
			Cast.chop(butcher, tablePos)
			sleep(0.45 + math.random() * 0.4)
		end
	end)
	Stage.go(function()
		at(2.6)
		Cast.laugh(brother, 2.2)
		at(6.4)
		Cast.laugh(brother, 1.6)
	end)

	Stage.fadeTo(0, 0.5)
	at(1.4)
	Stage.eyes(0.22, 1.1)
	at(2.8)
	Stage.eyes(0, 0.35)
	at(3.6)
	Stage.eyes(0.5, 1.4)
	Stage.blurTo(16, 3)
	-- the head lifts toward the table (kept below eye level: some table meshes are tall)
	local tableFocus = Vector3.new(tablePos.X, math.min(tablePos.Y + 1.2, eyePos.Y - 0.4), tablePos.Z)
	lookAt(function()
		return tableFocus
	end, 0.7)
	at(6)
	Stage.blurTo(8, 1.5)
	Stage.blink(0.18, 0.22, 0.5, 0.8)
	at(8)
	Stage.eyes(0, 0.16)
	at(8.4)
	Stage.eyes(1, 0.6)
	Stage.blurTo(2.5, 2.5)
	at(9.4)
	chopping = false
	at(10.6)
	HUD.subtitle("Butcher", "Fresh meat tonight, brother.", 3.6)
	lookAt(butcherHead, 1.4)
	Cast.pose(butcher, "neck", Cast.neck(butcher, 0, -0.55, 0), 0.6)
	at(12.2)
	Stage.go(function()
		Cast.laugh(brother, 1.3)
	end)
	at(14.4)
	HUD.subtitle("Brother", "This one's still breathin'…", 3.6)
	Stage.go(function()
		Cast.face(brother, eyePos, 0.9)
		Cast.pose(brother, "neck", Cast.neck(brother, -0.12, 0, 0.4), 0.8)
	end)
	lookAt(brotherHead, 2.6)
	Stage.zoom(50, 1.8)
	CameraController.shake(0.22, 2)
	at(15.6)
	local creep = Util.flat(eyePos - brother.root.Position)
	creep = if creep.Magnitude > 1e-3 then creep.Unit else Vector3.zero
	local brotherFeet = brother.root.Position - UP * brother.lift
	Stage.go(function()
		Cast.walk(brother, { brotherFeet + creep * 2.4 }, 2.2)
	end)
	at(18.6)
	HUD.subtitle("Butcher", "Leave it. It'll keep till mornin'.", 3.6)
	lookAt(butcherHead, 1.6)
	Stage.zoom(70, 1.4)
	Cast.pose(butcher, "neck", Cast.neck(butcher, 0, -0.9, 0), 0.6)
	at(20.6)
	-- he leaves; the door opens ahead of him
	Cast.pose(butcher, "neck", CFrame.identity, 0.5)
	Cast.pose(butcher, "rightShoulder", CFrame.identity, 0.5)
	Cast.pose(butcher, "waist", CFrame.identity, 0.5)
	Util.tween(doorAngle, 0.9, { Value = rad(100) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Stage.sfx("DoorOpen", nil, doorFocus, 0.7)
	Stage.go(function()
		Cast.walk(butcher, { H(11.5, 15.4), H(7, 16.5), H(2.5, 16.5) }, 6.5)
	end)
	lookAt(butcherHead, 1.5)
	at(21.6)
	Stage.go(function()
		Cast.laugh(brother, 1.1)
	end)
	at(23)
	Cast.pose(brother, "neck", CFrame.identity, 0.4)
	local brotherGone = false
	Stage.go(function()
		Cast.walk(brother, { H(23.2, 10.2), H(20.6, 14), H(12, 15.9), H(7, 16.5) }, 7)
		Cast.face(brother, eyePos, 0.5)
		Cast.pose(brother, "neck", Cast.neck(brother, -0.1, 0, 0.5), 0.5)
		sleep(0.9)
		Cast.pose(brother, "neck", CFrame.identity, 0.3)
		Cast.walk(brother, { H(2.5, 16.5) }, 6)
		brotherGone = true
	end)
	lookAt(brotherHead, 1.6)
	while not brotherGone and Stage.elapsed() < 31 do
		sleep(0.05)
	end

	-- the door slams
	Util.tween(doorAngle, 0.16, { Value = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	sleep(0.16)
	Stage.sfx("Impact", nil, doorFocus, 1, 0.42)
	Stage.sfx("DoorLocked", nil, doorFocus, 0.8)
	CameraController.shake(1.2, 2.5)
	swing, swingStart, flickerUntil = 0.32, os.clock(), os.clock() + 1.6
	butcher.model:Destroy()
	brother.model:Destroy()
	lookAt(atDoor, 1)

	Stage.resetClock()
	local function knifePoint(): Vector3
		return knife:GetPivot().Position
	end
	at(1.4)
	lookAt(knifePoint, 1.3)
	Util.tween(offsetV, 1.5, { Value = Vector3.new(0.2, -0.15, 0) })
	at(2.4)
	HUD.subtitle("You", "The knife… if I can just reach it…", 3.2)
	for i, t in { 3.2, 4 } do
		at(t)
		Util.tween(rollV, 0.22, { Value = if i == 1 then -0.12 else 0.1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		CameraController.shake(0.35, 4)
		Stage.sfx("Impact", nil, chairCF.Position, 0.45, 1.4)
	end
	at(4.9)
	-- the knife rises to the hands and goes to work on the wrist ropes
	Util.tween(rollV, 0.6, { Value = 0.02 })
	grip.Transparency = 0
	local lifted = chairCF * CF(1.9, 3.5, 0) * ANG(0, math.pi, rad(25))
	local wristSaw = chairCF * CF(1.3, 2.75, 0.4) * ANG(0, math.pi, rad(15))
	lookAt(knifePoint, 2.2)
	moveModel(knife, knifeRest, lifted, 0.6)
	moveModel(knife, lifted, wristSaw, 1)
	saw(knife, wristSaw, chairCF.UpVector * 0.14, 2.4)
	for _, r in wrists do
		snapRope(r)
	end
	CameraController.shake(0.6, 3)
	Stage.sfx("RopeCut", "Slash", chairCF.Position, 0.45, 1.3)
	sleep(0.6)

	-- then the ankles
	lookAt(function()
		return chairCF * Vector3.new(0, 0.5, -1)
	end, 1.6)
	Util.tween(offsetV, 1, { Value = Vector3.new(0, -0.35, -0.4) })
	local last = wristSaw
	for _, entry in ankles do
		local target = if entry.x >= 0
			then chairCF * CF(entry.x + 0.47, 0.62, -0.95) * ANG(0, math.pi, rad(-12))
			else chairCF * CF(entry.x - 0.47, 0.62, -0.95) * ANG(0, 0, rad(12))
		moveModel(knife, last, target, 0.8)
		saw(knife, target, chairCF.LookVector * 0.12, 1.2)
		snapRope(entry.rope)
		CameraController.shake(0.4, 4)
		Stage.sfx("RopeCut", "Slash", entry.rope.Position, 0.4, 1.4)
		last = target
		sleep(0.25)
	end

	-- free. The knife comes along; eyes on the door.
	Stage.go(function()
		moveModel(knife, last, chairCF * CF(0.9, 3.2, -1.2) * ANG(0, math.pi, 0), 0.8)
		knife:Destroy()
	end)
	lookAt(atDoor, 1.1)
	Util.tween(offsetV, 1.2, { Value = Vector3.zero })
	sleep(0.9)
	HUD.subtitle("You", "I need to get out… the door was chained. I need a key.", 4.6)
	sleep(3.8)
	Stage.fadeTo(1, 1.4)
	sleep(1.5)
end)

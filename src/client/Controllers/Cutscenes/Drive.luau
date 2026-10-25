--!strict
-- Drive (interactive, 30-55 s): the repaired truck follows the path while the
-- player holds the throttle and steers; the engine gives out near the end,
-- the truck stops on the wreck spot and explodes, then Papa and the lanterns
-- come out of the trees. RUN.
-- data: { truck: Model, truckCF: CFrame, path: { Vector2 }, wreck: CFrame }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

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
local UP = Vector3.yAxis
local at = Stage.at
local sleep = Stage.sleep
local groundY = Stage.groundY
local part = Stage.part

local MAX_SPEED = 55

-- W / up / touch / RT (or A) to accelerate; A-D / arrows / touch side / stick to steer.
local function inputReader(): () -> (boolean, number)
	local camera = workspace.CurrentCamera
	local touches: { [InputObject]: Vector3 } = {}
	Stage.connect(UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = input.Position
		end
	end))
	Stage.connect(UserInputService.InputChanged:Connect(function(input: InputObject)
		if touches[input] then
			touches[input] = input.Position
		end
	end))
	Stage.connect(UserInputService.InputEnded:Connect(function(input: InputObject)
		touches[input] = nil
	end))
	local function gamepad(): (boolean, number)
		if not UserInputService.GamepadEnabled then
			return false, 0
		end
		local gas, stick = false, 0
		for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if state.KeyCode == Enum.KeyCode.ButtonR2 and state.Position.Z > 0.2 then
				gas = true
			elseif state.KeyCode == Enum.KeyCode.ButtonA and state.UserInputState == Enum.UserInputState.Begin then
				gas = true
			elseif state.KeyCode == Enum.KeyCode.Thumbstick1 and math.abs(state.Position.X) > 0.15 then
				stick = state.Position.X
			end
		end
		return gas, stick
	end
	return function(): (boolean, number)
		local typing = UserInputService:GetFocusedTextBox() ~= nil
		local padGas, padSteer = gamepad()
		local gas = padGas or next(touches) ~= nil
		local steer = padSteer
		if not typing then
			gas = gas or UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up)
			if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
				steer -= 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
				steer += 1
			end
		end
		local width = camera.ViewportSize.X
		for _, pos in touches do
			if width > 0 then
				steer += math.clamp((pos.X / width - 0.5) * 3, -1, 1)
			end
			break
		end
		return gas, math.clamp(steer, -1, 1)
	end
end

return Stage.scene("Drive", function(data: any)
	local serverTruck = Stage.model(data.truck)
	local truckCF = Stage.cf(data.truckCF, if serverTruck then serverTruck:GetPivot() else workspace.CurrentCamera.CFrame)
	local path: { Vector2 } = {}
	if typeof(data.path) == "table" then
		for _, p in data.path do
			if typeof(p) == "Vector2" then
				table.insert(path, p)
			end
		end
	end
	if #path < 2 then
		path = table.clone(Config.DrivePath)
	end
	local lastPoint = path[#path]
	local wreck = Stage.cf(data.wreck, CF(lastPoint.X, groundY(lastPoint.X, lastPoint.Y), lastPoint.Y))
	path[#path] = Vector2.new(wreck.X, wreck.Z) -- the ride ends exactly on the wreck spot
	local total = Util.polylineLength(path)

	Stage.fadeWait(1, 0.4)
	Stage.letterbox(true, 0)

	-- local truck; the server one is hidden for the ride and shown again after
	local truck = Stage.cloneProp(serverTruck)
	local pivotOffset = CFrame.identity
	if serverTruck then
		pivotOffset = truckCF:ToObjectSpace(serverTruck:GetPivot())
		Stage.hide(serverTruck)
	end
	local body = truck or Cast.simpleTruck()
	body:PivotTo(truckCF * pivotOffset)

	-- driver's eye from the body's bounds (driver on the left of the travel direction)
	local bbCF, bbSize = body:GetBoundingBox()
	local center = truckCF:PointToObjectSpace(bbCF.Position)
	local eyeLocal = CF(center.X - 1.6, center.Y - bbSize.Y / 2 + bbSize.Y * 0.8, center.Z)
	local frontZ = center.Z - bbSize.Z / 2
	-- third person: the camera chases the truck, you at the wheel inside. The
	-- cockpit only drives the warning lamps now and stays out of the world.
	local cockpit = Cast.buildCockpit(6.6, rgb(122, 40, 32))
	cockpit.model.Parent = nil
	local me = Cast.me(CFrame.identity)
	Cast.sit(me, 1.1)
	local seatLocal = CF(eyeLocal.X, eyeLocal.Y - 1.6, center.Z + 0.6)
	-- headlights on the body itself
	local beams: { SpotLight } = {}
	local lampParts: { { part: BasePart, offset: CFrame } } = {}
	for _, x in { -2.5, 2.5 } do
		local lamp = part(Vector3.new(1, 0.6, 0.15), CFrame.identity, rgb(70, 70, 66), Enum.Material.Glass, { Transparency = 0.3 })
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Range = 75
		beam.Angle = 60
		beam.Brightness = 0
		beam.Color = rgb(255, 240, 210)
		beam.Shadows = true
		beam.Parent = lamp
		table.insert(beams, beam)
		table.insert(lampParts, { part = lamp :: BasePart, offset = CF(center.X + x, center.Y - bbSize.Y * 0.12, frontZ - 0.05) })
	end
	local function lights(on: boolean)
		for _, beam in beams do
			beam.Brightness = if on then 5 else 0
		end
		for _, l in lampParts do
			l.part.Material = if on then Enum.Material.Neon else Enum.Material.Glass
			l.part.Color = if on then rgb(255, 246, 222) else rgb(70, 70, 66)
		end
	end
	local chaseCam: CFrame? = nil
	local readInput = inputReader()

	-- drive state
	local sputterAt = total * 0.7
	local along, speed, lateral, latVel, steer = 0, 0, 0, 0, 0
	local control, done, sputtering = false, false, false
	local elapsed, idle, driveTime, gasTime, nextSputter = 0, 0, 0, 0, 0
	local smoothY: number? = nil
	local smoothPitch = 0
	local truckPose = truckCF
	local smoke: Smoke? = nil

	local function onSputter()
		HUD.subtitle("You", "No, no, no… not now!", 3)
		local smokePart = part(Vector3.one, truckPose * eyeLocal * CF(1.5, -1.2, -5.4), rgb(0, 0, 0), nil, { Transparency = 1 })
		smokePart.Parent = body
		local s = Instance.new("Smoke")
		s.Color = rgb(70, 70, 72)
		s.Opacity = 0.3
		s.RiseVelocity = 6
		s.Size = 3
		s.Parent = smokePart
		smoke = s
		Stage.go(function()
			local on = false
			while true do
				on = not on
				Cast.setWarnings(cockpit, on)
				sleep(0.28)
			end
		end)
	end

	local function directionAt(s: number): Vector2
		local d = Util.polylineSample(path, math.min(s + 7, total)) - Util.polylineSample(path, math.max(s - 7, 0))
		return if d.Magnitude > 1e-3 then d.Unit else Vector2.new(0, -1)
	end

	Stage.track(function(dt)
		elapsed += dt
		local gas, steerIn = 0, 0
		if control and not done then
			driveTime += dt
			local held, s = readInput()
			steerIn = s
			if held then
				gas = 1
				gasTime += dt
				idle = 0
			else
				idle += dt
				-- keep the story moving if nobody touches the pedal
				if idle > 4 or driveTime > 24 then
					gas = 0.65
				end
			end
		end
		if control and not sputtering and along >= sputterAt then
			sputtering = true
			onSputter()
		end
		local cap = MAX_SPEED
		if sputtering then
			cap = Util.lerp(34, 12, math.clamp((along - sputterAt) / math.max(total - sputterAt, 1), 0, 1))
			if elapsed >= nextSputter then
				nextSputter = elapsed + 0.45 + math.random() * 0.6
				speed *= 0.72
				CameraController.shake(0.55, 4)
				Stage.sfx("EngineFail", nil, nil, 0.7)
			end
		end
		if gas > 0 then
			speed += 14 * gas * dt
		else
			speed -= 5 * dt
		end
		speed = math.clamp(speed, 0, cap)
		if sputtering then
			speed = math.max(speed, 6)
		end
		local remaining = total - along
		if control then
			-- ease into a stop exactly at the end of the path
			speed = math.min(speed, math.sqrt(2 * 8 * math.max(remaining, 0)) + 1.2)
		else
			speed = 0
		end
		along = math.min(along + speed * dt, total)
		if control and along >= total - 0.02 then
			along = total
			speed = 0
			done = true
		end

		-- steering within +-6 studs of the path, squeezed back onto it near the end
		steer = Util.lerp(steer, steerIn, math.min(1, dt * 6))
		local limit = 6 * math.clamp((total - along) / 45, 0, 1)
		latVel = math.clamp((steer * limit - lateral) * 2.4, -7, 7) * math.clamp(speed / 10, 0, 1)
		lateral = math.clamp(lateral + latVel * dt, -limit, limit)

		-- pose on the terrain: height and pitch from the axles
		local p = Util.polylineSample(path, along)
		local d2 = directionAt(along)
		local c2 = p + Vector2.new(-d2.Y, d2.X) * lateral
		local fwd = Vector3.new(d2.X, 0, d2.Y)
		local base = Vector3.new(c2.X, 0, c2.Y)
		local f, b = base + fwd * 5.6, base - fwd * 5.8
		local yF, yR = groundY(f.X, f.Z), groundY(b.X, b.Z)
		local y = (yF + yR) / 2
		smoothY = if smoothY then Util.lerp(smoothY, y, math.min(1, dt * 10)) else y
		smoothPitch = Util.lerp(smoothPitch, math.atan2(yF - yR, 11.4), math.min(1, dt * 8))
		local pos = Vector3.new(c2.X, smoothY or y, c2.Y)
		local slip = -math.atan2(latVel, math.max(speed, 4))
		truckPose = CFrame.lookAt(pos, pos + fwd)
			* ANG(0, slip, 0)
			* ANG(smoothPitch, 0, -steer * 0.025 * math.clamp(speed / 30, 0, 1))
		body:PivotTo(truckPose * pivotOffset)
		me.root.CFrame = truckPose * seatLocal * CF(0, Cast.seatLift(me), 0)
		Cast.pose(me, "neck", Cast.neck(me, 0, -steer * 0.3, 0), 0)
		for _, l in lampParts do
			l.part.CFrame = truckPose * l.offset
		end

		-- the chase camera: behind and above, swinging a little into turns
		local behind = truckPose * CF(steer * 3, 7.2 + speed * 0.02, 17 + speed * 0.06)
		local goal = CFrame.lookAt(behind.Position, (truckPose * CF(0, 3.2, -8)).Position)
		local current = chaseCam
		chaseCam = if current then current:Lerp(goal, math.min(1, dt * 5)) else goal
		local bump = math.noise(along * 0.12, elapsed * 0.3) * 0.01 * (0.3 + speed / MAX_SPEED)
		return (chaseCam :: CFrame) * ANG(bump, 0, 0)
	end)
	Stage.zoom(62, 0)

	-- engine start
	Stage.resetClock()
	Stage.fadeTo(0, 1)
	at(0.6)
	Stage.sfx("EngineStart", nil, nil, 0.8)
	CameraController.shake(0.35, 3)
	HUD.subtitle("You", "Come on… come on…", 2.2)
	at(1.6)
	CameraController.shake(0.3, 3)
	at(2.6)
	CameraController.shake(0.8, 2.5)
	Cast.setGauges(cockpit, true)
	lights(true)
	Stage.loop("EngineLoop", true, 0.5)
	HUD.subtitle("You", "Yes! Okay… let's get out of here.", 2.6)
	at(3.4)
	control = true
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local padOnly = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
	local hintLabel = Stage.hint(if touchOnly
		then "Hold the screen to accelerate  ·  hold left / right to steer"
		elseif padOnly then "Hold RT to accelerate  ·  left stick to steer"
		else "Hold W to accelerate  ·  A / D to steer")
	Stage.go(function()
		while gasTime < 2.5 and not done do
			sleep(0.1)
		end
		Util.tween(hintLabel, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	local deadline = os.clock() + 48
	while not done and Stage.tracking() and os.clock() < deadline do
		sleep(0.05)
	end
	control = false
	hintLabel.Visible = false
	Stage.loop("EngineLoop", false)

	-- outside: the engine gives out for good and you bail out of the cab
	lights(false)
	local endPose = truckPose
	local hoodPos = (endPose * CF(0, 4.4, -6)).Position
	Stage.cut(CFrame.lookAt((endPose * CF(-12.5, 4.2, -15)).Position, (endPose * CF(0, 3.4, -4)).Position), 58)
	local activeSmoke = smoke
	if activeSmoke then
		activeSmoke.Opacity = 0.5
		activeSmoke.Size = 6
	end
	local outside = Stage.ground((endPose * CF(center.X - 5, 0, center.Z + 0.6)).Position)
	local diveTo = Stage.ground(wreck * Vector3.new(-7, 0, 9))
	Cast.stand(me, 0)
	me.root.CFrame = CFrame.lookAt(outside + UP * me.lift, diveTo + UP * me.lift)
	Stage.go(function()
		Cast.walk(me, { diveTo }, 17, { ground = true })
	end)
	sleep(0.5)
	CameraController.shake(0.4, 4)
	Stage.sfx("EngineFail", nil, hoodPos, 0.8)
	sleep(0.8)

	-- EXPLOSION (visual only)
	local boom = Instance.new("Explosion")
	boom.Position = hoodPos
	boom.BlastRadius = 9
	boom.BlastPressure = 0
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Parent = Stage.folder()
	Stage.flashWhite(0.5)
	Effects.flash(rgb(255, 170, 90), 0.7)
	CameraController.shake(3.4, 1.5)
	Stage.sfx("Explosion", "Impact", hoodPos, 1, 0.4)
	local firePart = part(Vector3.new(4, 1, 4), endPose * CF(0, 4.2, -5.5), rgb(0, 0, 0), nil, { Transparency = 1 })
	firePart.Parent = body
	local fire = Instance.new("Fire")
	fire.Size = 11
	fire.Heat = 16
	fire.Color = rgb(255, 120, 40)
	fire.SecondaryColor = rgb(255, 40, 10)
	fire.Parent = firePart
	local cabFire = Instance.new("Fire")
	cabFire.Size = 7
	cabFire.Heat = 10
	cabFire.Parent = part(Vector3.new(3, 1, 3), endPose * CF(0, 6, -0.5), rgb(0, 0, 0), nil, { Transparency = 1 })
	local blackSmoke = Instance.new("Smoke")
	blackSmoke.Color = rgb(22, 20, 20)
	blackSmoke.Opacity = 0.6
	blackSmoke.RiseVelocity = 9
	blackSmoke.Size = 10
	blackSmoke.Parent = firePart
	local fireLight = Instance.new("PointLight")
	fireLight.Range = 38
	fireLight.Brightness = 3.5
	fireLight.Color = rgb(255, 130, 50)
	fireLight.Shadows = true
	fireLight.Parent = firePart
	Stage.go(function()
		while true do
			fireLight.Brightness = 2.8 + math.noise(os.clock() * 5) * 1.6
			sleep(0)
		end
	end)
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") then
			p.Color = p.Color:Lerp(rgb(20, 18, 16), 0.65)
		end
	end
	local hoodPanel = body:FindFirstChild("Hood", true)
	if hoodPanel and hoodPanel:IsA("BasePart") then
		hoodPanel.Anchored = false
		hoodPanel.CanCollide = true
		hoodPanel.AssemblyLinearVelocity = endPose.UpVector * 55 + endPose.LookVector * 12
		hoodPanel.AssemblyAngularVelocity = Vector3.new(4, 1, 2)
	end
	for i = 1, 12 do
		local glowing = i % 3 == 0
		local piece = part(
			Vector3.new(0.3 + math.random() * 0.8, 0.2 + math.random() * 0.4, 0.3 + math.random() * 0.8),
			CF(hoodPos + Vector3.new(math.random() * 2 - 1, math.random(), math.random() * 2 - 1)),
			if glowing then rgb(255, 140, 50) else rgb(30, 26, 24),
			if glowing then Enum.Material.Neon else Enum.Material.CorrodedMetal
		)
		piece.Anchored = false
		piece.CanCollide = true
		piece.AssemblyLinearVelocity = Vector3.new(math.random(-35, 35), math.random(30, 65), math.random(-35, 35))
		piece.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
	end
	Stage.move(Stage.camCFrame() * CF(0, 0.4, 3), 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	sleep(0.4)
	Stage.setBlack(1)
	Stage.stopCamera()
	Stage.blur(24)
	sleep(1.6)

	-- ears ringing: you, face down beside the burning wreck
	local function W(x: number, z: number): Vector3
		return Stage.ground(wreck * Vector3.new(x, 0, z))
	end
	local awayDir = Util.flat(diveTo - endPose.Position)
	awayDir = if awayDir.Magnitude > 1e-3 then awayDir.Unit else Vector3.new(0, 0, 1)
	Cast.still(me)
	Cast.pose(me, "rightShoulder", Cast.arm(me, true, 2.6, 0.3), 0)
	Cast.pose(me, "leftShoulder", Cast.arm(me, false, 2.4, 0.4), 0)
	local prone = CFrame.fromMatrix(diveTo + UP * 0.55, awayDir:Cross(UP), awayDir)
	me.root.CFrame = prone
	local camPos = W(-4, 2.5) + UP * 2.2
	local wreckFocus = Cast.head(me)
	local focus = wreckFocus
	local focusFn: () -> Vector3 = function()
		return wreckFocus
	end
	local rate = 1
	Stage.track(function(dt)
		focus = focus:Lerp(focusFn(), 1 - math.exp(-rate * dt))
		return CFrame.lookAt(camPos, focus)
	end)
	Stage.zoom(60, 0)
	Stage.sway(0.7)

	-- they come out of the trees: lanterns, and Papa with the chainsaw
	local papa = Cast.actor("Papa", CFrame.lookAt(W(0, 46), camPos))
	local kinA = Cast.actor("Kin", CFrame.lookAt(W(-34, 36), camPos))
	local kinB = Cast.actor("Kin", CFrame.lookAt(W(38, 30), camPos))
	for _, a in { papa, kinA, kinB } do
		Cast.play(a, "idle")
	end
	for _, kin in { kinA, kinB } do
		Cast.lantern(kin)
		Cast.pose(kin, "leftShoulder", Cast.arm(kin, false, 0.9, 0.1), 0)
	end

	Stage.resetClock()
	Stage.fadeTo(0, 0.5)
	Stage.blurTo(6, 2)
	at(3.2)
	Stage.go(function()
		Cast.walk(papa, { W(-2, 24) }, 7, { ground = true })
	end)
	Stage.go(function()
		Cast.walk(kinA, { W(-17, 22) }, 6, { ground = true })
	end)
	Stage.go(function()
		Cast.walk(kinB, { W(15, 19) }, 6, { ground = true })
	end)
	at(3.8)
	focusFn = function()
		return (Cast.head(papa) + Cast.head(kinA) + Cast.head(kinB)) / 3
	end
	rate = 1.1
	at(5)
	-- you push yourself up to face them
	local standPos = diveTo + UP * me.lift
	local papaPos = papa.root.Position
	local standing = CFrame.lookAt(standPos, Vector3.new(papaPos.X, standPos.Y, papaPos.Z))
	Stage.go(function()
		Stage.animate(1.1, function(a)
			me.root.CFrame = prone:Lerp(standing, Stage.smooth(a))
		end)
		Cast.stand(me, 0.4)
	end)
	Stage.blurTo(2, 1.5)
	at(6.2)
	-- Papa revs the chainsaw
	Stage.sfx("Chainsaw", nil, papa.root.Position, 1)
	local chainsaw = papa.model:FindFirstChild("Chainsaw", true)
	local sawBody = chainsaw and chainsaw:FindFirstChild("Body", true)
	if sawBody and sawBody:IsA("BasePart") then
		local exhaust = Instance.new("Smoke")
		exhaust.Color = rgb(150, 160, 170)
		exhaust.Opacity = 0.25
		exhaust.RiseVelocity = 3
		exhaust.Size = 0.8
		exhaust.Parent = sawBody
	end
	Stage.go(function()
		local t = 0
		Stage.animate(3.2, function(a, dt)
			t += dt
			local raise = Util.lerp(0.4, 1.9, Stage.smooth(a * 3))
			Cast.pose(papa, "rightShoulder", Cast.arm(papa, true, raise + math.noise(t * 30) * 0.08, 0.1 + math.noise(t * 30, 2) * 0.05), 0)
		end)
	end)
	at(6.6)
	HUD.subtitle("Papa", "YOU BROKE MY TRUCK!", 3)
	focusFn = function()
		return Cast.head(papa)
	end
	rate = 2
	Stage.zoom(52, 0.8)
	CameraController.shake(0.5, 3)
	at(9.4)
	Stage.setBlack(1)
	Stage.stopCamera()
	CameraController.shake(1.2, 3)
	Stage.title("RUN.", { size = 130, color = Theme.Colors.BloodBright, fadeIn = 0.08, hold = 1.5, fadeOut = 0.6 })
	sleep(2.3)
end)

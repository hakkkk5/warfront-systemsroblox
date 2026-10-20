--!strict
-- TruckFound: the player walks into the logging clearing and finds the
-- broken-down pickup. Their eyes settle on it, a lightning flash cuts to a
-- letterboxed orbit (the gutted bonnet, then the jacked-up rear wheel), the
-- objective title rolls, and the camera glides back into the player's eyes so
-- control resumes looking at the truck.
--
-- Runs ~9 s (server timeout 14 s). Afterwards the server sets the Repair
-- stage and plays the "The engine's gone..." line, so the scene stays quiet
-- apart from one whisper at the start.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)

local TITLE = "THE TRUCK"
local SUBTITLE = "Find the engine, battery, spark plugs and a wheel."

-- timings (seconds)
local LOOK_TIME = 1.25 -- first-person turn toward the truck
local LOOK_HOLD = 0.3
local ORBIT_TIME = 5.6
local TITLE_DELAY = 0.8 -- the title (1 + hold + 0.8 s) is gone before the orbit ends
local TITLE_HOLD = 2.6
local SETTLE_TIME = 0.45

local BASE_FOV = 72 -- what Kit.finish restores
local NEAR_DISTANCE = 70 -- further away than this the camera blinks back instead of flying
local MAX_PITCH = math.rad(18)

-- Truck-local layout from Sites.buildTruck / Props.PickupTruck: the pivot is
-- the bottom centre, the bonnet faces -Z and the driver side is -X. Engine bay
-- z -8.5..-2.3 (bonnet top y 4.6), cab roof y 7, missing-wheel slot at
-- (-4.2, 1.6, 5.8) with the jack under it, work lamp post at (-7, -6) and the
-- log pile 17+ studs ahead. The keys below keep >= 2.4 studs from all of it.
type Shot = { pos: Vector3, look: Vector3, roll: number, fov: number }

local SHOTS: { Shot } = {
	-- wide and low from the front-right: the whole truck against the work lamp
	{ pos = Vector3.new(10, 3.4, -15.5), look = Vector3.new(0, 3, -0.5), roll = 0, fov = 50 },
	-- pushed in high over the grille, looking down at the bonnet / engine bay
	{ pos = Vector3.new(1.2, 8.8, -13.2), look = Vector3.new(0, 3.9, -5.6), roll = -3, fov = 54 },
	-- over the front-left wing, looking back down the driver side
	{ pos = Vector3.new(-6.4, 7.8, -2.2), look = Vector3.new(-3.9, 1.8, 6), roll = 2, fov = 57 },
	-- low beside the rear-left wheel slot and the jack
	{ pos = Vector3.new(-8.6, 2.5, 9.6), look = Vector3.new(-3.9, 1.4, 5.8), roll = 0, fov = 60 },
}

local FOCUS = Vector3.new(0, 3, -1.5) -- where the player's eyes settle (cab / bonnet)
local MOON = Vector3.new(-16, 26, -12) -- cold key light, high off the front-left
local WOODS = Vector3.new(-24, 3, 46) -- somewhere behind the truck, in the trees

---------------------------------------------------------------- helpers

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoother(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * x * (x * (x * 6 - 15) + 10)
end

local function tween(inst: Instance, duration: number, goal: { [string]: any }): Tween
	local t = TweenService:Create(inst, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal)
	t:Play()
	return t
end

-- Subtle breathing / hand sway for first-person shots.
local function handheld(t: number, amount: number): CFrame
	return CFrame.new(math.sin(t * 0.9) * 0.02 * amount, math.sin(t * 1.7) * 0.035 * amount, 0)
		* CFrame.Angles(
			math.sin(t * 1.3 + 0.4) * 0.006 * amount,
			math.sin(t * 0.8 + 1.7) * 0.008 * amount,
			math.sin(t * 0.6 + 1.1) * 0.004 * amount
		)
end

-- Look from `from` toward `target` with the pitch clamped, so a player standing
-- right beside the truck does not end up staring at their feet.
local function lookFrom(from: Vector3, target: Vector3, maxPitch: number): CFrame
	local d = target - from
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude < 0.05 then
		return CFrame.new(from)
	end
	local pitch = math.clamp(math.atan2(d.Y, flat.Magnitude), -maxPitch, maxPitch)
	local dir = flat.Unit * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
	return CFrame.lookAt(from, from + dir)
end

-- Yaw-only copy of a CFrame (the shot offsets assume an upright truck).
local function flatten(cf: CFrame): CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return CFrame.new(cf.Position)
	end
	return CFrame.lookAt(cf.Position, cf.Position + flat.Unit)
end

local function bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: number): Vector3
	local u = 1 - t
	return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
end

local function resolveTruck(data: any): CFrame?
	if typeof(data) == "table" and typeof(data.truck) == "CFrame" then
		return data.truck
	end
	-- missing payload: fall back to the replicated truck model
	local model = workspace:FindFirstChild("EscapeTruck", true)
	if model and model:IsA("Model") then
		return model:GetPivot()
	end
	return nil
end

-- The move from the last orbit key back into the player's head: leave the shot
-- heading for the player, then arrive from in front of their face, as if
-- pulling back into the eyes.
type Glide = { from: CFrame, to: CFrame, c1: Vector3, c2: Vector3, span: number, duration: number }

local function planGlide(from: CFrame, to: CFrame, truckPos: Vector3): Glide
	local a, d = from.Position, to.Position
	local span = (d - a).Magnitude
	local toTruck = Vector3.new(truckPos.X - d.X, 0, truckPos.Z - d.Z)
	local toward = if toTruck.Magnitude > 0.05 then toTruck.Unit else Vector3.zero
	-- the arrival point never reaches into the truck (half length ~9.5)
	local reach = math.clamp(toTruck.Magnitude - 11, 0, math.min(span * 0.35, 6))
	return {
		from = from,
		to = to,
		c1 = a + (d - a) * 0.33 + Vector3.new(0, math.min(span * 0.08, 2.5), 0),
		c2 = d + toward * reach + Vector3.new(0, 0.6, 0),
		span = span,
		duration = math.clamp(span / 11, 1.4, 2.2),
	}
end

-- Sweep a small sphere along the glide; any hit (truck, trees, lamp, a
-- cannibal) means the camera would clip, so the scene blinks back instead.
local function isClear(g: Glide, params: RaycastParams): boolean
	local prev = g.from.Position
	for i = 1, 12 do
		local p = bezier(g.from.Position, g.c1, g.c2, g.to.Position, i / 12)
		local step = p - prev
		if step.Magnitude > 0.01 and workspace:Spherecast(prev, 0.5, step, params) then
			return false
		end
		prev = p
	end
	return true
end

-- Double-pulse lightning flash that masks the cut; settles back to `base`.
local function lightning(kit: typeof(Kit), base: number)
	kit.flash(Color3.fromRGB(200, 215, 255), 0.45)
	kit.lighting({ Brightness = 2.8 }, 0.03)
	task.delay(0.08, function()
		kit.lighting({ Brightness = base + 0.3 }, 0.06)
		task.wait(0.1)
		kit.lighting({ Brightness = 2 }, 0.03)
		task.wait(0.07)
		kit.lighting({ Brightness = base }, 0.5)
	end)
end

---------------------------------------------------------------- scene

return function(data: any, kit: typeof(Kit))
	local player = kit.player
	local camera = kit.camera

	local truckCF = resolveTruck(data)
	if not truckCF then
		-- nothing to film: just the objective card over the current view
		kit.letterbox(true, 0.6)
		kit.wait(0.4)
		kit.title(TITLE, SUBTITLE, 2.2)
		kit.letterbox(false, 0.6)
		return
	end
	local base = flatten(truckCF)
	local function at(v: Vector3): Vector3
		return base:PointToWorldSpace(v)
	end
	local focus = at(FOCUS)

	-- the player's eyes: the camera at begin, following the body while it
	-- slides to a stop (movement is locked, not frozen)
	local startCF = kit.camCFrame()
	local character = player.Character
	local rootInst = character and character:FindFirstChild("HumanoidRootPart")
	local headInst = character and character:FindFirstChild("Head")
	local root: BasePart? = if rootInst and rootInst:IsA("BasePart") then rootInst else nil
	local head: BasePart? = if headInst and headInst:IsA("BasePart") then headInst else nil

	local eyeStart: Vector3? = nil
	if root then
		if head and (head.Position - startCF.Position).Magnitude > 4 then
			-- the camera was not in first person; use the head instead
			eyeStart = head.Position + Vector3.new(0, 0.25, 0)
		else
			eyeStart = startCF.Position
		end
	end
	local rootStart = if root then root.Position else Vector3.zero

	local function eyePos(): Vector3?
		if not eyeStart then
			return nil
		end
		if root and root.Parent then
			return eyeStart + (root.Position - rootStart)
		end
		return eyeStart
	end

	local near = false
	if eyeStart then
		local offset = eyeStart - base.Position
		near = Vector3.new(offset.X, 0, offset.Z).Magnitude < NEAR_DISTANCE
	end

	-- where the eyes end up: on the truck when close, otherwise where they were
	local function eyeCF(): CFrame?
		local p = eyePos()
		if not p then
			return nil
		end
		return if near then lookFrom(p, focus, MAX_PITCH) else CFrame.new(p) * startCF.Rotation
	end

	-- line-of-sight checks ignore every character and the camera's children
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { camera }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore

	local function shotCF(shot: Shot): CFrame
		local p = at(shot.pos)
		local pos = Vector3.new(p.X, math.max(p.Y, kit.ground(p.X, p.Z) + 1.2), p.Z)
		return CFrame.lookAt(pos, at(shot.look)) * CFrame.Angles(0, 0, math.rad(shot.roll))
	end

	-- Orbit order: bonnet first, wheel last. If the player stands where the
	-- glide home from the wheel would cut through the truck (e.g. the right
	-- side), play it reversed so it ends on the wide front-right shot instead.
	local order: { Shot } = table.clone(SHOTS)
	local eyeNow = eyeCF()
	if near and eyeNow then
		local fwd = planGlide(shotCF(SHOTS[#SHOTS]), eyeNow, base.Position)
		local rev = planGlide(shotCF(SHOTS[1]), eyeNow, base.Position)
		local fwdOk, revOk = isClear(fwd, params), isClear(rev, params)
		if revOk and (not fwdOk or rev.span + 6 < fwd.span) then
			local reversed: { Shot } = {}
			for i = #SHOTS, 1, -1 do
				table.insert(reversed, SHOTS[i])
			end
			order = reversed
		end
	end
	local keys: { CFrame } = {}
	for i, shot in order do
		keys[i] = shotCF(shot)
	end

	------------------------------------------------ 1. first person: the eyes find it
	local fov0 = camera.FieldOfView
	if near and eyeNow then
		local fromRot = startCF.Rotation
		local toRot = eyeNow.Rotation
		local elapsed = 0
		local stop = kit.follow(function(dt: number): CFrame?
			elapsed += dt
			local a = smoother(elapsed / LOOK_TIME)
			camera.FieldOfView = lerp(fov0, 64, a)
			local p = eyePos() or startCF.Position
			return CFrame.new(p) * fromRot:Lerp(toRot, a) * handheld(elapsed, 0.5 + 0.5 * a)
		end)
		kit.sound("Heartbeat", nil, 0.5)
		task.spawn(kit.say, "You", "...a truck.", 1.3)
		kit.wait(LOOK_TIME + LOOK_HOLD)
		stop()
	end

	------------------------------------------------ 2. lightning cut to the orbit
	if character then
		kit.hide(character)
	end
	local brightness0 = Lighting.Brightness
	local exposure0 = Lighting.ExposureCompensation
	kit.letterbox(true, 0.2)
	lightning(kit, brightness0)
	kit.lighting({ ExposureCompensation = exposure0 + 0.3 }, 1.2)
	local sting = kit.sound("Impact", nil, 0.6)
	if sting then
		sting.PlaybackSpeed = 0.42 -- a deep, dull thud
	end
	kit.shake(0.35, 3)
	kit.cam(keys[1], order[1].fov)

	-- moonlight breaking through, plus a faint fill riding with the camera so
	-- the truck reads even with the flashlight off; both fade before hand-off
	local moonPart = kit.part({
		Name = "TruckFoundMoon",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.lookAt(at(MOON), at(Vector3.new(0, 2.5, 0))),
	})
	local moon = Instance.new("SpotLight")
	moon.Face = Enum.NormalId.Front
	moon.Angle = 55
	moon.Range = 48
	moon.Brightness = 0
	moon.Color = Color3.fromRGB(150, 170, 215)
	moon.Shadows = true
	moon.Parent = moonPart
	tween(moon, 0.5, { Brightness = 2 })

	local fillPart = kit.part({
		Name = "TruckFoundFill",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = camera.CFrame,
	})
	local fill = Instance.new("PointLight")
	fill.Range = 14
	fill.Brightness = 0.55
	fill.Color = Color3.fromRGB(170, 186, 215)
	fill.Shadows = false
	fill.Parent = fillPart
	kit.track(RunService.RenderStepped:Connect(function()
		fillPart.CFrame = camera.CFrame * CFrame.new(0, 1.5, 0)
	end))

	local fovTween = tween(camera, ORBIT_TIME, { FieldOfView = order[#order].fov })
	task.delay(TITLE_DELAY, kit.title, TITLE, SUBTITLE, TITLE_HOLD)
	task.delay(1.7, function()
		kit.sound("Thunder", nil, 0.8)
		kit.shake(0.25, 2)
	end)
	task.delay(ORBIT_TIME - 1.4, function()
		kit.sound("Growl", at(WOODS), 0.5)
	end)
	kit.camPath(keys, ORBIT_TIME)
	fovTween:Cancel() -- the moves below drive the FOV themselves

	------------------------------------------------ 3. back into the player's eyes
	local eyeEnd = eyeCF()
	local glide = if near and eyeEnd then planGlide(kit.camCFrame(), eyeEnd, base.Position) else nil
	if glide and isClear(glide, params) then
		local g: Glide = glide
		kit.letterbox(false, 1)
		tween(moon, g.duration, { Brightness = 0 })
		tween(fill, g.duration, { Brightness = 0 })
		kit.lighting({ ExposureCompensation = exposure0 }, g.duration)

		local fovFrom = camera.FieldOfView
		local elapsed = 0
		local done = false
		local stop = kit.follow(function(dt: number): CFrame?
			elapsed += dt
			local u = math.clamp(elapsed / g.duration, 0, 1)
			local s = smoother(u)
			camera.FieldOfView = lerp(fovFrom, BASE_FOV, s)
			-- blend in any drift of the body so the landing is exact
			local live = eyePos() or g.to.Position
			local pos = bezier(g.from.Position, g.c1, g.c2, g.to.Position, s) + (live - g.to.Position) * s
			local rot = g.from.Rotation:Lerp(g.to.Rotation, smoother(u / 0.85))
			if u >= 1 then
				done = true
			end
			return CFrame.new(pos) * rot * handheld(elapsed, 0.6 * s)
		end)
		local started = os.clock()
		while not done and os.clock() - started < g.duration + 1 do
			task.wait()
		end
		stop()

		-- one breath behind the eyes before control returns
		local settle = elapsed
		stop = kit.follow(function(dt: number): CFrame?
			settle += dt
			camera.FieldOfView = BASE_FOV
			local p = eyePos() or g.to.Position
			return CFrame.new(p) * g.to.Rotation * handheld(settle, 0.6)
		end)
		kit.wait(SETTLE_TIME)
		stop()
	else
		-- too far away or no clear path: blink back into the body
		kit.eyes(0, 0.25)
		kit.letterbox(false, 0.2)
		moon.Brightness = 0
		fill.Brightness = 0
		kit.lighting({ ExposureCompensation = exposure0 }, 0.2)
		local eye = eyeCF()
		if eye then
			kit.cam(eye, BASE_FOV)
			kit.wait(0.25)
			local elapsed = 0
			local stop = kit.follow(function(dt: number): CFrame?
				elapsed += dt
				local p = eyePos() or eye.Position
				return CFrame.new(p) * eye.Rotation * handheld(elapsed, 0.6)
			end)
			kit.eyes(1, 0.5)
			kit.wait(0.2)
			stop()
		else
			-- no body to return to; Kit.finish opens the eyes again
			camera.FieldOfView = BASE_FOV
			kit.wait(0.3)
		end
	end
end

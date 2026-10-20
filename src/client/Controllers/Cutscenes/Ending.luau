--!strict
-- Ending (~30 s): the rescue helicopter lifts off at dawn, the family steps
-- out of the tree line to watch it go, "You escaped the Cannibal Family.", then
-- one sack-masked figure left standing in the trees.
-- data: { helicopter: Model?, pad: CFrame }

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Audio)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local Stage = require(script.Parent.Stage)
local Cast = require(script.Parent.Cast)

local rgb = Color3.fromRGB
local CF = CFrame.new
local ANG = CFrame.Angles
local UP = Vector3.yAxis
local at = Stage.at

-- Tweens a set of properties toward dawn and restores them when the scene ends.
local function dawn(inst: Instance?, goal: { [string]: any }, duration: number)
	if not inst then
		return
	end
	local saved: { [string]: any } = {}
	for key in goal do
		saved[key] = (inst :: any)[key]
	end
	local tween = Util.tween(inst, duration, goal, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	Stage.cleanup(function()
		tween:Cancel()
		for key, v in saved do
			(inst :: any)[key] = v
		end
	end)
end

return Stage.scene("Ending", function(data: any)
	local padSite = Config.Sites.Helipad.pos
	local pad = Stage.cf(data.pad, CF(padSite.X, Stage.groundY(padSite.X, padSite.Y), padSite.Y))
	local serverHeli = Stage.model(data.helicopter)
	Stage.fadeWait(1, 0.5)
	Stage.letterbox(true, 0)

	local landed = if serverHeli then serverHeli:GetPivot() else pad * CF(0, 0.8, 0) * ANG(0, math.rad(200), 0)
	local craft = Stage.cloneProp(serverHeli) or Cast.simpleHelicopter()
	Stage.hide(serverHeli)
	craft:PivotTo(landed)
	Cast.addCabin(craft, landed)
	local MAST = Vector3.new(0, 9.7, 0)
	local rotorParts: { { part: BasePart, offset: CFrame } } = {}
	local rotor = craft:FindFirstChild("Rotor")
	if rotor then
		for _, p in rotor:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(rotorParts, { part = p, offset = landed:ToObjectSpace(p.CFrame) })
			end
		end
	end

	-- dawn breaks over the whole scene
	dawn(Lighting, {
		ClockTime = 6.15,
		Brightness = 1.6,
		OutdoorAmbient = rgb(120, 104, 110),
		Ambient = rgb(44, 38, 42),
		ExposureCompensation = 0.1,
		ColorShift_Top = rgb(255, 196, 150),
	}, 24)
	dawn(Lighting:FindFirstChildOfClass("Atmosphere"), {
		Color = rgb(190, 150, 140),
		Decay = rgb(120, 90, 90),
		Density = 0.33,
		Haze = 1.6,
	}, 24)
	local grade = Lighting:FindFirstChild("Grade")
	dawn(if grade and grade:IsA("ColorCorrectionEffect") then grade else nil, {
		TintColor = rgb(255, 236, 220),
		Saturation = -0.1,
	}, 24)

	-- flight: lift off, turn toward the forest, climb away over the trees
	local padPos = pad.Position
	local wreckSite = Config.Sites.Wreck.pos
	local wreckPos = Vector3.new(wreckSite.X, Stage.groundY(wreckSite.X, wreckSite.Y), wreckSite.Y)
	local dir = Util.flat(wreckPos - padPos)
	dir = if dir.Magnitude > 1 then dir.Unit else Vector3.new(0, 0, -1)
	local rightDir = Vector3.new(-dir.Z, 0, dir.X)
	local leftDir = -rightDir
	local start = landed.Position
	local lift = start + UP * 16
	local route = Stage.spline({
		start,
		lift,
		lift + UP * 16 + dir * 40,
		lift + UP * 42 + dir * 150 + rightDir * 35,
		lift + UP * 58 + dir * 300 + rightDir * 80,
	})
	local FLIGHT = 22
	local flightT = 0
	local heliCF = landed
	local travel = CFrame.lookAt(Vector3.zero, dir)
	local tilt = 0
	local lastPos = start
	local function updateHeli(dt: number)
		flightT += dt
		local pos = Stage.splineAt(route, math.clamp(flightT / FLIGHT, 0, 1) ^ 1.7)
		local speed = (pos - lastPos).Magnitude / math.max(dt, 1e-3)
		lastPos = pos
		tilt = Util.lerp(tilt, -math.clamp(speed / 40, 0, 1) * 0.16, math.min(1, dt * 2))
		local rot = landed.Rotation:Lerp(travel, Stage.smooth(flightT / 5))
		heliCF = CF(pos) * rot * ANG(tilt, 0, math.sin(flightT * 0.6) * 0.025)
		craft:PivotTo(heliCF)
		local spin = CF(MAST) * ANG(0, os.clock() * 25, 0) * CF(-MAST)
		for _, e in rotorParts do
			e.part.CFrame = heliCF * spin * e.offset
		end
	end

	-- rotor wash kicking up dust on the pad
	local dustPart = Stage.part(Vector3.new(30, 1, 30), CF(padPos + UP * 0.5), rgb(0, 0, 0), nil, { Transparency = 1 })
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(rgb(150, 135, 115))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(1.5, 2.5)
	dust.Speed = NumberRange.new(10, 18)
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Rate = 50
	dust.Parent = dustPart

	-- the family steps out of the tree line to watch them go
	local watchers: { Cast.Actor } = {}
	for i, kind in { "Papa", "Hunter", "Kin", "Scavenger", "Kin" } do
		local offset = (i - 3) * 9
		local from = Stage.ground(padPos + leftDir * 50 + dir * offset)
		local to = Stage.ground(padPos + leftDir * 41 + dir * offset * 0.9)
		local a = Cast.actor(kind, CFrame.lookAt(from, Vector3.new(to.X, from.Y, to.Z)))
		if kind == "Kin" then
			Cast.lantern(a)
			Cast.pose(a, "leftShoulder", Cast.arm(a, false, 0.8, 0.1), 0)
		end
		Cast.play(a, "idle")
		table.insert(watchers, a)
	end

	Stage.resetClock()
	for i, a in watchers do
		Stage.go(function()
			at(3.6 + i * 0.25)
			Cast.walk(a, { padPos + leftDir * 41 + dir * (i - 3) * 8.1 }, 3.2, { ground = true })
			Cast.pose(a, "neck", Cast.neck(a, 0.55, 0, (i % 2 - 0.5) * 0.3), 1.2)
		end)
	end

	-- lift-off from the edge of the pad
	local camPos1 = padPos + rightDir * 20 - dir * 22 + UP * 3.2
	Stage.track(function(dt)
		updateHeli(dt)
		return CFrame.lookAt(camPos1, heliCF.Position + UP * 5)
	end)
	Stage.zoom(55, 0)
	Stage.fadeTo(0, 1.2)
	Stage.later(5, function()
		dust.Enabled = false
	end)

	-- out of the side door, looking down at them, then out toward the forest
	at(4.6)
	local pitchV = Stage.numberValue(-0.62)
	local yawV = Stage.numberValue(math.pi / 2 - 0.2)
	Stage.track(function(dt)
		updateHeli(dt)
		local t = os.clock()
		local rattle = ANG(math.noise(t * 7, 1) * 0.006, math.noise(t * 7, 2) * 0.006, 0)
		return heliCF * CF(-2.3, 5.7, 0.6) * ANG(0, yawV.Value, 0) * ANG(pitchV.Value, 0, 0) * rattle
	end)
	Stage.zoom(68, 0)
	Util.tween(pitchV, 7.8, { Value = -0.3 })
	Util.tween(yawV, 7.8, { Value = math.pi / 2 - 0.55 })

	-- wide: the helicopter heads off into the dawn
	at(12.4)
	local camPos3 = heliCF.Position + rightDir * 34 - dir * 30 + UP * 6
	Stage.track(function(dt)
		updateHeli(dt)
		return CFrame.lookAt(camPos3, heliCF.Position)
	end)
	Stage.zoom(50, 0)
	at(13.2)
	Stage.title("You escaped the Cannibal Family.", { size = 54, color = Theme.Colors.Bone, fadeIn = 1.6, hold = 3.2, fadeOut = 1.2 })
	at(16.8)
	Audio.loop("HelicopterLoop", false)
	at(18.4)
	Stage.fadeTo(1, 1.2)

	-- one of them is still standing in the trees
	at(19.8)
	for _, a in watchers do
		a.model:Destroy()
	end
	local figurePos = Stage.ground(padPos + leftDir * 47 + dir * 6)
	local figure = Cast.actor("Butcher", CFrame.lookAt(figurePos, Vector3.new(padPos.X, figurePos.Y, padPos.Z)))
	Cast.play(figure, "idle")
	local head = Cast.head(figure)
	local camFrom = Stage.ground(padPos + leftDir * 30 + dir * 2) + UP * 4.2
	local camTo = Stage.ground(padPos + leftDir * 35 + dir * 4) + UP * 4.6
	Stage.shot(7.8, { camFrom, camTo }, { head, head + UP * 0.2 }, { fov = 42, wait = false })
	Stage.fadeTo(0, 1.4)
	at(22.6)
	Cast.pose(figure, "neck", Cast.neck(figure, 0.1, 0, 0.42), 1.4)
	for _, d in figure.model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Eye" then
			Util.tween(d, 1.4, { Transparency = 0.1 })
		end
	end
	at(23.2)
	local last = Stage.title("…they are still hungry.", { size = 46, color = Theme.Colors.BloodBright, fadeIn = 1.6 })
	at(27.6)
	Stage.setBlack(1)
	Stage.stopCamera()
	Stage.sleep(0.8)
	Util.tween(last, 0.8, { TextTransparency = 1 })
	Stage.sleep(0.9)
end)

--!strict
-- Downed (~18 s): the rescue helicopter lifts off with everyone aboard and
-- heads for Pinecrest... someone on the ridge, a shot, the tail rotor goes,
-- and it spins down into the trees. A local copy flies the route; the real
-- one is hidden (the server leaves it as the wreck at the crash site).
-- data: { helicopter: Model, crash: CFrame }

local RunService = game:GetService("RunService")

local CameraController = require(script.Parent.Parent.CameraController)
local Settings = require(script.Parent.Parent.Settings)
local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local Stage = require(script.Parent.Stage)

local at = Stage.at

local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

return Stage.scene("Downed", function(data: any)
	local original = data.helicopter
	local crash = Stage.cf(data.crash, workspace.CurrentCamera.CFrame)
	Stage.fadeWait(1, 0.4)
	Stage.letterbox(true, 0)
	if typeof(original) ~= "Instance" or not original:IsA("Model") then
		Stage.sleep(2)
		return
	end

	-- the copy we fly, and the real one hidden meanwhile
	local heli = original:Clone()
	for _, d in heli:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	heli.Parent = workspace
	local hidden: { BasePart } = {}
	for _, d in original:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			table.insert(hidden, d)
		end
	end
	Stage.cleanup(function()
		heli:Destroy()
		for _, p in hidden do
			p.LocalTransparencyModifier = 0
		end
	end)
	local rotorParts: { { part: BasePart, offset: CFrame } } = {}
	local rotor = heli:FindFirstChild("Rotor")
	if rotor then
		for _, p in rotor:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(rotorParts, { part = p, offset = heli:GetPivot():ToObjectSpace(p.CFrame) })
			end
		end
	end
	local mast = Vector3.new(0, 9.7, 0)

	-- the route: up off the pad, south toward Pinecrest, then the spiral down
	local start = heli:GetPivot()
	local p0 = start.Position
	local p1 = p0 + Vector3.new(0, 32, 0)
	local target = crash.Position
	local flat = Vector3.new(target.X - p1.X, 0, target.Z - p1.Z).Unit
	local p2 = target - flat * 110 + Vector3.new(0, 55, 0)
	local p3 = target + Vector3.new(0, 2, 0)
	local HIT, IMPACT = 10, 14.5

	local tail: BasePart? = heli:FindFirstChildWhichIsA("BasePart", true)
	local function where(t: number): CFrame
		local pos: Vector3
		local yaw = math.atan2(-flat.X, -flat.Z)
		local pitch, roll = 0, 0
		if t < 3 then
			pos = p0:Lerp(p1, ease(t / 3))
		elseif t < HIT then
			pos = p1:Lerp(p2, (t - 3) / (HIT - 3))
			pitch = -0.12
		else
			local k = math.min(1, (t - HIT) / (IMPACT - HIT))
			local wobble = Vector3.new(math.sin(t * 5) * 6 * (1 - k), 0, math.cos(t * 5) * 6 * (1 - k))
			pos = p2:Lerp(p3, k * k) + wobble
			yaw += (t - HIT) ^ 2 * 1.6
			pitch = -0.25 * k
			roll = math.sin(t * 3) * 0.3
		end
		return CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
	end

	Stage.loop("HelicopterLoop", true, 0.7)
	Stage.resetClock()
	local t0 = os.clock()
	local done = false
	Stage.go(function()
		while not done do
			local t = os.clock() - t0
			local body = where(math.min(t, IMPACT))
			heli:PivotTo(body)
			local spin = CFrame.new(mast) * CFrame.Angles(0, os.clock() * (if t < IMPACT then 25 else 0), 0) * CFrame.new(-mast)
			for _, entry in rotorParts do
				entry.part.CFrame = body * spin * entry.offset
			end
			-- camera: from the pad, then chasing it, then too close
			local camPos: Vector3
			if t < 4 then
				camPos = p0 + Vector3.new(22, 4, 26)
			elseif t < HIT then
				camPos = body.Position - flat * 34 + Vector3.new(0, 13, 0)
			else
				camPos = body.Position - flat * 24 + Vector3.new(math.sin(t * 2) * 8, 10, math.cos(t * 2) * 8)
			end
			Stage.cut(CFrame.lookAt(camPos, body.Position + Vector3.new(0, 3, 0)), if t < 4 then 50 else 62)
			RunService.RenderStepped:Wait()
		end
	end)
	Stage.cleanup(function()
		done = true
	end)

	Stage.fadeTo(0, 0.8)
	at(1)
	HUD.subtitle("Pilot", "Hold on to something. Next stop, Pinecrest General.", 3.4)
	at(4.6)
	HUD.subtitle("You", "We made it... we actually made it out.", 3)
	at(7.6)
	HUD.subtitle("Pilot", "Is that... somebody standing on the ridge? With a-", 2.2)
	at(HIT - 0.2)
	Stage.sfx("Explosion", nil, heli:GetPivot().Position, 1)
	CameraController.shake(0.9, 2)
	if tail then
		local fire = Instance.new("Fire")
		fire.Size = 7
		fire.Heat = 12
		fire.Parent = tail
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(30, 28, 26)
		smoke.Size = 6
		smoke.RiseVelocity = 3
		smoke.Opacity = 0.5
		smoke.Parent = tail
	end
	at(HIT + 0.3)
	HUD.subtitle("Pilot", "We're hit! Tail rotor's gone - BRACE! BRACE!", 3.5)
	Stage.sfx("Radio", nil, nil, 0.4)
	at(12.2)
	CameraController.shake(1.2, 1)
	Stage.sfx("Scream", nil, nil, 0.5, 0.8)
	at(IMPACT)
	Stage.loop("HelicopterLoop", false)
	Stage.sfx("Crash", nil, nil, 1)
	Stage.sfx("Explosion", nil, nil, 1, 0.8)
	CameraController.shake(2, 1.5)
	if Settings.reduceFlashing then
		Stage.fadeTo(1, 0.15)
	else
		Stage.flashWhite(0.2)
		Stage.fadeTo(1, 0.25)
	end
	at(IMPACT + 1.8)
	HUD.subtitle("You", "...", 1.5)
	at(IMPACT + 3.2)
	done = true
end)

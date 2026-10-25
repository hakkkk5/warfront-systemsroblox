--!strict
-- The chase hazards the server calls out (Chase.luau), drawn here:
--   spike: a red circle tightens on the ground, then black-red spikes of
--          corrupted bone burst up out of it
--   tree:  a red strip flashes across the path, then a burning pine comes
--          crashing down along it and lies there burning
-- While you have adrenaline the view widens and pulses red.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Audio = require(script.Parent.Audio)
local CameraController = require(script.Parent.CameraController)
local Effects = require(script.Parent.Effects)

local ChaseFX = {}

local rgb = Color3.fromRGB
local UP = Vector3.yAxis
local RED = rgb(255, 30, 20)

local folder: Folder
local player = Players.LocalPlayer

local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = folder
	return p
end

local function shakeNear(pos: Vector3, radius: number, strength: number)
	local d = (workspace.CurrentCamera.CFrame.Position - pos).Magnitude
	if d < radius then
		CameraController.shake(strength * (1 - d / radius), 5)
	end
end

local function burst(pos: Vector3, color: Color3, amount: number)
	local holder = part(Vector3.one, CFrame.new(pos), color, Enum.Material.SmoothPlastic, { Transparency = 1 })
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(color)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.6, 1.2)
	dust.Speed = NumberRange.new(6, 14)
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.Rate = 0
	dust.Parent = holder
	dust:Emit(amount)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

---------------------------------------------------------------- spikes

local function spikes(pos: Vector3, delay: number)
	-- the warning: a red disc and a ring closing in on it
	local radius = 3.8
	local disc = part(Vector3.new(0.12, radius * 2, radius * 2), CFrame.new(pos + UP * 0.08) * CFrame.Angles(0, 0, math.rad(90)), RED, Enum.Material.Neon, {
		Shape = Enum.PartType.Cylinder,
		Transparency = 0.65,
	})
	local ring = part(Vector3.new(0.1, radius * 4.4, radius * 4.4), CFrame.new(pos + UP * 0.1) * CFrame.Angles(0, 0, math.rad(90)), RED, Enum.Material.Neon, {
		Shape = Enum.PartType.Cylinder,
		Transparency = 0.82,
	})
	TweenService:Create(ring, TweenInfo.new(delay, Enum.EasingStyle.Linear), { Size = Vector3.new(0.1, radius * 2, radius * 2), Transparency = 0.4 }):Play()
	TweenService:Create(disc, TweenInfo.new(delay / 3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.3 }):Play()
	task.wait(delay)
	disc:Destroy()
	ring:Destroy()

	-- the eruption
	Audio.play("Impact", pos, 1, 0.55)
	Audio.play("Chop", pos, 0.8, 0.5)
	shakeNear(pos, 30, 2.2)
	burst(pos, rgb(40, 12, 10), 25)
	local made: { BasePart } = {}
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2 + math.random() * 0.5
		local r = math.random() * 2.6
		local h = 3.5 + math.random() * 5
		local base = pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local tilt = CFrame.Angles(math.rad(math.random(-22, 22)), math.random() * math.pi * 2, math.rad(math.random(-22, 22)))
		local spike = Instance.new("WedgePart")
		spike.Anchored = true
		spike.CanCollide = false
		spike.CanQuery = false
		spike.CanTouch = false
		spike.Size = Vector3.new(0.5 + math.random() * 0.5, h, 1 + math.random() * 0.8)
		spike.Color = if i % 3 == 0 then rgb(140, 20, 16) else rgb(26, 14, 14)
		spike.Material = if i % 3 == 0 then Enum.Material.Neon else Enum.Material.Slate
		spike.CFrame = CFrame.new(base - UP * h) * tilt
		spike.Parent = folder
		TweenService:Create(spike, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = CFrame.new(base + UP * (h / 2 - 0.3)) * tilt }):Play()
		table.insert(made, spike)
	end
	task.wait(1.7)
	for _, s in made do
		TweenService:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = s.CFrame - UP * s.Size.Y }):Play()
	end
	task.wait(0.65)
	for _, s in made do
		s:Destroy()
	end
end

---------------------------------------------------------------- falling trees

local function burningTree(base: Vector3, fall: Vector3, length: number, delay: number)
	local mid = base + fall * length / 2
	local strip = part(Vector3.new(3.2, 0.12, length), CFrame.lookAt(mid + UP * 0.1, mid + fall + UP * 0.1), RED, Enum.Material.Neon, { Transparency = 0.6 })
	TweenService:Create(strip, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.25 }):Play()

	-- the tree: trunk along its own X axis, so "upright" turns X to UP
	local model = Instance.new("Model")
	model.Name = "BurningTree"
	model.Parent = folder
	local pieces: { { part: Part, offset: CFrame } } = {}
	local function piece(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, props: { [string]: any }?)
		local p = part(size, CFrame.identity, color, material, props)
		p.Parent = model
		table.insert(pieces, { part = p, offset = offset })
		return p
	end
	-- offsets are relative to the base, with +Y up along the trunk
	local trunk = piece(Vector3.new(length, 1.9, 1.9), CFrame.new(0, length / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(40, 28, 20), Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	for i = 0, 3 do
		local y = length * (0.45 + i * 0.15)
		local s = 7 - i * 1.5
		piece(Vector3.new(s, 2.6, s), CFrame.new(0, y, 0) * CFrame.Angles(0, i * 0.7, 0), if i % 2 == 0 then rgb(30, 24, 18) else rgb(60, 26, 12), Enum.Material.Slate)
	end
	for i = 1, 3 do
		local fire = Instance.new("Fire")
		fire.Size = 8
		fire.Heat = 12
		fire.Color = rgb(255, 120, 40)
		fire.SecondaryColor = rgb(255, 40, 10)
		local holder = piece(Vector3.one, CFrame.new(0, length * (0.35 + i * 0.18), 0), rgb(0, 0, 0), Enum.Material.SmoothPlastic, { Transparency = 1 })
		fire.Parent = holder
	end
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 130, 50)
	light.Range = 34
	light.Brightness = 3
	light.Parent = trunk

	local axis = UP:Cross(fall)
	axis = if axis.Magnitude > 1e-3 then axis.Unit else Vector3.xAxis
	local function place(angle: number)
		local rot = CFrame.fromAxisAngle(axis, angle)
		local frame = CFrame.new(base) * rot
		for _, e in pieces do
			e.part.CFrame = frame * e.offset
		end
	end
	place(math.rad(6))
	-- it creaks over...
	Audio.play("Whoosh", base, 0.8, 0.5)
	local start = os.clock()
	while os.clock() - start < delay do
		local t = (os.clock() - start) / delay
		place(math.rad(6 + 20 * t * t))
		task.wait()
	end
	-- ...and comes down
	local fallTime = 0.45
	local t0 = os.clock()
	while os.clock() - t0 < fallTime do
		local t = (os.clock() - t0) / fallTime
		place(math.rad(26 + 62 * t * t))
		RunService.Heartbeat:Wait()
	end
	place(math.rad(88))
	strip:Destroy()
	Audio.play("Crash", mid, 1, 0.6)
	Audio.play("Impact", mid, 1, 0.5)
	shakeNear(mid, 45, 2.8)
	burst(mid, rgb(255, 120, 40), 30)
	burst(mid, rgb(50, 44, 40), 20)
	task.wait(10)
	for _, e in pieces do
		TweenService:Create(e.part, TweenInfo.new(1), { Transparency = 1 }):Play()
	end
	task.wait(1)
	model:Destroy()
end

---------------------------------------------------------------- adrenaline

local function adrenaline(on: boolean)
	CameraController.setBaseFov(if on then 84 else 72)
	if on then
		Audio.play("Heartbeat", nil, 0.9, 1.3)
		Effects.flash(RED, 0.4)
	end
end

function ChaseFX.init()
	folder = Instance.new("Folder")
	folder.Name = "ChaseFX"
	folder.Parent = workspace
	Net.event("ChaseFX").OnClientEvent:Connect(function(kind, a, b, c, d)
		if kind == "spike" and typeof(a) == "Vector3" and typeof(b) == "number" then
			task.spawn(spikes, a, b)
		elseif kind == "tree" and typeof(a) == "Vector3" and typeof(b) == "Vector3" and typeof(c) == "number" and typeof(d) == "number" then
			task.spawn(burningTree, a, b, c, d)
		end
	end)
	player:GetAttributeChangedSignal("Adrenaline"):Connect(function()
		adrenaline(player:GetAttribute("Adrenaline") == true)
	end)
	-- the pulse while you run
	task.spawn(function()
		while true do
			task.wait(0.9)
			if player:GetAttribute("Adrenaline") == true then
				Audio.play("Heartbeat", nil, 0.6, 1.4)
				Effects.flash(rgb(120, 0, 0), 0.25)
			end
		end
	end)
end

return ChaseFX

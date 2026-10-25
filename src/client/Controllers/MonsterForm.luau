--!strict
-- When one of the family spots you, it stops pretending to be a man: legs
-- and arms stretch out, the body rises up on them, the neck pulls long, the
-- skin goes grey, spikes split out of its back and arms and the eyes burn
-- red. It settles back into a person once it has lost you.
--
-- Purely visual and done on every client: limb sizes and joint offsets are
-- changed locally, so the server's physics and hit boxes don't change.
-- Works on R6 rigs (the family is R6); anything else just gets the eyes.
-- Rigs wearing Blender bodies (CannibalSkins) swap to their monster parts
-- (stretched clawed arms, the distorted face) instead of growing spikes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Audio = require(script.Parent.Audio)
local CameraController = require(script.Parent.CameraController)
local CannibalSkins = require(script.Parent.CannibalSkins)
local Effects = require(script.Parent.Effects)

local MonsterForm = {}

local LEG = 1.8
local ARM = 1.9
local TORSO = 1.3
local NECK = 0.5
local TIME = 0.45

type Saved = {
	sizes: { [BasePart]: Vector3 },
	c0: { [Motor6D]: CFrame },
	c1: { [Motor6D]: CFrame },
	colors: { [BasePart]: Color3 },
	eyes: { [BasePart]: { size: Vector3, transparency: number } },
}

local saved: { [Model]: Saved } = {}
local extras: { [Model]: { Instance } } = {}
local monstrous: { [Model]: boolean } = {}
local tracked: { [Model]: boolean } = {}

local function withY(cf: CFrame, y: number): CFrame
	return CFrame.new(cf.X, y, cf.Z) * cf.Rotation
end

local function tween(inst: Instance, props: { [string]: any }, quick: boolean)
	if quick then
		for k, v in props do
			(inst :: any)[k] = v
		end
	else
		TweenService:Create(inst, TweenInfo.new(TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), props):Play()
	end
end

local function partNamed(model: Model, name: string): BasePart?
	local p = model:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

local function motorIn(parent: Instance?, name: string): Motor6D?
	local m = parent and parent:FindFirstChild(name)
	return if m and m:IsA("Motor6D") then m else nil
end

local function remember(model: Model): Saved
	local s = saved[model]
	if s then
		return s
	end
	local record: Saved = { sizes = {}, c0 = {}, c1 = {}, colors = {}, eyes = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			record.sizes[d] = d.Size
			record.colors[d] = d.Color
			if d.Name == "Eye" then
				record.eyes[d] = { size = d.Size, transparency = d.Transparency }
			end
		elseif d:IsA("Motor6D") then
			record.c0[d] = d.C0
			record.c1[d] = d.C1
		end
	end
	saved[model] = record
	return record
end

-- Spikes split out of the back and along the arms (local parts, welded).
local function grow(model: Model, quick: boolean): { Instance }
	local made: { Instance } = {}
	local torso = partNamed(model, "Torso")
	local function spike(parent: BasePart, offset: CFrame, length: number)
		-- a thin wedge reads as a blade of bone breaking through
		local full = Vector3.new(0.14, length, 0.55)
		local p = Instance.new("WedgePart")
		p.Name = "MonsterSpike"
		p.Size = if quick then full else Vector3.new(0.14, 0.2, 0.2)
		p.Color = Color3.fromRGB(196, 186, 168)
		p.Material = Enum.Material.Slate
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.CFrame = parent.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = parent
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
		if not quick then
			TweenService:Create(p, TweenInfo.new(TIME * 1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = full }):Play()
		end
		table.insert(made, p)
	end
	if torso then
		local ts = torso.Size
		for i = 0, 4 do
			local y = ts.Y * (0.38 - i * 0.18)
			local x = (if i % 2 == 0 then 0.25 else -0.25) * ts.X
			spike(torso, CFrame.new(x, y, ts.Z / 2 + 0.25) * CFrame.Angles(math.rad(-70 - i * 4), 0, math.rad((i - 2) * 9)), 1.2 + (i % 3) * 0.4)
		end
	end
	for _, name in { "Left Arm", "Right Arm" } do
		local arm = partNamed(model, name)
		if arm then
			for i = 0, 1 do
				spike(arm, CFrame.new(0, arm.Size.Y * (0.25 - i * 0.35), arm.Size.Z / 2 + 0.15) * CFrame.Angles(math.rad(-60), 0, 0), 0.9)
			end
		end
	end
	-- a red glow around the head
	local head = partNamed(model, "Head")
	if head then
		local glow = Instance.new("PointLight")
		glow.Name = "MonsterGlow"
		glow.Color = Color3.fromRGB(255, 30, 20)
		glow.Range = 14
		glow.Brightness = 2.5
		glow.Parent = head
		table.insert(made, glow)
	end
	return made
end

-- Turns a rig into the monster (on) or back (off). quiet: no scream/flash.
function MonsterForm.apply(model: Model, on: boolean, quiet: boolean?, quick: boolean?)
	if (monstrous[model] or false) == on then
		return
	end
	monstrous[model] = on
	local s = remember(model)
	local fast = quick == true
	local skinned = CannibalSkins.setForm(model, on)
	local torso = partNamed(model, "Torso")
	local root = partNamed(model, "HumanoidRootPart")

	if on then
		if torso and root then
			local t0 = s.sizes[torso]
			local unit = t0.Y / 2 -- 1 for a standard R6 body
			local torsoH = t0.Y * TORSO
			local legGain = 0
			for _, name in { "Left Leg", "Right Leg" } do
				local leg = partNamed(model, name)
				if leg then
					local l0 = s.sizes[leg]
					legGain = l0.Y * (LEG - 1)
					tween(leg, { Size = Vector3.new(l0.X * 0.8, l0.Y * LEG, l0.Z * 0.8) }, fast)
				end
			end
			for _, name in { "Left Arm", "Right Arm" } do
				local arm = partNamed(model, name)
				if arm then
					local a0 = s.sizes[arm]
					tween(arm, { Size = Vector3.new(a0.X * 0.75, a0.Y * ARM, a0.Z * 0.75) }, fast)
				end
			end
			tween(torso, { Size = Vector3.new(t0.X * 0.85, torsoH, t0.Z * 0.8) }, fast)
			local neck = motorIn(torso, "Neck")
			if neck then
				tween(neck, { C0 = withY(s.c0[neck], torsoH / 2 + NECK * unit) * CFrame.Angles(math.rad(-12), 0, 0) }, fast)
			end
			for _, name in { "Left Shoulder", "Right Shoulder" } do
				local m = motorIn(torso, name)
				local arm = partNamed(model, if name == "Left Shoulder" then "Left Arm" else "Right Arm")
				if m and arm then
					local a0 = s.sizes[arm]
					tween(m, { C0 = withY(s.c0[m], torsoH / 2 - 0.5 * unit), C1 = withY(s.c1[m], a0.Y * ARM / 2 - 0.5 * unit) }, fast)
				end
			end
			for _, name in { "Left Hip", "Right Hip" } do
				local m = motorIn(torso, name)
				local leg = partNamed(model, if name == "Left Hip" then "Left Leg" else "Right Leg")
				if m and leg then
					local l0 = s.sizes[leg]
					tween(m, { C0 = withY(s.c0[m], -torsoH / 2), C1 = withY(s.c1[m], l0.Y * LEG / 2) }, fast)
				end
			end
			local rootJoint = motorIn(root, "RootJoint")
			if rootJoint then
				local rise = legGain + (torsoH - t0.Y) / 2
				tween(rootJoint, { C0 = CFrame.new(0, rise, 0) * s.c0[rootJoint] }, fast)
			end
		end
		-- grey dead skin, burning eyes
		for part, color in s.colors do
			if part.Parent and (part.Name == "Head" or part.Name == "Left Arm" or part.Name == "Right Arm") then
				tween(part, { Color = Color3.fromRGB(104, 98, 94) }, fast)
			elseif part.Parent and (part.Name == "Torso" or part.Name == "Left Leg" or part.Name == "Right Leg") then
				tween(part, { Color = color:Lerp(Color3.new(0, 0, 0), 0.45) }, fast)
			end
		end
		for eye, e in s.eyes do
			if eye.Parent then
				eye.Transparency = 0
				eye.Color = Color3.fromRGB(255, 40, 20)
				tween(eye, { Size = e.size * 1.6 }, fast)
			end
		end
		if not skinned then
			extras[model] = grow(model, fast)
		end
		if not quiet then
			local head = partNamed(model, "Head")
			local camera = workspace.CurrentCamera
			if head then
				local distance = (camera.CFrame.Position - head.Position).Magnitude
				Audio.play("Scream", head.Position, 1, 0.75 + math.random() * 0.15)
				if distance < 70 then
					local strength = 1 - distance / 70
					CameraController.shake(0.6 + strength * 1.6, 3)
					Effects.flash(Color3.fromRGB(160, 10, 8), 0.25 + strength * 0.35)
				end
			end
		end
	else
		for part, size in s.sizes do
			if part.Parent and part.Name ~= "MonsterSpike" then
				tween(part, { Size = size, Color = s.colors[part] }, fast)
			end
		end
		for m, c0 in s.c0 do
			if m.Parent then
				tween(m, { C0 = c0, C1 = s.c1[m] }, fast)
			end
		end
		for eye, e in s.eyes do
			if eye.Parent then
				eye.Transparency = e.transparency
			end
		end
		local made = extras[model]
		if made then
			for _, inst in made do
				inst:Destroy()
			end
		end
		extras[model] = nil
	end
end

local function watch(model: Model)
	if tracked[model] or model:GetAttribute("Kind") == nil then
		return
	end
	tracked[model] = true
	local serial = 0
	local function update()
		local state = model:GetAttribute("State")
		local hunting = state == "Chase" or state == "Grab"
		serial += 1
		local mine = serial
		if hunting then
			MonsterForm.apply(model, true)
		else
			-- stay a monster a moment after losing you
			task.delay(2.5, function()
				if mine == serial and model.Parent then
					MonsterForm.apply(model, false)
				end
			end)
		end
	end
	model:GetAttributeChangedSignal("State"):Connect(update)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			tracked[model] = nil
			saved[model] = nil
			extras[model] = nil
			monstrous[model] = nil
		end
	end)
	update()
end

function MonsterForm.init()
	for _, inst in CollectionService:GetTagged("KeyframeAnimated") do
		if inst:IsA("Model") and not Players:GetPlayerFromCharacter(inst) then
			task.defer(watch, inst)
		end
	end
	CollectionService:GetInstanceAddedSignal("KeyframeAnimated"):Connect(function(inst: Instance)
		if inst:IsA("Model") and inst:IsDescendantOf(workspace) and not Players:GetPlayerFromCharacter(inst) then
			local model = inst :: Model
			task.delay(0.5, function()
				watch(model)
			end)
		end
	end)
end

return MonsterForm

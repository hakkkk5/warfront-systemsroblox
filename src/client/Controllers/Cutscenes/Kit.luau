--!strict
-- Shared toolkit for cutscenes: camera moves, letterbox, fades, eye blinks,
-- titles, subtitles, local actors and automatic cleanup. Every scene module
-- receives this kit; anything it creates through the kit is undone by
-- Kit.finish().

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Audio)
local CameraController = require(script.Parent.Parent.CameraController)
local Effects = require(script.Parent.Parent.Effects)
local Movement = require(script.Parent.Parent.Movement)
local Viewmodel = require(script.Parent.Parent.Viewmodel)
local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)

local Kit = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local gui: ScreenGui
local topBar: Frame
local bottomBar: Frame
local fadeFrame: Frame
local lidTop: Frame
local lidBottom: Frame
local titleLabel: TextLabel
local subLabel: TextLabel
local hintLabel: TextLabel

-- cleanup bookkeeping
local tracked: { Instance } = {}
local connections: { RBXScriptConnection } = {}
local hiddenParts: { [BasePart]: number } = {}
local lightingDefaults: { [string]: any } = {}

-- camera state: either a fixed CFrame or a per-frame function
local camCF = CFrame.new()
local camFn: ((dt: number) -> CFrame?)? = nil
local renderBound = false

Kit.camera = camera
Kit.player = player

---------------------------------------------------------------- lifecycle

function Kit.init()
	gui = Theme.screen("CutsceneKit", 9)
	gui.Enabled = false
	topBar = Theme.frame(gui, {
		Size = UDim2.new(1, 0, 0.12, 0),
		Position = UDim2.fromScale(0, -0.12),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 20,
	})
	bottomBar = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(1, 0, 0.12, 0),
		Position = UDim2.fromScale(0, 1.12),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 20,
	})
	lidTop = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(1, 0, 0.55, 0),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 25,
	})
	Util.create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 0.6) }),
		Parent = lidTop,
	})
	lidBottom = Theme.frame(gui, {
		Size = UDim2.new(1, 0, 0.55, 0),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 25,
	})
	Util.create("UIGradient", {
		Rotation = -90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 0.6) }),
		Parent = lidBottom,
	})
	fadeFrame = Theme.frame(gui, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 30,
	})
	titleLabel = Theme.label(gui, "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0.9, 0, 0, 110),
		TextSize = 92,
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.BloodBright,
		TextTransparency = 1,
		ZIndex = 40,
	})
	subLabel = Theme.label(gui, "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 80),
		Size = UDim2.new(0.8, 0, 0, 40),
		TextSize = 26,
		TextColor3 = Theme.Colors.Bone,
		TextTransparency = 1,
		ZIndex = 40,
	})
	hintLabel = Theme.label(gui, "", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.86, 0),
		Size = UDim2.new(0.6, 0, 0, 30),
		TextSize = 20,
		Font = Theme.Fonts.UIBold,
		TextColor3 = Theme.Colors.Bone,
		TextTransparency = 1,
		ZIndex = 40,
	})
end

-- Take over the camera and lock the player. Called by the dispatcher.
function Kit.begin()
	Movement.locked = true
	Viewmodel.hidden = true
	HUD.setVisible(false)
	CameraController.setEnabled(false)
	camera.CameraType = Enum.CameraType.Scriptable
	camCF = camera.CFrame
	camFn = nil
	gui.Enabled = true
	fadeFrame.BackgroundTransparency = 1
	lidTop.Position = UDim2.fromScale(0, 0)
	lidBottom.Position = UDim2.fromScale(0, 1)
	titleLabel.TextTransparency = 1
	subLabel.TextTransparency = 1
	hintLabel.TextTransparency = 1
	if not renderBound then
		renderBound = true
		RunService:BindToRenderStep("CutsceneCamera", Enum.RenderPriority.Camera.Value + 5, function(dt: number)
			if camFn then
				local cf = camFn(dt)
				if cf then
					camCF = cf
				end
			end
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = camCF * CameraController.shakeOffset()
		end)
	end
end

-- Undo everything the scene created and hand control back.
function Kit.finish()
	if renderBound then
		RunService:UnbindFromRenderStep("CutsceneCamera")
		renderBound = false
	end
	camFn = nil
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	for _, inst in tracked do
		inst:Destroy()
	end
	table.clear(tracked)
	for part, value in hiddenParts do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end
	table.clear(hiddenParts)
	for prop, value in lightingDefaults do
		(Lighting :: any)[prop] = value
	end
	table.clear(lightingDefaults)
	Effects.blurOverride = nil
	Kit.hint(nil)
	Kit.letterbox(false, 0.4)
	camera.FieldOfView = 72
	CameraController.setEnabled(true)
	Movement.locked = false
	Viewmodel.hidden = false
	if not player:GetAttribute("Hidden") then
		HUD.setVisible(true)
	end
	Util.tween(fadeFrame, 1.2, { BackgroundTransparency = 1 })
	Util.tween(lidTop, 0.6, { Position = UDim2.fromScale(0, 0) })
	Util.tween(lidBottom, 0.6, { Position = UDim2.fromScale(0, 1) })
	task.delay(1.3, function()
		if not renderBound then
			gui.Enabled = false
		end
	end)
end

---------------------------------------------------------------- timing

function Kit.wait(seconds: number)
	task.wait(seconds)
end

local function tweenAndWait(inst: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	if duration <= 0 then
		for k, v in goal do
			(inst :: any)[k] = v
		end
		return
	end
	local tween = Util.tween(inst, duration, goal, style, dir)
	tween.Completed:Wait()
end

---------------------------------------------------------------- screen effects

function Kit.letterbox(on: boolean, duration: number?)
	local d = duration or 0.8
	Util.tween(topBar, d, { Position = UDim2.fromScale(0, if on then 0 else -0.12) })
	Util.tween(bottomBar, d, { Position = UDim2.fromScale(0, if on then 1 else 1.12) })
end

-- alpha 1 = black screen, 0 = clear. Yields for the duration.
function Kit.fade(alpha: number, duration: number, color: Color3?)
	if color then
		fadeFrame.BackgroundColor3 = color
	end
	tweenAndWait(fadeFrame, duration, { BackgroundTransparency = 1 - alpha }, Enum.EasingStyle.Sine)
end

-- open = 1 eyes fully open, 0 closed. Yields.
function Kit.eyes(open: number, duration: number)
	local gap = math.clamp(open, 0, 1) * 0.55
	Util.tween(lidTop, duration, { Position = UDim2.fromScale(0, 0.55 - gap) }, Enum.EasingStyle.Sine)
	tweenAndWait(lidBottom, duration, { Position = UDim2.fromScale(0, 0.45 + gap) }, Enum.EasingStyle.Sine)
end

-- Slow, heavy blinks of someone barely conscious. Ends with eyes at `endOpen`.
function Kit.blink(times: number?, speed: number?, endOpen: number?)
	local s = speed or 1
	for _ = 1, times or 2 do
		Kit.eyes(0, 0.18 * s)
		task.wait(0.25 * s)
		Kit.eyes(0.8, 0.35 * s)
		task.wait(0.4 * s)
	end
	Kit.eyes(endOpen or 1, 0.4 * s)
end

-- Big title text. Yields `hold` seconds plus fades.
function Kit.title(text: string, sub: string?, hold: number?)
	titleLabel.Text = text
	subLabel.Text = sub or ""
	Util.tween(titleLabel, 1, { TextTransparency = 0 })
	if sub then
		Util.tween(subLabel, 1.4, { TextTransparency = 0 })
	end
	Audio.play("Whoosh", nil, 0.4)
	task.wait(1 + (hold or 2))
	Util.tween(titleLabel, 0.8, { TextTransparency = 1 })
	tweenAndWait(subLabel, 0.8, { TextTransparency = 1 })
end

-- Persistent hint near the bottom of the screen (nil hides it).
function Kit.hint(text: string?)
	if text then
		hintLabel.Text = text
		Util.tween(hintLabel, 0.3, { TextTransparency = 0 })
	else
		Util.tween(hintLabel, 0.3, { TextTransparency = 1 })
	end
end

-- Subtitle line; yields for `duration` (default scales with length).
function Kit.say(speaker: string, text: string, duration: number?)
	local d = duration or math.clamp(#text / 14, 2, 6)
	HUD.subtitle(speaker, text, d)
	task.wait(d)
end

function Kit.shake(amount: number, decay: number?)
	CameraController.shake(amount, decay)
end

function Kit.flash(color: Color3, strength: number)
	Effects.flash(color, strength)
end

-- Blur size; nil releases control back to the gameplay effects.
function Kit.blur(size: number?)
	Effects.blurOverride = size
end

function Kit.sound(name: string, position: Vector3?, volume: number?): Sound?
	return Audio.play(name, position, volume)
end

-- Tween Lighting properties locally; restored by finish().
function Kit.lighting(goal: { [string]: any }, duration: number)
	for prop in goal do
		if lightingDefaults[prop] == nil then
			lightingDefaults[prop] = (Lighting :: any)[prop]
		end
	end
	Util.tween(Lighting, duration, goal)
end

---------------------------------------------------------------- camera

function Kit.cam(cf: CFrame, fov: number?)
	camFn = nil
	camCF = cf
	if fov then
		camera.FieldOfView = fov
	end
end

function Kit.camCFrame(): CFrame
	return camCF
end

-- Tween the camera to `cf`. Yields.
function Kit.camTween(cf: CFrame, duration: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, fov: number?)
	camFn = nil
	local from = camCF
	local value = Instance.new("NumberValue")
	value.Value = 0
	local conn = value.Changed:Connect(function(t: number)
		camCF = from:Lerp(cf, t)
	end)
	if fov then
		Util.tween(camera, duration, { FieldOfView = fov }, style, dir)
	end
	tweenAndWait(value, duration, { Value = 1 }, style or Enum.EasingStyle.Sine, dir or Enum.EasingDirection.InOut)
	conn:Disconnect()
	value:Destroy()
	camCF = cf
end

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

-- Smooth camera move through several CFrames (positions follow a
-- Catmull-Rom spline, rotations blend between keys). Yields.
function Kit.camPath(points: { CFrame }, duration: number)
	assert(#points >= 2, "camPath needs at least two points")
	local n = #points
	local elapsed = 0
	local done = false
	camFn = function(dt: number): CFrame?
		elapsed += dt
		local u = math.clamp(elapsed / duration, 0, 1)
		local eased = u * u * (3 - 2 * u)
		local f = eased * (n - 1)
		local i = math.clamp(math.floor(f) + 1, 1, n - 1)
		local t = f - (i - 1)
		local p0 = points[math.max(i - 1, 1)].Position
		local p1 = points[i].Position
		local p2 = points[i + 1].Position
		local p3 = points[math.min(i + 2, n)].Position
		local pos = catmull(p0, p1, p2, p3, t)
		local rot = points[i].Rotation:Lerp(points[i + 1].Rotation, t)
		if u >= 1 then
			done = true
		end
		return rot + pos
	end
	while not done do
		task.wait()
	end
	camFn = nil
end

-- Drive the camera with a function every frame until the returned stop
-- function is called (or another camera call replaces it).
function Kit.follow(fn: (dt: number) -> CFrame?): () -> ()
	camFn = fn
	return function()
		if camFn == fn then
			camFn = nil
		end
	end
end

---------------------------------------------------------------- world helpers

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

-- Height of the terrain (and world geometry) under x, z.
function Kit.ground(x: number, z: number): number
	local world = workspace:FindFirstChild("World")
	groundParams.FilterDescendantsInstances = if world then { workspace.Terrain, world } else { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1200, 0), groundParams)
	return if hit then hit.Position.Y else 0
end

function Kit.track<T>(inst: T): T
	if typeof(inst) == "Instance" then
		table.insert(tracked, inst :: any)
	elseif typeof(inst) == "RBXScriptConnection" then
		table.insert(connections, inst :: any)
	end
	return inst
end

-- Local copy of any replicated instance; destroyed by finish().
function Kit.clone(inst: Instance, parent: Instance?): any
	local copy = inst:Clone()
	copy.Parent = parent or workspace
	table.insert(tracked, copy)
	return copy
end

-- Hide a server object locally for the rest of the cutscene.
function Kit.hide(inst: Instance)
	local function hide(p: BasePart)
		if hiddenParts[p] == nil then
			hiddenParts[p] = p.LocalTransparencyModifier
		end
		p.LocalTransparencyModifier = 1
	end
	if inst:IsA("BasePart") then
		hide(inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			hide(d)
		end
	end
end

function Kit.part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for k, v in props do
		(p :: any)[k] = v
	end
	if not p.Parent then
		p.Parent = workspace
	end
	table.insert(tracked, p)
	return p
end

---------------------------------------------------------------- actors

local ANIMS = {
	R15 = { idle = "rbxassetid://507766666", walk = "rbxassetid://507777826", run = "rbxassetid://507767714", slash = "rbxassetid://522635514" },
	R6 = { idle = "rbxassetid://180435571", walk = "rbxassetid://180426354", run = "rbxassetid://180426354", slash = "rbxassetid://129967390" },
}

export type Actor = {
	model: Model,
	root: BasePart,
	head: BasePart?,
	-- move the anchored root to `pos` (on the ground) at `speed` studs/s; yields
	walkTo: (self: Actor, pos: Vector3, speed: number?) -> (),
	-- turn to face a point; yields `duration`
	face: (self: Actor, pos: Vector3, duration: number?) -> (),
	-- play "idle" | "walk" | "run" | "slash" (slash plays once)
	play: (self: Actor, anim: string, speed: number?) -> AnimationTrack?,
	-- swing the weapon once (slash animation); yields ~0.6s
	swing: (self: Actor) -> (),
	-- set the glowing eyes on/off
	eyes: (self: Actor, on: boolean) -> (),
	destroy: (self: Actor) -> (),
}

-- Spawn a local cannibal (Butcher, Brother, Papa, Kin, Hunter, Scavenger)
-- standing at `cf` (feet on the CFrame's position, facing its look vector).
function Kit.actor(kind: string, cf: CFrame): Actor?
	local templates = ReplicatedStorage:FindFirstChild("CannibalTemplates")
	local template = templates and templates:FindFirstChild(kind)
	if not template or not template:IsA("Model") then
		warn("[Cutscene] no template for " .. kind)
		return nil
	end
	local model = template:Clone()
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		model:Destroy()
		return nil
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
			p.Anchored = false
		end
	end
	root.Anchored = true
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local hipOffset = root.Size.Y / 2 + (if humanoid then humanoid.HipHeight else 2)
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then
		hipOffset = root.Size.Y / 2 + root.Size.Y
	end
	local function place(at: CFrame)
		model:PivotTo(at + Vector3.new(0, hipOffset, 0))
	end
	place(cf)
	model.Parent = workspace
	table.insert(tracked, model)

	local tracks: { [string]: AnimationTrack } = {}
	local animator: Animator? = nil
	if humanoid then
		local existing = humanoid:FindFirstChildOfClass("Animator")
		if existing then
			animator = existing
		else
			local created = Instance.new("Animator")
			created.Parent = humanoid
			animator = created
		end
	end
	local ids = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then ANIMS.R6 else ANIMS.R15

	local actor = {} :: any
	actor.model = model
	actor.root = root
	actor.head = model:FindFirstChild("Head")

	function actor.play(_: any, anim: string, speed: number?): AnimationTrack?
		if not animator then
			return nil
		end
		local track = tracks[anim]
		if not track then
			local id = (ids :: any)[anim]
			if not id then
				return nil
			end
			local a = Instance.new("Animation")
			a.AnimationId = id
			local ok, loaded = pcall(function()
				return (animator :: Animator):LoadAnimation(a)
			end)
			if not ok or not loaded then
				return nil
			end
			loaded.Looped = anim ~= "slash"
			loaded.Priority = if anim == "slash" then Enum.AnimationPriority.Action else Enum.AnimationPriority.Movement
			tracks[anim] = loaded
			track = loaded
		end
		if anim ~= "slash" then
			for name, t in tracks do
				if name ~= anim and name ~= "slash" then
					t:Stop(0.2)
				end
			end
		end
		(track :: AnimationTrack):Play(0.2, 1, speed or 1)
		return track
	end

	function actor.walkTo(self: any, pos: Vector3, speed: number?)
		local s = speed or 8
		local from = root.CFrame - Vector3.new(0, hipOffset, 0)
		local target = Vector3.new(pos.X, pos.Y, pos.Z)
		local distance = (Util.flat(target - from.Position)).Magnitude
		if distance < 0.05 then
			return
		end
		self:play(if s > 12 then "run" else "walk", s / 9)
		local look = CFrame.lookAt(from.Position, Vector3.new(target.X, from.Position.Y, target.Z))
		local value = Instance.new("NumberValue")
		local conn = value.Changed:Connect(function(t: number)
			local p = from.Position:Lerp(target, t)
			place(look.Rotation + p)
		end)
		tweenAndWait(value, distance / s, { Value = 1 }, Enum.EasingStyle.Linear)
		conn:Disconnect()
		value:Destroy()
		self:play("idle")
	end

	function actor.face(_: any, pos: Vector3, duration: number?)
		local from = root.CFrame - Vector3.new(0, hipOffset, 0)
		local goal = CFrame.lookAt(from.Position, Vector3.new(pos.X, from.Position.Y, pos.Z))
		local value = Instance.new("NumberValue")
		local conn = value.Changed:Connect(function(t: number)
			place(from:Lerp(goal, t))
		end)
		tweenAndWait(value, duration or 0.5, { Value = 1 })
		conn:Disconnect()
		value:Destroy()
	end

	function actor.swing(self: any)
		self:play("slash", 1.1)
		task.wait(0.6)
	end

	function actor.eyes(_: any, on: boolean)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Eye" then
				d.Transparency = if on then 0.05 else 0.85
			end
		end
	end

	function actor.destroy(_: any)
		model:Destroy()
	end

	actor:play("idle")
	return actor :: Actor
end

return Kit

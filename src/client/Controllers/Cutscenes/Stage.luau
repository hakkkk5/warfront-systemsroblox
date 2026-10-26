--!strict
-- Scene runtime used by the scene modules on top of the Kit: a hard time
-- limit per scene, tracked threads that die with the scene, a timeline
-- clock, our own overlay (2.35:1 letterbox, black fade, flash, eyelids,
-- titles, static), a camera rig (tweens, per-frame tracking, splines, sway,
-- FOV, blur) driven through Kit.follow, and cleanup of everything a scene
-- creates or hides.
--
-- A scene module returns Stage.scene(name, body); the dispatcher calls it
-- with (data, kit) between Kit.begin() and Kit.finish().
--
-- The overlay lives in its own ScreenGui below the HUD (DisplayOrder 4) so
-- HUD subtitles and chapter cards show on top of the bars and fades.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Audio)
local Effects = require(script.Parent.Parent.Effects)
local MeshLibrary = require(script.Parent.Parent.MeshLibrary)
local Settings = require(script.Parent.Parent.Settings)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)

local Stage = {}

local camera = workspace.CurrentCamera
local rgb = Color3.fromRGB
local ANG = CFrame.Angles

-- Hard limits in seconds, each below the server timeout in Story.luau
-- (Crash 60, WakeUp 90, TheyKnow 30, TruckFound 14, Drive 75, Radio 30, Ending 60).
local LIMITS: { [string]: number } = {
	Crash = 68,
	WakeUp = 86,
	TheyKnow = 26,
	TruckFound = 12.5,
	Drive = 68,
	DoorLock = 25,
	DoorBreak = 14,
	Radio = 27,
	Ending = 56,
	Downed = 24,
	Mine = 18,
	Dawn = 26,
}
-- How long the screen stays black after a scene (the next cutscene or a
-- server teleport may follow), and how long the fade back takes.
local HOLD: { [string]: number } = { Crash = 4, Drive = 1.4, Ending = 1.5, Downed = 2.5, Mine = 1.5, Dawn = 3 }
local FADE_BACK: { [string]: number } = { Drive = 1.2, Ending = 2.5 }

local CANCEL = "CutsceneCancelled"

Stage.CANCEL = CANCEL

---------------------------------------------------------------- state

local gui: ScreenGui? = nil
local layer: Frame
local barTop: Frame
local barBottom: Frame
local lidTop: Frame
local lidBottom: Frame
local black: Frame
local white: Frame
local barsOn = false

local camCF = Instance.new("CFrameValue")
local camFov = Instance.new("NumberValue")
local blurValue = Instance.new("NumberValue")
local camTween: Tween? = nil
local fovTween: Tween? = nil
local blurTween: Tween? = nil
local follow: ((dt: number) -> CFrame)? = nil
local swayAmount = 0
local stopFollow: (() -> ())? = nil

local folder: Folder? = nil
local threads: { thread } = {}
local connections: { RBXScriptConnection } = {}
local cleanups: { () -> () } = {}
local savedLTM: { [Instance]: number } = {}
local savedTransparency: { [Instance]: number } = {}
local loops: { [string]: boolean } = {}
local hideCharacters = false
local aborting = false
local sceneClock = 0
local sceneId = 0
local running = false

-- the film look every scene shares (see begin): a cold, crushed grade, a
-- dark vignette and a lens that pulls focus onto whatever is in frame
local grade: ColorCorrectionEffect? = nil
local vignette: Frame? = nil
local focus = 30
local lensSaved: { [string]: number }? = nil

---------------------------------------------------------------- timeline

function Stage.folder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local created = Instance.new("Folder")
	created.Name = "CutsceneLocal"
	created.Parent = workspace
	folder = created
	return created
end

-- Yields; unwinds the scene thread if the scene was cut short.
function Stage.sleep(seconds: number)
	task.wait(math.max(seconds, 0))
	if aborting then
		error(CANCEL, 0)
	end
end

-- Unwinds the calling thread if the scene was cut short.
function Stage.check()
	if aborting then
		error(CANCEL, 0)
	end
end

-- Runs fn in a thread that is cancelled when the scene ends.
function Stage.go(fn: () -> ()): thread
	local thread = task.spawn(function()
		local ok, err = pcall(fn :: any)
		if not ok and not aborting and tostring(err) ~= CANCEL then
			warn("[Cutscene] " .. tostring(err))
		end
	end)
	table.insert(threads, thread)
	return thread
end

function Stage.later(delay: number, fn: () -> ())
	Stage.go(function()
		Stage.sleep(delay)
		fn()
	end)
end

-- Scene timelines are written against a clock the scene resets.
function Stage.resetClock()
	sceneClock = os.clock()
end

function Stage.at(t: number)
	Stage.sleep(sceneClock + t - os.clock())
end

function Stage.elapsed(): number
	return os.clock() - sceneClock
end

-- Calls fn every frame for duration seconds with alpha 0..1 (yields).
function Stage.animate(duration: number, fn: (alpha: number, dt: number) -> ())
	if duration <= 0 then
		fn(1, 0)
		return
	end
	local t = 0
	while t < duration do
		local dt = task.wait()
		if aborting then
			error(CANCEL, 0)
		end
		t += dt
		fn(math.min(t / duration, 1), dt)
	end
end

function Stage.smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function Stage.smoother(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

function Stage.numberValue(v: number): NumberValue
	local nv = Instance.new("NumberValue")
	nv.Value = v
	nv.Parent = Stage.folder()
	return nv
end

function Stage.cleanup(fn: () -> ())
	table.insert(cleanups, fn)
end

function Stage.connect(connection: RBXScriptConnection)
	table.insert(connections, connection)
end

---------------------------------------------------------------- data helpers

function Stage.cf(v: any, fallback: CFrame): CFrame
	return if typeof(v) == "CFrame" then v else fallback
end

function Stage.model(v: any): Model?
	if typeof(v) == "Instance" and v:IsA("Model") and v:IsDescendantOf(workspace) then
		return v
	end
	return nil
end

---------------------------------------------------------------- world helpers

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true

-- Terrain height under x, z (props and roofs are ignored).
function Stage.groundY(x: number, z: number, fallback: number?): number
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 900, z), Vector3.new(0, -1800, 0), groundParams)
	if hit then
		return hit.Position.Y
	end
	return fallback or 0
end

function Stage.ground(v: Vector3): Vector3
	return Vector3.new(v.X, Stage.groundY(v.X, v.Z, v.Y), v.Z)
end

-- Anchored, non-colliding local part in the scene folder.
function Stage.part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	if not p.Parent then
		p.Parent = Stage.folder()
	end
	return p
end

-- Hides a server object locally. Restored when the scene ends, unless
-- permanent (the server destroys those right after the cutscene).
function Stage.hide(root: Instance?, permanent: boolean?)
	if not root then
		return
	end
	local function apply(inst: Instance)
		if inst:IsA("BasePart") or inst:IsA("Decal") then
			if not permanent and savedLTM[inst] == nil then
				savedLTM[inst] = (inst :: any).LocalTransparencyModifier
			end
			(inst :: any).LocalTransparencyModifier = 1
		end
	end
	apply(root)
	for _, d in root:GetDescendants() do
		apply(d)
	end
end

-- Player characters stay hidden while a scene runs (the camera sits where
-- their heads are). Transparency changes are local-only on the client.
local function hideAllCharacters()
	for _, plr in Players:GetPlayers() do
		local character = plr.Character
		if character then
			for _, d in character:GetDescendants() do
				if (d:IsA("BasePart") or d:IsA("Decal")) and savedTransparency[d] == nil then
					savedTransparency[d] = (d :: any).Transparency;
					(d :: any).Transparency = 1
				end
			end
		end
	end
end

-- A part's own transparency, even while the scene keeps the characters
-- hidden (used when copying a player's avatar into a shot).
function Stage.trueTransparency(inst: BasePart | Decal): number
	local saved = savedTransparency[inst]
	return if saved ~= nil then saved else inst.Transparency
end

-- Local clone of a prop: anchored, inert, no prompts or scripts.
function Stage.prepareClone(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
end

-- Swaps Blender meshes onto a cloned prop. If that fails, drop any visual
-- copied from the server object so the procedural parts show cleanly.
function Stage.upgradeMeshes(root: Instance)
	local targets: { Instance } = {}
	if root:GetAttribute("Mesh") then
		table.insert(targets, root)
	end
	for _, d in root:GetDescendants() do
		if d:GetAttribute("Mesh") and not d:FindFirstAncestor("BlenderVisual") then
			table.insert(targets, d)
		end
	end
	for _, target in targets do
		local ok, visual = pcall(MeshLibrary.upgrade, target)
		if not (ok and visual) then
			local stale = target:FindFirstChild("BlenderVisual")
			if stale then
				stale:Destroy()
			end
			for _, d in target:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				end
			end
		end
	end
end

function Stage.cloneProp(source: Model?): Model?
	if not source then
		return nil
	end
	local copy = source:Clone()
	Stage.prepareClone(copy)
	copy.Parent = Stage.folder()
	Stage.upgradeMeshes(copy)
	return copy
end

function Stage.itemModel(name: string): Model?
	local items = ReplicatedStorage:FindFirstChild("ItemModels")
	local template = items and items:FindFirstChild(name)
	if template and template:IsA("Model") then
		local copy = template:Clone()
		Stage.prepareClone(copy)
		copy.Parent = Stage.folder()
		Stage.upgradeMeshes(copy)
		return copy
	end
	return nil
end

function Stage.sfx(name: string, fallback: string?, position: Vector3?, volume: number?, pitch: number?)
	local played = Audio.play(name, position, volume, pitch)
	if not played and fallback then
		Audio.play(fallback, position, volume, pitch)
	end
end

-- Ambient loop that is switched off when the scene ends.
function Stage.loop(name: string, on: boolean, volume: number?)
	Audio.loop(name, on, volume)
	if on then
		loops[name] = true
	else
		loops[name] = nil
	end
end

-- Rain state from the emitter Effects keeps above the camera.
function Stage.rainState(): (boolean, boolean)
	local holder = workspace:FindFirstChild("Rain")
	local emitter = holder and holder:FindFirstChildOfClass("ParticleEmitter")
	if emitter then
		return emitter.Enabled, emitter.Rate > 600
	end
	return false, false
end

---------------------------------------------------------------- overlay

local function barFraction(): number
	local size = camera.ViewportSize
	if size.Y <= 0 then
		return 0.12
	end
	return math.clamp((1 - (size.X / size.Y) / 2.35) / 2, 0.04, 0.2)
end

local function setBars(h: number, duration: number)
	for _, bar in { barTop, barBottom } do
		Util.tween(bar, duration, { Size = UDim2.fromScale(1, h) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	end
end

local function ensureGui()
	if gui then
		return
	end
	local screen = Theme.screen("CutsceneStage", 4)
	gui = screen
	local ink = Color3.new(0, 0, 0)
	barTop = Theme.frame(screen, { Name = "BarTop", BackgroundColor3 = ink, Size = UDim2.fromScale(1, 0), ZIndex = 2 })
	barBottom = Theme.frame(screen, {
		Name = "BarBottom",
		BackgroundColor3 = ink,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		ZIndex = 2,
	})
	lidTop = Theme.frame(screen, { Name = "LidTop", BackgroundColor3 = ink, Size = UDim2.fromScale(1, 0), ZIndex = 3 })
	lidBottom = Theme.frame(screen, {
		Name = "LidBottom",
		BackgroundColor3 = ink,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		ZIndex = 3,
	})
	local edge = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	Util.create("UIGradient", { Rotation = 90, Transparency = edge, Parent = lidTop })
	Util.create("UIGradient", { Rotation = -90, Transparency = edge, Parent = lidBottom })
	black = Theme.frame(screen, { Name = "Fade", BackgroundColor3 = ink, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8 })
	white = Theme.frame(screen, {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
	})
	layer = Theme.frame(screen, { Name = "Layer", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10 })
	local v = Theme.vignette(screen, ink, 0.3, 1)
	v.Visible = false
	vignette = v
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if barsOn then
			setBars(barFraction(), 0)
		end
	end)
end

function Stage.letterbox(on: boolean, duration: number?)
	barsOn = on
	setBars(if on then barFraction() else 0, duration or 0.8)
end

-- alpha 1 = black screen; does not yield
function Stage.fadeTo(alpha: number, duration: number)
	Util.tween(black, duration, { BackgroundTransparency = 1 - alpha }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

function Stage.fadeWait(alpha: number, duration: number)
	Stage.fadeTo(alpha, duration)
	Stage.sleep(duration)
end

-- Instant cut to (or from) black.
function Stage.setBlack(alpha: number)
	black.BackgroundTransparency = 1 - alpha
end

-- Eyelids: 0 = shut, 1 = wide open. Does not yield.
function Stage.eyes(open: number, duration: number)
	local h = (1 - math.clamp(open, 0, 1)) * 0.62
	for _, lid in { lidTop, lidBottom } do
		Util.tween(lid, duration, { Size = UDim2.fromScale(1, h) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
end

function Stage.blink(close: number, hold: number, open: number, openTo: number?)
	Stage.eyes(0, close)
	Stage.sleep(close + hold)
	Stage.eyes(openTo or 1, open)
	Stage.sleep(open)
end

function Stage.flashWhite(duration: number)
	white.BackgroundTransparency = if Settings.reduceFlashing then 0.65 else 0
	Util.tween(white, duration, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

export type TitleOptions = {
	size: number?,
	font: Enum.Font?,
	color: Color3?,
	y: number?,
	fadeIn: number?,
	hold: number?,
	fadeOut: number?,
}

-- Big centred text above everything, including the black fade.
function Stage.title(text: string, opts: TitleOptions?): TextLabel
	local o: TitleOptions = opts or {}
	local size = o.size or 54
	local label = Theme.label(layer, text, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, o.y or 0.46),
		Size = UDim2.new(0.9, 0, 0, math.floor(size * 1.5)),
		Font = o.font or Theme.Fonts.Title,
		TextColor3 = o.color or Theme.Colors.Bone,
		TextScaled = true,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		ZIndex = 20,
	})
	Util.create("UITextSizeConstraint", { MaxTextSize = size, Parent = label })
	Util.tween(label, o.fadeIn or 1.2, { TextTransparency = 0 })
	local hold = o.hold
	if hold then
		Stage.later((o.fadeIn or 1.2) + hold, function()
			Util.tween(label, o.fadeOut or 1, { TextTransparency = 1 })
		end)
	end
	return label
end

-- Control hint just above the bottom bar.
function Stage.hint(text: string): TextLabel
	local label = Theme.label(layer, text, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1 - barFraction(), -14),
		Size = UDim2.new(0.8, 0, 0, 30),
		Font = Theme.Fonts.UI,
		TextSize = 20,
		TextColor3 = Theme.Colors.Bone,
		TextStrokeTransparency = 0.5,
		TextTransparency = 1,
		ZIndex = 20,
	})
	Util.tween(label, 0.5, { TextTransparency = 0 })
	return label
end

-- A burst of radio static over the picture.
function Stage.staticNoise(duration: number)
	Stage.go(function()
		local lines: { Frame } = {}
		for _ = 1, 22 do
			table.insert(lines, Theme.frame(layer, { BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 4 }))
		end
		local veil = Theme.frame(layer, { BackgroundColor3 = rgb(190, 190, 190), Size = UDim2.fromScale(1, 1), ZIndex = 3 })
		Stage.animate(duration, function()
			for _, line in lines do
				line.Position = UDim2.fromScale(0, math.random())
				line.Size = UDim2.new(1, 0, 0, math.random(1, 4))
				line.BackgroundTransparency = 0.8 + math.random() * 0.18
			end
			veil.BackgroundTransparency = 0.88 + math.random() * 0.1
		end)
		for _, line in lines do
			line:Destroy()
		end
		veil:Destroy()
	end)
end

---------------------------------------------------------------- camera

function Stage.stopCamera()
	if camTween then
		camTween:Cancel()
		camTween = nil
	end
	follow = nil
end

function Stage.cut(cf: CFrame, fov: number?)
	Stage.stopCamera()
	camCF.Value = cf
	if fov then
		if fovTween then
			fovTween:Cancel()
			fovTween = nil
		end
		camFov.Value = fov
	end
end

-- Tweens the camera; does not yield.
function Stage.move(cf: CFrame, duration: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	Stage.stopCamera()
	camTween = Util.tween(camCF, duration, { Value = cf }, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.InOut)
end

function Stage.zoom(fov: number, duration: number)
	if fovTween then
		fovTween:Cancel()
	end
	fovTween = Util.tween(camFov, duration, { Value = fov }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

-- Drives the camera with a per-frame function (render step), so anything
-- moved inside it stays in lockstep with the camera.
function Stage.track(fn: (dt: number) -> CFrame)
	Stage.stopCamera()
	follow = fn
end

function Stage.tracking(): boolean
	return follow ~= nil
end

function Stage.camCFrame(): CFrame
	return camCF.Value
end

-- Hand-held drift (0 = locked off).
function Stage.sway(amount: number)
	swayAmount = amount
end

function Stage.blur(size: number)
	if blurTween then
		blurTween:Cancel()
		blurTween = nil
	end
	blurValue.Value = size
end

function Stage.blurTo(size: number, duration: number)
	if blurTween then
		blurTween:Cancel()
	end
	blurTween = Util.tween(blurValue, duration, { Value = size })
end

-- Per-frame camera for Kit.follow (the Kit adds screen shake on top).
local function render(dt: number): CFrame
	local fn = follow
	if fn then
		local ok, result = pcall(fn, dt)
		if ok then
			camCF.Value = result
		else
			follow = nil
			warn("[Cutscene] camera: " .. tostring(result))
		end
	end
	local sway = CFrame.identity
	if swayAmount > 0 then
		local t = os.clock()
		sway = ANG(
			math.noise(t * 0.55, 1.3) * swayAmount * 0.035,
			math.noise(t * 0.45, 7.1) * swayAmount * 0.045,
			math.noise(t * 0.35, 3.7) * swayAmount * 0.03
		)
	end
	camera.FieldOfView = camFov.Value
	Effects.blurOverride = blurValue.Value
	if hideCharacters then
		hideAllCharacters()
	end
	-- auto focus: pull focus to whatever sits in the middle of the frame
	local lens = game:GetService("Lighting"):FindFirstChild("Depth")
	if lens and lens:IsA("DepthOfFieldEffect") then
		local view = camCF.Value
		local hit = workspace:Raycast(view.Position, view.LookVector * 160)
		local target = if hit then (hit.Position - view.Position).Magnitude else 80
		focus += (target - focus) * math.min(1, dt * 3.5)
		lens.FocusDistance = focus
		lens.InFocusRadius = math.clamp(focus * 0.35, 2.5, 30)
	end
	return camCF.Value * sway
end

-- The shared film look, on for the length of a scene.
local function filmLook(on: boolean)
	local lens = game:GetService("Lighting"):FindFirstChild("Depth")
	if on then
		grade = Util.create("ColorCorrectionEffect", {
			Name = "CutsceneGrade",
			Contrast = 0.14,
			Saturation = -0.2,
			TintColor = rgb(228, 238, 255),
			Parent = camera,
		})
		if lens and lens:IsA("DepthOfFieldEffect") then
			lensSaved = { far = lens.FarIntensity, near = lens.NearIntensity, focus = lens.FocusDistance, radius = lens.InFocusRadius }
			lens.FarIntensity = 0.4
			lens.NearIntensity = 0.45
		end
		if vignette then
			vignette.Visible = true
		end
		swayAmount = 0.25 -- a hand on the camera; scenes can still set their own
	else
		if grade then
			grade:Destroy()
			grade = nil
		end
		local s = lensSaved
		if s and lens and lens:IsA("DepthOfFieldEffect") then
			lens.FarIntensity, lens.NearIntensity, lens.FocusDistance, lens.InFocusRadius = s.far, s.near, s.focus, s.radius
		end
		lensSaved = nil
		if vignette then
			vignette.Visible = false
		end
	end
end

---------------------------------------------------------------- splines

export type Spline = { samples: { Vector3 }, dist: { number }, total: number }

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2 = t * t
	local t3 = t2 * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

-- Catmull-Rom curve through the points, sampled for arc-length lookups.
function Stage.spline(points: { Vector3 }): Spline
	local samples: { Vector3 } = {}
	local n = #points
	if n == 1 then
		samples = { points[1], points[1] }
	else
		for i = 1, n - 1 do
			local p1, p2 = points[i], points[i + 1]
			local p0 = if i > 1 then points[i - 1] else p1 * 2 - p2
			local p3 = if i + 2 <= n then points[i + 2] else p2 * 2 - p1
			for s = 0, 19 do
				table.insert(samples, catmull(p0, p1, p2, p3, s / 20))
			end
		end
		table.insert(samples, points[n])
	end
	local dist = { 0 }
	for i = 2, #samples do
		dist[i] = dist[i - 1] + (samples[i] - samples[i - 1]).Magnitude
	end
	return { samples = samples, dist = dist, total = dist[#dist] }
end

-- Point at a fraction (0..1) of the curve's length.
function Stage.splineAt(sp: Spline, alpha: number): Vector3
	if sp.total <= 0 then
		return sp.samples[1]
	end
	local target = math.clamp(alpha, 0, 1) * sp.total
	local lo, hi = 1, #sp.dist
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if sp.dist[mid] < target then
			lo = mid
		else
			hi = mid
		end
	end
	local d0, d1 = sp.dist[lo], sp.dist[hi]
	local f = if d1 > d0 then (target - d0) / (d1 - d0) else 0
	return sp.samples[lo]:Lerp(sp.samples[hi], f)
end

export type ShotOptions = {
	fov: number?,
	fovTo: number?,
	roll: number?,
	ease: ((number) -> number)?,
	wait: boolean?,
}

-- Camera glide along a curve of positions while looking along a curve of targets.
function Stage.shot(duration: number, positions: { Vector3 }, targets: { Vector3 }, opts: ShotOptions?)
	local o: ShotOptions = opts or {}
	local ps = Stage.spline(positions)
	local ts = Stage.spline(targets)
	local ease = o.ease or Stage.smoother
	local roll = o.roll or 0
	if o.fov then
		Stage.cut(camCF.Value, o.fov)
	end
	if o.fovTo then
		Stage.zoom(o.fovTo, duration)
	end
	local elapsed = 0
	Stage.track(function(dt)
		elapsed += dt
		local a = ease(elapsed / duration)
		return CFrame.lookAt(Stage.splineAt(ps, a), Stage.splineAt(ts, a)) * ANG(0, 0, roll)
	end)
	if o.wait ~= false then
		Stage.sleep(duration)
	end
end

---------------------------------------------------------------- lifecycle

local function begin(kit: any)
	ensureGui()
	aborting = false
	camCF.Value = camera.CFrame
	camFov.Value = camera.FieldOfView
	blurValue.Value = 0
	swayAmount = 0
	hideCharacters = true
	filmLook(true)
	Stage.folder()
	stopFollow = kit.follow(render)
end

-- Tears the scene down. The screen is left black for the hand-off.
local function cleanup()
	aborting = true
	black.BackgroundTransparency = 0
	for _, thread in threads do
		if coroutine.status(thread) ~= "dead" then
			pcall(task.cancel, thread)
		end
	end
	table.clear(threads)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for i = #cleanups, 1, -1 do
		local ok, err = pcall(cleanups[i] :: any)
		if not ok then
			warn("[Cutscene] cleanup: " .. tostring(err))
		end
	end
	table.clear(cleanups)
	Stage.stopCamera()
	for _, tween in { fovTween, blurTween } do
		if tween then
			tween:Cancel()
		end
	end
	fovTween, blurTween = nil, nil
	local stop = stopFollow
	if stop then
		stop()
		stopFollow = nil
	end
	for inst, v in savedLTM do
		if inst.Parent then
			(inst :: any).LocalTransparencyModifier = v
		end
	end
	table.clear(savedLTM)
	hideCharacters = false
	for inst, v in savedTransparency do
		if inst.Parent then
			(inst :: any).Transparency = v
		end
	end
	table.clear(savedTransparency)
	for name in loops do
		Audio.loop(name, false)
	end
	table.clear(loops)
	local f = folder
	if f then
		f:Destroy()
		folder = nil
	end
	layer:ClearAllChildren()
	white.BackgroundTransparency = 1
	Stage.eyes(1, 0)
	filmLook(false)
	swayAmount = 0
	blurValue.Value = 0
	Effects.blurOverride = nil
end

-- Wraps a scene body for the dispatcher: runs it under its time limit, cuts
-- short a scene still running when a newer one arrives, cleans up, then
-- fades the picture back in after a short hold (the next cutscene or a
-- server teleport may follow while the screen is still black).
function Stage.scene(name: string, body: (data: any) -> ()): (data: any, kit: any) -> ()
	return function(data: any, kit: any)
		if running then
			pcall(cleanup :: any)
		end
		sceneId += 1
		local id = sceneId
		running = true
		local payload = if typeof(data) == "table" then data else {}
		begin(kit)
		local finished = false
		local main = task.spawn(function()
			local ok, err = xpcall(body :: any, debug.traceback, payload)
			if not ok and not string.find(tostring(err), CANCEL, 1, true) then
				warn("[Cutscene] " .. name .. " failed: " .. tostring(err))
			end
			finished = true
		end)
		table.insert(threads, main)
		local started = os.clock()
		local limit = LIMITS[name] or 20
		while not finished and sceneId == id and os.clock() - started < limit do
			task.wait(0.1)
		end
		if sceneId ~= id then
			return -- a newer scene took over and already cleaned up
		end
		if not finished then
			warn("[Cutscene] " .. name .. " hit its time limit")
		end
		local ok, err = pcall(cleanup :: any)
		if not ok then
			warn("[Cutscene] cleanup failed: " .. tostring(err))
		end
		running = false
		task.delay(HOLD[name] or 0.15, function()
			if sceneId == id and not running then
				Stage.letterbox(false, 0)
				Util.tween(black, FADE_BACK[name] or 0.9, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			end
		end)
	end
end

return Stage

--!strict
-- Cinematic cutscenes. Every scripted story beat is staged locally: a
-- letterboxed scriptable camera, fades, eye blinks, subtitles, actors cloned
-- from ReplicatedStorage.CannibalTemplates and local copies of the server
-- props involved.
--
-- Contract:
--   Cutscenes.init()   connects the "Cutscene" remote. For each cutscene the
--                      player is locked, the scene plays, everything is
--                      restored and "CutsceneDone" is fired with the
--                      cutscene name. The server waits for every player
--                      (with a timeout), so it is fired even on error.
--   Cutscenes.playing  true while a cutscene owns the camera.
--
-- Scenes never change server state. Server objects are only hidden locally
-- (LocalTransparencyModifier) and restored afterwards; everything a scene
-- creates lives in a scene folder / UI layer that is destroyed when it ends.
-- Each scene has a hard time limit below its server timeout.
--
-- Cutscene names and the data the server sends (see server Story.luau):
--   "Crash"      { sedan: Model, tree: CFrame, trapLog: CFrame, house: CFrame }
--   "WakeUp"     { eye: CFrame, seat: CFrame, tableTop: CFrame, butcher: CFrame,
--                  brother: CFrame, exit: CFrame, doorway: CFrame, knife: Model?,
--                  chair: Model, body: Model }
--   "TruckFound" { truck: CFrame }
--   "Drive"      { truck: Model, truckCF: CFrame, path: { Vector2 }, wreck: CFrame }
--   "Radio"      { radio: CFrame }
--   "Ending"     { helicopter: Model?, pad: CFrame }

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Audio)
local CameraController = require(script.Parent.CameraController)
local Effects = require(script.Parent.Effects)
local MeshLibrary = require(script.Parent.MeshLibrary)
local Movement = require(script.Parent.Movement)
local Viewmodel = require(script.Parent.Viewmodel)
local HUD = require(script.Parent.Parent.UI.HUD)
local Theme = require(script.Parent.Parent.UI.Theme)

local Cutscenes = {}

Cutscenes.playing = false

local camera = workspace.CurrentCamera
local C = Theme.Colors
local rgb = Color3.fromRGB
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local UP = Vector3.yAxis

-- Hard limits in seconds, each below the server timeout in Story.luau
-- (Crash 60, WakeUp 90, TruckFound 14, Drive 75, Radio 30, Ending 60).
local LIMITS: { [string]: number } = {
	Crash = 56,
	WakeUp = 84,
	TruckFound = 12.5,
	Drive = 68,
	Radio = 27,
	Ending = 56,
}
-- How long the screen stays black after a scene (waiting for the next one,
-- or for the server to move the player), and how long the fade back takes.
local HOLD: { [string]: number } = { Crash = 4, Drive = 1.4, Ending = 1.5 }
local FADE_BACK: { [string]: number } = { Drive = 1.2, Ending = 2.5 }

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

local CANCEL = "CutsceneCancelled"
local RENDER_STEP = "CutsceneCamera"

---------------------------------------------------------------- state

-- overlay
local gui: ScreenGui
local layer: Frame -- per-scene UI (titles, hints, static)
local barTop: Frame
local barBottom: Frame
local lidTop: Frame
local lidBottom: Frame
local black: Frame
local white: Frame
local barsOn = false

-- camera rig: a base CFrame (tweened or driven per frame) plus sway + shake
local camCF = Instance.new("CFrameValue")
local camFov = Instance.new("NumberValue")
local blurValue = Instance.new("NumberValue")
local camTween: Tween? = nil
local fovTween: Tween? = nil
local follow: ((dt: number) -> CFrame)? = nil
local swayAmount = 0

-- per-scene bookkeeping
local stage: Folder? = nil
local threads: { thread } = {}
local connections: { RBXScriptConnection } = {}
local cleanups: { () -> () } = {}
local savedLTM: { [Instance]: number } = {}
local savedTransparency: { [Instance]: number } = {}
local loops: { [string]: boolean } = {}
local hideCharacters = false
local aborting = false
local sceneClock = 0

local queue: { { name: string, data: any } } = {}
local running = false

---------------------------------------------------------------- scene runtime

local function scene(): Folder
	local f = stage
	if f and f.Parent then
		return f
	end
	local created = Instance.new("Folder")
	created.Name = "CutsceneLocal"
	created.Parent = workspace
	stage = created
	return created
end

local function sleep(seconds: number)
	task.wait(math.max(seconds, 0))
	if aborting then
		error(CANCEL, 0)
	end
end

-- Runs fn in a tracked thread that is cancelled when the scene ends.
local function go(fn: () -> ()): thread
	local thread = task.spawn(function()
		local ok, err = pcall(fn :: any)
		if not ok and not aborting and tostring(err) ~= CANCEL then
			warn("[Cutscenes] " .. tostring(err))
		end
	end)
	table.insert(threads, thread)
	return thread
end

local function later(delay: number, fn: () -> ())
	go(function()
		sleep(delay)
		fn()
	end)
end

-- Scene timelines are written against a clock that each scene resets.
local function resetClock()
	sceneClock = os.clock()
end

local function at(t: number)
	sleep(sceneClock + t - os.clock())
end

-- Calls fn every frame for duration seconds with alpha in 0..1 (blocking).
local function animate(duration: number, fn: (alpha: number, dt: number) -> ())
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

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function smoother(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function numberValue(v: number): NumberValue
	local nv = Instance.new("NumberValue")
	nv.Value = v
	nv.Parent = scene()
	return nv
end

local function asCF(v: any, fallback: CFrame): CFrame
	return if typeof(v) == "CFrame" then v else fallback
end

local function asModel(v: any): Model?
	if typeof(v) == "Instance" and v:IsA("Model") and v:IsDescendantOf(workspace) then
		return v
	end
	return nil
end

---------------------------------------------------------------- world helpers

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true

local function groundY(x: number, z: number, fallback: number?): number
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 900, z), Vector3.new(0, -1800, 0), groundParams)
	if hit then
		return hit.Position.Y
	end
	return fallback or 0
end

local function ground(v: Vector3): Vector3
	return Vector3.new(v.X, groundY(v.X, v.Z, v.Y), v.Z)
end

-- Anchored, non-colliding local part in the scene folder.
local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
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
		p.Parent = scene()
	end
	return p
end

-- Hides a server object locally. Restored when the scene ends, unless
-- permanent (the server destroys those right after the cutscene).
local function hide(root: Instance?, permanent: boolean?)
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
-- their heads are). Transparency is local-only on the client.
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

-- Local clone of a prop: anchored, inert, no prompts or scripts.
local function prepareClone(root: Instance)
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
local function upgradeMeshes(root: Instance)
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

local function cloneProp(source: Model?): Model?
	if not source then
		return nil
	end
	local copy = source:Clone()
	prepareClone(copy)
	copy.Parent = scene()
	upgradeMeshes(copy)
	return copy
end

local function itemModel(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("ItemModels")
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") then
		local copy = template:Clone()
		prepareClone(copy)
		copy.Parent = scene()
		upgradeMeshes(copy)
		return copy
	end
	return nil
end

local function sfx(name: string, fallback: string?, position: Vector3?, volume: number?, pitch: number?)
	local played = Audio.play(name, position, volume, pitch)
	if not played and fallback then
		Audio.play(fallback, position, volume, pitch)
	end
end

local function loop(name: string, on: boolean, volume: number?)
	Audio.loop(name, on, volume)
	if on then
		loops[name] = true
	else
		loops[name] = nil
	end
end

-- Rain state from the emitter Effects keeps above the camera.
local function rainState(): (boolean, boolean)
	local holder = workspace:FindFirstChild("Rain")
	local emitter = holder and holder:FindFirstChildOfClass("ParticleEmitter")
	if emitter then
		return emitter.Enabled, emitter.Rate > 600
	end
	return false, false
end

---------------------------------------------------------------- overlay

-- 2.35:1 bars for the current viewport.
local function barFraction(): number
	local size = camera.ViewportSize
	if size.Y <= 0 then
		return 0.12
	end
	return math.clamp((1 - (size.X / size.Y) / 2.35) / 2, 0.04, 0.2)
end

local function letterbox(on: boolean, duration: number?)
	barsOn = on
	local h = if on then barFraction() else 0
	local d = duration or 0.8
	for _, bar in { barTop, barBottom } do
		Util.tween(bar, d, { Size = UDim2.fromScale(1, h) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	end
end

-- alpha 1 = black screen
local function fadeTo(alpha: number, duration: number)
	Util.tween(black, duration, { BackgroundTransparency = 1 - alpha }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

local function fadeWait(alpha: number, duration: number)
	fadeTo(alpha, duration)
	sleep(duration)
end

-- Eyelids: 0 = shut, 1 = wide open.
local function eyes(open: number, duration: number)
	local h = (1 - math.clamp(open, 0, 1)) * 0.62
	for _, lid in { lidTop, lidBottom } do
		Util.tween(lid, duration, { Size = UDim2.fromScale(1, h) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
end

local function blink(close: number, hold: number, open: number, openTo: number?)
	eyes(0, close)
	sleep(close + hold)
	eyes(openTo or 1, open)
	sleep(open)
end

local function flashWhite(duration: number)
	white.BackgroundTransparency = 0
	Util.tween(white, duration, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

type TitleOptions = {
	size: number?,
	font: Enum.Font?,
	color: Color3?,
	y: number?,
	fadeIn: number?,
	hold: number?,
	fadeOut: number?,
}

-- Big centred text over everything (including the black fade).
local function title(text: string, opts: TitleOptions?): TextLabel
	local o: TitleOptions = opts or {}
	local size = o.size or 54
	local label = Theme.label(layer, text, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, o.y or 0.46),
		Size = UDim2.new(0.9, 0, 0, math.floor(size * 1.5)),
		Font = o.font or Theme.Fonts.Title,
		TextColor3 = o.color or C.Bone,
		TextScaled = true,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		ZIndex = 20,
	})
	Util.create("UITextSizeConstraint", { MaxTextSize = size, Parent = label })
	Util.tween(label, o.fadeIn or 1.2, { TextTransparency = 0 })
	local hold = o.hold
	if hold then
		later((o.fadeIn or 1.2) + hold, function()
			Util.tween(label, o.fadeOut or 1, { TextTransparency = 1 })
		end)
	end
	return label
end

-- Control hint just above the bottom bar.
local function hint(text: string): TextLabel
	local label = Theme.label(layer, text, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1 - barFraction(), -14),
		Size = UDim2.new(0.8, 0, 0, 30),
		Font = Theme.Fonts.UI,
		TextSize = 20,
		TextColor3 = C.Bone,
		TextStrokeTransparency = 0.5,
		TextTransparency = 1,
		ZIndex = 20,
	})
	Util.tween(label, 0.5, { TextTransparency = 0 })
	return label
end

-- A burst of radio static over the picture.
local function staticNoise(duration: number)
	go(function()
		local lines: { Frame } = {}
		for _ = 1, 22 do
			table.insert(lines, Theme.frame(layer, { BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 4 }))
		end
		local veil = Theme.frame(layer, { BackgroundColor3 = rgb(190, 190, 190), Size = UDim2.fromScale(1, 1), ZIndex = 3 })
		animate(duration, function()
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

local function stopCamera()
	if camTween then
		camTween:Cancel()
		camTween = nil
	end
	follow = nil
end

local function cut(cf: CFrame, fov: number?)
	stopCamera()
	camCF.Value = cf
	if fov then
		if fovTween then
			fovTween:Cancel()
			fovTween = nil
		end
		camFov.Value = fov
	end
end

local function move(cf: CFrame, duration: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	stopCamera()
	camTween = Util.tween(camCF, duration, { Value = cf }, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.InOut)
end

local function zoom(fov: number, duration: number)
	if fovTween then
		fovTween:Cancel()
	end
	fovTween = Util.tween(camFov, duration, { Value = fov }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

-- Drives the camera with a per-frame function (runs in RenderStepped, so
-- anything moved inside it stays in lockstep with the camera).
local function track(fn: (dt: number) -> CFrame)
	stopCamera()
	follow = fn
end

local function render(dt: number)
	local fn = follow
	if fn then
		local ok, result = pcall(fn, dt)
		if ok then
			camCF.Value = result
		else
			follow = nil
			warn("[Cutscenes] camera: " .. tostring(result))
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
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = camCF.Value * sway * CameraController.shakeOffset()
	camera.FieldOfView = camFov.Value
	Effects.blurOverride = blurValue.Value
	if hideCharacters then
		hideAllCharacters()
	end
end

---------------------------------------------------------------- splines

type Spline = { samples: { Vector3 }, dist: { number }, total: number }

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2 = t * t
	local t3 = t2 * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

-- Catmull-Rom curve through the points, sampled for arc-length lookups.
local function spline(points: { Vector3 }): Spline
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
local function splineAt(sp: Spline, alpha: number): Vector3
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

type ShotOptions = {
	fov: number?,
	fovTo: number?,
	roll: number?,
	ease: ((number) -> number)?,
	wait: boolean?,
}

-- Camera glide along a curve of positions while looking along a curve of targets.
local function shot(duration: number, positions: { Vector3 }, targets: { Vector3 }, opts: ShotOptions?)
	local o: ShotOptions = opts or {}
	local ps = spline(positions)
	local ts = spline(targets)
	local ease = o.ease or smoother
	local roll = o.roll or 0
	if o.fov then
		cut(camCF.Value, o.fov)
	end
	if o.fovTo then
		zoom(o.fovTo, duration)
	end
	local elapsed = 0
	track(function(dt)
		elapsed += dt
		local a = ease(elapsed / duration)
		return CFrame.lookAt(splineAt(ps, a), splineAt(ts, a)) * ANG(0, 0, roll)
	end)
	if o.wait ~= false then
		sleep(duration)
	end
end

---------------------------------------------------------------- actors

type Actor = {
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
	local root = part(Vector3.new(2, 2, 1), CF(0, 3, 0), C.Ink, nil, { Transparency = 1, Name = "HumanoidRootPart" })
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

-- Local clone of a cannibal, standing on floorCF (feet level). The root is
-- anchored and moved by hand; animations and joint poses do the rest.
local function spawnActor(kind: string, floorCF: CFrame): Actor
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
	model.Parent = scene()

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

local function playAnim(actor: Actor, name: string, speed: number?)
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
local function armOffset(actor: Actor, right: boolean, raise: number, out: number?): CFrame
	local o = out or 0
	if actor.r15 then
		return ANG(raise, 0, if right then o else -o)
	end
	return ANG(-o, 0, if right then raise else -raise)
end

-- pitch > 0 looks up, yaw > 0 turns left
local function neckOffset(actor: Actor, pitch: number, yaw: number, roll: number): CFrame
	if actor.r15 then
		return ANG(pitch, yaw, roll)
	end
	return ANG(-pitch, roll, yaw)
end

-- lean > 0 bends forward
local function waistOffset(actor: Actor, lean: number, twist: number?): CFrame
	if actor.r15 then
		return ANG(-lean, twist or 0, 0)
	end
	return ANG(lean, 0, twist or 0)
end

local function pose(actor: Actor, joint: string, offset: CFrame, duration: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
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

local function headOf(actor: Actor): Vector3
	local head = actor.model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return actor.root.Position + UP * 2
end

-- Turns the actor in place to face a point (blocking).
local function face(actor: Actor, point: Vector3, duration: number)
	local from = actor.root.CFrame
	local pos = from.Position
	local flat = Vector3.new(point.X, pos.Y, point.Z)
	if (flat - pos).Magnitude < 0.05 then
		return
	end
	local to = CFrame.lookAt(pos, flat)
	animate(duration, function(a)
		actor.root.CFrame = from:Lerp(to, smooth(a))
	end)
end

type WalkOptions = { ground: boolean?, onPoint: ((index: number) -> ())?, anim: number? }

-- Walks through floor-level points at a fixed speed (blocking).
local function walk(actor: Actor, points: { Vector3 }, speed: number, opts: WalkOptions?)
	local o: WalkOptions = opts or {}
	playAnim(actor, "walk", o.anim or math.clamp(speed / 11, 0.35, 1.6))
	local pos = actor.root.Position - UP * actor.lift
	local heading = Util.flat(actor.root.CFrame.LookVector)
	heading = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.new(0, 0, -1)
	for i, target in points do
		local goal = if o.ground then ground(target) else target
		while true do
			local dt = task.wait()
			if aborting then
				error(CANCEL, 0)
			end
			local delta = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
			local dist = delta.Magnitude
			local step = speed * dt
			local dir = if dist > 1e-3 then delta / dist else heading
			if dist <= step then
				pos = goal
			else
				pos += dir * step
				local y = if o.ground then groundY(pos.X, pos.Z, pos.Y) else Util.lerp(pos.Y, goal.Y, math.min(1, step / dist))
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
	playAnim(actor, "idle")
end

-- Shoulders shaking with laughter (blocking).
local function laugh(actor: Actor, duration: number)
	local t = 0
	animate(duration, function(_, dt)
		t += dt
		local k = math.sin(t * 24) * 0.5 + 0.5
		pose(actor, "waist", waistOffset(actor, 0.08 + k * 0.07), 0)
		pose(actor, "neck", neckOffset(actor, 0.14 * k - 0.04, 0, 0), 0)
	end)
	pose(actor, "waist", CFrame.identity, 0.3)
	pose(actor, "neck", CFrame.identity, 0.3)
end

-- One cleaver swing down onto the table (blocking, about 1.3 s).
local function chop(actor: Actor, target: Vector3)
	pose(actor, "rightShoulder", armOffset(actor, true, 2.9, 0.15), 0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	pose(actor, "waist", waistOffset(actor, -0.1), 0.42)
	sleep(0.46)
	pose(actor, "rightShoulder", armOffset(actor, true, 0.55, 0.05), 0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	pose(actor, "waist", waistOffset(actor, 0.3), 0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	sleep(0.11)
	sfx("Chop", "Impact", target, 0.9, 0.62 + math.random() * 0.1)
	CameraController.shake(0.3, 6)
	sleep(0.32)
	pose(actor, "rightShoulder", armOffset(actor, true, 0.25, 0), 0.5)
	pose(actor, "waist", waistOffset(actor, 0.12), 0.5)
	sleep(0.5)
end

-- A lit lantern welded into the actor's left hand.
local function giveLantern(actor: Actor)
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
type Cockpit = {
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

type CockpitOptions = {
	hood: Color3?, -- builds a bonnet with headlights (the crash car)
	lights: { Vector3 }?, -- headlight positions relative to the eye (the truck)
}

local function buildCockpit(width: number, opts: CockpitOptions): Cockpit
	local model = Instance.new("Model")
	model.Name = "Cockpit"
	model.Parent = scene()
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
	local hood: { BasePart } = {}
	local lightPositions: { Vector3 } = opts.lights or {}
	local paint = opts.hood
	if paint then
		table.insert(hood, add("static", Vector3.new(width - 0.4, 0.25, 4.6), CF(cx, -1.62, -4.6) * ANG(rad(-5), 0, 0), paint, Enum.Material.Metal))
		table.insert(hood, add("static", Vector3.new(width, 0.9, 0.35), CF(cx, -2, -6.95), paint, Enum.Material.Metal))
		lightPositions = { Vector3.new(cx - width * 0.36, -1.9, -7.15), Vector3.new(cx + width * 0.36, -1.9, -7.15) }
	end
	local lights: { SpotLight } = {}
	for _, pos in lightPositions do
		local lamp = add("static", Vector3.new(0.9, 0.32, 0.08), CF(pos), rgb(255, 244, 220), Enum.Material.Neon, {
			Transparency = if paint then 0 else 1,
		})
		if paint then
			table.insert(hood, lamp)
		end
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 50
		spot.Range = 70
		spot.Brightness = 5
		spot.Shadows = true
		spot.Color = rgb(255, 238, 210)
		spot.Enabled = paint ~= nil
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

local function placeCockpit(c: Cockpit, eye: CFrame)
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

local function setGauges(c: Cockpit, on: boolean)
	for _, g in c.gauges do
		g.Color = if on then rgb(110, 230, 170) else rgb(25, 45, 35)
		g.Transparency = if on then 0.2 else 0.5
	end
	c.glow.Enabled = on
end

local function setWarnings(c: Cockpit, on: boolean)
	for i, w in c.warnings do
		w.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		w.Color = if on then c.warningColors[i] else rgb(40, 14, 12)
	end
end

-- Stand-in truck if the server one is missing (front faces -Z, pivot at the
-- bottom centre like Props.PickupTruck).
local function simpleTruck(): Model
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
	for _, x in { -2.6, 2.6 } do
		add(Vector3.new(1, 0.6, 0.3), CF(x, 3.6, -8.6), rgb(230, 225, 200), "Headlight")
	end
	for _, z in { -5.6, 5.8 } do
		for _, x in { -3.4, 3.4 } do
			add(Vector3.new(1.1, 3.2, 3.2), CF(x, 1.6, z), rgb(24, 24, 24))
		end
	end
	m.WorldPivot = CFrame.new()
	return m
end

-- Stand-in rescue helicopter (same layout as Props.Helicopter).
local function simpleHelicopter(): Model
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
	return m
end

-- Cabin interior around the left side door, so the door shot has a frame.
local function addCabin(heli: Model, pivot: CFrame)
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

---------------------------------------------------------------- 1. Crash (~40 s)

local function crashScene(data: any)
	local road = Config.Roads[1].points
	local site = Config.Sites.Crash.pos
	local tree = asCF(data.tree, CF(site.X, groundY(site.X, site.Y + 6), site.Y + 6))
	local logCF = asCF(data.trapLog, CF(site.X + 36, groundY(site.X + 36, site.Y - 12), site.Y - 12) * ANG(0, rad(78), 0))
	local sedan = asModel(data.sedan)
	local treePos = tree.Position

	black.BackgroundTransparency = 0
	letterbox(true, 0)
	Effects.setRain(true, true)
	blurValue.Value = 0
	cut(camera.CFrame, 72)

	-- the route: west along the highway toward the log, then the swerve
	local SPEED = 60
	local LANE = 3.4
	local EYE = 3.9
	local APPROACH = 6.4
	local _, _, logAlong = Util.polylineClosest(road, Vector2.new(logCF.X, logCF.Z))
	local swerveAlong = logAlong + 34
	local startAlong = swerveAlong + SPEED * APPROACH

	-- eye position on the ground in the right-hand lane, and the travel direction
	local function lane(s: number): (Vector3, Vector3)
		local p = Util.polylineSample(road, s)
		local behind = Util.polylineSample(road, s + 9)
		local ahead = Util.polylineSample(road, math.max(s - 9, 0))
		local d2 = ahead - behind
		d2 = if d2.Magnitude > 1e-3 then d2.Unit else Vector2.new(-1, 0)
		local c2 = p + Vector2.new(-d2.Y, d2.X) * LANE
		return Vector3.new(c2.X, groundY(c2.X, c2.Y), c2.Y), Vector3.new(d2.X, 0, d2.Y)
	end

	local function carFrame(base: Vector3, dir: Vector3, yaw: number, roll: number): CFrame
		local f = base + dir * 4
		local b = base - dir * 4
		local pitch = math.atan2(groundY(f.X, f.Z, base.Y) - groundY(b.X, b.Z, base.Y), 8)
		local eye = base + UP * EYE
		return CFrame.lookAt(eye, eye + dir) * ANG(0, yaw, 0) * ANG(pitch, 0, roll)
	end

	-- swerve around the end of the log nearest the tree, then into the tree
	local p0, dir0 = lane(swerveAlong)
	local axis = logCF.RightVector
	local endA, endB = logCF.Position + axis * 15, logCF.Position - axis * 15
	local logEnd = if (endA - treePos).Magnitude < (endB - treePos).Magnitude then endA else endB
	local outward = Util.flat(logEnd - logCF.Position)
	outward = if outward.Magnitude > 1e-3 then outward.Unit else Vector3.new(0, 0, 1)
	local around = Util.flat(logEnd) + outward * 7.5
	local inDir = Util.flat(treePos) - around
	inDir = if inDir.Magnitude > 1e-3 then inDir.Unit else dir0
	local contact = Util.flat(treePos) - inDir * 8.6 - Vector3.new(-inDir.Z, 0, inDir.X) * 1.45
	local turn = if dir0:Cross(inDir).Y >= 0 then 1 else -1 -- 1 = swerving left
	local toAround = Util.flat(around - p0)
	local mid = Util.flat(p0) + dir0 * 14 + (if toAround.Magnitude > 1e-3 then toAround.Unit else dir0) * 2.5
	local swerve = spline({ Util.flat(p0), mid, around, contact })
	local V1 = 40
	local swerveTime = 2 * swerve.total / (SPEED + V1)
	local decel = (V1 - SPEED) / swerveTime

	-- the figure in the headlights, lantern raised
	local figurePos = lane(logAlong) - dir0 * 2.6
	local figure = spawnActor("Hunter", CFrame.lookAt(figurePos, figurePos - dir0))
	playAnim(figure, "idle")
	pose(figure, "leftShoulder", armOffset(figure, false, 1.05, 0.1), 0)
	pose(figure, "neck", neckOffset(figure, -0.05, 0, 0.22), 0)
	local figureHead = figurePos + UP * 5.4

	local cockpit = buildCockpit(6.2, { hood = rgb(32, 40, 66) })
	setGauges(cockpit, true)
	cockpit.speed = 0.62
	cockpit.rpm = 0.45

	resetClock()
	local elapsed = 0
	local crashed = false
	local lurch = 0
	track(function(dt)
		elapsed += dt
		local spot, dir, yaw, roll = p0, dir0, 0, 0
		if elapsed < APPROACH then
			spot, dir = lane(startAlong - SPEED * elapsed)
			cockpit.rpm = 0.45 + math.noise(elapsed * 2, 0.5) * 0.04
		else
			local t = elapsed - APPROACH
			local s = math.min(SPEED * t + 0.5 * decel * t * t, swerve.total)
			local prog = if swerve.total > 0 then s / swerve.total else 1
			local pos = splineAt(swerve, prog)
			local d = splineAt(swerve, math.min(prog + 0.03, 1)) - splineAt(swerve, math.max(prog - 0.03, 0))
			dir = if d.Magnitude > 1e-3 then d.Unit else dir0
			spot = Vector3.new(pos.X, groundY(pos.X, pos.Z), pos.Z)
			local slide = math.sin(prog * math.pi)
			yaw = turn * slide * 0.4
			roll = -turn * slide * 0.08
			cockpit.steer = -turn * math.min(1, prog * 3)
			cockpit.speed = Util.lerp(0.62, 0.42, prog)
			cockpit.rpm = 0.8
			if prog >= 1 and not crashed then
				crashed = true
				lurch = 1
			end
		end
		lurch = math.max(0, lurch - dt * 2.5)
		local frame = carFrame(spot, dir, yaw, roll)
		placeCockpit(cockpit, frame)
		local eye = frame.Position
		local toFigure = figureHead - eye
		local k = if elapsed < APPROACH + 0.6 then smooth((110 - toFigure.Magnitude) / 80) * 0.35 else 0
		local look = frame.LookVector:Lerp(toFigure.Unit, k)
		local cam = CFrame.lookAt(eye, eye + look, frame.UpVector) * ANG(0, -yaw * 0.45, 0)
		if lurch > 0 then
			cam = cam * CF(0, -0.2 * lurch, -0.5 * lurch) * ANG(-0.35 * lurch, 0, 0.1 * lurch)
		end
		return cam
	end)

	swayAmount = 0.25
	fadeTo(0, 2.6)
	at(0.9)
	HUD.subtitle("You", "Two more hours to Pinecrest… and not one gas station out here.", 3.6)
	at(2.8)
	Effects.lightning()
	at(4.5)
	HUD.subtitle("You", "Wait… is someone standing in the road?!", 2.2)
	zoom(60, 1.6)
	at(APPROACH)
	CameraController.shake(1.1, 2.5)
	HUD.subtitle("You", "WHOA—!", 1.6)
	sfx("Whoosh", nil, nil, 0.6, 0.6)
	go(function()
		face(figure, Util.flat(treePos) + UP * figurePos.Y, 1.4)
	end)
	local deadline = os.clock() + swerveTime + 1.5
	while not crashed and os.clock() < deadline do
		sleep(0)
	end

	-- impact: white flash, hard shake, black
	flashWhite(0.45)
	Effects.flash(Color3.new(1, 1, 1), 0.9)
	CameraController.shake(3.6, 1.3)
	sfx("Crash", "Impact", nil, 1, 0.5)
	sleep(0.16)
	black.BackgroundTransparency = 0
	stopCamera()
	swayAmount = 0
	figure.model:Destroy()
	cockpit.model.Parent = nil
	blurValue.Value = 22
	zoom(70, 0)
	sleep(1.8)

	-- the wreck from outside: smoke, hazard lights, rain
	local carCF: CFrame
	local eyeCF: CFrame
	if sedan then
		local pivot = sedan:GetPivot()
		carCF = if Util.flat(treePos - pivot.Position):Dot(pivot.LookVector) >= 0 then pivot else pivot * ANG(0, math.pi, 0)
		local bbCF, bbSize = sedan:GetBoundingBox()
		local center = carCF:PointToObjectSpace(bbCF.Position)
		local bottom = center.Y - bbSize.Y / 2
		eyeCF = carCF * CF(center.X - 1.45, bottom + bbSize.Y * 0.8, center.Z + 0.3) * ANG(rad(-5), 0, rad(5))
	else
		local base = ground(contact)
		carCF = CFrame.lookAt(base, Vector3.new(treePos.X, base.Y, treePos.Z))
		eyeCF = carCF * CF(-1.45, 4.1, 0) * ANG(rad(-5), 0, rad(5))
	end
	local _, roadPoint = Util.polylineClosest(road, Vector2.new(carCF.X, carCF.Z))
	local side = if (Vector3.new(roadPoint.X, carCF.Y, roadPoint.Y) - carCF.Position):Dot(carCF.RightVector) >= 0 then 1 else -1

	local smokePart = part(Vector3.one, carCF * CF(0, 3.4, -6), C.Ink, nil, { Transparency = 1 })
	local smoke = Instance.new("Smoke")
	smoke.Color = rgb(90, 90, 94)
	smoke.Opacity = 0.18
	smoke.RiseVelocity = 3
	smoke.Size = 3.5
	smoke.Parent = smokePart
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(rgb(255, 170, 70))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.12)
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Speed = NumberRange.new(6, 12)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.Rate = 0
	sparks.Parent = smokePart

	cut(CFrame.lookAt(carCF * Vector3.new(side * 14, 2.4, 2), carCF * Vector3.new(0, 2.4, -2.5)), 55)
	Util.tween(blurValue, 2.5, { Value = 2 })
	fadeTo(0, 2)
	move(CFrame.lookAt(carCF * Vector3.new(side * 9.5, 1.7, 3), carCF * Vector3.new(0, 2.6, -2)), 6.6)
	later(2.4, function()
		sparks:Emit(14)
	end)
	later(3.4, Effects.lightning)
	sleep(5.3)
	fadeTo(1, 1.2)
	sleep(1.3)

	-- inside the wreck: cracked glass, crumpled bonnet, flickering dash, blurred
	-- and blinking. The server sedan is hidden so any car model works here.
	hide(sedan)
	cockpit.model.Parent = scene()
	for _, item in cockpit.items do
		if table.find(cockpit.hood, item.part) then
			item.base = CF(0, 0.35, 0.6) * item.base * ANG(rad(14), rad(3), rad(-4))
		end
	end
	for _, l in cockpit.lights do
		l.Enabled = false
		local lamp = l.Parent
		if lamp and lamp:IsA("BasePart") then
			lamp.Material = Enum.Material.Glass
			lamp.Color = rgb(60, 60, 58)
		end
	end
	for _, p in cockpit.cracks do
		p.Transparency = 0.25
	end
	cockpit.glass.Transparency = 0.55
	cockpit.glass.Color = rgb(205, 212, 216)
	cockpit.steer = 0.35
	cockpit.speed = 0
	cockpit.rpm = 0
	setGauges(cockpit, false)
	eyes(0, 0)
	local doorV = numberValue(0)
	local yawV, pitchV, rollV = numberValue(0.15), numberValue(-0.42), numberValue(0.1)
	track(function()
		cockpit.door = doorV.Value
		placeCockpit(cockpit, eyeCF)
		return eyeCF * ANG(0, yawV.Value, 0) * ANG(pitchV.Value, 0, rollV.Value)
	end)
	zoom(70, 0)
	swayAmount = 1.4
	blurValue.Value = 22
	go(function()
		while true do
			setGauges(cockpit, math.random() < 0.35)
			sleep(0.08 + math.random() * 0.5)
		end
	end)

	-- the Butcher walks up from behind the car to the driver's door
	local doorSpot = eyeCF * Vector3.new(-3.3, 0, 0.5)
	local start = ground(carCF * Vector3.new(-4.5, 0, 17))
	local butcher = spawnActor("Butcher", CFrame.lookAt(start, Vector3.new(doorSpot.X, start.Y, doorSpot.Z)))
	go(function()
		walk(butcher, { doorSpot }, 3.7, { ground = true })
		face(butcher, eyeCF.Position, 0.7)
	end)

	resetClock()
	fadeTo(0, 0.3)
	at(0.7)
	eyes(0.3, 1.4)
	at(2.5)
	eyes(0, 0.25)
	at(3.25)
	eyes(0.5, 0.8)
	Util.tween(blurValue, 3, { Value = 13 })
	at(3.4)
	-- head lolls toward the side window
	Util.tween(yawV, 2.2, { Value = 1.25 })
	Util.tween(pitchV, 2.2, { Value = -0.08 })
	Util.tween(rollV, 2.2, { Value = 0.05 })
	at(6.2)
	pose(butcher, "waist", waistOffset(butcher, 0.45), 0.9)
	pose(butcher, "neck", neckOffset(butcher, -0.35, 0, 0.15), 0.9)
	at(6.6)
	eyes(0, 0.22)
	at(7.1)
	eyes(0.6, 0.5)
	at(7.4)
	-- the door opens, the dome light comes on
	Util.tween(doorV, 0.9, { Value = -1.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	cockpit.dome.Enabled = true
	sfx("DoorOpen", nil, eyeCF.Position, 0.8, 0.8)
	at(7.8)
	HUD.subtitle("You", "…no… stop…", 2.8)
	at(8.2)
	-- he reaches in
	go(function()
		local from = butcher.root.CFrame
		local toward = Util.flat(eyeCF.Position - from.Position)
		toward = if toward.Magnitude > 1e-3 then toward.Unit else Vector3.zero
		animate(1.2, function(a)
			butcher.root.CFrame = from + toward * (1.5 * smooth(a))
		end)
	end)
	pose(butcher, "leftShoulder", armOffset(butcher, false, 1.45, -0.15), 1.1)
	zoom(56, 1.4)
	Util.tween(yawV, 1.2, { Value = 1.1 })
	Util.tween(rollV, 1.2, { Value = -0.1 })
	at(9.4)
	eyes(0, 0.35)
	sleep(0.35)
	fadeTo(1, 0.15)
	sleep(0.2)
	stopCamera()
	cockpit.model:Destroy()

	-- dragged by the ankles down the driveway, looking up at the trees
	local driveway = Config.Roads[2].points
	local pts: { Vector2 } = {}
	for i = #driveway, 1, -1 do
		table.insert(pts, driveway[i])
	end
	local DRAG_START, DRAG_LEN, DRAG_TIME = 5, 24, 8
	local thetaV = numberValue(1.2)
	for _, joint in { "waist", "neck" } do
		pose(butcher, joint, CFrame.identity, 0)
	end
	pose(butcher, "waist", waistOffset(butcher, 0.12), 0)
	pose(butcher, "leftShoulder", armOffset(butcher, false, -0.45, 0.15), 0)
	pose(butcher, "rightShoulder", armOffset(butcher, true, -0.45, 0.15), 0)
	playAnim(butcher, "walk", 0.38)
	local dragElapsed = 0
	track(function(dt)
		dragElapsed += dt
		local prog = math.clamp(dragElapsed / DRAG_TIME, 0, 1)
		local tug = math.sin(prog * math.pi * 14)
		local s = DRAG_START + DRAG_LEN * (prog + tug * 0.012)
		local p2 = Util.polylineSample(pts, s)
		local d2 = Util.polylineSample(pts, s + 3) - Util.polylineSample(pts, math.max(s - 3, 0))
		d2 = if d2.Magnitude > 1e-3 then d2.Unit else Vector2.new(0, 1)
		local d = Vector3.new(d2.X, 0, d2.Y)
		local pos = Vector3.new(p2.X, groundY(p2.X, p2.Y) + 0.85, p2.Y)
		local th = thetaV.Value
		local look = d * math.cos(th) + UP * math.sin(th)
		local up = UP * math.cos(th) - d * math.sin(th)
		local b2 = Util.polylineSample(pts, s + 5.4)
		local bpos = Vector3.new(b2.X, groundY(b2.X, b2.Y), b2.Y) + UP * butcher.lift
		butcher.root.CFrame = CFrame.lookAt(bpos, bpos + d)
		return CFrame.lookAt(pos, pos + look, up) * ANG(tug * 0.015, 0, math.sin(dragElapsed * 0.9) * 0.06)
	end)
	resetClock()
	eyes(0, 0)
	blurValue.Value = 14
	swayAmount = 0.6
	zoom(70, 0)
	fadeTo(0, 0.6)
	at(0.5)
	eyes(0.45, 1.2)
	at(1.8)
	Util.tween(thetaV, 1.4, { Value = 1.02 })
	at(2.6)
	eyes(0, 0.3)
	at(3.1)
	eyes(0.55, 0.6)
	at(3.5)
	Util.tween(thetaV, 1.6, { Value = 0.36 })
	at(4)
	HUD.subtitle("You", "…please…", 2.6)
	at(6.3)
	Util.tween(thetaV, 1.4, { Value = 0.9 })
	at(7)
	eyes(0, 0.9)
	at(7.9)
	fadeTo(1, 0.3)
	sleep(0.4)
	stopCamera()
	butcher.model:Destroy()
	title("Hours later…", { font = Theme.Fonts.Type, size = 34, color = C.BoneDim, fadeIn = 1.2, hold = 1.8, fadeOut = 1 })
	sleep(4.2)
end

---------------------------------------------------------------- 2. WakeUp (~50 s)

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
	animate(duration, function(a)
		model:PivotTo(from:Lerp(to, smooth(a)))
	end)
end

-- Saws the knife back and forth along a world axis (blocking).
local function saw(model: Model, base: CFrame, axis: Vector3, duration: number)
	local t = 0
	local strokes = 0
	animate(duration, function(_, dt)
		t += dt
		model:PivotTo(base + axis * math.sin(t * math.pi * 6.4))
		local n = math.floor(t * 6.4)
		if n ~= strokes then
			strokes = n
			CameraController.shake(0.1, 8)
			sfx("RopeCut", "Whoosh", base.Position, 0.18, 1.8)
		end
	end)
	model:PivotTo(base)
end

local function simpleKnife(): Model
	local m = Instance.new("Model")
	m.Name = "HuntingKnife"
	local blade = part(Vector3.new(0.8, 0.04, 0.16), CF(0.35, 0.04, 0), rgb(180, 180, 185), Enum.Material.Metal)
	local handle = part(Vector3.new(0.5, 0.12, 0.14), CF(-0.35, 0.04, 0), rgb(70, 46, 30), Enum.Material.Wood)
	blade.Parent = m
	handle.Parent = m
	m.WorldPivot = CFrame.new()
	m.Parent = scene()
	return m
end

local function wakeUpScene(data: any)
	local eye = asCF(data.eye, camera.CFrame)
	local seat = asCF(data.seat, eye * CF(0, -2.55, 0.2))
	local chairCF = seat * CF(0, -2.05, 0)
	local tableTop = asCF(data.tableTop, eye * CF(0, -1.1, -14))
	local doorway = asCF(data.doorway, chairCF * CF(-18, 0, 3))
	local exit = asCF(data.exit, doorway * CF(-4.5, 0, 0))
	local eyePos = eye.Position
	local eyeLocal = chairCF:PointToObjectSpace(eyePos)
	local tablePos = tableTop.Position

	-- house frame (Config.House: axis aligned, doorway = L(7, 0, 16.5), exit = L(2.5, 0, 16.5))
	local xAxis = doorway.Position - exit.Position
	local houseCF = if xAxis.Magnitude > 0.5
		then CFrame.fromMatrix(doorway.Position, xAxis.Unit, UP) * CF(-7, 0, -16.5)
		else CF(doorway.Position) * CF(-7, 0, -16.5)
	local function H(x: number, z: number): Vector3
		return (houseCF * CF(x, 0, z)).Position
	end

	Effects.setRain(false) -- indoors
	letterbox(true, 0)
	black.BackgroundTransparency = 0
	eyes(0, 0)
	blurValue.Value = 28
	swayAmount = 0.55
	cut(CFrame.lookAt(eyePos, eyePos + eye.LookVector * 5 - UP * 3.6), 70)

	-- the slaughter room door swings locally (closed again at the end)
	local chair = asModel(data.chair)
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
	local doorAngle = numberValue(0)
	table.insert(connections, doorAngle:GetPropertyChangedSignal("Value"):Connect(function()
		local rot = hinge * ANG(0, doorAngle.Value, 0) * hinge:Inverse()
		for _, e in doorParts do
			e.part.CFrame = rot * e.cf
		end
	end))
	table.insert(cleanups, function()
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
		hide(r, true)
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
	later(0.25, function()
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
	local serverKnife = asModel(data.knife)
	local knifeRest = if serverKnife then serverKnife:GetPivot() else chairCF * CF(2.3, 2.82, 0.4) * ANG(0, rad(70), 0)
	local knife = cloneProp(serverKnife) or itemModel("HuntingKnife") or simpleKnife()
	hide(serverKnife, true)
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
	go(function()
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
	local butcher = spawnActor("Butcher", asCF(data.butcher, CFrame.lookAt(H(17, 12.4), H(17, 9))))
	local brother = spawnActor("Brother", asCF(data.brother, CFrame.lookAt(H(20.5, 5.4), H(17, 9))))
	playAnim(butcher, "idle")
	playAnim(brother, "idle")

	-- the camera is the captive's head: it turns toward a focus point
	local offsetV = Instance.new("Vector3Value")
	offsetV.Parent = scene()
	local rollV = numberValue(0.06)
	local focus = eyePos + eye.LookVector * 5 - UP * 3.6
	local focusFn: () -> Vector3 = function()
		return eyePos + eye.LookVector * 5 - UP * 3.6
	end
	local rate = 1.2
	local function lookAt(fn: () -> Vector3, r: number)
		focusFn = fn
		rate = r
	end
	track(function(dt)
		focus = focus:Lerp(focusFn(), 1 - math.exp(-rate * dt))
		local p = chairCF * (eyeLocal + offsetV.Value)
		return CFrame.lookAt(p, focus) * ANG(0, 0, rollV.Value)
	end)
	local function butcherHead(): Vector3
		return headOf(butcher)
	end
	local function brotherHead(): Vector3
		return headOf(brother)
	end
	local doorFocus = H(5, 16.5) + UP * 4.5
	local function atDoor(): Vector3
		return doorFocus
	end

	resetClock()
	local chopping = true
	go(function()
		sleep(0.6)
		while chopping do
			chop(butcher, tablePos)
			sleep(0.45 + math.random() * 0.4)
		end
	end)
	go(function()
		at(2.6)
		laugh(brother, 2.2)
		at(6.4)
		laugh(brother, 1.6)
	end)

	fadeTo(0, 0.5)
	at(1.4)
	eyes(0.22, 1.1)
	at(2.8)
	eyes(0, 0.35)
	at(3.6)
	eyes(0.5, 1.4)
	Util.tween(blurValue, 3, { Value = 16 })
	lookAt(function()
		return tablePos + UP * 1.2
	end, 0.7)
	at(6)
	Util.tween(blurValue, 1.5, { Value = 8 })
	blink(0.18, 0.22, 0.5, 0.8)
	at(8)
	eyes(0, 0.16)
	at(8.4)
	eyes(1, 0.6)
	Util.tween(blurValue, 2.5, { Value = 2 })
	at(9.4)
	chopping = false
	at(10.6)
	HUD.subtitle("Butcher", "Fresh meat tonight, brother.", 3.6)
	lookAt(butcherHead, 1.4)
	pose(butcher, "neck", neckOffset(butcher, 0, -0.55, 0), 0.6)
	at(12.2)
	go(function()
		laugh(brother, 1.3)
	end)
	at(14.4)
	HUD.subtitle("Brother", "This one's still breathin'…", 3.6)
	go(function()
		face(brother, eyePos, 0.9)
		pose(brother, "neck", neckOffset(brother, -0.12, 0, 0.4), 0.8)
	end)
	lookAt(brotherHead, 2.6)
	zoom(50, 1.8)
	CameraController.shake(0.22, 2)
	at(15.6)
	local creep = Util.flat(eyePos - brother.root.Position)
	creep = if creep.Magnitude > 1e-3 then creep.Unit else Vector3.zero
	local brotherFeet = brother.root.Position - UP * brother.lift
	go(function()
		walk(brother, { brotherFeet + creep * 2.4 }, 2.2)
	end)
	at(18.6)
	HUD.subtitle("Butcher", "Leave it. It'll keep till mornin'.", 3.6)
	lookAt(butcherHead, 1.6)
	zoom(70, 1.4)
	pose(butcher, "neck", neckOffset(butcher, 0, -0.9, 0), 0.6)
	at(20.6)
	-- he leaves; the door opens ahead of him
	pose(butcher, "neck", CFrame.identity, 0.5)
	pose(butcher, "rightShoulder", CFrame.identity, 0.5)
	pose(butcher, "waist", CFrame.identity, 0.5)
	Util.tween(doorAngle, 0.9, { Value = rad(100) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	sfx("DoorOpen", nil, doorFocus, 0.7)
	go(function()
		walk(butcher, { H(11.5, 15.4), H(7, 16.5), H(2.5, 16.5) }, 6.5)
	end)
	lookAt(butcherHead, 1.5)
	at(21.6)
	go(function()
		laugh(brother, 1.1)
	end)
	at(23)
	pose(brother, "neck", CFrame.identity, 0.4)
	local brotherGone = false
	go(function()
		walk(brother, { H(23.2, 10.2), H(20.6, 14), H(12, 15.9), H(7, 16.5) }, 7)
		face(brother, eyePos, 0.5)
		pose(brother, "neck", neckOffset(brother, -0.1, 0, 0.5), 0.5)
		sleep(0.9)
		pose(brother, "neck", CFrame.identity, 0.3)
		walk(brother, { H(2.5, 16.5) }, 6)
		brotherGone = true
	end)
	lookAt(brotherHead, 1.6)
	while not brotherGone and os.clock() < sceneClock + 31 do
		sleep(0.05)
	end

	-- the door slams
	Util.tween(doorAngle, 0.16, { Value = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	sleep(0.16)
	sfx("Impact", nil, doorFocus, 1, 0.42)
	sfx("DoorLocked", nil, doorFocus, 0.8)
	CameraController.shake(1.2, 2.5)
	swing, swingStart, flickerUntil = 0.32, os.clock(), os.clock() + 1.6
	butcher.model:Destroy()
	brother.model:Destroy()
	lookAt(atDoor, 1)

	resetClock()
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
		sfx("Impact", nil, chairCF.Position, 0.45, 1.4)
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
	sfx("RopeCut", "Slash", chairCF.Position, 0.45, 1.3)
	sleep(0.6)

	-- then the ankles
	lookAt(function()
		return chairCF * Vector3.new(0, 0.5, -1)
	end, 1.6)
	Util.tween(offsetV, 1, { Value = Vector3.new(0, -0.35, -0.4) })
	local last = wristSaw
	for _, entry in ankles do
		local right = entry.x >= 0
		local target = if right
			then chairCF * CF(entry.x + 0.47, 0.62, -0.95) * ANG(0, math.pi, rad(-12))
			else chairCF * CF(entry.x - 0.47, 0.62, -0.95) * ANG(0, 0, rad(12))
		moveModel(knife, last, target, 0.8)
		saw(knife, target, chairCF.LookVector * 0.12, 1.2)
		snapRope(entry.rope)
		CameraController.shake(0.4, 4)
		sfx("RopeCut", "Slash", entry.rope.Position, 0.4, 1.4)
		last = target
		sleep(0.25)
	end

	-- free. The knife comes along; eyes on the door.
	go(function()
		moveModel(knife, last, chairCF * CF(0.9, 3.2, -1.2) * ANG(0, math.pi, 0), 0.8)
		knife:Destroy()
	end)
	lookAt(atDoor, 1.1)
	Util.tween(offsetV, 1.2, { Value = Vector3.zero })
	sleep(0.9)
	HUD.subtitle("You", "I need to get out… the door was chained. I need a key.", 4.6)
	sleep(3.8)
	fadeTo(1, 1.4)
	sleep(1.5)
end

---------------------------------------------------------------- 3. TruckFound (~10 s)

local function truckFoundScene(data: any)
	local truckCF = asCF(data.truck, camera.CFrame)
	local function T(x: number, y: number, z: number): Vector3
		return truckCF * Vector3.new(x, y, z)
	end
	fadeWait(1, 0.45)
	letterbox(true, 0)
	-- a cold moonlight key so the truck reads in the dark
	local key = part(Vector3.one, truckCF * CF(-6, 16, -9), C.Ink, nil, { Transparency = 1 })
	local moon = Instance.new("PointLight")
	moon.Range = 36
	moon.Brightness = 1.3
	moon.Color = rgb(150, 170, 210)
	moon.Shadows = true
	moon.Parent = key
	-- orbit from the front-left, low past the bonnet, ending on the driver's door
	shot(9.3, {
		T(-15, 7.5, -12),
		T(-5, 5.6, -17.5),
		T(5, 4.2, -13.5),
		T(3, 6.9, -9.2),
		T(-11, 6.2, -3),
		T(-9.2, 4.9, 1.8),
	}, {
		T(0, 3, 0),
		T(0, 3.4, -4.5),
		T(0, 3.6, -5.6),
		T(0, 3.3, -5.8),
		T(-3.6, 4.3, -1.6),
		T(-3.8, 4.4, -0.6),
	}, { fov = 60, fovTo = 52, wait = false })
	fadeTo(0, 0.8)
	later(1.2, function()
		HUD.subtitle("You", "A truck… out here? Maybe it still runs.", 3.6)
	end)
	sleep(8.5)
	fadeTo(1, 0.8)
	sleep(0.85)
end

---------------------------------------------------------------- 5. Radio (~19 s)

local function radioScene(data: any)
	local radioCF = asCF(data.radio, camera.CFrame)
	-- the set sits turned around on the desk: its face points along +Z here
	local front = radioCF * ANG(0, math.pi, 0)
	local function R(x: number, y: number, z: number): Vector3
		return front * Vector3.new(x, y, z)
	end
	local rainOn, rainHeavy = rainState()
	fadeWait(1, 0.4)
	letterbox(true, 0)
	Effects.setRain(false)
	table.insert(cleanups, function()
		Effects.setRain(rainOn, rainHeavy)
	end)

	-- dial glow that stutters with the static
	local dial = part(Vector3.new(0.95, 0.32, 0.03), front * CF(0, 0.05, -0.64), rgb(255, 170, 70), Enum.Material.Neon, {
		Transparency = 0.3,
	})
	local glow = Instance.new("PointLight")
	glow.Color = rgb(255, 160, 80)
	glow.Range = 7
	glow.Brightness = 1.3
	glow.Parent = dial
	local staticOn = false
	go(function()
		while true do
			dial.Transparency = if staticOn then math.random() * 0.6 else 0.3
			glow.Brightness = if staticOn then 0.4 + math.random() * 1.8 else 1.3
			sleep(0.04)
		end
	end)
	local function burst(duration: number)
		staticOn = true
		staticNoise(duration)
		sfx("Radio", nil, nil, 0.5)
		later(duration, function()
			staticOn = false
		end)
	end

	shot(18.4, { R(1.7, 1.2, -3.8), R(0.5, 0.5, -2.7), R(-0.4, 0.35, -2.2) }, { R(0, -0.1, 0), R(0, -0.15, 0), R(0.1, -0.1, 0) }, {
		fov = 60,
		fovTo = 48,
		ease = smooth,
		wait = false,
	})
	swayAmount = 0.45
	resetClock()
	fadeTo(0, 0.6)
	loop("Radio", true, 0.35)
	at(0.8)
	HUD.subtitle("You", "Mayday, mayday! Is anyone there?", 3.2)
	at(4.2)
	burst(0.9)
	CameraController.shake(0.15, 4)
	at(4.6)
	HUD.subtitle("Dispatch", "…Pinecrest dispatch… copy… what's your location?", 4)
	at(6.4)
	burst(0.4)
	at(8.8)
	HUD.subtitle("You", "The ranger station off Hollow Road! They're… they're eating people!", 4)
	swayAmount = 0.8
	at(12.9)
	burst(0.8)
	at(13.2)
	HUD.subtitle("Dispatch", "…rescue chopper inbound, two minutes. Hold on. Barricade yourself in.", 4.4)
	at(15.2)
	burst(0.3)
	at(17.5)
	fadeTo(1, 0.9)
	sleep(0.95)
end

---------------------------------------------------------------- 4. Drive (interactive, 30-55 s)

local function driveScene(data: any)
	local serverTruck = asModel(data.truck)
	local truckCF = asCF(data.truckCF, if serverTruck then serverTruck:GetPivot() else camera.CFrame)
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
	local wreck = asCF(data.wreck, CF(lastPoint.X, groundY(lastPoint.X, lastPoint.Y), lastPoint.Y))
	path[#path] = Vector2.new(wreck.X, wreck.Z) -- the ride ends exactly on the wreck spot
	local total = Util.polylineLength(path)

	fadeWait(1, 0.4)
	letterbox(true, 0)

	-- local truck; the server one is hidden for the ride and shown again after
	local truck = cloneProp(serverTruck)
	local pivotOffset = CFrame.identity
	if serverTruck then
		pivotOffset = truckCF:ToObjectSpace(serverTruck:GetPivot())
		hide(serverTruck)
	end
	if not truck then
		local built = simpleTruck()
		built.Parent = scene()
		truck = built
	end
	local body = truck :: Model
	body:PivotTo(truckCF * pivotOffset)

	-- driver's eye from the body's bounds (driver on the left of the travel direction)
	local bbCF, bbSize = body:GetBoundingBox()
	local center = truckCF:PointToObjectSpace(bbCF.Position)
	local eyeLocal = CF(center.X - 1.6, center.Y - bbSize.Y / 2 + bbSize.Y * 0.8, center.Z)
	-- From the driver's seat the body is hidden and the cockpit (with its own
	-- bonnet and headlights) stands in for it, so the view works with any
	-- truck model, procedural or imported mesh. The body shows again outside.
	local bodyParts: { { part: BasePart, transparency: number } } = {}
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(bodyParts, { part = p, transparency = p.Transparency })
			p.Transparency = 1
		end
	end
	local cockpit = buildCockpit(6.6, { hood = rgb(122, 40, 32) })

	-- input: W / up / touch / RT to accelerate, A-D / arrows / touch side / stick to steer
	local touches: { [InputObject]: Vector3 } = {}
	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = input.Position
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject)
		if touches[input] then
			touches[input] = input.Position
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input: InputObject)
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
	local function readInput(): (boolean, number)
		local typing = UserInputService:GetFocusedTextBox() ~= nil
		local padGas, padSteer = gamepad()
		local gas = padGas or next(touches) ~= nil
		local steerIn = padSteer
		if not typing then
			gas = gas or UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up)
			if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
				steerIn -= 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
				steerIn += 1
			end
		end
		local width = camera.ViewportSize.X
		for _, pos in touches do
			if width > 0 then
				steerIn += math.clamp((pos.X / width - 0.5) * 3, -1, 1)
			end
			break
		end
		return gas, math.clamp(steerIn, -1, 1)
	end

	-- drive state
	local MAX = 55
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
		local smokePart = part(Vector3.one, truckPose * eyeLocal * CF(1.5, -1.2, -5.4), C.Ink, nil, { Transparency = 1 })
		smokePart.Parent = body
		local s = Instance.new("Smoke")
		s.Color = rgb(70, 70, 72)
		s.Opacity = 0.3
		s.RiseVelocity = 6
		s.Size = 3
		s.Parent = smokePart
		smoke = s
		go(function()
			local on = false
			while true do
				on = not on
				setWarnings(cockpit, on)
				sleep(0.28)
			end
		end)
	end

	local function directionAt(s: number): Vector2
		local d = Util.polylineSample(path, math.min(s + 7, total)) - Util.polylineSample(path, math.max(s - 7, 0))
		return if d.Magnitude > 1e-3 then d.Unit else Vector2.new(0, -1)
	end

	track(function(dt)
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
		local cap = MAX
		if sputtering then
			cap = Util.lerp(34, 12, math.clamp((along - sputterAt) / math.max(total - sputterAt, 1), 0, 1))
			if elapsed >= nextSputter then
				nextSputter = elapsed + 0.45 + math.random() * 0.6
				speed *= 0.72
				CameraController.shake(0.55, 4)
				sfx("EngineFail", nil, nil, 0.7)
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

		local eyeCF = truckPose * eyeLocal
		cockpit.steer = steer
		cockpit.speed = speed / 70
		cockpit.rpm = if control
			then 0.25 + (speed / MAX) * 0.6 + (if sputtering then math.random() * 0.15 else 0)
			else 0.1 + math.random() * 0.04
		placeCockpit(cockpit, eyeCF)
		local bump = math.noise(along * 0.12, elapsed * 0.3) * 0.012 * (0.3 + speed / MAX)
		return eyeCF * ANG(-0.06 + bump, -steer * 0.1, 0)
	end)
	zoom(70, 0)

	-- engine start
	resetClock()
	fadeTo(0, 1)
	at(0.6)
	sfx("EngineStart", nil, nil, 0.8)
	CameraController.shake(0.35, 3)
	HUD.subtitle("You", "Come on… come on…", 2.2)
	at(1.6)
	CameraController.shake(0.3, 3)
	at(2.6)
	CameraController.shake(0.8, 2.5)
	setGauges(cockpit, true)
	for _, l in cockpit.lights do
		l.Enabled = true
	end
	loop("EngineLoop", true, 0.5)
	HUD.subtitle("You", "Yes! Okay… let's get out of here.", 2.6)
	at(3.4)
	control = true
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local padOnly = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
	local hintLabel = hint(if touchOnly
		then "Hold the screen to accelerate  ·  hold left / right to steer"
		elseif padOnly then "Hold RT to accelerate  ·  left stick to steer"
		else "Hold W to accelerate  ·  A / D to steer")
	go(function()
		while gasTime < 2.5 and not done do
			sleep(0.1)
		end
		Util.tween(hintLabel, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	local deadline = os.clock() + 48
	while not done and follow ~= nil and os.clock() < deadline do
		sleep(0.05)
	end
	control = false
	hintLabel.Visible = false
	loop("EngineLoop", false)

	-- outside: the engine gives out for good
	for _, e in bodyParts do
		e.part.Transparency = e.transparency
	end
	cockpit.model.Parent = nil
	local endPose = truckPose
	local hoodPos = (endPose * CF(0, 4.4, -6)).Position
	cut(CFrame.lookAt((endPose * CF(-12.5, 4.2, -15)).Position, (endPose * CF(0, 3.4, -4)).Position), 58)
	local activeSmoke = smoke
	if activeSmoke then
		activeSmoke.Opacity = 0.5
		activeSmoke.Size = 6
	end
	sleep(0.5)
	CameraController.shake(0.4, 4)
	sfx("EngineFail", nil, hoodPos, 0.8)
	sleep(0.8)

	-- EXPLOSION (visual only)
	local boom = Instance.new("Explosion")
	boom.Position = hoodPos
	boom.BlastRadius = 9
	boom.BlastPressure = 0
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Parent = scene()
	flashWhite(0.5)
	Effects.flash(rgb(255, 170, 90), 0.7)
	CameraController.shake(3.4, 1.5)
	sfx("Explosion", "Impact", hoodPos, 1, 0.4)
	local firePart = part(Vector3.new(4, 1, 4), endPose * CF(0, 4.2, -5.5), C.Ink, nil, { Transparency = 1 })
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
	cabFire.Parent = part(Vector3.new(3, 1, 3), endPose * CF(0, 6, -0.5), C.Ink, nil, { Transparency = 1 })
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
	go(function()
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
	move(camCF.Value * CF(0, 0.4, 3), 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	sleep(0.4)
	black.BackgroundTransparency = 0
	stopCamera()
	blurValue.Value = 24
	sleep(1.6)

	-- ringing ears; on the ground beside the burning wreck
	local function W(x: number, z: number): Vector3
		return ground(wreck * Vector3.new(x, 0, z))
	end
	local camPos = W(-7, 9) + UP * 0.6
	local wreckFocus = endPose.Position + UP * 3
	local focus = wreckFocus
	local focusFn: () -> Vector3 = function()
		return wreckFocus
	end
	local rate = 1
	local rollV = numberValue(1.25)
	track(function(dt)
		focus = focus:Lerp(focusFn(), 1 - math.exp(-rate * dt))
		return CFrame.lookAt(camPos, focus) * ANG(0, 0, rollV.Value)
	end)
	zoom(70, 0)
	swayAmount = 0.7
	eyes(0, 0)

	-- they come out of the trees: lanterns, and Papa with the chainsaw
	local papa = spawnActor("Papa", CFrame.lookAt(W(0, 46), camPos))
	local kinA = spawnActor("Kin", CFrame.lookAt(W(-34, 36), camPos))
	local kinB = spawnActor("Kin", CFrame.lookAt(W(38, 30), camPos))
	giveLantern(kinA)
	giveLantern(kinB)
	for _, a in { papa, kinA, kinB } do
		playAnim(a, "idle")
	end
	pose(kinA, "leftShoulder", armOffset(kinA, false, 0.9, 0.1), 0)
	pose(kinB, "leftShoulder", armOffset(kinB, false, 0.9, 0.1), 0)

	resetClock()
	fadeTo(0, 0.5)
	at(0.4)
	eyes(0.35, 1)
	at(1.8)
	eyes(0, 0.25)
	at(2.3)
	eyes(0.7, 0.6)
	Util.tween(blurValue, 2, { Value = 12 })
	at(3.2)
	go(function()
		walk(papa, { W(-2, 24) }, 7, { ground = true })
	end)
	go(function()
		walk(kinA, { W(-17, 22) }, 6, { ground = true })
	end)
	go(function()
		walk(kinB, { W(15, 19) }, 6, { ground = true })
	end)
	at(3.8)
	focusFn = function()
		return (headOf(papa) + headOf(kinA) + headOf(kinB)) / 3
	end
	rate = 1.1
	Util.tween(rollV, 2, { Value = 0.35 })
	at(5)
	eyes(0, 0.2)
	at(5.4)
	eyes(1, 0.5)
	Util.tween(blurValue, 1.5, { Value = 5 })
	at(6.2)
	-- Papa revs the chainsaw
	sfx("Chainsaw", nil, papa.root.Position, 1)
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
	go(function()
		local t = 0
		animate(3.2, function(a, dt)
			t += dt
			local raise = Util.lerp(0.4, 1.9, smooth(a * 3))
			pose(papa, "rightShoulder", armOffset(papa, true, raise + math.noise(t * 30) * 0.08, 0.1 + math.noise(t * 30, 2) * 0.05), 0)
		end)
	end)
	at(6.6)
	HUD.subtitle("Papa", "YOU BROKE MY TRUCK!", 3)
	focusFn = function()
		return headOf(papa)
	end
	rate = 2
	zoom(52, 0.8)
	CameraController.shake(0.5, 3)
	at(9.4)
	black.BackgroundTransparency = 0
	stopCamera()
	CameraController.shake(1.2, 3)
	title("RUN.", { size = 130, color = C.BloodBright, fadeIn = 0.08, hold = 1.5, fadeOut = 0.6 })
	sleep(2.3)
end

---------------------------------------------------------------- 6. Ending (~30 s)

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
	table.insert(cleanups, function()
		tween:Cancel()
		for key, v in saved do
			(inst :: any)[key] = v
		end
	end)
end

local function endingScene(data: any)
	local padSite = Config.Sites.Helipad.pos
	local pad = asCF(data.pad, CF(padSite.X, groundY(padSite.X, padSite.Y), padSite.Y))
	local serverHeli = asModel(data.helicopter)
	fadeWait(1, 0.5)
	letterbox(true, 0)

	local landed = if serverHeli then serverHeli:GetPivot() else pad * CF(0, 0.8, 0) * ANG(0, rad(200), 0)
	local heli = cloneProp(serverHeli)
	hide(serverHeli)
	if not heli then
		local built = simpleHelicopter()
		built.Parent = scene()
		heli = built
	end
	local craft = heli :: Model
	craft:PivotTo(landed)
	addCabin(craft, landed)
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
	local wreckPos = Vector3.new(wreckSite.X, groundY(wreckSite.X, wreckSite.Y), wreckSite.Y)
	local dir = Util.flat(wreckPos - padPos)
	dir = if dir.Magnitude > 1 then dir.Unit else Vector3.new(0, 0, -1)
	local rightDir = Vector3.new(-dir.Z, 0, dir.X)
	local leftDir = -rightDir
	local start = landed.Position
	local lift = start + UP * 16
	local route = spline({
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
		local pos = splineAt(route, math.clamp(flightT / FLIGHT, 0, 1) ^ 1.7)
		local speed = (pos - lastPos).Magnitude / math.max(dt, 1e-3)
		lastPos = pos
		tilt = Util.lerp(tilt, -math.clamp(speed / 40, 0, 1) * 0.16, math.min(1, dt * 2))
		local rot = landed.Rotation:Lerp(travel, smooth(flightT / 5))
		heliCF = CF(pos) * rot * ANG(tilt, 0, math.sin(flightT * 0.6) * 0.025)
		craft:PivotTo(heliCF)
		local spin = CF(MAST) * ANG(0, os.clock() * 25, 0) * CF(-MAST)
		for _, e in rotorParts do
			e.part.CFrame = heliCF * spin * e.offset
		end
	end

	-- rotor wash kicking up dust on the pad
	local dustPart = part(Vector3.new(30, 1, 30), CF(padPos + UP * 0.5), C.Ink, nil, { Transparency = 1 })
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
	local watchers: { Actor } = {}
	for i, kind in { "Papa", "Hunter", "Kin", "Scavenger", "Kin" } do
		local offset = (i - 3) * 9
		local from = ground(padPos + leftDir * 50 + dir * offset)
		local to = ground(padPos + leftDir * 41 + dir * offset * 0.9)
		local a = spawnActor(kind, CFrame.lookAt(from, Vector3.new(to.X, from.Y, to.Z)))
		if kind == "Kin" then
			giveLantern(a)
			pose(a, "leftShoulder", armOffset(a, false, 0.8, 0.1), 0)
		end
		playAnim(a, "idle")
		table.insert(watchers, a)
	end

	resetClock()
	for i, a in watchers do
		go(function()
			at(3.6 + i * 0.25)
			walk(a, { padPos + leftDir * 41 + dir * (i - 3) * 8.1 }, 3.2, { ground = true })
			pose(a, "neck", neckOffset(a, 0.55, 0, (i % 2 - 0.5) * 0.3), 1.2)
		end)
	end

	-- lift-off from the edge of the pad
	local camPos1 = padPos + rightDir * 20 - dir * 22 + UP * 3.2
	track(function(dt)
		updateHeli(dt)
		return CFrame.lookAt(camPos1, heliCF.Position + UP * 5)
	end)
	zoom(55, 0)
	fadeTo(0, 1.2)
	later(5, function()
		dust.Enabled = false
	end)

	-- out of the side door, looking down at them, then out toward the forest
	at(4.6)
	local pitchV = numberValue(-0.62)
	local yawV = numberValue(math.pi / 2 - 0.2)
	track(function(dt)
		updateHeli(dt)
		local t = os.clock()
		local rattle = ANG(math.noise(t * 7, 1) * 0.006, math.noise(t * 7, 2) * 0.006, 0)
		return heliCF * CF(-2.3, 5.7, 0.6) * ANG(0, yawV.Value, 0) * ANG(pitchV.Value, 0, 0) * rattle
	end)
	zoom(68, 0)
	Util.tween(pitchV, 7.8, { Value = -0.3 })
	Util.tween(yawV, 7.8, { Value = math.pi / 2 - 0.55 })

	-- wide: the helicopter heads off into the dawn
	at(12.4)
	local camPos3 = heliCF.Position + rightDir * 34 - dir * 30 + UP * 6
	track(function(dt)
		updateHeli(dt)
		return CFrame.lookAt(camPos3, heliCF.Position)
	end)
	zoom(50, 0)
	at(13.2)
	title("You escaped Butcher's Hollow.", { size = 54, color = C.Bone, fadeIn = 1.6, hold = 3.2, fadeOut = 1.2 })
	at(16.8)
	Audio.loop("HelicopterLoop", false)
	at(18.4)
	fadeTo(1, 1.2)

	-- one of them is still standing in the trees
	at(19.8)
	for _, a in watchers do
		a.model:Destroy()
	end
	local figurePos = ground(padPos + leftDir * 47 + dir * 6)
	local figure = spawnActor("Butcher", CFrame.lookAt(figurePos, Vector3.new(padPos.X, figurePos.Y, padPos.Z)))
	playAnim(figure, "idle")
	local head = headOf(figure)
	local camFrom = ground(padPos + leftDir * 30 + dir * 2) + UP * 4.2
	local camTo = ground(padPos + leftDir * 35 + dir * 4) + UP * 4.6
	shot(7.8, { camFrom, camTo }, { head, head + UP * 0.2 }, { fov = 42, wait = false })
	fadeTo(0, 1.4)
	at(22.6)
	pose(figure, "neck", neckOffset(figure, 0.1, 0, 0.42), 1.4)
	for _, d in figure.model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Eye" then
			Util.tween(d, 1.4, { Transparency = 0.1 })
		end
	end
	at(23.2)
	local last = title("…they are still hungry.", { size = 46, color = C.BloodBright, fadeIn = 1.6 })
	at(27.6)
	black.BackgroundTransparency = 0
	stopCamera()
	sleep(0.8)
	Util.tween(last, 0.8, { TextTransparency = 1 })
	sleep(0.9)
end

---------------------------------------------------------------- runner

-- Unknown names still lock briefly and report back.
local function genericScene(_data: any)
	fadeWait(1, 0.6)
	sleep(0.6)
end

local SCENES: { [string]: (data: any) -> () } = {
	Crash = crashScene,
	WakeUp = wakeUpScene,
	TruckFound = truckFoundScene,
	Drive = driveScene,
	Radio = radioScene,
	Ending = endingScene,
}

local function begin()
	aborting = false
	Cutscenes.playing = true
	Movement.locked = true
	Viewmodel.hidden = true
	HUD.setVisible(false)
	CameraController.setEnabled(false)
	camera.CameraType = Enum.CameraType.Scriptable
	camCF.Value = camera.CFrame
	camFov.Value = camera.FieldOfView
	blurValue.Value = 0
	swayAmount = 0
	hideCharacters = true
	scene()
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 2, render)
end

-- Tears the scene down and hands the camera back; the screen is left black.
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
			warn("[Cutscenes] cleanup: " .. tostring(err))
		end
	end
	table.clear(cleanups)
	stopCamera()
	if fovTween then
		fovTween:Cancel()
		fovTween = nil
	end
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_STEP)
	end)
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
	local folder = stage
	if folder then
		folder:Destroy()
		stage = nil
	end
	layer:ClearAllChildren()
	white.BackgroundTransparency = 1
	eyes(1, 0)
	swayAmount = 0
	blurValue.Value = 0
	Effects.blurOverride = nil
	CameraController.setEnabled(true)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	Cutscenes.playing = false
end

local function play(name: string, data: any)
	local scenefn = SCENES[name] or genericScene
	local payload = if typeof(data) == "table" then data else {}
	local finished = false
	local ok, err = pcall(begin :: any)
	if ok then
		local main = task.spawn(function()
			local played, problem = xpcall(scenefn :: any, debug.traceback, payload)
			if not played and not string.find(tostring(problem), CANCEL, 1, true) then
				warn("[Cutscenes] " .. name .. " failed: " .. tostring(problem))
			end
			finished = true
		end)
		table.insert(threads, main)
		local started = os.clock()
		local limit = LIMITS[name] or 20
		while not finished and #queue == 0 and os.clock() - started < limit do
			task.wait(0.1)
		end
		if not finished and #queue == 0 then
			warn("[Cutscenes] " .. name .. " hit its time limit")
		end
	else
		warn("[Cutscenes] could not start " .. name .. ": " .. tostring(err))
	end
	local cleaned, problem = pcall(cleanup :: any)
	if not cleaned then
		warn("[Cutscenes] cleanup failed: " .. tostring(problem))
		Cutscenes.playing = false
		Effects.blurOverride = nil
		pcall(CameraController.setEnabled, true)
	end
	Net.event("CutsceneDone"):FireServer(name)
end

-- Cutscenes play one after another. A new one arriving mid-scene means the
-- server already moved on, so the current scene is cut short.
local function runQueue()
	if running then
		return
	end
	running = true
	while #queue > 0 do
		local job = table.remove(queue, 1) :: { name: string, data: any }
		play(job.name, job.data)
		-- stay black for a moment: the next cutscene (or a teleport) may follow
		local deadline = os.clock() + (HOLD[job.name] or 0.15)
		while #queue == 0 and os.clock() < deadline do
			task.wait(0.05)
		end
		if #queue == 0 then
			Movement.locked = false
			Viewmodel.hidden = false
			HUD.setVisible(true)
			letterbox(false, 0)
			Util.tween(black, FADE_BACK[job.name] or 0.9, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end
	running = false
end

function Cutscenes.init()
	gui = Theme.screen("Cutscene", 4) -- below the HUD so subtitles and chapter cards show on top
	local ink = Color3.new(0, 0, 0)
	barTop = Theme.frame(gui, { Name = "BarTop", BackgroundColor3 = ink, Size = UDim2.fromScale(1, 0), ZIndex = 2 })
	barBottom = Theme.frame(gui, {
		Name = "BarBottom",
		BackgroundColor3 = ink,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		ZIndex = 2,
	})
	lidTop = Theme.frame(gui, { Name = "LidTop", BackgroundColor3 = ink, Size = UDim2.fromScale(1, 0), ZIndex = 3 })
	lidBottom = Theme.frame(gui, {
		Name = "LidBottom",
		BackgroundColor3 = ink,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		ZIndex = 3,
	})
	-- soft lid edges
	local edge = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	Util.create("UIGradient", { Rotation = 90, Transparency = edge, Parent = lidTop })
	Util.create("UIGradient", { Rotation = -90, Transparency = edge, Parent = lidBottom })
	black = Theme.frame(gui, { Name = "Fade", BackgroundColor3 = ink, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8 })
	white = Theme.frame(gui, {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
	})
	layer = Theme.frame(gui, { Name = "Layer", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10 })

	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if barsOn then
			letterbox(true, 0)
		end
	end)

	Net.event("Cutscene").OnClientEvent:Connect(function(name: any, data: any)
		if typeof(name) ~= "string" then
			return
		end
		table.insert(queue, { name = name, data = data })
		task.spawn(runQueue)
	end)
end

return Cutscenes

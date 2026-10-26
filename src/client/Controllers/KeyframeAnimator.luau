--!strict
-- Plays the R6 animations (Shared.AnimData: baked, or written as code with
-- AnimData/Author) on every R6 rig this client can see by writing
-- Motor6D.Transform every frame after the Animator has run: player
-- characters, the family, the hosts and cutscene actors. Idle,
-- walk or run is picked from how fast each rig moves, so nothing has to be
-- uploaded as an animation asset and it works the same in live servers.
--
-- Player characters are always included; other rigs opt in with the
-- "KeyframeAnimated" tag. Optional attributes on the model:
--   AnimIdle / AnimWalk / AnimRun   clip names (AnimData modules)
--   AnimRunAt                       speed where running starts
--   AnimWalkRef / AnimRunRef        speed that plays a clip at 1x
--   AnimForce                       "idle" | "walk" | "run" to force a clip
--                                   (cutscenes), "none" to stop writing
--   AnimRate                        playback rate while forced
--   AnimBusy                        true while an Animator action plays
--   AnimLegsOnly                    true to animate only the legs

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local KeyframeAnimator = {}

local TAG = "KeyframeAnimated"
local FADE = 0.2
local RANGE = 260
local IDLES = { "Idle1", "Idle2", "Idle3", "Idle4" }
-- players stand easy: Idle4 holds both arms straight out (a T-pose from
-- the side) and Idle3 leans and reaches; those suit the family, not you
local PLAYER_IDLES = { "Idle1", "Idle2" }

type Clip = { length: number, fps: number, loop: boolean, joints: { string }, frames: { { CFrame } } }

type Rig = {
	model: Model,
	root: BasePart,
	motors: { [string]: Motor6D },
	idle: string,
	clip: string,
	time: number,
	previous: string?,
	previousTime: number,
	blend: number,
	lastPos: Vector3,
	speed: number,
	stopped: boolean,
}

local clips: { [string]: Clip } = {}
local missing: { [string]: boolean } = {} -- clips that failed to load
local rigs: { [Model]: Rig } = {}

local function loadClip(name: string): Clip?
	if missing[name] then
		return nil
	end
	local cached = clips[name]
	if cached then
		return cached
	end
	local folder = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("AnimData")
	local module = folder and folder:FindFirstChild(name)
	if not (module and module:IsA("ModuleScript")) then
		missing[name] = true
		return nil
	end
	local ok, raw = pcall(require, module)
	if not ok or typeof(raw) ~= "table" then
		warn("[KeyframeAnimator] could not load " .. name)
		missing[name] = true
		return nil
	end
	local data = raw :: any
	local frames: { { CFrame } } = {}
	for i, row in data.frames do
		local frame: { CFrame } = {}
		for j = 1, #data.joints do
			local o = (j - 1) * 6
			local r = Vector3.new(row[o + 4], row[o + 5], row[o + 6])
			local rot = if r.Magnitude > 1e-6 then CFrame.fromAxisAngle(r.Unit, r.Magnitude) else CFrame.identity
			frame[j] = CFrame.new(row[o + 1], row[o + 2], row[o + 3]) * rot
		end
		frames[i] = frame
	end
	local clip: Clip = {
		length = math.max(data.length, 1 / data.fps),
		fps = data.fps,
		loop = data.loop,
		joints = data.joints,
		frames = frames,
	}
	clips[name] = clip
	return clip
end

local function sample(clip: Clip, t: number, j: number): CFrame
	local n = #clip.frames
	local x = (if clip.loop then t % clip.length else math.min(t, clip.length)) * clip.fps
	local i = math.floor(x)
	local a = x - i
	local f1 = clip.frames[math.min(i + 1, n)][j]
	local f2 = clip.frames[math.min(i + 2, n)][j]
	return f1:Lerp(f2, a)
end

local function attr(model: Model, name: string): any
	return model:GetAttribute(name)
end

---------------------------------------------------------------- rigs

local function untrack(model: Model)
	local rig = rigs[model]
	if rig then
		for _, motor in rig.motors do
			if motor.Parent then
				motor.Transform = CFrame.identity
			end
		end
		rigs[model] = nil
	end
end

local function track(model: Model)
	if rigs[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return -- the baked clips are R6 only
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local motors: { [string]: Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 then
			motors[d.Part1.Name] = d
		end
	end
	if not motors.Torso then
		return
	end
	local idle = attr(model, "AnimIdle")
	local pool = if Players:GetPlayerFromCharacter(model) then PLAYER_IDLES else IDLES
	rigs[model] = {
		model = model,
		root = root,
		motors = motors,
		idle = if typeof(idle) == "string" then idle else pool[math.random(#pool)],
		clip = "",
		time = math.random() * 4,
		previous = nil,
		previousTime = 0,
		blend = 1,
		lastPos = root.Position,
		speed = 0,
		stopped = false,
	}
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			untrack(model)
		end
	end)
end

-- The default Animate script would fight the baked clips on our own body.
local function silenceDefaultAnimate(character: Model)
	local animate = character:WaitForChild("Animate", 5)
	if animate then
		animate:Destroy()
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, t in animator:GetPlayingAnimationTracks() do
			t:Stop(0)
		end
	end
end

local function onCharacter(player: Player, character: Model)
	if player == Players.LocalPlayer then
		task.spawn(silenceDefaultAnimate, character)
	end
	character:WaitForChild("HumanoidRootPart", 10)
	character:WaitForChild("Humanoid", 10)
	track(character)
end

---------------------------------------------------------------- per frame

local function choose(rig: Rig): (string?, number)
	local model = rig.model
	local force = attr(model, "AnimForce")
	-- players move on the clips written for them (AnimData/Author): their
	-- own walk and run, and low and slow while crouching
	local owner = Players:GetPlayerFromCharacter(model)
	if owner and typeof(force) ~= "string" then
		local speed = rig.speed
		if owner:GetAttribute("Crouching") == true then
			if speed < 0.7 then
				return "CrouchIdle", 1
			end
			return "CrouchWalk", math.clamp(speed / 4.5, 0.5, 1.8)
		elseif speed < 0.7 then
			return rig.idle, 1
		elseif speed >= 15 then
			return "PlayerRun", math.clamp(speed / 7.5, 0.7, 1.6)
		end
		return "PlayerWalk", math.clamp(speed / 6, 0.5, 1.6)
	end
	local walkClip = attr(model, "AnimWalk") or "Walk1"
	local runClip = attr(model, "AnimRun") or "Run2"
	if typeof(force) == "string" then
		local rate = attr(model, "AnimRate")
		local r = if typeof(rate) == "number" then rate else 1
		if force == "idle" then
			return rig.idle, 1
		elseif force == "walk" then
			return walkClip, r
		elseif force == "run" then
			return runClip, r
		end
		return nil, 0
	end
	local runAt = attr(model, "AnimRunAt") or 14
	local speed = rig.speed
	if speed < 0.7 then
		return rig.idle, 1
	elseif speed >= runAt then
		local ref = attr(model, "AnimRunRef") or 19
		return runClip, math.clamp(speed / ref, 0.6, 1.6)
	end
	local ref = attr(model, "AnimWalkRef") or 10
	return walkClip, math.clamp(speed / ref, 0.45, 1.6)
end

local function step(rig: Rig, dt: number, camPos: Vector3)
	local root = rig.root
	local pos = root.Position
	local moved = Vector3.new(pos.X - rig.lastPos.X, 0, pos.Z - rig.lastPos.Z).Magnitude
	rig.lastPos = pos
	if dt > 0 then
		rig.speed += (math.min(moved / dt, 60) - rig.speed) * math.min(1, dt * 10)
	end
	if (pos - camPos).Magnitude > RANGE then
		return
	end
	local humanoid = rig.model:FindFirstChildOfClass("Humanoid")
	if (humanoid and humanoid.Health <= 0) or attr(rig.model, "AnimBusy") == true then
		return
	end
	local name, rate = choose(rig)
	if not name then
		if not rig.stopped then
			rig.stopped = true
			for _, motor in rig.motors do
				motor.Transform = CFrame.identity
			end
		end
		return
	end
	rig.stopped = false
	local clip = loadClip(name)
	if not clip then
		return
	end
	if name ~= rig.clip then
		rig.previous = if rig.clip ~= "" then rig.clip else nil
		rig.previousTime = rig.time
		rig.clip = name
		rig.time = 0
		rig.blend = if rig.previous then 0 else 1
	end
	rig.time += dt * rate
	rig.blend = math.min(1, rig.blend + dt / FADE)
	local previous = if rig.blend < 1 and rig.previous then loadClip(rig.previous) else nil
	if previous then
		rig.previousTime += dt
	end
	-- AnimLegsOnly: walk with the legs while the arms hold a pose (carrying)
	local legsOnly = attr(rig.model, "AnimLegsOnly") == true
	for j, joint in clip.joints do
		local motor = rig.motors[joint]
		if motor then
			if legsOnly and joint ~= "Left Leg" and joint ~= "Right Leg" then
				motor.Transform = CFrame.identity
				continue
			end
			local cf = sample(clip, rig.time, j)
			if previous then
				cf = sample(previous, rig.previousTime, j):Lerp(cf, rig.blend)
			end
			motor.Transform = cf
		end
	end
end

function KeyframeAnimator.init()
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end)
	for _, inst in CollectionService:GetTagged(TAG) do
		if inst:IsA("Model") then
			task.spawn(track, inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		if inst:IsA("Model") then
			local model = inst :: Model
			-- replicated rigs can arrive before their parts do
			task.defer(function()
				model:WaitForChild("HumanoidRootPart", 5)
				track(model)
			end)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		if inst:IsA("Model") and not Players:GetPlayerFromCharacter(inst) then
			untrack(inst)
		end
	end)

	-- after the Animator has stepped (it resets Transform every frame), as
	-- the Motor6D.Transform docs recommend
	RunService.PreSimulation:Connect(function(dt: number)
		local camPos = workspace.CurrentCamera.CFrame.Position
		for model, rig in rigs do
			if model.Parent and rig.root.Parent then
				step(rig, dt, camPos)
			else
				rigs[model] = nil
			end
		end
	end)
end

return KeyframeAnimator

--!strict
-- The jumpscare. A monster's distorted face (its Blender MonsterHead, the
-- clawed MonsterArms reaching up past it) lunges out of a ViewportFrame at
-- you, so it can never clip into a wall, while the screen strobes red /
-- white / black and flips to a negative (white world, black face), the view
-- punches and it screeches. Used by the random scares and the caught screen.
-- Reduce flashing (Settings) keeps the lunge and the sound but trades the
-- strobe and the negative for one soft red pulse.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Audio)
local CameraController = require(script.Parent.CameraController)
local Effects = require(script.Parent.Effects)
local MeshLibrary = require(script.Parent.MeshLibrary)
local Settings = require(script.Parent.Settings)

local Jumpscare = {}

export type Options = {
	tail: boolean?, -- end on a black frame that fades out (the random scares)
	duration: number?, -- how long the face stays in your face
}

local player = Players.LocalPlayer
local RED = Color3.fromRGB(255, 20, 10)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local STROBE_HZ = 15

-- One strobe step: what fills the screen behind the face, and the face tint.
local STROBE: { { bg: Color3, bgAlpha: number, tint: Color3 } } = {
	{ bg = RED, bgAlpha = 0, tint = WHITE },
	{ bg = WHITE, bgAlpha = 0, tint = BLACK }, -- the negative
	{ bg = BLACK, bgAlpha = 0, tint = Color3.fromRGB(255, 232, 220) },
	{ bg = RED, bgAlpha = 0.55, tint = Color3.fromRGB(255, 130, 120) },
	{ bg = WHITE, bgAlpha = 0, tint = BLACK },
	{ bg = BLACK, bgAlpha = 0.2, tint = WHITE },
}

local playing = false

local function pickKind(): string
	local templates = ReplicatedStorage:FindFirstChild("CannibalTemplates")
	local options = templates and templates:GetChildren() or {}
	if #options == 0 then
		return "Butcher"
	end
	return options[math.random(#options)].Name
end

-- The face around the origin, looking down -Z: the Blender monster head with
-- both clawed arms coming up at the lens, or, without the imported meshes,
-- the kind's rig with its head at the origin.
local function buildFace(kind: string): Model?
	local face = Instance.new("Model")
	local head = MeshLibrary.template(kind .. "MonsterHead")
	if head then
		head.model:Clone().Parent = face
		local arm = MeshLibrary.template(kind .. "MonsterArm")
		if arm then
			for _, side in { -1, 1 } do
				local a = arm.model:Clone()
				-- tipped forward so the claws point at the lens, from below the jaw
				a:PivotTo(CFrame.new(side * 1.25, -1.4, 0.8) * CFrame.Angles(math.rad(72), 0, side * math.rad(-24)))
				a.Parent = face
			end
		end
		return face
	end
	local templates = ReplicatedStorage:FindFirstChild("CannibalTemplates")
	local template = templates and templates:FindFirstChild(kind)
	local headPart = template and template:FindFirstChild("Head")
	if not (template and template:IsA("Model") and headPart and headPart:IsA("BasePart")) then
		face:Destroy()
		return nil
	end
	local rig = template:Clone()
	rig:PivotTo(headPart.CFrame:ToObjectSpace(template:GetPivot()))
	rig.Parent = face
	return face
end

function Jumpscare.isPlaying(): boolean
	return playing
end

-- Yields until the scare is over. kind: whose face (random if nil).
function Jumpscare.play(kind: string?, opts: Options?)
	if playing then
		return
	end
	playing = true
	local o: Options = opts or {}
	local reduced = Settings.reduceFlashing
	local duration = o.duration or 0.75
	local face = buildFace(kind or pickKind())

	local gui = Instance.new("ScreenGui")
	gui.Name = "Jumpscare"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ResetOnSpawn = false
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BorderSizePixel = 0
	bg.BackgroundTransparency = 1
	bg.Parent = gui
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(150, 70, 60)
	vp.LightColor = Color3.fromRGB(255, 210, 180)
	vp.LightDirection = Vector3.new(0.2, 0.7, 1) -- lit from below, like a torch under the chin
	vp.Parent = gui
	local cam = Instance.new("Camera")
	cam.FieldOfView = 70
	cam.Parent = vp
	vp.CurrentCamera = cam
	if face then
		face.Parent = vp
	end
	local wash = Instance.new("Frame")
	wash.Size = UDim2.fromScale(1, 1)
	wash.BorderSizePixel = 0
	wash.BackgroundColor3 = RED
	wash.BackgroundTransparency = 1
	wash.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	-- the screech: the jumpscare sting under a scream pushed up and distorted
	Audio.play("Jumpscare", nil, 1.3, 1)
	local scream = Audio.play("Scream", nil, 1.15, 1.3)
	if scream then
		local distortion = Instance.new("DistortionSoundEffect")
		distortion.Level = 0.6
		distortion.Parent = scream
	end
	CameraController.punch(if reduced then 10 else 26)
	CameraController.shake(if reduced then 2 else 4, 1.6)
	Effects.flash(RED, 0.7)
	if reduced then
		wash.BackgroundTransparency = 0.55
		Util.tween(wash, 0.7, { BackgroundTransparency = 1 })
	end

	local lunge = if reduced then 0.42 else 0.22
	local start = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		local k = math.min(t / lunge, 1)
		local ease = 1 - (1 - k) ^ 3 -- out of the dark and into your face
		local d = Util.lerp(9, 1.45, ease)
		local jitter = if k >= 1 then 1 else 0.3
		cam.FieldOfView = Util.lerp(70, 48, ease)
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.05, -d), Vector3.new(0, 0.05, 0))
			* CFrame.Angles(math.noise(t * 28, 1) * 0.05 * jitter, math.noise(t * 28, 2) * 0.05 * jitter, math.noise(t * 28, 3) * 0.08 * jitter)
		if not reduced and t > 0.05 then
			local step = STROBE[math.floor(t * STROBE_HZ) % #STROBE + 1]
			bg.BackgroundColor3 = step.bg
			bg.BackgroundTransparency = step.bgAlpha
			vp.ImageColor3 = step.tint
		end
	end)
	task.wait(duration)
	conn:Disconnect()
	vp.ImageColor3 = WHITE
	if o.tail ~= false then
		bg.BackgroundColor3 = BLACK
		bg.BackgroundTransparency = 0
		vp.Visible = false
		task.wait(0.25)
		Util.tween(bg, 0.5, { BackgroundTransparency = 1 })
		task.wait(0.55)
	end
	gui:Destroy()
	playing = false
end

return Jumpscare

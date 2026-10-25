--!strict
-- The syringe fight-back. When you go for the needle while one of the family
-- has you, the camera locks onto its face and the keys to hit come up one at
-- a time, each with a ring closing in: W A S D (arrows and a gamepad work
-- too, and a phone gets four big buttons). Every key hit in time and the
-- needle goes in; one wrong or late and you get slammed. The server decides
-- what happens; this only reports whether you made it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local Theme = require(script.Parent.Theme)

local Struggle = {}

local C = Theme.Colors
local player = Players.LocalPlayer

local KEYCODES: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.W] = "W",
	[Enum.KeyCode.Up] = "W",
	[Enum.KeyCode.DPadUp] = "W",
	[Enum.KeyCode.ButtonY] = "W",
	[Enum.KeyCode.A] = "A",
	[Enum.KeyCode.Left] = "A",
	[Enum.KeyCode.DPadLeft] = "A",
	[Enum.KeyCode.ButtonX] = "A",
	[Enum.KeyCode.S] = "S",
	[Enum.KeyCode.Down] = "S",
	[Enum.KeyCode.DPadDown] = "S",
	[Enum.KeyCode.ButtonA] = "S",
	[Enum.KeyCode.D] = "D",
	[Enum.KeyCode.Right] = "D",
	[Enum.KeyCode.DPadRight] = "D",
	[Enum.KeyCode.ButtonB] = "D",
}
local ARROWS: { [string]: string } = { W = "▲", A = "◀", S = "▼", D = "▶" }

local gui: ScreenGui
local active = false
local pressed: string? = nil

local function onKey(key: string)
	if active then
		pressed = key
	end
end

local function build(): (Frame, TextLabel, Frame, TextLabel, Frame, Frame, TextLabel)
	local root = Theme.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	-- blood-red edges and letterbox bars
	Theme.vignette(root, C.Blood, 0.32, 1)
	for _, top in { true, false } do
		Theme.frame(root, {
			AnchorPoint = Vector2.new(0, if top then 0 else 1),
			Position = UDim2.fromScale(0, if top then 0 else 1),
			Size = UDim2.new(1, 0, 0.11, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			ZIndex = 2,
		})
	end
	local title = Theme.label(root, "FIGHT BACK!", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.14, 0),
		Size = UDim2.fromOffset(600, 70),
		Font = Theme.Fonts.Title,
		TextSize = 64,
		TextColor3 = C.BloodBright,
		TextStrokeTransparency = 0.3,
		ZIndex = 3,
	})
	-- the key and the ring closing in on it
	local holder = Theme.frame(root, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(130, 130),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.15,
		ZIndex = 3,
	})
	Theme.corner(holder, 18)
	Theme.stroke(holder, C.Bone, 3)
	local keyLabel = Theme.label(holder, "W", {
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Fonts.UIBold,
		TextSize = 72,
		TextColor3 = C.Bone,
		ZIndex = 4,
	})
	local ring = Theme.frame(root, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(300, 300),
		BackgroundTransparency = 1,
		ZIndex = 3,
	})
	Theme.corner(ring, 150)
	local ringStroke = Theme.stroke(ring, C.BloodBright, 5)
	ringStroke.Transparency = 0.1
	local hint = Theme.label(root, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 90),
		Size = UDim2.fromOffset(500, 30),
		Font = Theme.Fonts.UI,
		TextSize = 18,
		TextColor3 = C.BoneDim,
		ZIndex = 3,
	})
	local pips = Theme.frame(root, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.14, 80),
		Size = UDim2.fromOffset(400, 18),
		BackgroundTransparency = 1,
		ZIndex = 3,
	})
	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = pips,
	})
	return root, keyLabel, ring, hint, pips, holder, title
end

local function touchPad(parent: Instance): Frame
	-- four big buttons, bottom right, for phones and tablets
	local pad = Theme.frame(parent, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -30, 0.89, -20),
		Size = UDim2.fromOffset(240, 240),
		BackgroundTransparency = 1,
		ZIndex = 5,
	})
	local spots: { [string]: UDim2 } = { W = UDim2.fromOffset(80, 0), A = UDim2.fromOffset(0, 80), S = UDim2.fromOffset(80, 160), D = UDim2.fromOffset(160, 80) }
	for key, pos in spots do
		local b = Theme.button(pad, ARROWS[key], {
			Position = pos,
			Size = UDim2.fromOffset(80, 80),
			TextSize = 40,
			Font = Theme.Fonts.UIBold,
			ZIndex = 6,
		})
		b.Activated:Connect(function()
			onKey(key)
		end)
	end
	return pad
end

local function run(data: any)
	if active or typeof(data) ~= "table" or typeof(data.keys) ~= "table" then
		return
	end
	local model = data.cannibal
	local head = if typeof(model) == "Instance" then model:FindFirstChild("Head") else nil
	local character = player.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not (myRoot and myRoot:IsA("BasePart")) then
		Net.event("StruggleResult"):FireServer(data.id, false)
		return
	end
	active = true
	pressed = nil
	local window = if typeof(data.window) == "number" then data.window else 1.2

	-- camera: locked on its face, close, pushing in
	local camera = workspace.CurrentCamera
	CameraController.setEnabled(false)
	camera.CameraType = Enum.CameraType.Scriptable
	local push = 0
	local shake = 0
	local renderConn = RunService.RenderStepped:Connect(function(dt: number)
		push = math.min(push + dt * 0.35, 1)
		shake = math.max(0, shake - dt * 3)
		local eye = (myRoot :: BasePart).Position + Vector3.new(0, 1.6, 0)
		local target = if head and head:IsA("BasePart") then head.Position else eye + (myRoot :: BasePart).CFrame.LookVector * 5
		local toward = (target - eye)
		local pos = eye + toward * (0.25 + push * 0.2)
		local t = os.clock() * 30
		local wobble = CFrame.Angles(math.noise(t, 1) * 0.02 * (1 + shake * 4), math.noise(t, 2) * 0.02 * (1 + shake * 4), math.noise(t, 3) * 0.04 * (1 + shake * 3))
		camera.CFrame = CFrame.lookAt(pos, target) * wobble
		camera.FieldOfView = 58 - push * 12
	end)
	-- movement keys only feed the struggle now
	ContextActionService:BindActionAtPriority("StruggleKeys", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			local key = KEYCODES[input.KeyCode]
			if key then
				onKey(key)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY)

	local root, keyLabel, ring, hint, pips, holder, title = build()
	local pad = if UserInputService.TouchEnabled then touchPad(root) else nil
	hint.Text = if pad then "Tap the arrow!" else "Press the key before the ring closes!"
	local pipFrames: { Frame } = {}
	for i = 1, #data.keys do
		local pip = Theme.frame(pips, { Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C.PanelLight, LayoutOrder = i, ZIndex = 4 })
		Theme.corner(pip, 9)
		pipFrames[i] = pip
	end
	root.Visible = true
	Effects.flash(C.BloodBright, 0.4)
	CameraController.shake(1.2, 4)
	Audio.play("Growl", nil, 1, 0.8)
	task.wait(0.7)

	local success = true
	for i, key in data.keys do
		if typeof(key) ~= "string" then
			success = false
			break
		end
		keyLabel.Text = if pad then ARROWS[key] or key else key
		holder.Size = UDim2.fromOffset(150, 150)
		Util.tween(holder, 0.12, { Size = UDim2.fromOffset(130, 130) })
		ring.Size = UDim2.fromOffset(320, 320)
		Util.tween(ring, window, { Size = UDim2.fromOffset(130, 130) }, Enum.EasingStyle.Linear)
		pressed = nil
		local started = os.clock()
		while pressed == nil and os.clock() - started < window do
			task.wait()
		end
		if pressed ~= key then
			success = false
			pipFrames[i].BackgroundColor3 = C.Blood
			break
		end
		pipFrames[i].BackgroundColor3 = C.Sickly
		shake = 1
		CameraController.shake(0.7, 6)
		Audio.play("Slash", nil, 0.6, 1 + i * 0.05)
		Util.tween(holder, 0.08, { BackgroundColor3 = C.Sickly })
		task.wait(0.12)
		holder.BackgroundColor3 = C.Ink
	end

	if success then
		-- the needle goes in
		title.Text = "NOW!"
		keyLabel.Text = "💉"
		push = 1
		Audio.play("Inject", nil, 1, 1)
		Effects.flash(Color3.new(1, 1, 1), 0.5)
		CameraController.shake(2, 3)
	else
		title.Text = "TOO SLOW"
		Audio.play("Impact", nil, 1, 0.7)
		Effects.flash(C.BloodBright, 0.8)
		CameraController.shake(3, 2)
	end
	Net.event("StruggleResult"):FireServer(data.id, success)
	task.wait(0.8)

	ContextActionService:UnbindAction("StruggleKeys")
	renderConn:Disconnect()
	root:Destroy()
	CameraController.setEnabled(true)
	active = false
end

function Struggle.init()
	gui = Theme.screen("Struggle", 30)
	Net.event("Struggle").OnClientEvent:Connect(function(data)
		task.spawn(run, data)
	end)
end

return Struggle

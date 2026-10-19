--!strict
-- In-game HUD: chapter cards, objectives, stamina / battery bars, detection
-- eye, subtitles, notifications, survive timer, objective hints and the
-- crosshair.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Movement = require(script.Parent.Parent.Controllers.Movement)
local Viewmodel = require(script.Parent.Parent.Controllers.Viewmodel)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Theme = require(script.Parent.Theme)

local HUD = {}

local player = Players.LocalPlayer
local C = Theme.Colors

local gui: ScreenGui
local root: Frame
local objectivePanel: Frame
local objectiveList: Frame
local chapterLabel: TextLabel
local titleLabel: TextLabel
local staminaBar: Frame
local staminaFill: Frame
local batteryBar: Frame
local batteryFill: Frame
local eye: Frame
local eyeFill: Frame
local subtitle: TextLabel
local toastHolder: Frame
local timerLabel: TextLabel
local crosshair: Frame
local hintLabel: TextLabel
local markers: Folder

HUD.visible = false
local lastChapter = ""
local hintReady = 0

local function makeBar(parent: Instance, position: UDim2, color: Color3, iconText: string): (Frame, Frame)
	local bar = Theme.frame(parent, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = position,
		Size = UDim2.fromOffset(220, 6),
		BackgroundColor3 = Color3.fromRGB(20, 18, 16),
		BackgroundTransparency = 0.3,
	})
	Theme.corner(bar, 3)
	local fill = Theme.frame(bar, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color })
	Theme.corner(fill, 3)
	Theme.label(bar, iconText, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -8, 0.5, 0),
		Size = UDim2.fromOffset(90, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 14,
		TextColor3 = C.BoneDim,
		Font = Theme.Fonts.UI,
	})
	return bar, fill
end

function HUD.setVisible(v: boolean)
	HUD.visible = v
	root.Visible = v
end

function HUD.chapterCard(chapter: string, title: string)
	local card = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(700, 140),
		BackgroundTransparency = 1,
		ZIndex = 20,
	})
	local a = Theme.label(card, chapter, {
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 26,
		TextColor3 = C.BoneDim,
		Font = Theme.Fonts.Type,
		TextTransparency = 1,
		ZIndex = 20,
	})
	local b = Theme.label(card, title, {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 80),
		TextSize = 70,
		TextColor3 = C.BloodBright,
		Font = Theme.Fonts.Title,
		TextTransparency = 1,
		ZIndex = 20,
	})
	Util.tween(a, 1.2, { TextTransparency = 0 })
	Util.tween(b, 1.6, { TextTransparency = 0 })
	Audio.play("Whoosh", nil, 0.4)
	task.delay(4, function()
		Util.tween(a, 1.5, { TextTransparency = 1 })
		Util.tween(b, 1.5, { TextTransparency = 1 })
		task.wait(1.6)
		card:Destroy()
	end)
end

local function renderObjectives(data: any)
	for _, c in objectiveList:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	chapterLabel.Text = string.upper(data.chapter or "")
	titleLabel.Text = data.title or ""
	for i, o in data.objectives or {} do
		local mark = if o.done then "<font color=\"#7f6f5f\"><s>" else ""
		local close = if o.done then "</s></font>" else ""
		local box = if o.done then "[x] " else "[  ] "
		local opt = if o.optional then " <font color=\"#8a8070\">(optional)</font>" else ""
		local line = Theme.label(objectiveList, box .. mark .. o.text .. close .. opt, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 17,
			LayoutOrder = i,
			TextColor3 = if o.done then C.BoneDim else C.Bone,
		})
		line.TextTransparency = 1
		Util.tween(line, 0.4 + i * 0.08, { TextTransparency = 0 })
	end
	-- a title card whenever a new chapter begins
	if data.chapter ~= lastChapter and data.chapter ~= "" then
		lastChapter = data.chapter
		HUD.chapterCard(data.chapter, data.title)
	end
end

function HUD.toast(text: string, kind: string?)
	local color = if kind == "warn" then C.Warn elseif kind == "item" then C.Sickly else C.Bone
	local t = Theme.frame(toastHolder, {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.25,
	})
	Theme.corner(t, 4)
	Theme.frame(t, { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = color })
	local label = Theme.label(t, text, {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -16, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		TextColor3 = color,
		Font = Theme.Fonts.UI,
	})
	t.BackgroundTransparency = 1
	label.TextTransparency = 1
	Util.tween(t, 0.25, { BackgroundTransparency = 0.25 })
	Util.tween(label, 0.25, { TextTransparency = 0 })
	task.delay(4, function()
		Util.tween(t, 0.6, { BackgroundTransparency = 1 })
		Util.tween(label, 0.6, { TextTransparency = 1 })
		task.wait(0.7)
		t:Destroy()
	end)
end

local subtitleToken = 0
function HUD.subtitle(speaker: string, text: string, duration: number?)
	subtitleToken += 1
	local token = subtitleToken
	local color = if speaker == "You" then "#d9cdb4" elseif speaker == "Dispatch" or speaker == "Pilot" then "#9fc6ff" else "#e0463a"
	subtitle.Text = string.format("<font color=\"%s\"><b>%s:</b></font> %s", color, string.upper(speaker), text)
	subtitle.TextTransparency = 1
	Util.tween(subtitle, 0.3, { TextTransparency = 0 })
	task.delay(duration or 4, function()
		if token == subtitleToken then
			Util.tween(subtitle, 0.5, { TextTransparency = 1 })
		end
	end)
end

local function showHints(targets: { Vector3 })
	markers:ClearAllChildren()
	if #targets == 0 then
		HUD.toast("No hint right now. Trust your instincts.", "info")
		return
	end
	for _, pos in targets do
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
		anchor.Parent = markers
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(60, 70)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Adornee = anchor
		bb.Parent = anchor
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Image = Assets.Images.MapPin
		icon.ImageColor3 = C.BloodBright
		icon.Size = UDim2.fromOffset(34, 34)
		icon.Position = UDim2.fromOffset(13, 0)
		icon.Parent = bb
		local dist = Theme.label(bb, "", {
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.fromOffset(60, 20),
			TextSize = 14,
			Font = Theme.Fonts.UI,
		})
		task.spawn(function()
			local t0 = os.clock()
			while anchor.Parent and os.clock() - t0 < 6 do
				local cam = workspace.CurrentCamera
				dist.Text = string.format("%dm", math.floor((cam.CFrame.Position - pos).Magnitude * 0.28))
				local fade = math.clamp((os.clock() - t0 - 4.5) / 1.5, 0, 1)
				icon.ImageTransparency = fade
				dist.TextTransparency = fade
				task.wait()
			end
			anchor:Destroy()
		end)
	end
end

function HUD.init()
	gui = Theme.screen("HUD", 5)
	root = Theme.frame(gui, { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	markers = Instance.new("Folder")
	markers.Name = "HintMarkers"
	markers.Parent = workspace

	-- objectives (top left)
	objectivePanel = Theme.frame(root, {
		Position = UDim2.fromOffset(28, 70),
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
	Util.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = objectivePanel })
	chapterLabel = Theme.label(objectivePanel, "", {
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		TextColor3 = C.BoneDim,
		Font = Theme.Fonts.UI,
		LayoutOrder = 1,
	})
	titleLabel = Theme.label(objectivePanel, "", {
		Size = UDim2.new(1, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 34,
		TextColor3 = C.BloodBright,
		Font = Theme.Fonts.Title,
		LayoutOrder = 2,
	})
	objectiveList = Theme.frame(objectivePanel, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
	})
	Util.create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = objectiveList })

	-- bars (bottom centre)
	staminaBar, staminaFill = makeBar(root, UDim2.new(0.5, 0, 1, -38), C.Bone, "STAMINA")
	batteryBar, batteryFill = makeBar(root, UDim2.new(0.5, 0, 1, -24), C.Warn, "BATTERY")

	-- detection eye (top centre)
	eye = Theme.frame(root, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.fromOffset(64, 26),
		BackgroundColor3 = Color3.fromRGB(12, 10, 10),
		BackgroundTransparency = 0.2,
	})
	Theme.corner(eye, 13)
	Theme.stroke(eye, C.Blood, 1.5)
	eyeFill = Theme.frame(eye, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0, 0.7),
		BackgroundColor3 = C.BloodBright,
	})
	Theme.corner(eyeFill, 10)
	Theme.frame(eye, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Color3.new(0, 0, 0),
	})

	-- subtitles
	subtitle = Theme.label(gui, "", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -80),
		Size = UDim2.new(0.7, 0, 0, 60),
		TextSize = 22,
		TextStrokeTransparency = 0.4,
		ZIndex = 30,
	})

	-- notifications (right side)
	toastHolder = Theme.frame(root, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 80),
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
	Util.create("UIListLayout", { Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Top, Parent = toastHolder })

	timerLabel = Theme.label(root, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(300, 50),
		TextSize = 44,
		Font = Theme.Fonts.Title,
		TextColor3 = C.BloodBright,
		Visible = false,
	})

	crosshair = Theme.frame(root, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.4,
	})
	Theme.corner(crosshair, 2)

	hintLabel = Theme.label(root, "[TAB] Inventory   [F] Flashlight   [SHIFT] Run   [C] Crouch   [H] Hint", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -12),
		Size = UDim2.fromOffset(560, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 13,
		TextColor3 = C.BoneDim,
		TextTransparency = 0.3,
		Font = Theme.Fonts.UI,
	})
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		hintLabel.Visible = false
	end

	HUD.setVisible(false)

	Net.event("Story").OnClientEvent:Connect(renderObjectives)
	Net.event("Notify").OnClientEvent:Connect(HUD.toast)
	Net.event("Subtitle").OnClientEvent:Connect(HUD.subtitle)
	Net.event("Hint").OnClientEvent:Connect(showHints)
	Net.event("Timer").OnClientEvent:Connect(function(remaining: number?)
		if remaining then
			timerLabel.Visible = true
			timerLabel.Text = "RESCUE IN " .. Util.formatTime(remaining)
		else
			timerLabel.Visible = false
		end
	end)

	ContextActionService:BindAction("Hint", function(_, state)
		if state == Enum.UserInputState.Begin and HUD.visible then
			if os.clock() < hintReady then
				HUD.toast(string.format("Hint ready in %ds", math.ceil(hintReady - os.clock())), "warn")
			else
				hintReady = os.clock() + Config.Player.HintCooldown
				Net.event("RequestHint"):FireServer()
			end
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.H, Enum.KeyCode.DPadUp)
	ContextActionService:SetTitle("Hint", "Hint")
	ContextActionService:SetPosition("Hint", UDim2.new(1, -100, 1, -290))

	RunService.RenderStepped:Connect(function(dt: number)
		if not HUD.visible then
			return
		end
		local stamina = Movement.stamina / Config.Player.StaminaMax
		staminaFill.Size = UDim2.fromScale(stamina, 1)
		staminaFill.BackgroundColor3 = if Movement.exhausted then C.Blood else C.Bone
		staminaBar.BackgroundTransparency = Util.lerp(staminaBar.BackgroundTransparency, if stamina >= 0.999 then 1 else 0.3, dt * 4)
		staminaFill.BackgroundTransparency = staminaBar.BackgroundTransparency * 0.9
		local hasLight = player:GetAttribute("HasFlashlight") == true
		batteryBar.Visible = hasLight
		batteryFill.Size = UDim2.fromScale(Viewmodel.battery / 100, 1)
		batteryFill.BackgroundColor3 = if Viewmodel.battery < 15 then C.BloodBright else C.Warn

		local detection = (player:GetAttribute("Detection") :: number?) or 0
		local chased = player:GetAttribute("Chased") == true
		eyeFill.Size = UDim2.fromScale(if chased then 0.9 else detection * 0.9, 0.7)
		eye.BackgroundTransparency = if detection > 0.02 or chased then 0.2 else 1
		for _, d in eye:GetDescendants() do
			if d:IsA("Frame") then
				d.BackgroundTransparency = if detection > 0.02 or chased then 0 else 1
			elseif d:IsA("UIStroke") then
				d.Transparency = if detection > 0.02 or chased then 0 else 1
			end
		end
		if chased then
			eyeFill.BackgroundColor3 = if math.floor(os.clock() * 4) % 2 == 0 then C.BloodBright else C.Blood
		end
	end)
end

return HUD

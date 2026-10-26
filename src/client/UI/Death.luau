--!strict
-- Getting caught: a jumpscare with the cannibal's face in the camera, then the
-- death card until the player respawns at the last checkpoint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Jumpscare = require(script.Parent.Parent.Controllers.Jumpscare)
local Viewmodel = require(script.Parent.Parent.Controllers.Viewmodel)
local Theme = require(script.Parent.Theme)
local HUD = require(script.Parent.HUD)

local Death = {}

local C = Theme.Colors
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local NAMES: { [string]: string } = {
	Butcher = "JASON",
	Brother = "MICHEL",
	Hunter = "THE HUNTER",
	Scavenger = "THE SCAVENGER",
	Papa = "PAPA",
	Kin = "THE FAMILY",
}

local TIPS = {
	"Crouching makes you much harder to notice.",
	"Your flashlight makes you easier to spot. Switch it off when they're close.",
	"Running is loud. They hear footsteps through walls.",
	"Break line of sight before you hide, or they will drag you out.",
	"A sedative only works from behind.",
	"Press H if you're lost.",
	"Bandages heal you. Check your inventory with TAB.",
}

local gui: ScreenGui
local red: Frame
local black: Frame
local caption: TextLabel
local killerLabel: TextLabel
local tipLabel: TextLabel
local countdown: TextLabel
local skull: ImageLabel

-- The one who caught you, in your face (Jumpscare.luau); the camera holds
-- still behind it.
local function jumpscare(kind: string?)
	CameraController.setEnabled(false)
	camera.CameraType = Enum.CameraType.Scriptable
	local templates = ReplicatedStorage:FindFirstChild("CannibalTemplates")
	local known = templates and kind and templates:FindFirstChild(kind)
	Jumpscare.play(if known then kind else "Butcher", { tail = false, duration = 0.9 })
end

-- Out of lives: the camera follows a teammate who's still alive (Next
-- cycles them), with a way back to the lobby. Nobody left standing: the card.
local watching = 0
local buttons: Frame
local function spectate()
	buttons.Visible = true
	local alive: { Humanoid } = {}
	for _, other in Players:GetPlayers() do
		local h = other ~= player and other.Character and other.Character:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then
			table.insert(alive, h)
		end
	end
	if #alive == 0 then
		return
	end
	watching = watching % #alive + 1
	Util.tween(black, 0.8, { BackgroundTransparency = 0.55 })
	for _, l in { killerLabel, tipLabel } do
		Util.tween(l, 0.5, { TextTransparency = 1 })
	end
	Util.tween(skull, 0.5, { ImageTransparency = 1 })
	Util.tween(caption, 0.5, { TextTransparency = 1 })
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = alive[watching]
	local name = Players:GetPlayerFromCharacter(alive[watching].Parent)
	countdown.Text = Lang.f("Watching %s", if name then name.DisplayName else "?")
end

local function gameOver()
	gui.Enabled = true
	HUD.setVisible(false)
	buttons.Visible = true
	black.BackgroundTransparency = 1
	Util.tween(black, 1.5, { BackgroundTransparency = 0 })
	caption.Text = Lang.t("THE FAMILY ATE WELL TONIGHT")
	killerLabel.Text = Lang.t("Nobody made it out.")
	tipLabel.Text = Lang.t("Back to the lobby in a moment.")
	countdown.Text = ""
	for _, l in { caption, killerLabel, tipLabel } do
		Util.tween(l, 1.5, { TextTransparency = 0 })
	end
	Util.tween(skull, 1.5, { ImageTransparency = 0.2 })
end

local function onCaught(kind: string?)
	HUD.setVisible(false)
	Viewmodel.hidden = true
	gui.Enabled = true
	black.BackgroundTransparency = 1
	red.BackgroundTransparency = 1
	for _, l in { caption, killerLabel, tipLabel, countdown } do
		l.TextTransparency = 1
	end
	skull.ImageTransparency = 1
	red.BackgroundTransparency = 0.6
	Util.tween(red, 0.4, { BackgroundTransparency = 1 })
	jumpscare(kind)
	black.BackgroundTransparency = 0
	killerLabel.Text = "CAUGHT BY " .. (NAMES[kind or ""] or "THE FAMILY")
	tipLabel.Text = TIPS[math.random(1, #TIPS)]
	Util.tween(caption, 1.2, { TextTransparency = 0 })
	Util.tween(skull, 1.2, { ImageTransparency = 0.2 })
	Util.tween(killerLabel, 1.6, { TextTransparency = 0 })
	Util.tween(tipLabel, 2, { TextTransparency = 0.2 })
	Util.tween(countdown, 2, { TextTransparency = 0.3 })
	if player:GetAttribute("Out") == true then
		-- no lives left: watch the rest of the party, or go back
		countdown.Text = Lang.t("No lives left.")
		task.wait(3)
		spectate()
		return
	end
	local lives = player:GetAttribute("Lives")
	local left = if typeof(lives) == "number" and lives > 0 then Lang.f("%d lives left", lives) .. "  ·  " else ""
	local remaining = Config.RespawnDelay
	while remaining > 0 and gui.Enabled do
		countdown.Text = left .. Lang.f("Waking up in %d...", math.ceil(remaining))
		task.wait(0.25)
		remaining -= 0.25
	end
end

function Death.init()
	gui = Theme.screen("Death", 25)
	gui.Enabled = false
	black = Theme.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0) })
	red = Theme.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(140, 0, 0), ZIndex = 5 })
	skull = Util.create("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(90, 90),
		BackgroundTransparency = 1,
		Image = Assets.Images.Skull,
		ImageColor3 = C.Blood,
		Parent = gui,
	})
	caption = Theme.label(gui, "YOU WERE EATEN", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0.9, 0, 0, 100),
		TextSize = 96,
		Font = Theme.Fonts.Title,
		TextColor3 = C.BloodBright,
	})
	killerLabel = Theme.label(gui, "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(600, 30),
		TextSize = 22,
		TextColor3 = C.Bone,
	})
	tipLabel = Theme.label(gui, "", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.65),
		Size = UDim2.fromOffset(700, 30),
		TextSize = 18,
		TextColor3 = C.BoneDim,
	})
	countdown = Theme.label(gui, "", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(400, 24),
		TextSize = 16,
		TextColor3 = C.BoneDim,
		Font = Theme.Fonts.UI,
	})

	-- out of lives: watch the others or leave
	buttons = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -76),
		Size = UDim2.fromOffset(380, 40),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 6,
	})
	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = buttons,
	})
	local nextButton = Theme.button(buttons, "Next", { Size = UDim2.fromOffset(120, 40), TextSize = 18, ZIndex = 6 })
	local lobbyButton = Theme.button(buttons, "Back to the lobby", { Size = UDim2.fromOffset(220, 40), TextSize = 18, ZIndex = 6 })
	nextButton.Activated:Connect(spectate)
	lobbyButton.Activated:Connect(function()
		lobbyButton.Active = false
		Net.event("PlayAgain"):FireServer()
	end)

	Net.event("Caught").OnClientEvent:Connect(function(kind: string?)
		task.spawn(onCaught, kind)
	end)
	Net.event("GameOver").OnClientEvent:Connect(gameOver)

	player.CharacterAdded:Connect(function()
		if not gui.Enabled then
			return
		end
		task.wait(0.4)
		CameraController.setEnabled(true)
		Viewmodel.hidden = false
		Util.tween(black, 1.2, { BackgroundTransparency = 1 })
		for _, l in { caption, killerLabel, tipLabel, countdown } do
			Util.tween(l, 0.8, { TextTransparency = 1 })
		end
		Util.tween(skull, 0.8, { ImageTransparency = 1 })
		task.wait(1.3)
		gui.Enabled = false
		if not player:GetAttribute("InCutscene") then
			HUD.setVisible(true)
		end
	end)
end

return Death

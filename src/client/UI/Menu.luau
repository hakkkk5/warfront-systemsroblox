--!strict
-- Title screen: slow camera drift over the cannibal house at night, title,
-- play / settings / how to play / credits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local Theme = require(script.Parent.Theme)
local HUD = require(script.Parent.HUD)
local SettingsPage = require(script.Parent.SettingsPage)

local Menu = {}

local C = Theme.Colors
local camera = workspace.CurrentCamera
local player = Players.LocalPlayer

local gui: ScreenGui
local main: Frame
local pages: { [string]: Frame } = {}
local fade: Frame
local loading: TextLabel
local playButton: TextButton
local renderConn: RBXScriptConnection? = nil

Menu.isOpen = false

local function groundAt(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -600, 0), params)
	return if hit then hit.Position.Y else 10
end

local function startCameraDrift()
	local house = Config.Sites.House.pos
	local y = groundAt(house.X, house.Y)
	local center = Vector3.new(house.X, y + 14, house.Y)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 55
	if renderConn then
		renderConn:Disconnect()
	end
	renderConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() * 0.035
		local pos = center + Vector3.new(math.cos(t) * 95, 18 + math.sin(t * 2.3) * 4, math.sin(t) * 95 - 20)
		camera.CFrame = CFrame.lookAt(pos, center + Vector3.new(0, -2, 0)) * CFrame.Angles(0, 0, math.sin(t * 3) * 0.02)
	end)
end

local function stopCameraDrift()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

local function showPage(name: string?)
	for key, page in pages do
		page.Visible = key == name
	end
	main.Visible = name == nil
end

local function panel(name: string, title: string): Frame
	local p = Theme.frame(gui, {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(560, 470),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08,
		Visible = false,
	})
	Theme.corner(p, 8)
	Theme.stroke(p, C.Blood, 1.5)
	Theme.padding(p, 26)
	Util.create("UISizeConstraint", { MaxSize = Vector2.new(600, 520), Parent = p })
	Theme.autoScale(p, Vector2.new(600, 520))
	Theme.label(p, title, {
		Size = UDim2.new(1, 0, 0, 46),
		TextSize = 40,
		Font = Theme.Fonts.Title,
		TextColor3 = C.BloodBright,
	})
	local back = Theme.button(p, "Back", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(180, 42),
	})
	back.Activated:Connect(function()
		showPage(nil)
	end)
	pages[name] = p
	return p
end

function Menu.open()
	Menu.isOpen = true
	gui.Enabled = true
	Effects.menuMode = true
	HUD.setVisible(false)
	CameraController.setEnabled(false)
	showPage(nil)
	startCameraDrift()
	Audio.music("Menu", 0.45)
end

function Menu.close()
	Menu.isOpen = false
	stopCameraDrift()
	Effects.menuMode = false
	gui.Enabled = false
end

local function play()
	if not Menu.isOpen or workspace:GetAttribute("WorldReady") ~= true then
		return
	end
	playButton.Active = false
	Audio.play("Whoosh")
	Util.tween(fade, 1.2, { BackgroundTransparency = 0 })
	task.wait(1.3)
	Menu.close()
	Audio.music(nil)
	CameraController.setEnabled(true)
	Net.event("RequestPlay"):FireServer()
	task.wait(0.6)
	Util.tween(fade, 1.5, { BackgroundTransparency = 1 })
	-- if no cutscene grabs the camera (joining a game in progress), show the HUD
	task.delay(2.5, function()
		if not player:GetAttribute("InCutscene") then
			HUD.setVisible(true)
		end
	end)
end

function Menu.init()
	gui = Theme.screen("Menu", 30)
	Theme.vignette(gui, Color3.new(0, 0, 0), 0.4, 1)

	-- laid out for at least 960 x 640 and scaled down to fit phones
	main = Theme.canvas(gui, Vector2.new(960, 640))
	local title = Theme.label(main, Config.GameName, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.14),
		Size = UDim2.new(0.9, 0, 0, 120),
		TextSize = 110,
		Font = Theme.Fonts.Title,
		TextColor3 = C.BloodBright,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = Color3.fromRGB(30, 0, 0),
	})
	Util.create("UITextSizeConstraint", { MaxTextSize = 110, Parent = title })
	title.TextScaled = true
	Theme.label(main, Config.Tagline, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.14, 124),
		Size = UDim2.fromOffset(600, 30),
		TextSize = 24,
		TextColor3 = C.BoneDim,
	})

	local buttons = Theme.frame(main, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(300, 260),
		BackgroundTransparency = 1,
	})
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttons,
	})
	playButton = Theme.button(buttons, "PLAY", { Size = UDim2.new(1, 0, 0, 54), TextSize = 28, LayoutOrder = 1 })
	local settingsButton = Theme.button(buttons, "Settings", { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 2 })
	local howButton = Theme.button(buttons, "How to play", { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3 })
	local creditsButton = Theme.button(buttons, "Credits", { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 4 })

	loading = Theme.label(main, "The woods are growing...", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -60),
		Size = UDim2.fromOffset(500, 26),
		TextSize = 18,
		TextColor3 = C.BoneDim,
	})
	Theme.label(main, "Contains horror themes, violence, blood and flashing lights (Settings > Reduce flashing). Best played alone, at night, with headphones.", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(800, 22),
		TextSize = 14,
		TextColor3 = C.BoneDim,
		Font = Theme.Fonts.UI,
	})

	-- settings
	local s = panel("Settings", "Settings")
	local list = Theme.frame(s, {
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -130),
		BackgroundTransparency = 1,
	})
	SettingsPage.fill(list)

	-- how to play
	local h = panel("How", "How to survive")
	Theme.label(h, table.concat({
		"<b>WASD</b> move   <b>Mouse</b> look   <b>Shift</b> run   <b>C</b> crouch",
		"<b>E</b> interact / hold to use   <b>F</b> flashlight   <b>Tab</b> inventory   <b>H</b> hint",
		"",
		"- Cannibals see you better when your flashlight is on and hear you when you run.",
		"- Crouch to sneak. Break line of sight, then hide in wardrobes, closets and lockers.",
		"- If they see you hide, they will drag you out.",
		"- A sedative syringe drops a cannibal for a while - but only from behind.",
		"- Batteries recharge the flashlight. Bandages heal. Notes tell you where to go.",
	}, "\n"), {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 1, -120),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	-- credits
	local c = panel("Credits", "Credits")
	Theme.label(c, table.concat({
		"A horror game for Roblox.",
		"",
		"Vehicles, engine parts, syringe, knife, keys, butcher table,",
		"meat hooks and trees: generated with ForgeGUI.",
		"Lanterns, cleavers, chainsaw, masks, generator, radio and more:",
		"modelled in Blender (tools/blender/build_props.py).",
		"Music: APM Music and DistroKid tracks from the Roblox creator store.",
		"",
		"Thank you for playing. Don't go into the woods.",
	}, "\n"), {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 1, -120),
		TextSize = 17,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	fade = Theme.frame(gui, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0,
		ZIndex = 40,
	})

	playButton.Activated:Connect(function()
		task.spawn(play)
	end)
	settingsButton.Activated:Connect(function()
		showPage("Settings")
	end)
	howButton.Activated:Connect(function()
		showPage("How")
	end)
	creditsButton.Activated:Connect(function()
		showPage("Credits")
	end)

	-- title flicker
	task.spawn(function()
		while true do
			task.wait(math.random(20, 60) / 10)
			if Menu.isOpen then
				title.TextTransparency = 0.6
				task.wait(0.06)
				title.TextTransparency = 0
				task.wait(0.08)
				title.TextTransparency = 0.4
				task.wait(0.05)
				title.TextTransparency = 0
			end
		end
	end)

	Menu.open()
	local function ready()
		local isReady = workspace:GetAttribute("WorldReady") == true
		loading.Text = if isReady then "" else "The woods are growing..."
		playButton.Text = if isReady then "PLAY" else "..."
		if isReady then
			startCameraDrift()
			Util.tween(fade, 2.5, { BackgroundTransparency = 1 })
		end
	end
	workspace:GetAttributeChangedSignal("WorldReady"):Connect(ready)
	ready()
end

return Menu

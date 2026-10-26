--!strict
-- Phone and tablet controls: big round buttons in an arc around Roblox's jump
-- button. Run is a latch (tap to run, tap again or stop moving to walk),
-- Crouch and Light toggle, Bag opens the inventory, Hint asks where to go,
-- and Throw shows up while you hold something you can throw.
-- They light up while their thing is on. Shown only while playing on touch:
-- hidden in menus, the lobby, cutscenes, while hiding or grabbed, and when a
-- keyboard or gamepad is being used instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Movement = require(script.Parent.Parent.Controllers.Movement)
local Throwing = require(script.Parent.Parent.Controllers.Throwing)
local MapView = require(script.Parent.MapView)
local Viewmodel = require(script.Parent.Parent.Controllers.Viewmodel)
local HUD = require(script.Parent.HUD)
local Inventory = require(script.Parent.Inventory)
local Notes = require(script.Parent.Notes)
local Theme = require(script.Parent.Theme)

local TouchControls = {}

local C = Theme.Colors
local player = Players.LocalPlayer

-- Offsets from the centre of the jump button at its phone size (70 px); on
-- tablets (120 px) the arc is spread out to match.
type Spot = { offset: Vector2, size: number }
local LAYOUT: { [string]: Spot } = {
	Run = { offset = Vector2.new(-90, 5), size = 64 },
	Crouch = { offset = Vector2.new(-53, -53), size = 56 },
	Light = { offset = Vector2.new(5, -80), size = 56 },
	Hint = { offset = Vector2.new(-70, -125), size = 48 },
	Bag = { offset = Vector2.new(5, -150), size = 48 },
	Throw = { offset = Vector2.new(-140, -80), size = 56 },
	Map = { offset = Vector2.new(-125, -150), size = 48 },
}
local STOP_RUN_AFTER = 0.75 -- seconds standing still before Run lets go

type Button = { button: TextButton, label: TextLabel, spot: Spot }

local gui: ScreenGui
local buttons: { [string]: Button } = {}
local touchActive = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local running = false
local stillFor = 0

local function makeButton(name: string, text: string, icon: string?): Button
	local spot = LAYOUT[name]
	local b = Util.create("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutoButtonColor = false,
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.35,
		Text = "",
		Parent = gui,
	}) :: TextButton
	Util.create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = b })
	Theme.stroke(b, C.Bone, 2).Transparency = 0.45
	local press = Util.create("UIScale", { Parent = b }) :: UIScale
	if icon then
		Util.create("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.16),
			Size = UDim2.fromScale(0.4, 0.4),
			BackgroundTransparency = 1,
			Image = icon,
			ImageColor3 = C.Bone,
			Parent = b,
		})
	end
	local label = Theme.label(b, text, {
		AnchorPoint = Vector2.new(0.5, if icon then 0 else 0.5),
		Position = UDim2.fromScale(0.5, if icon then 0.56 else 0.5),
		Size = UDim2.fromScale(0.9, if icon then 0.3 else 0.5),
		Font = Theme.Fonts.UIBold,
		TextSize = if icon then 11 else 13,
		TextWrapped = false,
	})
	b.MouseButton1Down:Connect(function()
		press.Scale = 0.88
		Util.tween(press, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	local entry: Button = { button = b, label = label, spot = spot }
	buttons[name] = entry
	return entry
end

-- Places the arc around the jump button (whose size and spot Roblox picks
-- from the screen size: 70 px on phones, 120 px on tablets). The gui covers
-- the whole screen; the viewport is read because a disabled gui's size is stale.
local function layout()
	local size = workspace.CurrentCamera.ViewportSize
	if size.X <= 0 then
		return
	end
	local small = math.min(size.X, size.Y) <= 500
	local jump = if small then Vector2.new(-60, -55) else Vector2.new(-110, -150)
	local spread = if small then 1 else 1.6
	local grow = if small then 1 else 1.25
	for _, entry in buttons do
		local at = jump + entry.spot.offset * spread
		entry.button.Position = UDim2.new(1, at.X, 1, at.Y)
		entry.button.Size = UDim2.fromOffset(entry.spot.size * grow, entry.spot.size * grow)
	end
end

local function setRunning(on: boolean)
	running = on
	stillFor = 0
	Movement.setSprint(on)
end

local function playing(): boolean
	if not touchActive or not HUD.visible or Inventory.isOpen or Notes.isOpen then
		return false
	end
	for _, attr in { "InCutscene", "Struggling", "Hidden" } do
		if player:GetAttribute(attr) == true then
			return false
		end
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function paint(entry: Button, on: boolean, color: Color3)
	entry.button.BackgroundColor3 = if on then color else C.Ink
	entry.button.BackgroundTransparency = if on then 0.1 else 0.35
end

function TouchControls.init()
	gui = Theme.screen("TouchControls", 8)
	gui.Enabled = false

	local run = makeButton("Run", "RUN")
	local crouch = makeButton("Crouch", "CROUCH")
	local light = makeButton("Light", "LIGHT")
	local hint = makeButton("Hint", "HINT", Assets.Images.MapPin)
	local bag = makeButton("Bag", "BAG", Assets.Images.Backpack)
	local throw = makeButton("Throw", "THROW")
	throw.button.MouseButton1Down:Connect(Throwing.throw)
	local map = makeButton("Map", "MAP", Assets.Images.MapPin)
	map.button.MouseButton1Down:Connect(function()
		MapView.toggle()
	end)

	run.button.MouseButton1Down:Connect(function()
		setRunning(not running)
	end)
	crouch.button.MouseButton1Down:Connect(function()
		if running then
			setRunning(false)
		end
		Movement.toggleCrouch()
	end)
	light.button.MouseButton1Down:Connect(function()
		Viewmodel.toggle()
	end)
	hint.button.MouseButton1Down:Connect(HUD.requestHint)
	bag.button.MouseButton1Down:Connect(function()
		Audio.play("Whoosh", nil, 0.2)
		Inventory.setOpen(true)
	end)

	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	layout()

	-- a keyboard or gamepad on a touch laptop / tablet takes over
	UserInputService.LastInputTypeChanged:Connect(function(kind: Enum.UserInputType)
		if kind == Enum.UserInputType.Touch then
			touchActive = true
		elseif kind == Enum.UserInputType.Keyboard or kind.Name:find("Gamepad") then
			touchActive = false
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local show = playing()
		gui.Enabled = show
		if not show then
			if running then
				setRunning(false)
			end
			return
		end
		-- Run lets go when you stop or run out of breath
		if running then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1
			stillFor = if moving then 0 else stillFor + dt
			if Movement.exhausted or stillFor > STOP_RUN_AFTER or Movement.isCrouching() then
				setRunning(false)
			end
		end
		paint(run, running, C.BloodBright)
		run.label.TextColor3 = if Movement.exhausted then C.BoneDim else C.Bone
		paint(crouch, Movement.isCrouching(), C.Blood)
		light.button.Visible = player:GetAttribute("HasFlashlight") == true
		paint(light, Viewmodel.on, C.Warn)
		throw.button.Visible = Throwing.held() ~= nil
		light.label.TextColor3 = if Viewmodel.on then C.Ink else C.Bone
		local wait = HUD.hintCooldown()
		local on = HUD.hintsOn()
		hint.label.Text = if not on then "OFF" elseif wait > 0 then string.format("%ds", math.ceil(wait)) else "HINT"
		hint.label.TextColor3 = if wait > 0 or not on then C.BoneDim else C.Bone
	end)
end

return TouchControls

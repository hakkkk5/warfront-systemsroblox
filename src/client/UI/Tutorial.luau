--!strict
-- First-time tutorial: once the player first has control (after the wake-up
-- cutscene, or on joining mid-game), a card walks through the controls one
-- step at a time. Each step ticks off when the player does it (or after a
-- while for the ones that may not come up). Runs once per session.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Theme = require(script.Parent.Theme)

local Tutorial = {}

local C = Theme.Colors
local player = Players.LocalPlayer

local PLAYING: { [string]: boolean } = {
	HouseEscape = true,
	Forest = true,
	Repair = true,
	Hunt = true,
	Power = true,
	Radio = true,
	Survive = true,
}

type Step = { text: string, touchText: string?, done: () -> boolean, timeout: number? }

local started = false

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function ready(): boolean
	local stage = workspace:GetAttribute("Stage")
	return typeof(stage) == "string"
		and PLAYING[stage] == true
		and player:GetAttribute("InCutscene") ~= true
		and rootPosition() ~= nil
end

local function run()
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	-- action trackers
	local moved = 0
	local last = rootPosition()
	local usedPrompt = false
	local pressedTab, pressedHint = false, false
	local connections = {
		ProximityPromptService.PromptTriggered:Connect(function()
			usedPrompt = true
		end),
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Tab then
				pressedTab = true
			elseif input.KeyCode == Enum.KeyCode.H then
				pressedHint = true
			end
		end),
	}
	local function attr(name: string): () -> boolean
		return function()
			return player:GetAttribute(name) == true
		end
	end

	local steps: { Step } = {
		{
			text = "<b>WASD</b> to move, <b>mouse</b> to look around.",
			touchText = "Use the <b>joystick</b> to move, drag to look around.",
			done = function()
				return moved > 10
			end,
		},
		{
			text = "Hold <b>Shift</b> to run. Running is loud and drains stamina.",
			touchText = "Tap <b>Run</b> to sprint. Running is loud and drains stamina.",
			done = attr("Sprinting"),
			timeout = 25,
		},
		{
			text = "Press <b>C</b> to crouch. Slower, but almost silent.",
			touchText = "Tap <b>Crouch</b>. Slower, but almost silent.",
			done = attr("Crouching"),
			timeout = 25,
		},
		{
			text = "Press <b>F</b> for the flashlight (once you find one). They can see the light.",
			touchText = "Use the <b>flashlight</b> button once you find one. They can see the light.",
			done = attr("Flashlight"),
			timeout = 14,
		},
		{
			text = "When a prompt appears, press or hold <b>E</b> to use, open or pick up.",
			touchText = "When a prompt appears, <b>tap</b> or hold it to use, open or pick up.",
			done = function()
				return usedPrompt
			end,
			timeout = 30,
		},
		{
			text = "<b>Tab</b> opens your bag. <b>H</b> marks where to go if you're stuck.",
			touchText = "Your <b>bag</b> and <b>hint</b> buttons are on the right.",
			done = function()
				return pressedTab or pressedHint
			end,
			timeout = 14,
		},
		{
			text = "If they spot you: break line of sight, then hide in a wardrobe, closet or locker.",
			done = function()
				return false
			end,
			timeout = 8,
		},
	}

	local gui = Theme.screen("Tutorial", 6)
	local card = Theme.frame(gui, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.55, 0),
		Size = UDim2.fromOffset(330, 96),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 1,
	})
	Theme.corner(card, 6)
	local stroke = Theme.stroke(card, C.Blood, 1)
	stroke.Transparency = 1
	Theme.padding(card, 12)
	local counter = Theme.label(card, "", {
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 13,
		Font = Theme.Fonts.UIBold,
		TextColor3 = C.BoneDim,
		TextTransparency = 1,
	})
	local body = Theme.label(card, "", {
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 1, -20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 17,
		TextTransparency = 1,
	})

	local function show(on: boolean)
		local t = if on then 0 else 1
		Util.tween(card, 0.35, { BackgroundTransparency = if on then 0.15 else 1 })
		Util.tween(stroke, 0.35, { Transparency = if on then 0.4 else 1 })
		Util.tween(counter, 0.35, { TextTransparency = t })
		Util.tween(body, 0.35, { TextTransparency = t })
	end

	for i, step in steps do
		counter.Text = string.format("TUTORIAL  %d/%d", i, #steps)
		body.Text = if touch and step.touchText then step.touchText else step.text
		body.TextColor3 = C.Bone
		show(true)
		local stepStart = os.clock()
		while true do
			task.wait(0.1)
			local pos = rootPosition()
			if pos and last then
				moved += (pos - last).Magnitude
			end
			last = pos
			if step.done() or (step.timeout and os.clock() - stepStart > step.timeout) then
				break
			end
			-- pause while a cutscene or a hiding spot takes over the screen
			while player:GetAttribute("InCutscene") == true do
				task.wait(0.5)
				stepStart = os.clock()
			end
		end
		if step.done() then
			body.TextColor3 = C.Sickly
			Audio.play("Pickup", nil, 0.3)
		end
		task.wait(0.9)
		show(false)
		task.wait(0.5)
	end

	for _, c in connections do
		c:Disconnect()
	end
	gui:Destroy()
end

-- Waits until the player first has control, then runs the steps once.
function Tutorial.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while not ready() do
			task.wait(0.5)
		end
		task.wait(2.5) -- let the stage title and first subtitle land
		run()
	end)
end

return Tutorial

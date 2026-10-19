--!strict
-- Custom look for every ProximityPrompt (server prompts use Style = Custom).

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Util = require(ReplicatedStorage.Shared.Util)
local Theme = require(script.Parent.Theme)

local Prompts = {}

local C = Theme.Colors

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return string.gsub(prompt.GamepadKeyCode.Name, "Button", "")
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	end
	return prompt.KeyboardKeyCode.Name
end

local function build(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType, gui: ScreenGui): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "Prompt"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(260, 64)
	bb.SizeOffset = Vector2.new(0, 0.6)
	bb.LightInfluence = 0
	bb.Active = true
	bb.Adornee = prompt.Parent :: any
	bb.Parent = gui

	local holder = Theme.frame(bb, {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local key = Theme.frame(holder, {
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromOffset(0, 10),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
	})
	Theme.corner(key, 22)
	local ring = Theme.stroke(key, C.Bone, 2)
	local keyLabel = Theme.label(key, keyText(prompt, inputType), {
		Size = UDim2.fromScale(1, 1),
		TextSize = 18,
		Font = Theme.Fonts.UIBold,
	})
	local progress = Theme.frame(key, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = C.Blood,
		BackgroundTransparency = 0.25,
		ZIndex = 0,
	})
	Theme.corner(progress, 22)
	local action = Theme.label(holder, prompt.ActionText, {
		Position = UDim2.fromOffset(54, 8),
		Size = UDim2.new(1, -54, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 22,
		TextStrokeTransparency = 0.5,
	})
	local object = Theme.label(holder, prompt.ObjectText, {
		Position = UDim2.fromOffset(54, 32),
		Size = UDim2.new(1, -54, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
		TextColor3 = C.BoneDim,
		Font = Theme.Fonts.UI,
		TextStrokeTransparency = 0.6,
	})

	local holdTween: Tween? = nil
	local conns = {}
	table.insert(conns, prompt.PromptButtonHoldBegan:Connect(function()
		if prompt.HoldDuration > 0 then
			progress.Size = UDim2.fromScale(1, 0)
			holdTween = Util.tween(progress, prompt.HoldDuration, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
		end
	end))
	table.insert(conns, prompt.PromptButtonHoldEnded:Connect(function()
		if holdTween then
			holdTween:Cancel()
		end
		Util.tween(progress, 0.15, { Size = UDim2.fromScale(1, 0) })
	end))
	table.insert(conns, prompt.Triggered:Connect(function()
		ring.Color = C.BloodBright
		Util.tween(key, 0.1, { Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(-3, 7) }).Completed:Connect(function()
			Util.tween(key, 0.15, { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(0, 10) })
			ring.Color = C.Bone
		end)
	end))
	table.insert(conns, prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		action.Text = prompt.ActionText
	end))
	table.insert(conns, prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
		object.Text = prompt.ObjectText
	end))

	-- touch: tap the key to trigger
	if inputType == Enum.ProximityPromptInputType.Touch or UserInputService.TouchEnabled then
		local button = Instance.new("TextButton")
		button.BackgroundTransparency = 1
		button.Size = UDim2.fromScale(1, 1)
		button.Text = ""
		button.Parent = key
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldBegin()
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldEnd()
			end
		end)
	end

	holder.Position = UDim2.fromOffset(0, 8)
	for _, d in holder:GetDescendants() do
		if d:IsA("TextLabel") then
			d.TextTransparency = 1
			Util.tween(d, 0.2, { TextTransparency = 0 })
		end
	end
	Util.tween(holder, 0.2, { Position = UDim2.fromOffset(0, 0) })
	local _ = keyLabel

	bb.Destroying:Connect(function()
		for _, c in conns do
			c:Disconnect()
		end
	end)
	return bb
end

function Prompts.init()
	local gui = Theme.screen("Prompts", 6)
	local shown: { [ProximityPrompt]: BillboardGui } = {}
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Default then
			return
		end
		local existing = shown[prompt]
		if existing then
			existing:Destroy()
		end
		shown[prompt] = build(prompt, inputType, gui)
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		local bb = shown[prompt]
		if bb then
			shown[prompt] = nil
			bb:Destroy()
		end
	end)
end

return Prompts

--!strict
-- The owner's admin panel: F2 (or the ADMIN tab on the right) opens it.
-- Skip the cutscene or the part of the story you're on, jump to the
-- objective, freeze the family, god mode, heal, give yourself any item.
-- Only shows for players the server marked "Admin" (Systems/Admin), which
-- checks every request again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Theme = require(script.Parent.Theme)

local AdminPanel = {}

local C = Theme.Colors
local player = Players.LocalPlayer
local action = Net.event("AdminAction")

local gui: ScreenGui
local panel: Frame
local stageLabel: TextLabel
local skipButton: TextButton
local freezeButton: TextButton
local godButton: TextButton
local open = false

local function onOff(value: any): string
	return if value then "<font color=\"#96DC78\">ON</font>" else "OFF"
end

local function refresh()
	local inCutscene = player:GetAttribute("InCutscene") == true
	stageLabel.Text = "Part: " .. tostring(workspace:GetAttribute("Stage") or "-") .. (if inCutscene then "  (cutscene)" else "")
	skipButton.Text = if inCutscene then "Skip cutscene" else "Skip this part"
	freezeButton.Text = "Freeze family: " .. onOff(workspace:GetAttribute("AdminFrozen"))
	godButton.Text = "God mode: " .. onOff(player:GetAttribute("AdminGod"))
end

local function setOpen(value: boolean)
	open = value
	panel.Visible = value
	if value then
		refresh()
		panel.Position = UDim2.new(1, 20, 0.5, 0)
		Util.tween(panel, 0.2, { Position = UDim2.new(1, -16, 0.5, 0) })
	end
end

local function button(text: string, order: number, onClick: () -> ()): TextButton
	local b = Theme.button(panel, text, {
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = order,
		Font = Theme.Fonts.UI,
		TextSize = 17,
		RichText = true,
	})
	b.Activated:Connect(onClick)
	return b
end

local function build()
	gui = Theme.screen("AdminPanel", 50)

	local tab = Theme.button(gui, "ADMIN  F2", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, -190),
		Size = UDim2.fromOffset(92, 26),
		Font = Theme.Fonts.UIBold,
		TextSize = 12,
	})
	tab.Activated:Connect(function()
		setOpen(not open)
	end)

	panel = Theme.frame(gui, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.06,
		Visible = false,
	})
	Theme.corner(panel, 8)
	Theme.stroke(panel, C.Blood, 1.5)
	Theme.padding(panel, 14)
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel,
	})

	local header = Theme.frame(panel, { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 1 })
	Theme.label(header, "ADMIN", {
		Size = UDim2.new(1, -36, 1, 0),
		Font = Theme.Fonts.Title,
		TextSize = 28,
		TextColor3 = C.BloodBright,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	-- a Modal button frees the mouse in first person while the panel is open
	local close = Theme.button(header, "X", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(28, 28),
		Font = Theme.Fonts.UIBold,
		TextSize = 14,
	})
	close.Modal = true
	close.Activated:Connect(function()
		setOpen(false)
	end)

	stageLabel = Theme.label(panel, "", {
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 2,
		Font = Theme.Fonts.UI,
		TextSize = 14,
		TextColor3 = C.BoneDim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	skipButton = button("Skip this part", 3, function()
		action:FireServer("skip")
	end)
	skipButton.BackgroundColor3 = C.Blood
	button("Go to objective", 4, function()
		action:FireServer("objective")
	end)
	freezeButton = button("Freeze family", 5, function()
		action:FireServer("freeze")
	end)
	godButton = button("God mode", 6, function()
		action:FireServer("god")
	end)
	button("Heal", 7, function()
		action:FireServer("heal")
	end)

	-- give yourself anything: one per click
	Theme.label(panel, "GIVE ITEM", {
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 8,
		Font = Theme.Fonts.UIBold,
		TextSize = 12,
		TextColor3 = C.BoneDim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local list = Util.create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 190),
		LayoutOrder = 9,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.Blood,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}) :: ScrollingFrame
	Util.create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -4, 0, 28),
		CellPadding = UDim2.fromOffset(4, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	for i, id in Items.Order do
		local def = Items.get(id)
		if def then
			local b = Theme.button(list, def.name, {
				LayoutOrder = i,
				Font = Theme.Fonts.UI,
				TextSize = 12,
				TextWrapped = true,
			})
			b.Activated:Connect(function()
				action:FireServer("give", id)
			end)
		end
	end
end

function AdminPanel.init()
	local function start()
		if gui or not player:GetAttribute("Admin") then
			return
		end
		build()
		UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.F2 and not processed then
				setOpen(not open)
			end
		end)
		for _, signal in {
			workspace:GetAttributeChangedSignal("Stage"),
			workspace:GetAttributeChangedSignal("AdminFrozen"),
			player:GetAttributeChangedSignal("AdminGod"),
			player:GetAttributeChangedSignal("InCutscene"),
		} do
			signal:Connect(function()
				if open then
					refresh()
				end
			end)
		end
	end
	player:GetAttributeChangedSignal("Admin"):Connect(start)
	start()
end

return AdminPanel

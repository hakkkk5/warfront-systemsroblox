--!strict
-- The workbench screen: every recipe (shared Crafting) as a card with what
-- it needs, what you have, and a Craft button. Opened by the server when you
-- use a bench; closes when you walk away. The bag keeps it up to date.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CraftingData = require(ReplicatedStorage.Shared.Crafting)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Inventory = require(script.Parent.Inventory)
local Theme = require(script.Parent.Theme)

local Crafting = {}

local C = Theme.Colors
local player = Players.LocalPlayer

local gui: ScreenGui
local panel: Frame
local openedAt: Vector3? = nil
local counts: { [string]: number } = {}

type Card = { recipe: CraftingData.Recipe, needs: TextLabel, button: TextButton }
local cards: { Card } = {}

Crafting.isOpen = false

local function rootPosition(): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function itemName(id: string): string
	local def = Items.get(id)
	return if def then def.name else id
end

local function refresh()
	for _, card in cards do
		local lines: { string } = {}
		local ready = true
		for _, need in card.recipe.needs do
			local have = counts[need.item] or 0
			local ok = have >= need.count
			ready = ready and ok
			table.insert(lines, string.format("<font color=\"%s\">%s  %d/%d</font>", if ok then "#96dc78" else "#968c7c", itemName(need.item), have, need.count))
		end
		card.needs.Text = table.concat(lines, "\n")
		card.button.Active = ready
		card.button.AutoButtonColor = false
		card.button.BackgroundColor3 = if ready then C.Blood else C.PanelLight
		card.button.TextColor3 = if ready then Color3.new(1, 1, 1) else C.BoneDim
		card.button.Text = if ready then "CRAFT" else "MISSING PARTS"
	end
end

function Crafting.setOpen(open: boolean)
	Crafting.isOpen = open
	gui.Enabled = open
	if open then
		openedAt = rootPosition()
		refresh()
		panel.Position = UDim2.fromScale(0.5, 0.53)
		Util.tween(panel, 0.25, { Position = UDim2.fromScale(0.5, 0.5) })
		Audio.play("Repair", nil, 0.3, 1.4)
	end
end

function Crafting.init()
	gui = Theme.screen("Crafting", 13)
	gui.Enabled = false
	-- a Modal button frees the mouse in first person
	local modal = Instance.new("TextButton")
	modal.Modal = true
	modal.BackgroundColor3 = Color3.new(0, 0, 0)
	modal.BackgroundTransparency = 0.45
	modal.Size = UDim2.fromScale(1, 1)
	modal.Text = ""
	modal.AutoButtonColor = false
	modal.Parent = gui
	modal.Activated:Connect(function()
		Crafting.setOpen(false)
	end)

	panel = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(780, 400),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.04,
		ZIndex = 2,
	})
	Theme.corner(panel, 8)
	Theme.stroke(panel, C.Blood, 1.5)
	Theme.padding(panel, 22)
	Theme.autoScale(panel, Vector2.new(820, 440))
	Theme.label(panel, "Workbench", {
		Size = UDim2.new(1, -56, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.Title,
		TextSize = 40,
		TextColor3 = C.BloodBright,
	})
	Theme.label(panel, "Junk turns up everywhere: bottles, rags, moonshine, tape, old clocks.", {
		Position = UDim2.fromOffset(2, 42),
		Size = UDim2.new(1, -56, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
		TextColor3 = C.BoneDim,
	})
	local close = Theme.button(panel, "X", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(44, 44),
		TextSize = 20,
	})
	close.Activated:Connect(function()
		Crafting.setOpen(false)
	end)

	local row = Theme.frame(panel, {
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 1, -80),
		BackgroundTransparency = 1,
	})
	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local n = #CraftingData.Recipes
	for i, recipe in CraftingData.Recipes do
		local card = Theme.frame(row, {
			Size = UDim2.new(1 / n, -14 * (n - 1) / n, 1, 0),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.25,
			LayoutOrder = i,
		})
		Theme.corner(card, 6)
		Theme.stroke(card, C.Blood, 1).Transparency = 0.6
		Theme.padding(card, 12)
		local preview = Theme.viewport(card, Inventory.itemModel(recipe.result), { Size = UDim2.new(1, 0, 0, 84) })
		preview:SetAttribute("Spin", true)
		Theme.label(card, itemName(recipe.result), {
			Position = UDim2.fromOffset(0, 88),
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Fonts.UIBold,
			TextSize = 17,
		})
		Theme.label(card, recipe.blurb, {
			Position = UDim2.fromOffset(0, 112),
			Size = UDim2.new(1, 0, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextSize = 13,
			TextColor3 = C.BoneDim,
		})
		local needs = Theme.label(card, "", {
			Position = UDim2.fromOffset(0, 156),
			Size = UDim2.new(1, 0, 1, -156 - 50),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Font = Theme.Fonts.UI,
			TextSize = 14,
		})
		local button = Util.create("TextButton", {
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 44),
			Font = Theme.Fonts.UIBold,
			TextSize = 16,
			BorderSizePixel = 0,
			Parent = card,
		}) :: TextButton
		Theme.corner(button, 4)
		button.Activated:Connect(function()
			if button.Active then
				Net.event("Craft"):FireServer(recipe.id)
			end
		end)
		table.insert(cards, { recipe = recipe, needs = needs, button = button })
	end

	Net.event("Crafting").OnClientEvent:Connect(function()
		Crafting.setOpen(true)
	end)
	Net.event("Inventory").OnClientEvent:Connect(function(snapshot: any)
		table.clear(counts)
		if typeof(snapshot) == "table" and typeof(snapshot.items) == "table" then
			for _, entry in snapshot.items do
				if typeof(entry) == "table" and typeof(entry.id) == "string" then
					counts[entry.id] = tonumber(entry.count) or 1
				end
			end
		end
		if Crafting.isOpen then
			refresh()
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not Crafting.isOpen then
			return
		end
		-- walked off, or something else took over
		local pos = rootPosition()
		if not pos or (openedAt and (pos - openedAt).Magnitude > CraftingData.BENCH_RANGE) or player:GetAttribute("InCutscene") then
			Crafting.setOpen(false)
			return
		end
		local a = os.clock() * 0.8
		for _, d in panel:GetDescendants() do
			if d:IsA("ViewportFrame") and d.CurrentCamera then
				local center = d:GetAttribute("Center") :: Vector3
				local distance = d:GetAttribute("Distance") :: number
				d.CurrentCamera.CFrame = CFrame.lookAt(center + Vector3.new(math.cos(a) * 0.9, 0.5, math.sin(a) * 0.9).Unit * distance, center)
			end
		end
	end)
end

return Crafting

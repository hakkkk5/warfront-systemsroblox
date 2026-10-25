--!strict
-- Inventory and journal screen (TAB). Items are shown as rotating 3D
-- previews; usable items can be used, held items equipped.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Items = require(ReplicatedStorage.Shared.Items)
local Lore = require(ReplicatedStorage.Shared.Lore)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local MeshLibrary = require(script.Parent.Parent.Controllers.MeshLibrary)
local Theme = require(script.Parent.Theme)

local Inventory = {}

local C = Theme.Colors
local SLOTS = 12

type Entry = { id: string, count: number }

local gui: ScreenGui
local panel: Frame
local grid: Frame
local detailName: TextLabel
local detailDesc: TextLabel
local detailView: Frame
local useButton: TextButton
local equipButton: TextButton
local journalList: ScrollingFrame
local itemsTab: TextButton
local journalTab: TextButton
local itemsPage: Frame
local journalPage: Frame
local modal: TextButton

local entries: { Entry } = {}
local equipped: string? = nil
local selected: string? = nil
local readNotes: { string } = {}

Inventory.isOpen = false
Inventory.onNoteSelected = nil :: ((string) -> ())?

-- A fresh preview model of an item (for ViewportFrames); nil until the
-- server has published ItemModels.
function Inventory.itemModel(id: string): Model?
	local def = Items.get(id)
	local folder = ReplicatedStorage:FindFirstChild("ItemModels")
	if not def or not folder then
		return nil
	end
	local m = folder:FindFirstChild(def.model)
	if not m or not m:IsA("Model") then
		return nil
	end
	local clone = m:Clone()
	if clone:GetAttribute("Mesh") then
		MeshLibrary.upgrade(clone)
		-- ViewportFrames ignore LocalTransparencyModifier, so drop the stand-in
		if clone:FindFirstChild("BlenderVisual") then
			for _, d in clone:GetChildren() do
				if d.Name ~= "BlenderVisual" then
					d:Destroy()
				end
			end
		end
	end
	return clone
end

local function setDetail(id: string?)
	selected = id
	detailView:ClearAllChildren()
	local def = if id then Items.get(id) else nil
	if not def or not id then
		detailName.Text = ""
		detailDesc.Text = "Select an item."
		useButton.Visible = false
		equipButton.Visible = false
		return
	end
	detailName.Text = def.name
	detailDesc.Text = def.description
	useButton.Visible = def.usable == true
	equipButton.Visible = def.equippable == true
	equipButton.Text = if equipped == id then "Put away" else "Hold"
	local vp = Theme.viewport(detailView, Inventory.itemModel(id), { Size = UDim2.fromScale(1, 1) })
	vp:SetAttribute("Spin", true)
end

local function render()
	for _, c in grid:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i = 1, SLOTS do
		local entry = entries[i]
		local slot = Theme.frame(grid, {
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.25,
			LayoutOrder = i,
		})
		Theme.corner(slot, 6)
		local stroke = Theme.stroke(slot, if entry and entry.id == equipped then C.Sickly else C.Ink, 1.5)
		if entry then
			local def = Items.get(entry.id)
			if def then
				local vp = Theme.viewport(slot, Inventory.itemModel(entry.id), {
					Size = UDim2.new(1, -8, 1, -8),
					Position = UDim2.fromOffset(4, 4),
				})
				vp:SetAttribute("Spin", true)
				if not vp.CurrentCamera and def.icon then
					Util.create("ImageLabel", {
						BackgroundTransparency = 1,
						Image = def.icon,
						ImageColor3 = def.tint or C.Bone,
						Size = UDim2.fromScale(0.7, 0.7),
						Position = UDim2.fromScale(0.15, 0.15),
						Parent = slot,
					})
				end
				if entry.count > 1 then
					Theme.label(slot, "x" .. entry.count, {
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.new(1, -6, 1, -4),
						Size = UDim2.fromOffset(40, 18),
						TextXAlignment = Enum.TextXAlignment.Right,
						TextSize = 15,
						Font = Theme.Fonts.UIBold,
					})
				end
				if def.questItem then
					Util.create("ImageLabel", {
						BackgroundTransparency = 1,
						Image = Assets.Images.Wrench,
						ImageColor3 = C.Rust,
						Size = UDim2.fromOffset(14, 14),
						Position = UDim2.fromOffset(6, 6),
						Parent = slot,
					})
				end
				local button = Instance.new("TextButton")
				button.BackgroundTransparency = 1
				button.Size = UDim2.fromScale(1, 1)
				button.Text = ""
				button.Parent = slot
				button.MouseEnter:Connect(function()
					stroke.Color = C.BloodBright
				end)
				button.MouseLeave:Connect(function()
					stroke.Color = if entry.id == equipped then C.Sickly else C.Ink
				end)
				button.Activated:Connect(function()
					Audio.play("Pickup", nil, 0.2)
					setDetail(entry.id)
				end)
			end
		end
	end
	if selected then
		local still = false
		for _, e in entries do
			if e.id == selected then
				still = true
			end
		end
		setDetail(if still then selected else nil)
	end
end

local function renderJournal()
	for _, c in journalList:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	if #readNotes == 0 then
		return
	end
	for i, id in readNotes do
		local note = Lore[id]
		if note then
			local b = Theme.button(journalList, "  " .. note.title, {
				Size = UDim2.new(1, -8, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 18,
				LayoutOrder = i,
			})
			b.Activated:Connect(function()
				if Inventory.onNoteSelected then
					Inventory.onNoteSelected(id)
				end
			end)
		end
	end
end

function Inventory.addNote(id: string)
	if not table.find(readNotes, id) then
		table.insert(readNotes, id)
		renderJournal()
	end
end

local function showPage(name: string)
	itemsPage.Visible = name == "items"
	journalPage.Visible = name == "journal"
	itemsTab.TextColor3 = if name == "items" then C.BloodBright else C.BoneDim
	journalTab.TextColor3 = if name == "journal" then C.BloodBright else C.BoneDim
end

function Inventory.setOpen(open: boolean)
	if open == Inventory.isOpen then
		return
	end
	Inventory.isOpen = open
	gui.Enabled = true
	modal.Visible = open
	if open then
		render()
		panel.Visible = true
		panel.Position = UDim2.fromScale(0.5, 0.53)
		Util.tween(panel, 0.25, { Position = UDim2.fromScale(0.5, 0.5) })
		Audio.play("Whoosh", nil, 0.3)
	else
		panel.Visible = false
	end
end

function Inventory.init()
	gui = Theme.screen("Inventory", 12)
	-- a Modal button frees the mouse while the screen is open in first person
	modal = Instance.new("TextButton")
	modal.Modal = true
	modal.BackgroundColor3 = Color3.new(0, 0, 0)
	modal.BackgroundTransparency = 0.45
	modal.Size = UDim2.fromScale(1, 1)
	modal.Text = ""
	modal.AutoButtonColor = false
	modal.Visible = false
	modal.Parent = gui

	panel = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(820, 520),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 2,
	})
	Theme.corner(panel, 8)
	Theme.stroke(panel, C.Blood, 1.5)
	Util.create("UISizeConstraint", { MaxSize = Vector2.new(900, 600), Parent = panel })
	Theme.autoScale(panel, Vector2.new(860, 560))

	Util.create("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Assets.Images.Backpack,
		ImageColor3 = C.BloodBright,
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.fromOffset(20, 16),
		Parent = panel,
	})
	itemsTab = Theme.button(panel, "BELONGINGS", {
		Position = UDim2.fromOffset(64, 16),
		Size = UDim2.fromOffset(170, 34),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.UIBold,
		TextSize = 16,
	})
	journalTab = Theme.button(panel, "JOURNAL", {
		Position = UDim2.fromOffset(240, 16),
		Size = UDim2.fromOffset(140, 34),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.UIBold,
		TextSize = 16,
	})
	local close = Theme.button(panel, "X", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(34, 34),
	})
	close.Activated:Connect(function()
		Inventory.setOpen(false)
	end)

	itemsPage = Theme.frame(panel, {
		Position = UDim2.fromOffset(20, 66),
		Size = UDim2.new(1, -40, 1, -86),
		BackgroundTransparency = 1,
	})
	grid = Theme.frame(itemsPage, {
		Size = UDim2.new(0.55, 0, 1, 0),
		BackgroundTransparency = 1,
	})
	Util.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(98, 98),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local detail = Theme.frame(itemsPage, {
		Position = UDim2.new(0.58, 0, 0, 0),
		Size = UDim2.new(0.42, 0, 1, 0),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.4,
	})
	Theme.corner(detail, 6)
	Theme.padding(detail, 14)
	detailView = Theme.frame(detail, {
		Size = UDim2.new(1, 0, 0, 190),
		BackgroundTransparency = 1,
	})
	detailName = Theme.label(detail, "", {
		Position = UDim2.fromOffset(0, 196),
		Size = UDim2.new(1, 0, 0, 32),
		TextSize = 26,
		TextColor3 = C.BloodBright,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	detailDesc = Theme.label(detail, "Select an item.", {
		Position = UDim2.fromOffset(0, 232),
		Size = UDim2.new(1, 0, 0, 90),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	useButton = Theme.button(detail, "Use", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0.48, 0, 0, 40),
		Visible = false,
	})
	equipButton = Theme.button(detail, "Hold", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0.48, 0, 0, 40),
		Visible = false,
	})
	useButton.Activated:Connect(function()
		if selected then
			Net.event("InventoryAction"):FireServer("use", selected)
		end
	end)
	equipButton.Activated:Connect(function()
		if selected then
			Net.event("InventoryAction"):FireServer("equip", selected)
		end
	end)

	journalPage = Theme.frame(panel, {
		Position = UDim2.fromOffset(20, 66),
		Size = UDim2.new(1, -40, 1, -86),
		BackgroundTransparency = 1,
		Visible = false,
	})
	Theme.label(journalPage, "Notes you have read. Click one to read it again.", {
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.BoneDim,
		TextSize = 16,
	})
	journalList = Util.create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = journalPage,
	})
	Util.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = journalList })

	itemsTab.Activated:Connect(function()
		showPage("items")
	end)
	journalTab.Activated:Connect(function()
		showPage("journal")
	end)
	showPage("items")

	Net.event("Inventory").OnClientEvent:Connect(function(data)
		entries = data.items or {}
		equipped = data.equipped
		if Inventory.isOpen then
			render()
		end
	end)

	ContextActionService:BindAction("Inventory", function(_, state)
		if state == Enum.UserInputState.Begin then
			local player = game:GetService("Players").LocalPlayer
			if not player:GetAttribute("InCutscene") and player.Character then
				Inventory.setOpen(not Inventory.isOpen)
			end
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Tab, Enum.KeyCode.I, Enum.KeyCode.ButtonSelect) -- phones: UI TouchControls

	-- spin previews
	RunService.RenderStepped:Connect(function()
		if not Inventory.isOpen then
			return
		end
		for _, d in gui:GetDescendants() do
			if d:IsA("ViewportFrame") and d:GetAttribute("Spin") and d.CurrentCamera then
				local center = d:GetAttribute("Center") :: Vector3
				local distance = d:GetAttribute("Distance") :: number
				local a = os.clock() * 0.8
				d.CurrentCamera.CFrame = CFrame.lookAt(center + Vector3.new(math.cos(a) * 0.9, 0.5, math.sin(a) * 0.9).Unit * distance, center)
			end
		end
	end)
end

return Inventory

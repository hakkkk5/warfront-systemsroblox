--!strict
-- Readable notes: an aged-paper overlay. Read notes are added to the journal.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lore = require(ReplicatedStorage.Shared.Lore)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Theme = require(script.Parent.Theme)
local Inventory = require(script.Parent.Inventory)

local Notes = {}

local gui: ScreenGui
local paper: Frame
local title: TextLabel
local body: TextLabel
local modal: TextButton

Notes.isOpen = false

function Notes.close()
	if not Notes.isOpen then
		return
	end
	Notes.isOpen = false
	Util.tween(paper, 0.2, { Position = UDim2.fromScale(0.5, 0.56) })
	task.delay(0.2, function()
		if not Notes.isOpen then
			gui.Enabled = false
		end
	end)
	ContextActionService:UnbindAction("CloseNote")
end

function Notes.open(id: string)
	local note = Lore[id]
	if not note then
		return
	end
	Inventory.setOpen(false)
	Inventory.addNote(id)
	title.Text = note.title
	body.Text = note.body
	gui.Enabled = true
	Notes.isOpen = true
	paper.Position = UDim2.fromScale(0.5, 0.56)
	paper.Rotation = math.random(-2, 2)
	Util.tween(paper, 0.3, { Position = UDim2.fromScale(0.5, 0.5) })
	ContextActionService:BindActionAtPriority("CloseNote", function(_, state)
		if state == Enum.UserInputState.Begin then
			Notes.close()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.E, Enum.KeyCode.Escape, Enum.KeyCode.Space, Enum.KeyCode.ButtonB)
end

function Notes.init()
	gui = Theme.screen("Notes", 15)
	gui.Enabled = false
	modal = Instance.new("TextButton")
	modal.Modal = true
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.new(0, 0, 0)
	modal.BackgroundTransparency = 0.35
	modal.Text = ""
	modal.AutoButtonColor = false
	modal.Parent = gui
	modal.Activated:Connect(Notes.close)

	paper = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 620),
		BackgroundColor3 = Color3.fromRGB(206, 192, 158),
	})
	Util.create("UISizeConstraint", { MaxSize = Vector2.new(560, 700), Parent = paper })
	Util.create("UIAspectRatioConstraint", { AspectRatio = 520 / 620, Parent = paper })
	Theme.autoScale(paper, Vector2.new(560, 680))
	Util.create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 225, 196)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(210, 196, 160)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 120, 84)),
		}),
		Rotation = 60,
		Parent = paper,
	})
	Theme.stroke(paper, Color3.fromRGB(90, 70, 50), 2)
	Theme.padding(paper, 34)
	-- a blood smear on the corner
	local smear = Theme.frame(paper, {
		Position = UDim2.new(1, -60, 1, -50),
		Size = UDim2.fromOffset(90, 70),
		BackgroundColor3 = Color3.fromRGB(110, 14, 10),
		BackgroundTransparency = 0.35,
		Rotation = 24,
	})
	Theme.corner(smear, 30)
	title = Theme.label(paper, "", {
		Size = UDim2.new(1, 0, 0, 44),
		Font = Theme.Fonts.Type,
		TextSize = 30,
		TextColor3 = Color3.fromRGB(60, 30, 20),
	})
	body = Theme.label(paper, "", {
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -90),
		Font = Theme.Fonts.Hand,
		TextSize = 23,
		TextColor3 = Color3.fromRGB(40, 30, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	Theme.label(paper, "[E] close", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.fromOffset(200, 20),
		TextSize = 14,
		TextColor3 = Color3.fromRGB(90, 70, 50),
		Font = Theme.Fonts.UI,
	})

	Net.event("Note").OnClientEvent:Connect(Notes.open)
	Inventory.onNoteSelected = Notes.open
end

return Notes

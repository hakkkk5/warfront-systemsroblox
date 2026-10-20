--!strict
-- Credits after the rescue, with a play-again button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Theme = require(script.Parent.Theme)
local HUD = require(script.Parent.HUD)

local Ending = {}

local C = Theme.Colors

local LINES = {
	"<font size=\"60\" face=\"Creepster\" color=\"#d6221a\">" .. Config.GameName .. "</font>",
	"",
	"You escaped. Most never do.",
	"",
	"<b>DESIGN, CODE & WORLD</b>",
	"Built with Claude Code",
	"",
	"<b>3D MODELS</b>",
	"ForgeGUI - vehicles, engine parts, syringe, knife, keys, butcher table, meat hooks, trees",
	"Blender - lanterns, cleavers, chainsaw, sack masks, generator, radio, barrels, crates,",
	"chairs, cage, gravestones, dead trees, rocks, tent, campfire, helicopter and items",
	"",
	"<b>MUSIC</b>",
	"APM Music & DistroKid via the Roblox creator store",
	"",
	"<b>THE FAMILY</b>",
	"Jason - Michel - The Hunter - The Scavenger - Papa",
	"",
	"",
	"<i>...they are still hungry.</i>",
}

function Ending.init()
	local gui = Theme.screen("Ending", 28)
	gui.Enabled = false
	local modal = Instance.new("TextButton")
	modal.Modal = true
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.new(0, 0, 0)
	modal.BackgroundTransparency = 0
	modal.Text = ""
	modal.AutoButtonColor = false
	modal.Parent = gui

	local scroller = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(0.8, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroller,
	})
	for i, line in LINES do
		Theme.label(scroller, line, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 22,
			LayoutOrder = i,
		})
	end
	Util.create("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Assets.Images.Trophy,
		ImageColor3 = C.Bone,
		Size = UDim2.fromOffset(60, 60),
		LayoutOrder = 0,
		Parent = scroller,
	})

	local again = Theme.button(gui, "Play again", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, -110, 1, -40),
		Size = UDim2.fromOffset(200, 48),
		Visible = false,
	})
	local stay = Theme.button(gui, "Stay a while", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 110, 1, -40),
		Size = UDim2.fromOffset(200, 48),
		Visible = false,
	})
	again.Activated:Connect(function()
		again.Text = "..."
		Net.event("PlayAgain"):FireServer()
	end)
	stay.Activated:Connect(function()
		gui.Enabled = false
		HUD.setVisible(true)
	end)

	Net.event("Ending").OnClientEvent:Connect(function()
		HUD.setVisible(false)
		gui.Enabled = true
		Audio.music("Ending", 0.6)
		scroller.Position = UDim2.fromScale(0.5, 1)
		task.wait(0.1)
		local height = scroller.AbsoluteSize.Y
		Util.tween(scroller, 38, { Position = UDim2.new(0.5, 0, 0, -height * 0.55) }, Enum.EasingStyle.Linear)
		task.delay(6, function()
			again.Visible = true
			stay.Visible = true
		end)
	end)
end

return Ending

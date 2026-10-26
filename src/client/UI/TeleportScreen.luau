--!strict
-- The ride out. When a truck leaves (or you drive out alone, or the search
-- finds you company) the lobby hands Roblox this screen to show while the
-- teleport loads: the dark, the road, who's riding with you and how bad
-- tonight will be. In the game server the same screen is picked up again
-- on arrival and stays until the woods are built (WorldReady), then fades.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Lang = require(ReplicatedStorage.Shared.Lang)
local Util = require(ReplicatedStorage.Shared.Util)
local Theme = require(script.Parent.Theme)

local TeleportScreen = {}

local C = Theme.Colors

local LINES = {
	"The truck rattles off the asphalt and onto Hollow Road.",
	"No radio out here. Just the engine and the trees.",
	"The headlights only reach so far.",
	"Somebody in the back says they smell smoke. Supper smoke.",
	"The last road sign has been painted over.",
}

local DIFFICULTY_COLORS: { [string]: Color3 } = {
	Normal = C.Bone,
	Hard = C.Warn,
	Nightmare = C.BloodBright,
}

local prepared = false

local function build(difficulty: string, riders: { string }): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RideOut"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.ResetOnSpawn = false
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(0, 0, 0)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	-- a strip of road lit by headlights, fading into the dark
	local road = Instance.new("Frame")
	road.AnchorPoint = Vector2.new(0.5, 1)
	road.Position = UDim2.fromScale(0.5, 1)
	road.Size = UDim2.fromScale(0.5, 0.42)
	road.BackgroundColor3 = Color3.fromRGB(46, 40, 34)
	road.BorderSizePixel = 0
	road.Parent = bg
	local fade = Instance.new("UIGradient")
	fade.Rotation = -90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = road
	local function text(value: string, y: number, size: number, color: Color3, font: Enum.Font)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, y)
		label.Size = UDim2.new(0.9, 0, 0, size + 10)
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextSize = size
		label.TextColor3 = color
		label.TextWrapped = true
		label.Text = value
		label.Parent = bg
	end
	text(Lang.t("HOLLOW ROAD"), 0.3, 64, C.BloodBright, Theme.Fonts.Title)
	text(Lang.t(LINES[math.random(1, #LINES)]), 0.42, 20, C.Bone, Theme.Fonts.UI)
	text(Lang.f("Tonight: %s", Lang.t(difficulty)), 0.5, 22, DIFFICULTY_COLORS[difficulty] or C.Bone, Theme.Fonts.UIBold)
	if #riders > 0 then
		text(Lang.t("In the back of the truck") .. "\n" .. table.concat(riders, "   "), 0.6, 17, C.BoneDim, Theme.Fonts.UI)
	end
	return gui
end

-- Lobby: we're leaving. Once per departure.
function TeleportScreen.prepare(difficulty: string, riders: { string })
	if prepared then
		return
	end
	prepared = true
	pcall(function()
		TeleportService:SetTeleportGui(build(difficulty, riders))
	end)
end

-- Lobby: the departure fell through (the truck wouldn't start).
function TeleportScreen.cancel()
	prepared = false
end

-- Game server: keep the arriving screen up until the world is ready.
function TeleportScreen.arrive()
	local ok, gui = pcall(function()
		return TeleportService:GetArrivingTeleportGui()
	end)
	if not ok or not gui or not gui:IsA("ScreenGui") then
		return
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	task.spawn(function()
		while workspace:GetAttribute("WorldReady") ~= true do
			task.wait(0.25)
		end
		task.wait(0.5)
		for _, d in gui:GetDescendants() do
			if d:IsA("TextLabel") then
				Util.tween(d, 1.2, { TextTransparency = 1 })
			elseif d:IsA("Frame") then
				Util.tween(d, 1.2, { BackgroundTransparency = 1 })
			end
		end
		task.wait(1.3)
		gui:Destroy()
	end)
end

return TeleportScreen

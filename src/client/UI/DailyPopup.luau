--!strict
-- Daily supplies: shown in the lobby the first time you turn up each day
-- (server Profiles.claimDaily). The week of rewards as a row of crates,
-- today's lit up, the ones before it ticked off, and what tomorrow brings
-- if you come back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lang = require(ReplicatedStorage.Shared.Lang)
local StoreCatalog = require(ReplicatedStorage.Shared.StoreCatalog)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Theme = require(script.Parent.Theme)

local DailyPopup = {}

local C = Theme.Colors
local SHOWN_FOR = 9

function DailyPopup.show(parent: Frame, amount: number, streak: number)
	local old = parent:FindFirstChild("DailyPopup")
	if old then
		old:Destroy()
	end
	local days = StoreCatalog.Daily
	-- where today sits in the row: the week rolls on after day seven
	local todayIndex = math.clamp(streak, 1, #days)
	local panel = Theme.frame(parent, {
		Name = "DailyPopup",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.new(0.9, 0, 0, 200),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
		ZIndex = 20,
	})
	Util.create("UISizeConstraint", { MaxSize = Vector2.new(560, 200), Parent = panel })
	Theme.corner(panel, 8)
	Theme.stroke(panel, C.Blood, 1.5).Transparency = 0.2
	Theme.padding(panel, 16)
	Theme.label(panel, "DAILY SUPPLIES", {
		Size = UDim2.new(1, 0, 0, 34),
		Font = Theme.Fonts.Title,
		TextSize = 32,
		TextColor3 = C.BloodBright,
		ZIndex = 21,
	})
	Theme.label(panel, Lang.f("Day %d in a row: +%d %s", streak, amount, Lang.t(StoreCatalog.Currency)), {
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.Fonts.UIBold,
		TextSize = 18,
		TextColor3 = C.Bone,
		ZIndex = 21,
	})
	local row = Theme.frame(panel, {
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 62),
		BackgroundTransparency = 1,
		ZIndex = 21,
	})
	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = row,
	})
	for i, teeth in days do
		local isToday = i == todayIndex
		local done = i < todayIndex
		local crate = Theme.frame(row, {
			Size = UDim2.new(1 / #days, -6, 1, 0),
			BackgroundColor3 = if isToday then C.Blood else C.PanelLight,
			BackgroundTransparency = if done then 0.5 else 0,
			LayoutOrder = i,
			ZIndex = 22,
		})
		Theme.corner(crate, 5)
		if isToday then
			Theme.stroke(crate, C.BloodBright, 2)
		end
		Theme.label(crate, Lang.f("Day %d", i) .. (if i == #days then "+" else ""), {
			Size = UDim2.new(1, 0, 0, 22),
			TextSize = 13,
			TextColor3 = if isToday then Color3.new(1, 1, 1) else C.BoneDim,
			ZIndex = 23,
		})
		Theme.label(crate, if done then "✓" else "+" .. teeth, {
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 34),
			Font = Theme.Fonts.UIBold,
			TextSize = 20,
			TextColor3 = if done then C.Sickly elseif isToday then Color3.new(1, 1, 1) else C.Bone,
			ZIndex = 23,
		})
	end
	Theme.label(panel, Lang.f("Come back tomorrow for +%d.", StoreCatalog.dailyFor(streak + 1)), {
		Position = UDim2.fromOffset(0, 136),
		Size = UDim2.new(1, -110, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
		TextColor3 = C.BoneDim,
		ZIndex = 21,
	})
	local close = Theme.button(panel, "Take it", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 134),
		Size = UDim2.fromOffset(100, 34),
		TextSize = 16,
		ZIndex = 21,
	})
	Audio.play("Pickup", nil, 0.6, 0.9)
	local function dismiss()
		if panel.Parent then
			Util.tween(panel, 0.3, { BackgroundTransparency = 1 })
			task.delay(0.3, function()
				panel:Destroy()
			end)
		end
	end
	close.Activated:Connect(dismiss)
	task.delay(SHOWN_FOR, dismiss)
end

return DailyPopup

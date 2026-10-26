--!strict
-- The settings rows shared by the title menu and the lobby (one - / + row per
-- shared PlayerSettings entry), and the one place a setting is applied to the
-- camera, effects and audio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lang = require(ReplicatedStorage.Shared.Lang)
local PlayerSettings = require(ReplicatedStorage.Shared.PlayerSettings)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local Settings = require(script.Parent.Parent.Controllers.Settings)
local Theme = require(script.Parent.Theme)

local SettingsPage = {}

local function apply(key: string, value: number)
	if key == "sensitivity" then
		CameraController.setSensitivity(value)
	elseif key == "brightness" then
		Effects.brightness = value
	elseif key == "fov" then
		CameraController.setBaseFov(value)
	elseif key == "volume" then
		Audio.setMasterVolume(value)
	elseif key == "language" then
		Lang.set(Lang.fromSetting(value))
	end
	-- reduceFlashing is read straight from Settings by the effects
end

local function row(parent: Instance, spec: PlayerSettings.Spec, order: number)
	local frame = Theme.frame(parent, {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	})
	Theme.label(frame, spec.label, {
		Size = UDim2.new(0.5, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 20,
	})
	local value = Theme.label(frame, spec.format(Settings.get(spec.key)), {
		Position = UDim2.new(0.62, 0, 0, 0),
		Size = UDim2.new(0.2, 0, 1, 0),
		TextSize = 20,
		Font = Theme.Fonts.UIBold,
	})
	local minus = Theme.button(frame, "-", { Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(44, 40) })
	local plus = Theme.button(frame, "+", { Position = UDim2.new(0.84, 0, 0, 2), Size = UDim2.fromOffset(44, 40) })
	minus.Activated:Connect(function()
		Settings.step(spec.key, -1)
	end)
	plus.Activated:Connect(function()
		Settings.step(spec.key, 1)
	end)
	-- follows changes made elsewhere too (the other menu, the saved profile)
	Settings.Changed:Connect(function(key: string, v: number)
		if key == spec.key then
			value.Text = spec.format(v)
		end
	end)
end

-- Fills `list` with a row per setting.
function SettingsPage.fill(list: Frame)
	Util.create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	for i, spec in PlayerSettings.List do
		row(list, spec, i)
	end
end

-- Applies the defaults now and the saved settings once the profile loads.
function SettingsPage.init()
	for key, value in Settings.values do
		apply(key, value)
	end
	Settings.Changed:Connect(apply)
	Settings.init()
end

return SettingsPage

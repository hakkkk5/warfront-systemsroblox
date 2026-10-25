--!strict
-- Player settings (shared PlayerSettings): mouse sensitivity, brightness,
-- field of view, volume and Reduce flashing. Changed from the title menu or
-- the lobby (UI SettingsPage, which also applies them to the camera, effects
-- and audio), and saved with the profile so they follow the player into the
-- game and to the next session.
--
-- Reduce flashing is for photosensitive players: jumpscares drop their strobe
-- and colour flips for one soft pulse, and every full-screen flash is toned
-- down. It starts on when the device asks for reduced motion.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local PlayerSettings = require(ReplicatedStorage.Shared.PlayerSettings)
local Signal = require(ReplicatedStorage.Shared.Signal)

local Settings = {}

local SAVE_DELAY = 2

Settings.values = {} :: { [string]: number }
for _, spec in PlayerSettings.List do
	Settings.values[spec.key] = spec.default
end
local ok, reduced = pcall(function()
	return (GuiService :: any).ReducedMotionEnabled
end)
if ok and reduced == true then
	Settings.values.reduceFlashing = 1
end
Settings.reduceFlashing = Settings.values.reduceFlashing >= 0.5

-- (key, value) after a setting changes, including when the saved ones load
Settings.Changed = Signal.new() :: Signal.Signal<string, number>

local saveQueued = false

local function queueSave()
	if saveQueued then
		return
	end
	saveQueued = true
	task.delay(SAVE_DELAY, function()
		saveQueued = false
		Net.event("SaveSettings"):FireServer(Settings.values)
	end)
end

local function store(key: string, value: number): boolean
	local spec = PlayerSettings.ByKey[key]
	if not spec then
		return false
	end
	value = PlayerSettings.clamp(spec, value)
	if Settings.values[key] == value then
		return false
	end
	Settings.values[key] = value
	if key == "reduceFlashing" then
		Settings.reduceFlashing = value >= 0.5
	end
	Settings.Changed:Fire(key, value)
	return true
end

function Settings.get(key: string): number
	return Settings.values[key] or 0
end

function Settings.set(key: string, value: number)
	if store(key, value) then
		queueSave()
	end
end

-- Steps a setting up or down by its step (the menu's - / + buttons).
function Settings.step(key: string, direction: number)
	local spec = PlayerSettings.ByKey[key]
	if spec then
		Settings.set(key, Settings.get(key) + direction * spec.step)
	end
end

-- Multiplier for full-screen flash strength.
function Settings.flashScale(): number
	return if Settings.reduceFlashing then 0.35 else 1
end

-- Loads the saved settings once the profile is ready (attributes
-- Setting<key>, published by the server).
function Settings.init()
	local player = Players.LocalPlayer
	local function load()
		if player:GetAttribute("ProfileReady") ~= true then
			return
		end
		for _, spec in PlayerSettings.List do
			local saved = player:GetAttribute("Setting" .. spec.key)
			if typeof(saved) == "number" then
				store(spec.key, saved)
			end
		end
	end
	player:GetAttributeChangedSignal("ProfileReady"):Connect(load)
	load()
end

return Settings

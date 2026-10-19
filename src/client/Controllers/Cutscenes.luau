--!strict
-- Cinematic cutscenes. PLACEHOLDER: every cutscene currently just fades and
-- reports itself done so the story keeps flowing. The full versions are
-- described below and are being implemented separately.
--
-- Contract (keep it when implementing):
--   Cutscenes.init()   connects the "Cutscene" remote. For each cutscene,
--                      play it, then FireServer on "CutsceneDone" with the
--                      cutscene name. The server waits for every player (with
--                      a timeout), so always fire it, even on error.
--   Cutscenes.playing  true while a cutscene owns the camera.
--
-- Cutscene names and the data the server sends (see server Story.luau):
--   "Crash"      { sedan: Model, tree: CFrame, trapLog: CFrame, house: CFrame }
--   "WakeUp"     { eye: CFrame, seat: CFrame, tableTop: CFrame, butcher: CFrame,
--                  brother: CFrame, exit: CFrame, doorway: CFrame, knife: Model?,
--                  chair: Model, body: Model }
--   "TruckFound" { truck: CFrame }
--   "Drive"      { truck: Model, truckCF: CFrame, path: { Vector2 }, wreck: CFrame }
--   "Radio"      { radio: CFrame }
--   "Ending"     { helicopter: Model?, pad: CFrame }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local CameraController = require(script.Parent.CameraController)
local Movement = require(script.Parent.Movement)
local Viewmodel = require(script.Parent.Viewmodel)
local HUD = require(script.Parent.Parent.UI.HUD)
local Theme = require(script.Parent.Parent.UI.Theme)

local Cutscenes = {}

Cutscenes.playing = false

local player = Players.LocalPlayer
local fade: Frame

local function begin()
	Cutscenes.playing = true
	Movement.locked = true
	Viewmodel.hidden = true
	HUD.setVisible(false)
	CameraController.setEnabled(false)
end

local function finish(name: string)
	CameraController.setEnabled(true)
	Movement.locked = false
	Viewmodel.hidden = false
	HUD.setVisible(true)
	Cutscenes.playing = false
	Net.event("CutsceneDone"):FireServer(name)
end

function Cutscenes.init()
	local gui = Theme.screen("Cutscene", 9)
	fade = Theme.frame(gui, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 50,
	})
	Net.event("Cutscene").OnClientEvent:Connect(function(name: string, _data: any)
		begin()
		Util.tween(fade, 0.6, { BackgroundTransparency = 0 })
		task.wait(1.2)
		finish(name)
		Util.tween(fade, 1, { BackgroundTransparency = 1 })
	end)
	local _ = player
end

return Cutscenes

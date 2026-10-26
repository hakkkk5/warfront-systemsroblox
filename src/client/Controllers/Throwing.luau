--!strict
-- Throws the held item (G, R1, or the touch HUD's Throw button) where the
-- camera looks; the server (Systems/Throwing) checks it and flies it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local CameraController = require(script.Parent.CameraController)

local Throwing = {}

local player = Players.LocalPlayer
local COOLDOWN = 0.7
local last = 0

-- The held item, if it can be thrown.
function Throwing.held(): string?
	local id = player:GetAttribute("Equipped")
	if typeof(id) ~= "string" then
		return nil
	end
	local def = Items.get(id)
	return if def and def.throwable then id else nil
end

function Throwing.throw()
	local now = os.clock()
	if now - last < COOLDOWN or not Throwing.held() then
		return
	end
	if player:GetAttribute("InCutscene") or player:GetAttribute("Hidden") or player:GetAttribute("Struggling") then
		return
	end
	last = now
	CameraController.shake(0.15, 6)
	Net.event("Throw"):FireServer(workspace.CurrentCamera.CFrame.LookVector)
end

function Throwing.init()
	-- phones get their button from UI TouchControls
	ContextActionService:BindAction("Throw", function(_, state)
		if state == Enum.UserInputState.Begin then
			Throwing.throw()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.G, Enum.KeyCode.ButtonR1)
end

return Throwing

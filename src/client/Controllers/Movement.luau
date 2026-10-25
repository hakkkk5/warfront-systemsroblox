--!strict
-- Sprinting with stamina, crouch-walking, heavy-item slowdown. Movement state
-- is sent to the server so cannibals can hear / see the player.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local CameraController = require(script.Parent.CameraController)

local Movement = {}

local player = Players.LocalPlayer
local P = Config.Player

Movement.stamina = P.StaminaMax
Movement.exhausted = false
Movement.locked = false -- cutscenes / hiding

local wantSprint = false
local crouching = false
local flashlight = false
local lastSent = ""
local movementRemote = Net.event("Movement")

local function send()
	local sprinting = CameraController.sprinting
	local key = tostring(sprinting) .. tostring(crouching) .. tostring(flashlight)
	if key ~= lastSent then
		lastSent = key
		movementRemote:FireServer({ sprinting = sprinting, crouching = crouching, flashlight = flashlight })
	end
end

function Movement.setFlashlight(on: boolean)
	flashlight = on
	send()
end

function Movement.isCrouching(): boolean
	return crouching
end

function Movement.init()
	ContextActionService:BindAction("Sprint", function(_, state)
		wantSprint = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("Sprint", "Run")
	ContextActionService:SetPosition("Sprint", UDim2.new(1, -170, 1, -170))

	ContextActionService:BindAction("Crouch", function(_, state)
		if state == Enum.UserInputState.Begin then
			crouching = not crouching
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("Crouch", "Crouch")
	ContextActionService:SetPosition("Crouch", UDim2.new(1, -240, 1, -110))

	RunService.Heartbeat:Connect(function(dt: number)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local heavy = player:GetAttribute("Heavy") == true
		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local canSprint = wantSprint and moving and not crouching and not heavy and not Movement.exhausted and not Movement.locked

		if canSprint then
			Movement.stamina = math.max(0, Movement.stamina - P.StaminaDrain * dt)
			if Movement.stamina <= 0 then
				Movement.exhausted = true
			end
		else
			Movement.stamina = math.min(P.StaminaMax, Movement.stamina + P.StaminaRegen * dt * (if moving then 0.7 else 1))
			if Movement.exhausted and Movement.stamina >= P.StaminaLockout then
				Movement.exhausted = false
			end
		end

		local speed = if canSprint then P.SprintSpeed elseif crouching then P.CrouchSpeed else P.WalkSpeed
		if heavy then
			speed *= P.CarrySpeedMultiplier
		end
		if Movement.exhausted then
			speed = math.min(speed, P.WalkSpeed * 0.8)
		end
		local hurt = humanoid.Health / humanoid.MaxHealth
		if hurt < 0.35 then
			speed *= 0.85
		end
		-- the chase after the explosion: pure adrenaline, no stamina limit
		if player:GetAttribute("Adrenaline") == true and not crouching then
			speed = if moving then 30 else P.WalkSpeed
			Movement.stamina = P.StaminaMax
			Movement.exhausted = false
		end
		local frozen = Movement.locked or player:GetAttribute("Struggling") == true
		humanoid.WalkSpeed = Util.lerp(humanoid.WalkSpeed, if frozen then 0 else speed, math.min(1, dt * 8))

		CameraController.sprinting = canSprint
		CameraController.crouching = crouching
		send()
	end)

	player.CharacterAdded:Connect(function()
		Movement.stamina = P.StaminaMax
		Movement.exhausted = false
		crouching = false
	end)
end

return Movement

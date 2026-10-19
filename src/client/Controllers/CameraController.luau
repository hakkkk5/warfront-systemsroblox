--!strict
-- First-person feel on top of LockFirstPerson: head bob, strafe tilt,
-- breathing sway, sprint FOV, crouch height and screen shake.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Util = require(ReplicatedStorage.Shared.Util)

local CameraController = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local enabled = true
local bobTime = 0
local tilt = 0
local fov = 72
local shakeAmount = 0
local shakeDecay = 4
local crouchOffset = 0
local baseFov = 72
local sensitivity = 0.6

CameraController.sprinting = false
CameraController.crouching = false

function CameraController.setEnabled(value: boolean)
	enabled = value
	if value then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = baseFov
	end
end

function CameraController.isEnabled(): boolean
	return enabled
end

function CameraController.shake(amount: number, decay: number?)
	shakeAmount = math.max(shakeAmount, amount)
	shakeDecay = decay or 4
end

function CameraController.setBaseFov(value: number)
	baseFov = value
end

function CameraController.setSensitivity(value: number)
	sensitivity = value
	UserInputService.MouseDeltaSensitivity = value
end

function CameraController.getSensitivity(): number
	return sensitivity
end

-- Shake is also applied during cutscenes, so expose it as a CFrame.
function CameraController.shakeOffset(): CFrame
	if shakeAmount <= 0.001 then
		return CFrame.new()
	end
	local t = os.clock() * 40
	return CFrame.Angles(
		math.noise(t, 0.3) * shakeAmount * 0.05,
		math.noise(t, 2.1) * shakeAmount * 0.05,
		math.noise(t, 5.7) * shakeAmount * 0.03
	)
end

function CameraController.init()
	UserInputService.MouseDeltaSensitivity = sensitivity
	RunService:BindToRenderStep("HorrorCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		shakeAmount = math.max(0, shakeAmount - shakeDecay * dt * math.max(shakeAmount, 0.3))
		if not enabled or camera.CameraType ~= Enum.CameraType.Custom then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root or humanoid.Health <= 0 then
			return
		end

		local velocity = Util.flat(root.AssemblyLinearVelocity)
		local speed = velocity.Magnitude
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		local moving = speed > 1 and grounded
		local freq = if CameraController.sprinting then 13 elseif CameraController.crouching then 6 else 8.5
		local amp = if CameraController.sprinting then 0.16 elseif CameraController.crouching then 0.05 else 0.08
		if moving then
			bobTime += dt * freq * math.clamp(speed / 11, 0.5, 1.6)
		else
			amp = 0
		end

		local bobY = math.abs(math.sin(bobTime)) * amp
		local bobX = math.cos(bobTime) * amp * 0.6
		local breathe = math.sin(os.clock() * 1.4) * 0.006

		local right = camera.CFrame.RightVector
		local strafe = velocity:Dot(right) / 20
		tilt = Util.lerp(tilt, -strafe * 0.035, math.min(1, dt * 8))

		local targetCrouch = if CameraController.crouching then -1.9 else 0
		crouchOffset = Util.lerp(crouchOffset, targetCrouch, math.min(1, dt * 10))
		humanoid.CameraOffset = Vector3.new(0, crouchOffset, 0)

		local targetFov = baseFov + (if CameraController.sprinting and moving then 8 else 0)
		fov = Util.lerp(fov, targetFov, math.min(1, dt * 6))
		camera.FieldOfView = fov

		camera.CFrame = camera.CFrame
			* CFrame.new(bobX, bobY + breathe, 0)
			* CFrame.Angles(breathe * 0.5, 0, tilt)
			* CameraController.shakeOffset()
	end)
end

return CameraController

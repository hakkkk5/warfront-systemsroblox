--!strict
-- First-person feel on top of LockFirstPerson: head bob that rolls and dips
-- with each step, leaning into a strafe, banking into a turn at speed,
-- tipping forward into a sprint (and the FOV opening up), the knees taking
-- a landing, breathing sway, crouch height and screen shake. Settings >
-- Camera motion scales all the movement down (or off).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage.Shared.Signal)
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
local punchFov = 0
local crouchOffset = 0
local baseFov = 72
local sensitivity = 0.6
local motion = 1 -- Settings > Camera motion: 0 off, 0.5 low, 1 full
local lean = 0
local lastYaw = 0
local landing = 0
local fallSpeed = 0
local wasAirborne = false

CameraController.sprinting = false
CameraController.crouching = false
-- (floor material, "walk" | "run" | "crouch") each time a foot comes down
CameraController.Stepped = Signal.new() :: Signal.Signal<Enum.Material, string>
local lastStep = 0

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

-- A sudden kick: the view lurches in (FOV) and jolts up, settling fast.
function CameraController.punch(fovKick: number)
	punchFov = math.max(punchFov, fovKick)
end

function CameraController.setBaseFov(value: number)
	baseFov = value
end

function CameraController.setSensitivity(value: number)
	sensitivity = value
	UserInputService.MouseDeltaSensitivity = value
end

-- How much the view moves with you (Settings > Camera motion).
function CameraController.setMotion(value: number)
	motion = math.clamp(value, 0, 1)
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
	-- always follow the newest body: after a death the camera was left on the
	-- old (destroyed) character and stayed where the player died
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			camera.CameraSubject = humanoid
			if enabled then
				camera.CameraType = Enum.CameraType.Custom
			end
		end
	end)
	RunService:BindToRenderStep("HorrorCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		shakeAmount = math.max(0, shakeAmount - shakeDecay * dt * math.max(shakeAmount, 0.3))
		punchFov = math.max(0, punchFov - dt * math.max(punchFov * 6, 20))
		if not enabled or camera.CameraType ~= Enum.CameraType.Custom then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root or humanoid.Health <= 0 then
			return
		end

		local fullVelocity = root.AssemblyLinearVelocity
		local velocity = Util.flat(fullVelocity)
		local speed = velocity.Magnitude
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		local moving = speed > 1 and grounded
		local sprinting = CameraController.sprinting and moving
		local freq = if CameraController.sprinting then 13 elseif CameraController.crouching then 6 else 8.5
		local amp = if CameraController.sprinting then 0.22 elseif CameraController.crouching then 0.05 else 0.09
		if moving then
			bobTime += dt * freq * math.clamp(speed / 11, 0.5, 1.6)
			-- a foot comes down at the bottom of every bob (BodySounds)
			local step = math.floor(bobTime / math.pi)
			if step ~= lastStep then
				lastStep = step
				CameraController.Stepped:Fire(humanoid.FloorMaterial, if CameraController.sprinting then "run" elseif CameraController.crouching then "crouch" else "walk")
			end
		else
			amp = 0
		end
		amp *= motion
		-- third person (the lobby): the steps still sound, the view stays put
		if player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
			camera.FieldOfView = baseFov + punchFov
			camera.CFrame = camera.CFrame * CameraController.shakeOffset()
			return
		end

		-- each step: the head rises and falls, sways side to side, rolls
		-- with the stride and dips a little as the foot comes down
		local bobY = math.abs(math.sin(bobTime)) * amp
		local bobX = math.cos(bobTime) * amp * 0.6
		local stepRoll = math.cos(bobTime) * amp * 0.1
		local stepPitch = -(1 - math.abs(math.sin(bobTime))) * amp * 0.06
		local breathe = math.sin(os.clock() * 1.4) * 0.006

		-- lean into where you're running: sideways into a strafe, banking
		-- into a turn at speed, tipping forward when you sprint ahead
		local look = camera.CFrame.LookVector
		local flatLook = Util.flat(look)
		local right = camera.CFrame.RightVector
		local strafe = velocity:Dot(right) / 20
		local ahead = if flatLook.Magnitude > 0.01 then velocity:Dot(flatLook.Unit) / 20 else 0
		local yaw = math.atan2(-look.X, -look.Z)
		local turn = (yaw - lastYaw + math.pi) % (2 * math.pi) - math.pi
		lastYaw = yaw
		local turnRate = if dt > 0 then math.clamp(turn / dt, -8, 8) else 0
		local pace = math.clamp(speed / 16, 0, 1.2)
		local rollTarget = (-strafe * 0.075 + turnRate * 0.01 * pace) * motion
		tilt = Util.lerp(tilt, rollTarget, math.min(1, dt * 7))
		local leanTarget = (-ahead * (if sprinting then 0.05 else 0.02)) * motion
		lean = Util.lerp(lean, leanTarget, math.min(1, dt * 5))

		-- landing from a jump or a fall: the knees take it
		if not grounded then
			fallSpeed = math.max(fallSpeed, -fullVelocity.Y)
		elseif wasAirborne then
			landing = math.max(landing, math.clamp((fallSpeed - 12) / 40, 0, 0.9) * motion)
			fallSpeed = 0
		end
		wasAirborne = not grounded
		landing = math.max(0, landing - dt * 2.4)

		local targetCrouch = if CameraController.crouching then -1.9 else 0
		crouchOffset = Util.lerp(crouchOffset, targetCrouch, math.min(1, dt * 10))
		humanoid.CameraOffset = Vector3.new(0, crouchOffset, 0)

		local targetFov = baseFov + (if sprinting then 6 + 6 * motion else 0)
		fov = Util.lerp(fov, targetFov, math.min(1, dt * 6))
		camera.FieldOfView = fov + punchFov

		camera.CFrame = camera.CFrame
			* CFrame.new(bobX, bobY + breathe - landing, 0)
			* CFrame.Angles(breathe * 0.5 + math.rad(punchFov * 0.12) + lean + stepPitch - landing * 0.12, 0, tilt + stepRoll)
			* CameraController.shakeOffset()
	end)
end

return CameraController

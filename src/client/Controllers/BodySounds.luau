--!strict
-- The sounds a body makes: your footsteps, each one landing as the camera's
-- bob comes down (CameraController.Stepped), by what's underfoot (a hollow
-- thud on the farmhouse boards, a gritty crunch in the dirt and leaves),
-- soft crouched and heavy at a run; your teammates' steps out in the world
-- where they are; and you gasping for breath when your stamina runs out.
-- Roblox's own running loop is silenced so it doesn't play over them.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Audio = require(script.Parent.Audio)
local CameraController = require(script.Parent.CameraController)
local Movement = require(script.Parent.Movement)

local BodySounds = {}

local me = Players.LocalPlayer

local DIRT: { [Enum.Material]: boolean } = {
	[Enum.Material.Grass] = true,
	[Enum.Material.LeafyGrass] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true,
	[Enum.Material.Sand] = true,
	[Enum.Material.Snow] = true,
	[Enum.Material.Pebble] = true,
}
local WOOD: { [Enum.Material]: boolean } = {
	[Enum.Material.Wood] = true,
	[Enum.Material.WoodPlanks] = true,
}
local VOLUME: { [string]: number } = { crouch = 0.12, walk = 0.32, run = 0.6 }

-- One footfall: which sound, how loud, how deep.
local function step(material: Enum.Material, gait: string, position: Vector3?)
	local volume = (VOLUME[gait] or 0.32) * (if position then 1.4 else 1)
	local jitter = (math.random() - 0.5) * 0.12
	if DIRT[material] then
		local s = Audio.play("StepDirt", position, volume * 0.8, 1.35 + jitter)
		-- just the first crunch of the recording
		if s then
			task.delay(0.16, function()
				s:Stop()
			end)
		end
	else
		local pitch = if WOOD[material] then 0.78 else 1
		Audio.play("Footstep", position, volume, pitch + jitter)
	end
end

-- Roblox's default running sound loop, off (we play our own steps).
local function silence(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local function mute(s: Instance)
		if s:IsA("Sound") and s.Name == "Running" then
			s.Volume = 0
			s:GetPropertyChangedSignal("Volume"):Connect(function()
				if s.Volume ~= 0 then
					s.Volume = 0
				end
			end)
		end
	end
	for _, c in root:GetChildren() do
		mute(c)
	end
	root.ChildAdded:Connect(mute)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(silence)
	if player.Character then
		task.spawn(silence, player.Character)
	end
end

function BodySounds.init()
	CameraController.Stepped:Connect(function(material: Enum.Material, gait: string)
		step(material, gait, nil)
	end)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)

	-- teammates: a step every few studs they cover on the ground
	local travelled: { [Player]: number } = {}
	local breathing = false
	RunService.Heartbeat:Connect(function(dt: number)
		for _, other in Players:GetPlayers() do
			if other ~= me then
				local character = other.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and humanoid.FloorMaterial ~= Enum.Material.Air then
					local v = root.AssemblyLinearVelocity
					local speed = Vector3.new(v.X, 0, v.Z).Magnitude
					local gait = if other:GetAttribute("Sprinting") then "run" elseif other:GetAttribute("Crouching") then "crouch" else "walk"
					local stride = if gait == "run" then 5.5 elseif gait == "crouch" then 3 else 4.2
					local d = (travelled[other] or 0) + speed * dt
					if d >= stride then
						d -= stride
						step(humanoid.FloorMaterial, gait, root.Position - Vector3.new(0, 2.5, 0))
					end
					travelled[other] = d
				end
			end
		end
		-- out of breath
		local want = Movement.exhausted == true
		if want ~= breathing then
			breathing = want
			Audio.loop("Breath", want, 0.45)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		travelled[player] = nil
	end)
end

return BodySounds

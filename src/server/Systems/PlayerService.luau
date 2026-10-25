--!strict
-- Spawning, death, respawn at checkpoints and movement state replication.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Cannibals = require(script.Parent.Cannibals)
local Hiding = require(script.Parent.Hiding)
local R6Characters = require(script.Parent.R6Characters)
local Story = require(script.Parent.Story)

local PlayerService = {}

local playing: { [Player]: boolean } = {}

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 3
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Player"
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Player"
		end
	end)
	player:SetAttribute("Sprinting", false)
	player:SetAttribute("Crouching", false)
	player:SetAttribute("Hidden", false)
	player:SetAttribute("LastAttacker", nil)

	humanoid.Died:Connect(function()
		local killer = player:GetAttribute("LastAttacker")
		Net.event("Caught"):FireClient(player, killer)
		Hiding.leave(player, true)
		Cannibals.forgetPlayer(player)
		task.delay(Config.RespawnDelay, function()
			if player.Parent and playing[player] then
				PlayerService.spawn(player)
			end
		end)
	end)
end

function PlayerService.spawn(player: Player)
	-- your own avatar on an R6 body, every spawn and respawn
	local character = R6Characters.load(player)
	if not character then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if root then
		-- stand on the floor under the checkpoint at this avatar's own height
		-- (checkpoints assume a default-size body; bigger avatars sank into the floor)
		local checkpoint = Story.checkpoint()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local height = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15
			then humanoid.HipHeight + root.Size.Y / 2
			else root.Size.Y * 1.5
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = {}
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		local npcs = workspace:FindFirstChild("Cannibals")
		if npcs then
			table.insert(ignore, npcs)
		end
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(checkpoint.Position + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
		local floorY = if hit then hit.Position.Y else checkpoint.Position.Y - 3
		root.CFrame = CFrame.new(checkpoint.X, floorY + height + 0.15, checkpoint.Z) * checkpoint.Rotation
		root.AssemblyLinearVelocity = Vector3.zero
		-- a moment to get your bearings: nobody near the checkpoint, nobody looking
		player:SetAttribute("SafeUntil", os.clock() + 10)
		Cannibals.retreatFrom(checkpoint.Position, 70)
	end
	Story.syncPlayer(player)
end

function PlayerService.init()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			setupCharacter(player, character)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		playing[player] = nil
	end)

	Net.event("RequestPlay").OnServerEvent:Connect(function(player)
		if playing[player] then
			return
		end
		playing[player] = true
		PlayerService.spawn(player)
		Story.begin()
	end)

	Net.event("Movement").OnServerEvent:Connect(function(player, state)
		if typeof(state) ~= "table" then
			return
		end
		local s = state :: { [string]: any }
		player:SetAttribute("Sprinting", s.sprinting == true)
		player:SetAttribute("Crouching", s.crouching == true)
		player:SetAttribute("Flashlight", s.flashlight == true)
	end)

	Net.event("PlayAgain").OnServerEvent:Connect(function(player)
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, { player })
		end)
		if not ok then
			warn("[PlayerService] teleport failed: " .. tostring(err))
			player:Kick("Thanks for playing The Cannibal Family! Rejoin to play again.")
		end
	end)
end

return PlayerService

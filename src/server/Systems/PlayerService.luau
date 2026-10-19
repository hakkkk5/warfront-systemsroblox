--!strict
-- Spawning, death, respawn at checkpoints and movement state replication.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Cannibals = require(script.Parent.Cannibals)
local Hiding = require(script.Parent.Hiding)
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
	local ok = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok then
		(player :: any):LoadCharacter()
	end
	local character = player.Character
	if not character then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if root then
		root.CFrame = Story.checkpoint()
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
			player:Kick("Thanks for playing Butcher's Hollow! Rejoin to play again.")
		end
	end)
end

return PlayerService

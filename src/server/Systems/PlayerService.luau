--!strict
-- Spawning, death, respawn at checkpoints and movement state replication.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Net = require(ReplicatedStorage.Shared.Net)
local Places = require(ReplicatedStorage.Shared.Places)
local Cannibals = require(script.Parent.Cannibals)
local Hiding = require(script.Parent.Hiding)
local Inventory = require(script.Parent.Inventory)
local R6Characters = require(script.Parent.R6Characters)
local Profiles = require(script.Parent.Profiles)
local Rejoin = require(script.Parent.Rejoin)
local Store = require(script.Parent.Store)
local Story = require(script.Parent.Story)

local PlayerService = {}

local checkGameOver: () -> ()

local playing: { [Player]: boolean } = {}
local over = false

-- Everyone who's playing is out of lives: the family ate well. Everyone
-- sees it, and after a while they're all sent back to the lobby.
checkGameOver = function()
	if over then
		return
	end
	local anyone = false
	for player in playing do
		if player.Parent then
			anyone = true
			if player:GetAttribute("Out") ~= true then
				return
			end
		end
	end
	if not anyone then
		return
	end
	over = true
	task.delay(4, function()
		Net.event("GameOver"):FireAllClients()
		task.wait(40)
		for _, player in Players:GetPlayers() do
			Profiles.save(player)
			pcall(function()
				TeleportService:TeleportAsync(Places.LOBBY, { player })
			end)
		end
	end)
end

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
		Profiles.record(player, "deaths")
		-- one life gone (Easy has no limit: -1)
		local lives = player:GetAttribute("Lives")
		if typeof(lives) == "number" and lives > 0 then
			lives -= 1
			player:SetAttribute("Lives", lives)
		end
		local out = lives == 0
		if out then
			player:SetAttribute("Out", true)
		end
		Net.event("Caught"):FireClient(player, killer)
		Hiding.leave(player, true)
		Cannibals.forgetPlayer(player)
		if out then
			checkGameOver()
			return
		end
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
		task.defer(checkGameOver)
	end)

	Net.event("RequestPlay").OnServerEvent:Connect(function(player)
		if playing[player] then
			return
		end
		playing[player] = true
		Store.grantPerks(player) -- what they stocked up on in the lobby store
		-- the map (Use it, or M)
		if not Inventory.has(player, "Map") then
			Inventory.add(player, "Map", 1, true)
		end
		-- Survivor Kit (game pass)
		if player:GetAttribute("Pass_SurvivorKit") == true then
			Inventory.add(player, "Bandage", 1, true)
			Inventory.add(player, "Battery", 1, true)
		end
		-- lives for this run (a player who rejoined keeps what they had left)
		if player:GetAttribute("Lives") == nil then
			local lives = Difficulty.lives()
			-- Second Wind (game pass): one more
			if lives > 0 and player:GetAttribute("Pass_ExtraLife") == true then
				lives += 1
			end
			player:SetAttribute("Lives", lives)
		end
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
		Profiles.save(player) -- the lobby server reads it next
		Rejoin.forget(player.UserId) -- leaving on purpose: don't send them back here
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(Places.LOBBY, { player })
		end)
		if not ok then
			warn("[PlayerService] teleport failed: " .. tostring(err))
			player:Kick("Thanks for playing The Cannibal Family! Rejoin to play again.")
		end
	end)
end

return PlayerService

--!strict
-- The owner's admin panel (UI/AdminPanel, F2): skip the part of the story
-- you're on, jump to the objective, freeze the family, god mode, heal, and
-- give yourself any item. Only the game's owner and the players listed here
-- get it (everyone in a Studio test); every request is checked here, on the
-- server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Cannibals = require(script.Parent.Cannibals)
local Interact = require(script.Parent.Interact)
local Inventory = require(script.Parent.Inventory)
local Story = require(script.Parent.Story)

local Admin = {}

-- UserIds with the panel on top of the game's owner
local ADMINS: { [number]: boolean } = {
	[1864017860] = true, -- hakkkk5
}

local lastAction: { [Player]: number } = {}

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() or ADMINS[player.UserId] then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local ACTIONS: { [string]: (player: Player, arg: unknown) -> () } = {
	skip = function(player)
		local skipped = Story.adminSkip()
		Interact.notify(player, if skipped then "Skipped " .. skipped else "Nothing to skip right now", "info")
	end,
	objective = function(player)
		local target = Story.hintTargets()[1]
		local root = rootOf(player)
		if not target or not root then
			Interact.notify(player, "No objective to go to", "info")
			return
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.new(target + Vector3.new(0, 4, 0)) * root.CFrame.Rotation
	end,
	freeze = function(player)
		local value = not Cannibals.frozen()
		Cannibals.setFrozen(value)
		workspace:SetAttribute("AdminFrozen", value)
		Interact.notify(player, if value then "The family is frozen" else "The family moves again", "info")
	end,
	god = function(player)
		local value = not player:GetAttribute("AdminGod")
		player:SetAttribute("AdminGod", value)
		Interact.notify(player, if value then "God mode on: they ignore you" else "God mode off", "info")
	end,
	heal = function(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
		end
	end,
	give = function(player, id)
		local def = if typeof(id) == "string" then Items.get(id) else nil
		if def then
			Inventory.add(player, def.id, 1)
		end
	end,
}

function Admin.init()
	local function added(player: Player)
		if isAdmin(player) then
			player:SetAttribute("Admin", true)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, player in Players:GetPlayers() do
		task.spawn(added, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)

	Net.event("AdminAction").OnServerEvent:Connect(function(player: Player, action: unknown, arg: unknown)
		if typeof(action) ~= "string" or not player:GetAttribute("Admin") then
			return
		end
		local run = ACTIONS[action]
		local now = os.clock()
		if not run or now - (lastAction[player] or 0) < 0.2 then
			return
		end
		lastAction[player] = now
		run(player, arg)
	end)

	-- god mode: anything that still lands (a fall, a fire) heals straight back
	RunService.Heartbeat:Connect(function()
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("AdminGod") then
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = humanoid.MaxHealth
				end
			end
		end
	end)
end

return Admin

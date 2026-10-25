--!strict
-- Teeth earned in a run (amounts in shared StoreCatalog.Rewards): escaping,
-- sedating one of the family, the household chores. Reading notes pays from
-- Pickups.note. Records (escapes) are kept in Profiles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local StoreCatalog = require(ReplicatedStorage.Shared.StoreCatalog)
local Cannibals = require(script.Parent.Cannibals)
local Chores = require(script.Parent.Chores)
local Profiles = require(script.Parent.Profiles)
local Story = require(script.Parent.Story)

local Rewards = {}

local R = StoreCatalog.Rewards

function Rewards.init()
	Cannibals.Sedated:Connect(function(c, player)
		if player and player.Parent then
			Profiles.award(player, R.sedate, "Put " .. c.spec.display .. " to sleep")
		end
	end)
	Chores.Completed:Connect(function()
		for _, player in Players:GetPlayers() do
			Profiles.award(player, R.chore, "Chore done")
		end
	end)
	Story.Ended:Connect(function()
		local bonus = StoreCatalog.DifficultyBonus[Difficulty.current()] or 1
		for _, player in Players:GetPlayers() do
			Profiles.record(player, "escapes")
			Profiles.award(player, math.floor(R.escape * bonus), "You escaped")
		end
	end)
end

return Rewards

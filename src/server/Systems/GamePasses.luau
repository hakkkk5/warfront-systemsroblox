--!strict
-- Who owns which game pass (shared GamePasses): checked when a player joins
-- and the moment they buy one, and published as Pass_<key> attributes that
-- the rest of the game reads (Profiles doubles Teeth, PlayerService adds the
-- extra life and the survivor kit).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Passes = require(ReplicatedStorage.Shared.GamePasses)

local GamePasses = {}

local function check(player: Player)
	for _, pass in Passes.List do
		if pass.id > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owns then
				player:SetAttribute("Pass_" .. pass.key, true)
			end
		end
	end
end

function GamePasses.init()
	Players.PlayerAdded:Connect(check)
	for _, player in Players:GetPlayers() do
		task.spawn(check, player)
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, id: number, bought: boolean)
		if not bought then
			return
		end
		for _, pass in Passes.List do
			if pass.id == id then
				player:SetAttribute("Pass_" .. pass.key, true)
			end
		end
	end)
end

return GamePasses

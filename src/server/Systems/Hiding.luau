--!strict
-- Wardrobes, closets, lockers and bushes players can hide in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Interact = require(script.Parent.Interact)
local Net = require(ReplicatedStorage.Shared.Net)

local Hiding = {}

export type Spot = {
	inside: CFrame, -- where the player's root part is held
	exit: CFrame,
	occupant: Player?,
	position: Vector3,
	kind: string, -- "furniture" (slats to peek through) or "bush" (leaves)
}

local spots: { Spot } = {}
local byPlayer: { [Player]: Spot } = {}
local hidingRemote = Net.event("Hiding")

function Hiding.add(promptParent: BasePart, inside: CFrame, exit: CFrame, label: string?): Spot
	local spot: Spot = {
		inside = inside,
		exit = exit,
		occupant = nil,
		position = inside.Position,
		kind = if label == "Bush" then "bush" else "furniture",
	}
	table.insert(spots, spot)
	Interact.add(promptParent, {
		action = "Hide",
		object = label or "Wardrobe",
		distance = 6,
		canUse = function()
			if spot.occupant then
				return false, "Someone is already hiding here."
			end
			return true
		end,
		onUse = function(player)
			Hiding.enter(player, spot)
		end,
	})
	return spot
end

function Hiding.enter(player: Player, spot: Spot)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	spot.occupant = player
	byPlayer[player] = spot
	root.Anchored = true
	root.CFrame = spot.inside
	player:SetAttribute("Hidden", true)
	player:SetAttribute("HiddenAt", os.clock())
	hidingRemote:FireClient(player, true, spot.inside, spot.kind)
end

function Hiding.leave(player: Player, forced: boolean?)
	local spot = byPlayer[player]
	if not spot then
		return
	end
	byPlayer[player] = nil
	spot.occupant = nil
	player:SetAttribute("Hidden", false)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and not forced then
		root.CFrame = spot.exit
		root.Anchored = false
	elseif root then
		root.Anchored = false
	end
	hidingRemote:FireClient(player, false)
end

function Hiding.spotOf(player: Player): Spot?
	return byPlayer[player]
end

function Hiding.init()
	Net.event("LeaveHiding").OnServerEvent:Connect(function(player)
		Hiding.leave(player)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		local spot = byPlayer[player]
		if spot then
			spot.occupant = nil
			byPlayer[player] = nil
		end
	end)
end

return Hiding

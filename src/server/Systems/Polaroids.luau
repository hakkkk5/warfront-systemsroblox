--!strict
-- The family album: thirteen polaroids hidden around the valley (shared
-- Trophies). Each one stays where it is so everyone in the party can take a
-- look; the first look adds it to your album for good (Profiles) and pays a
-- few Teeth. All thirteen is an achievement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Trophies = require(ReplicatedStorage.Shared.Trophies)
local AssetService = require(script.Parent.AssetService)
local Interact = require(script.Parent.Interact)
local Pickups = require(script.Parent.Pickups)
local Profiles = require(script.Parent.Profiles)

local Polaroids = {}

-- (player, id) the first time a photo goes in someone's album
Polaroids.Collected = Signal.new() :: Signal.Signal<Player, string>

function Polaroids.place(id: string, cf: CFrame, parent: Instance)
	local photo = Trophies.Polaroids[id]
	assert(photo, "unknown polaroid " .. id)
	local model = AssetService.create("Polaroid")
	model.Name = "Polaroid_" .. id
	model:PivotTo(cf)
	local main: BasePart? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			main = main or d
		end
	end
	model.Parent = parent
	if not main then
		return
	end
	Pickups.glint(main)
	Interact.add(main, {
		action = "Look at",
		object = "Polaroid",
		distance = 6,
		onUse = function(player)
			Net.event("Sound"):FireClient(player, "PageTurn")
			Net.event("Note"):FireClient(player, "Polaroid_" .. id)
			if Profiles.collectPolaroid(player, id) then
				Profiles.award(player, Trophies.POLAROID_TEETH, string.format("Polaroid %d/%d", Profiles.polaroidCount(player), #Trophies.polaroidList()))
				Polaroids.Collected:Fire(player, id)
			end
		end,
	})
end

return Polaroids

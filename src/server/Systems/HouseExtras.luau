--!strict
-- Things to do in every room of the (bigger) farmhouse: the piano in the
-- parlor, the stew on the stove, the mirror upstairs, the crib in the attic...
-- Each one tells you something about the family, a few of them answer back
-- (a scare, just for you), and the first time you try one it pays a couple
-- of Teeth. They are there from the moment you wake up and stay all night.
--
-- Positions are on the house plan (HouseLayout.place moves them with the
-- furniture they belong to).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseLayout = require(ReplicatedStorage.Shared.HouseLayout)
local Net = require(ReplicatedStorage.Shared.Net)
local Build = require(script.Parent.Parent.World.Build)
local Interact = require(script.Parent.Interact)
local Profiles = require(script.Parent.Profiles)

local HouseExtras = {}

local U = 13
local TEETH = 2

type Extra = {
	at: Vector3, -- house plan
	action: string,
	object: string,
	lines: { string }, -- one is said (to you), picked at random
	scare: string?, -- a Scares kind for you, sometimes
	chance: number?, -- how often the scare comes (default 1)
	hold: number?,
}

local EXTRAS: { Extra } = {
	-- ground floor
	{ at = Vector3.new(-50, 3.6, -21.2), action = "Play a few notes", object = "Piano", lines = { "The piano plays one more note after you stop.", "Out of tune. Except for one key, which plays perfectly." }, scare = "footsteps", chance = 0.5 },
	{ at = Vector3.new(-9.4, 3.4, -20), action = "Thump the TV", object = "Television", lines = { "The static makes a face for a second. Then it's static again.", "For a moment the channel shows this room. You aren't in it." }, scare = "whisper", chance = 0.5 },
	{ at = Vector3.new(30.6, 4, -18), action = "Look at the plates", object = "China hutch", lines = { "Every plate has a name painted round the rim. None of them are the family's." } },
	{ at = Vector3.new(-9, 4.3, 22), action = "Lift the lid", object = "Stew pot", lines = { "Stew. Something in it blinks.", "A wedding ring floats to the top, then sinks again." }, scare = "jumpscare", chance = 0.3 },
	{ at = Vector3.new(-17, 3.7, 22.4), action = "Run the tap", object = "Sink", lines = { "The water runs red. Then clear. Then red again." } },
	{ at = Vector3.new(28.5, 2, 4.5), action = "Rattle the cage", object = "Cage", lines = { "Something in the dark corner of it rattles back." }, scare = "breath", chance = 0.6 },
	{ at = Vector3.new(-44, 1, 21.6), action = "Count the boots", object = "Boots", lines = { "Twenty pairs. One of them is your size. Brand new." } },
	{ at = Vector3.new(60, 3.5, 8), action = "Look at the plank", object = "Sawhorse", lines = { "Half sawn through. It isn't a plank." } },
	{ at = Vector3.new(64, 6, -20), action = "Look in the cage", object = "Birdcage", lines = { "Finger bones, threaded like a necklace. Some still wear rings." } },
	{ at = Vector3.new(65.4, 3.2, -6), action = "Blow out the candles", object = "Shrine", lines = { "They light themselves again, one by one, when you turn away." }, scare = "lights", chance = 0.5 },
	-- upstairs
	{ at = Vector3.new(-12, U + 5.6, -23.2), action = "Look in the mirror", object = "Cracked mirror", lines = { "Just you. Pale. Tired. Then something moves behind your reflection.", "Your reflection blinks a moment after you do." }, scare = "behind", chance = 0.6 },
	{ at = Vector3.new(14, U + 2.2, -22.8), action = "Turn a doll around", object = "Dolls", lines = { "You turn one to face the wall. When you look back, they're all facing you." }, scare = "whisper", chance = 0.7 },
	{ at = Vector3.new(30, U + 1.5, -1), action = "Switch off the night light", object = "Night light", lines = { "Something under the bed giggles. You switch it back on." } },
	{ at = Vector3.new(-9, U + 1.2, 22), action = "Lift the lid", object = "Toilet", lines = { "You really didn't need to see that." } },
	{ at = Vector3.new(30.9, U + 3.2, 10), action = "Look at the jars", object = "Jars", lines = { "Eyes, floating. One of them turns to follow you." }, scare = "whisper", chance = 0.5 },
	{ at = Vector3.new(22, U + 3.2, 21.5), action = "Open the desk drawer", object = "Desk", lines = { "Driver's licences. Dozens of them. Yours is on top." } },
	{ at = Vector3.new(-42.5, U + 4.4, 12), action = "Turn the wheel", object = "Sewing machine", lines = { "The needle punches through something that isn't cloth." } },
	{ at = Vector3.new(42, U + 3, -20), action = "Open the suitcase", object = "Suitcase", lines = { "Folded clothes, a hairbrush, and a bus ticket home. Never used." } },
	{ at = Vector3.new(52, U + 2.5, 21.5), action = "Pull off the sheet", object = "Covered furniture", lines = { "A chair under it. Straps on the arms. Scratches on the straps." }, scare = "breath", chance = 0.4 },
	-- the attic
	{ at = Vector3.new(-24, 26.6, -2), action = "Rock the crib", object = "Crib", lines = { "It keeps rocking after you let go. And rocking." }, scare = "whisper", chance = 0.8 },
	{ at = Vector3.new(14, 27, 3), action = "Push the rocking horse", object = "Rocking horse", lines = { "Somewhere below you, something creaks back. Same rhythm." }, scare = "footsteps", chance = 0.6 },
}

function HouseExtras.build(origin: CFrame, parent: Instance)
	local folder = Build.folder(parent, "HouseExtras")
	local subtitle = Net.event("Subtitle")
	local scare = Net.event("Scare")
	local tried: { [Player]: { [number]: boolean } } = {}
	for i, extra in EXTRAS do
		local anchor = Build.part(folder, Vector3.new(1.6, 1.6, 1.6), origin * CFrame.new(HouseLayout.place(extra.at)), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, {
			Name = extra.object,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		Interact.add(anchor, {
			action = extra.action,
			object = extra.object,
			hold = extra.hold or 0.4,
			distance = 7,
			onUse = function(player)
				subtitle:FireClient(player, "You", extra.lines[math.random(1, #extra.lines)], 4)
				local mine = tried[player] or {}
				tried[player] = mine
				if not mine[i] then
					mine[i] = true
					Profiles.award(player, TEETH, "Curiosity")
				end
				if extra.scare and math.random() < (extra.chance or 1) then
					task.delay(1.2, function()
						if player.Parent then
							scare:FireClient(player, extra.scare)
						end
					end)
				end
			end,
		})
	end
	Players.PlayerRemoving:Connect(function(player)
		tried[player] = nil
	end)
end

return HouseExtras

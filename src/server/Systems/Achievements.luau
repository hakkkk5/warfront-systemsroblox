--!strict
-- Decides when an achievement (shared Trophies) is earned and hands it out:
-- saved with the profile, a toast, and Teeth the first time. Story beats come
-- from Story.StageChanged / Story.Ended, the rest from the systems that see
-- them happen (sedations, throws, crafting, notes, hiding, polaroids).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Net = require(ReplicatedStorage.Shared.Net)
local Trophies = require(ReplicatedStorage.Shared.Trophies)
local Cannibals = require(script.Parent.Cannibals)
local Crafting = require(script.Parent.Crafting)
local Pickups = require(script.Parent.Pickups)
local Polaroids = require(script.Parent.Polaroids)
local Profiles = require(script.Parent.Profiles)
local Story = require(script.Parent.Story)
local Throwing = require(script.Parent.Throwing)

local Achievements = {}

local SEDATIONS_FOR_LULLABY = 3
local CRAFTS_FOR_HANDY = 5
local BOOKWORM_MIN_NOTES = 12
local HIDER_RANGE = 8

-- per player, this night
local sedations: { [Player]: number } = {}
local crafts: { [Player]: number } = {}
local notesRead: { [Player]: { [string]: boolean } } = {}
local chasedIn: { [Player]: boolean } = {} -- in the current dangerous chapter

function Achievements.award(player: Player, id: string)
	local a = Trophies.Achievements[id]
	if not a or not player.Parent or not Profiles.unlock(player, id) then
		return
	end
	Net.event("Notify"):FireClient(player, "ACHIEVEMENT - " .. a.name, "achievement")
	Profiles.award(player, a.teeth, a.name)
end

local function awardAll(id: string)
	for _, player in Players:GetPlayers() do
		Achievements.award(player, id)
	end
end

-- Chapters you can get through unseen, by the stages they span.
local DANGEROUS: { [string]: string } = {
	HouseEscape = "house",
	Forest = "woods",
	Repair = "woods",
	Plant = "plant",
	Church = "church",
}

local function onStage(new: string, old: string)
	-- leaving a dangerous chapter without ever being chased
	local was, now = DANGEROUS[old], DANGEROUS[new]
	if was and was ~= now then
		for _, player in Players:GetPlayers() do
			if not chasedIn[player] then
				Achievements.award(player, "Unseen")
			end
		end
		table.clear(chasedIn)
	end
	if old == "HouseEscape" and new == "Forest" then
		awardAll("HouseEscape")
	elseif new == "Drive" then
		awardAll("TruckFixed")
	elseif new == "Radio" then
		awardAll("PowerOn")
	elseif new == "Downed" then
		awardAll("Rescued")
	elseif new == "Wreck" then
		awardAll("Downed")
	elseif new == "Church" then
		awardAll("MineEscape")
	end
	if old == "Plant" and new ~= "Plant" then
		awardAll("PlantEscape")
	end
end

local function watch()
	while true do
		task.wait(0.5)
		local stage = workspace:GetAttribute("Stage")
		local dangerous = typeof(stage) == "string" and DANGEROUS[stage] ~= nil
		for _, player in Players:GetPlayers() do
			if dangerous and player:GetAttribute("Chased") == true then
				chasedIn[player] = true
			end
			-- one of them walked right past your hiding spot
			if player:GetAttribute("Hidden") == true then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					for _, c in Cannibals.all() do
						if c.alive and c.state ~= "Sedated" and c.target ~= player and (c.root.Position - root.Position).Magnitude < HIDER_RANGE then
							Achievements.award(player, "Hider")
							break
						end
					end
				end
			end
		end
	end
end

function Achievements.init()
	Story.StageChanged:Connect(onStage)
	Story.Ended:Connect(function()
		awardAll("Finished")
		if Difficulty.current() == "Nightmare" then
			awardAll("Nightmare")
		end
		if Story.trueEnding() then
			awardAll("TrueEnding")
		end
	end)
	Cannibals.Sedated:Connect(function(_, player)
		if player and player.Parent then
			sedations[player] = (sedations[player] or 0) + 1
			if sedations[player] >= SEDATIONS_FOR_LULLABY then
				Achievements.award(player, "Lullaby")
			end
		end
	end)
	Throwing.Distracted:Connect(function(player)
		Achievements.award(player, "Distraction")
	end)
	Throwing.Burned:Connect(function(player)
		Achievements.award(player, "Molotov")
	end)
	Crafting.Crafted:Connect(function(player)
		crafts[player] = (crafts[player] or 0) + 1
		if crafts[player] >= CRAFTS_FOR_HANDY then
			Achievements.award(player, "Crafter")
		end
	end)
	Pickups.NoteRead:Connect(function(player, noteId)
		local read = notesRead[player]
		if not read then
			read = {}
			notesRead[player] = read
		end
		read[noteId] = true
		local n = 0
		for _ in read do
			n += 1
		end
		if n >= math.max(BOOKWORM_MIN_NOTES, Pickups.notesPlaced) then
			Achievements.award(player, "Bookworm")
		end
	end)
	Polaroids.Collected:Connect(function(player)
		if Profiles.polaroidCount(player) >= #Trophies.polaroidList() then
			Achievements.award(player, "Collector")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sedations[player] = nil
		crafts[player] = nil
		notesRead[player] = nil
		chasedIn[player] = nil
	end)
	task.spawn(watch)
end

return Achievements

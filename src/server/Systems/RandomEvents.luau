--!strict
-- Every run feels different: now and then each player gets a scare of their
-- own (played by the client's Scares controller). What can happen depends on
-- where the story is; how often depends on the difficulty. Jumpscares are
-- rare and never land while you are already being chased or hiding.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local RandomEvents = {}

-- kind -> weight, per story stage
local TABLES: { [string]: { [string]: number } } = {
	-- the hosts are still pretending: only small wrong things
	Investigate = { lights = 2, knock = 3, whisper = 1 },
	HouseEscape = { apparition = 3, jumpscare = 1, lights = 3, whisper = 2, shadow = 2, knock = 1 },
	Forest = { apparition = 3, jumpscare = 1, shadow = 3, scream = 3, whisper = 2, thunder = 2 },
	Repair = { apparition = 3, jumpscare = 1, shadow = 3, scream = 3, whisper = 1, thunder = 2 },
	Hunt = { apparition = 2, jumpscare = 1, shadow = 3, scream = 2, thunder = 2 },
	Power = { apparition = 2, jumpscare = 1, lights = 3, scream = 2, shadow = 2, whisper = 1 },
	Radio = { lights = 2, scream = 2, whisper = 2 },
	Survive = { apparition = 2, jumpscare = 1, lights = 3, shadow = 2, scream = 2 },
}

local INTERVAL: { [string]: { number } } = {
	Easy = { 75, 120 },
	Normal = { 50, 90 },
	Hard = { 35, 65 },
	Nightmare = { 22, 45 },
}

local JUMPSCARE_COOLDOWN = 150

local nextAt: { [Player]: number } = {}
local lastJumpscare: { [Player]: number } = {}

local function pick(weights: { [string]: number }): string?
	local total = 0
	for _, w in weights do
		total += w
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	for kind, w in weights do
		roll -= w
		if roll <= 0 then
			return kind
		end
	end
	return nil
end

local function interval(): number
	local range = INTERVAL[workspace:GetAttribute("Difficulty") or "Normal"] or INTERVAL.Normal
	return math.random(range[1], range[2])
end

local function canScare(player: Player): boolean
	if player:GetAttribute("InCutscene") or player:GetAttribute("Struggling") then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function RandomEvents.init()
	local remote = Net.event("Scare")
	Players.PlayerRemoving:Connect(function(player)
		nextAt[player] = nil
		lastJumpscare[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(3)
			local stage = workspace:GetAttribute("Stage")
			local weights = if typeof(stage) == "string" then TABLES[stage] else nil
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				if not nextAt[player] then
					nextAt[player] = now + interval()
				end
				if weights and now >= nextAt[player] and canScare(player) then
					nextAt[player] = now + interval()
					local hidden = player:GetAttribute("Hidden") == true
					local chased = player:GetAttribute("Chased") == true
					local recent = now - (lastJumpscare[player] or -math.huge) < JUMPSCARE_COOLDOWN
					local options: { [string]: number } = {}
					for kind, w in weights do
						local blocked = (kind == "jumpscare" and (hidden or chased or recent))
							or ((kind == "apparition" or kind == "shadow") and (hidden or chased))
						if not blocked then
							options[kind] = w
						end
					end
					local kind = pick(options)
					if kind then
						if kind == "jumpscare" then
							lastJumpscare[player] = now
						end
						remote:FireClient(player, kind)
					end
				end
			end
		end
	end)
end

return RandomEvents

--!strict
-- The fear director. Instead of scares on a timer it paces them for each
-- player by how much pressure they're under (the "menace gauge" idea from
-- Alien: Isolation). Tension rises when one of the family is close, has
-- spotted you or is chasing you, and drains away slowly. Then:
--
--   * quiet for a while: dread builds - footsteps coming up behind you, a
--     door slamming somewhere out of sight, whispers, knocking, the lights
--     going, the music dropping to nothing. After the worst of those a jolt
--     sometimes follows (one of them watching you from far off, a shadow,
--     rarely a jumpscare) and sometimes nothing does at all.
--   * quiet for too long: one of them wanders over to look around near you
--     (never right at you).
--   * at the boil for too long without being caught: they back off for a
--     breather before it starts over.
--
-- What can happen depends on where the story is, how often on the
-- difficulty. Jumpscares are rare and never land while you're chased or
-- hiding. The client plays them (Scares.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Cannibals = require(script.Parent.Cannibals)
local Doors = require(script.Parent.Doors)

local RandomEvents = {}

-- dread cues per story stage: kind -> weight
local CUES: { [string]: { [string]: number } } = {
	-- the hosts are still pretending: only small wrong things
	Investigate = { lights = 2, knock = 3, whisper = 1, footsteps = 2, doorslam = 1 },
	HouseEscape = { footsteps = 4, doorslam = 3, silence = 3, whisper = 2, lights = 2, knock = 1 },
	Forest = { footsteps = 3, silence = 3, scream = 3, whisper = 2, thunder = 2 },
	Repair = { footsteps = 3, silence = 2, scream = 3, whisper = 1, thunder = 2 },
	Power = { footsteps = 2, silence = 2, lights = 3, scream = 2, doorslam = 2, whisper = 1 },
	Radio = { lights = 2, scream = 2, whisper = 2, silence = 1 },
	Survive = { footsteps = 2, lights = 3, scream = 2, silence = 2 },
}

-- what can follow a build-up (silence / footsteps)
local JOLTS: { [string]: { [string]: number } } = {
	Investigate = { lights = 1 },
	HouseEscape = { apparition = 3, shadow = 2, jumpscare = 1 },
	Forest = { apparition = 3, shadow = 3, jumpscare = 1 },
	Repair = { apparition = 3, shadow = 3, jumpscare = 1 },
	Power = { apparition = 2, shadow = 2, jumpscare = 1 },
	Radio = { shadow = 1 },
	Survive = { apparition = 2, shadow = 2, jumpscare = 1 },
}

type Tuning = { gap: { number }, jolt: number, nudge: number }
local TUNING: { [string]: Tuning } = {
	-- gap: seconds between cues while it's quiet; jolt: chance a build-up
	-- pays off; nudge: seconds of quiet before one of them comes looking
	Easy = { gap = { 45, 80 }, jolt = 0.3, nudge = 140 },
	Normal = { gap = { 30, 60 }, jolt = 0.45, nudge = 95 },
	Hard = { gap = { 22, 45 }, jolt = 0.55, nudge = 70 },
	Nightmare = { gap = { 15, 32 }, jolt = 0.65, nudge = 50 },
}

local CALM = 0.2 -- below this a player is "quiet"
local HIGH = 0.65 -- above this they're under real pressure
local BACK_OFF_AFTER = 50 -- seconds at the boil before the family eases off
local RELAX_FOR = 25
local JUMPSCARE_COOLDOWN = 150

type State = {
	tension: number,
	calmSince: number?,
	highSince: number?,
	nextCue: number,
	nextNudge: number,
	relaxUntil: number,
	lastJumpscare: number,
	pending: boolean,
}

local states: { [Player]: State } = {}
local remote: RemoteEvent

local function tuning(): Tuning
	return TUNING[workspace:GetAttribute("Difficulty") or "Normal"] or TUNING.Normal
end

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

local function rootOf(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function canScare(player: Player): boolean
	if player:GetAttribute("InCutscene") or player:GetAttribute("Struggling") then
		return false
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function gap(): number
	local g = tuning().gap
	return math.random(g[1], g[2])
end

-- How much pressure they're under right now, 0..1.
local function pressure(player: Player, root: BasePart): number
	if player:GetAttribute("Chased") == true then
		return 1
	end
	local nearest = math.huge
	for _, c in Cannibals.all() do
		if c.alive and c.state ~= "Sedated" then
			nearest = math.min(nearest, (c.root.Position - root.Position).Magnitude)
		end
	end
	local close = math.clamp(1 - (nearest - 8) / 52, 0, 1)
	local seen = (player:GetAttribute("Detection") :: number?) or 0
	return math.max(close * 0.7, seen * 0.9)
end

local function send(player: Player, kind: string, st: State)
	if kind == "doorslam" then
		local root = rootOf(player)
		local door = root and Doors.near(root.Position, 14, 45)
		if not door then
			return
		end
		Doors.setOpen(door, not door.isOpen, nil)
		Net.event("Sound"):FireAllClients("Impact", door.center)
		return
	end
	if kind == "jumpscare" then
		st.lastJumpscare = os.clock()
	end
	remote:FireClient(player, kind)
end

-- After a build-up: maybe a jolt, maybe nothing (a false alarm is a scare too).
local function maybeJolt(player: Player, stage: string, st: State)
	if st.pending then
		return
	end
	st.pending = true
	task.delay(math.random(5, 9), function()
		st.pending = false
		if not player.Parent or not canScare(player) or math.random() > tuning().jolt then
			return
		end
		local hidden = player:GetAttribute("Hidden") == true
		local chased = player:GetAttribute("Chased") == true
		if hidden or chased then
			return
		end
		local options: { [string]: number } = {}
		local jolts: { [string]: number } = JOLTS[stage] or {}
		for kind, w in jolts do
			if not (kind == "jumpscare" and os.clock() - st.lastJumpscare < JUMPSCARE_COOLDOWN) then
				options[kind] = w
			end
		end
		local kind = pick(options)
		if kind then
			send(player, kind, st)
		end
	end)
end

-- One of them wanders over to look around 12-22 studs from you.
local function nudge(root: BasePart): boolean
	local best, bestDistance = nil, math.huge
	for _, c in Cannibals.all() do
		local d = (c.root.Position - root.Position).Magnitude
		if c.alive and c.state ~= "Chase" and c.state ~= "Sedated" and d < bestDistance then
			best, bestDistance = c, d
		end
	end
	if not best or bestDistance < 20 then
		return false
	end
	local a = math.random() * math.pi * 2
	local r = 12 + math.random() * 10
	return Cannibals.investigate(best, root.Position + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
end

local function step(player: Player, stage: string, now: number)
	local st = states[player]
	if not st then
		st = { tension = 0, calmSince = now, highSince = nil, nextCue = now + gap(), nextNudge = now + tuning().nudge, relaxUntil = 0, lastJumpscare = -math.huge, pending = false }
		states[player] = st
	end
	local root = rootOf(player)
	if not root or not canScare(player) then
		return
	end
	local target = pressure(player, root)
	st.tension = if target > st.tension then st.tension + (target - st.tension) * 0.5 else math.max(0, st.tension - 0.02)

	-- at the boil: give them a breather once it's lasted too long
	if st.tension > HIGH then
		st.highSince = st.highSince or now
		st.calmSince = nil
		if now - (st.highSince :: number) > BACK_OFF_AFTER and player:GetAttribute("Chased") ~= true then
			Cannibals.retreatFrom(root.Position, 60)
			st.relaxUntil = now + RELAX_FOR
			st.highSince = nil
		end
		return
	end
	st.highSince = nil
	if st.tension < CALM then
		st.calmSince = st.calmSince or now
	else
		st.calmSince = nil
		return
	end
	if now < st.relaxUntil then
		return
	end

	-- quiet for too long: someone comes looking
	if now - (st.calmSince :: number) > tuning().nudge and now >= st.nextNudge then
		st.nextNudge = now + tuning().nudge
		if nudge(root) then
			st.calmSince = now
		end
	end

	-- dread cues
	local cues = CUES[stage]
	if cues and now >= st.nextCue then
		st.nextCue = now + gap()
		local options = table.clone(cues)
		if player:GetAttribute("Hidden") == true then
			-- hiding: only what you'd hear, and the breathing outside
			options = { breath = 3, whisper = 1, knock = 1 }
		end
		local kind = pick(options)
		if kind then
			send(player, kind, st)
			if kind == "silence" or kind == "footsteps" then
				maybeJolt(player, stage, st)
			end
		end
	end
end

function RandomEvents.init()
	remote = Net.event("Scare")
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local stage = workspace:GetAttribute("Stage")
			if typeof(stage) == "string" then
				local now = os.clock()
				for _, player in Players:GetPlayers() do
					step(player, stage, now)
				end
			end
		end
	end)
end

return RandomEvents

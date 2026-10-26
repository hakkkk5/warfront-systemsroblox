--!strict
-- Difficulty presets. The lobby party's choice travels in the teleport data;
-- the game server publishes it as workspace.Difficulty and both server and
-- client scale the shared tuning in Config from its base values (so applying
-- twice never stacks). The server also passes Cannibals.Kinds to scale the
-- family's walk and run speeds.

local Config = require(script.Parent.Config)

local Difficulty = {}

Difficulty.NAMES = { "Normal", "Hard", "Nightmare" }

Difficulty.INFO = {
	Normal = "The intended scare.",
	Hard = "They hear more, search longer and hit harder. Your light dies faster.",
	Nightmare = "No hints. They see further, run faster and sedatives barely work.",
} :: { [string]: string }

type Scale = {
	cannibal: { [string]: number },
	player: { [string]: number },
	survive: number,
	respawn: number,
	speed: number,
}

local SCALES: { [string]: Scale } = {
	Normal = { cannibal = {}, player = {}, survive = 1, respawn = 1, speed = 1 },
	Hard = {
		cannibal = {
			DetectRate = 1.35,
			DetectDecay = 0.8,
			HearSprint = 1.2,
			HearWalk = 1.25,
			LoseSightTime = 1.3,
			SearchTime = 1.3,
			AttackCooldown = 0.9,
			SedateTime = 0.75,
		},
		player = { FlashlightDrain = 1.3, HintCooldown = 1.6 },
		survive = 1.25,
		respawn = 1.25,
		speed = 1.06,
	},
	Nightmare = {
		cannibal = {
			ViewRange = 1.25,
			ViewAngle = 1.15,
			DetectRate = 1.8,
			DetectDecay = 0.6,
			HearSprint = 1.4,
			HearWalk = 1.6,
			LoseSightTime = 1.7,
			SearchTime = 1.6,
			AttackWindup = 0.85,
			AttackCooldown = 0.8,
			SedateTime = 0.5,
		},
		player = { FlashlightDrain = 1.7, StaminaDrain = 1.25, StaminaRegen = 0.85, HintCooldown = math.huge },
		survive = 1.5,
		respawn = 1.5,
		speed = 1.12,
	},
}

local baseCannibal: { [string]: number } = {}
local basePlayer: { [string]: number } = {}
for k, v in Config.Cannibal :: any do
	baseCannibal[k] = v
end
for k, v in Config.Player :: any do
	basePlayer[k] = v
end
local baseSurvive = Config.SurviveDuration
local baseRespawn = Config.RespawnDelay
local baseSpeeds: { [any]: { walk: number, run: number } } = {}

local current = "Normal"

function Difficulty.current(): string
	return current
end

-- Hard and Nightmare: one blow from the family kills.
function Difficulty.oneShot(): boolean
	return current == "Hard" or current == "Nightmare"
end

function Difficulty.valid(name: any): boolean
	return typeof(name) == "string" and SCALES[name] ~= nil
end

-- kinds: Cannibals.Kinds on the server (walk / run speeds), nil on clients.
function Difficulty.apply(name: string, kinds: { [string]: any }?)
	local scale = SCALES[name] or SCALES.Normal
	current = if SCALES[name] then name else "Normal"
	local cannibal = Config.Cannibal :: any
	for k, v in baseCannibal do
		cannibal[k] = v * (scale.cannibal[k] or 1)
	end
	local playerTune = Config.Player :: any
	for k, v in basePlayer do
		playerTune[k] = v * (scale.player[k] or 1)
	end
	Config.SurviveDuration = baseSurvive * scale.survive
	Config.RespawnDelay = baseRespawn * scale.respawn
	if kinds then
		for _, spec in kinds do
			local base = baseSpeeds[spec]
			if not base then
				base = { walk = spec.walk, run = spec.run }
				baseSpeeds[spec] = base
			end
			spec.walk = base.walk * scale.speed
			spec.run = base.run * scale.speed
		end
	end
end

-- Applies workspace.Difficulty now and whenever it changes.
function Difficulty.watch(kinds: { [string]: any }?)
	local function sync()
		local name = workspace:GetAttribute("Difficulty")
		Difficulty.apply(if Difficulty.valid(name) then name :: string else "Normal", kinds)
	end
	sync()
	workspace:GetAttributeChangedSignal("Difficulty"):Connect(sync)
end

return Difficulty

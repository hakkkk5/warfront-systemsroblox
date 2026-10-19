--!strict
-- World layout and gameplay tuning. All site positions are on the XZ plane;
-- heights come from the terrain generator at runtime.

local Config = {}

Config.GameName = "BUTCHER'S HOLLOW"
Config.Tagline = "They are always hungry."

Config.Map = {
	TerrainHalf = 720, -- terrain is generated from -720..720 on X and Z
	PlayHalf = 615, -- invisible boundary walls
	WaterLevel = 3,
	Seed = 6613,
}

export type Site = { pos: Vector2, radius: number }

-- Named locations. radius = area that gets flattened / kept clear of trees.
local sites: { [string]: Site } = {
	House = { pos = Vector2.new(-120, -300), radius = 82 },
	Crash = { pos = Vector2.new(-188, -527), radius = 22 },
	Truck = { pos = Vector2.new(170, -60), radius = 46 },
	Barn = { pos = Vector2.new(-345, -95), radius = 48 },
	Camp = { pos = Vector2.new(70, 140), radius = 38 },
	Trailer = { pos = Vector2.new(-235, 170), radius = 40 },
	Cemetery = { pos = Vector2.new(320, -255), radius = 46 },
	Wreck = { pos = Vector2.new(360, 130), radius = 30 },
	Station = { pos = Vector2.new(505, 330), radius = 72 },
	Tower = { pos = Vector2.new(420, 405), radius = 26 },
	Shed = { pos = Vector2.new(560, 260), radius = 22 },
	Helipad = { pos = Vector2.new(592, 458), radius = 44 },
}
Config.Sites = sites

Config.Lake = { pos = Vector2.new(-390, 405), radius = 150 }

export type Road = {
	name: string,
	width: number, -- half width in studs
	material: Enum.Material,
	points: { Vector2 },
}

local S = sites
Config.Roads = {
	{
		name = "Highway",
		width = 13,
		material = Enum.Material.Asphalt,
		points = {
			Vector2.new(-760, -505),
			Vector2.new(-520, -515),
			Vector2.new(-330, -545),
			Vector2.new(-188, -540),
			Vector2.new(-20, -505),
			Vector2.new(180, -470),
			Vector2.new(400, -500),
			Vector2.new(760, -485),
		},
	},
	{
		name = "Driveway",
		width = 8,
		material = Enum.Material.Mud,
		points = {
			S.House.pos + Vector2.new(0, -36),
			Vector2.new(-140, -400),
			Vector2.new(-172, -478),
			Vector2.new(-186, -528),
		},
	},
	{
		name = "LoggingRoad",
		width = 10,
		material = Enum.Material.Ground,
		points = {
			S.House.pos + Vector2.new(52, 40),
			Vector2.new(-55, -215),
			Vector2.new(40, -150),
			S.Truck.pos,
			Vector2.new(262, 22),
			S.Wreck.pos,
			Vector2.new(432, 232),
			S.Station.pos + Vector2.new(-30, -30),
		},
	},
	{
		name = "TrailCamp",
		width = 4.5,
		material = Enum.Material.Mud,
		points = { S.Truck.pos, Vector2.new(125, 40), S.Camp.pos },
	},
	{
		name = "TrailTrailer",
		width = 4.5,
		material = Enum.Material.Mud,
		points = { S.Camp.pos, Vector2.new(-80, 175), S.Trailer.pos },
	},
	{
		name = "TrailBarn",
		width = 4.5,
		material = Enum.Material.Mud,
		points = { S.Trailer.pos, Vector2.new(-305, 45), S.Barn.pos },
	},
	{
		name = "TrailHouse",
		width = 4.5,
		material = Enum.Material.Mud,
		points = { S.Barn.pos, Vector2.new(-255, -205), S.House.pos + Vector2.new(-40, 0) },
	},
	{
		name = "TrailCemetery",
		width = 4.5,
		material = Enum.Material.Mud,
		points = { S.Truck.pos, Vector2.new(250, -165), S.Cemetery.pos },
	},
	{
		name = "TrailTower",
		width = 4,
		material = Enum.Material.Mud,
		points = { S.Station.pos, S.Tower.pos },
	},
	{
		name = "TrailHelipad",
		width = 5,
		material = Enum.Material.Mud,
		points = { S.Station.pos, Vector2.new(560, 400), S.Helipad.pos },
	},
	{
		name = "TrailShed",
		width = 4,
		material = Enum.Material.Mud,
		points = { S.Station.pos, S.Shed.pos },
	},
} :: { Road }

-- The scripted drive after the truck is repaired follows this path.
Config.DrivePath = {
	S.Truck.pos + Vector2.new(4, 6),
	Vector2.new(262, 22),
	S.Wreck.pos,
}

-- House: axis aligned, front door faces north (-Z).
Config.House = {
	Width = 64, -- X
	Depth = 48, -- Z
	FloorHeight = 12,
	Foundation = 1.5,
}

Config.Player = {
	WalkSpeed = 11,
	SprintSpeed = 20,
	CrouchSpeed = 6,
	CarrySpeedMultiplier = 0.65,
	StaminaMax = 100,
	StaminaDrain = 17, -- per second while sprinting
	StaminaRegen = 13,
	StaminaLockout = 25, -- must regen to this after running dry
	FlashlightDrain = 100 / 420, -- percent per second (7 minutes of light)
	HintCooldown = 25,
}

Config.Cannibal = {
	ViewRange = 72,
	ViewAngle = 62, -- half angle in degrees
	ProximitySense = 7, -- always notices players this close
	HearSprint = 46,
	HearWalk = 14,
	DetectRate = 2.4,
	DetectDecay = 0.4,
	LoseSightTime = 6,
	SearchTime = 11,
	AttackRange = 5,
	HitRange = 6.8,
	AttackWindup = 0.45,
	AttackCooldown = 1.35,
	SedateTime = 80,
}

Config.SurviveDuration = 120
Config.RespawnDelay = 4

return Config

--!strict
-- Item definitions shared by the server inventory and the inventory UI.

local Assets = require(script.Parent.Assets)

export type ItemDef = {
	id: string,
	name: string,
	description: string,
	model: string, -- template name in ReplicatedStorage.ItemModels
	icon: string?,
	tint: Color3?,
	stackable: boolean?,
	usable: boolean?, -- shows a "Use" button
	equippable: boolean?, -- can be held in the right hand
	heavy: boolean?, -- slows the player and blocks sprinting
	questItem: boolean?,
}

local Items = {}

local defs: { [string]: ItemDef } = {
	Flashlight = {
		id = "Flashlight",
		name = "Flashlight",
		description = "Heavy metal flashlight. Press F to toggle. Batteries drain over time.",
		model = "Flashlight",
	},
	Knife = {
		id = "Knife",
		name = "Hunting Knife",
		description = "The blade I used to cut the ropes. Still sharp.",
		model = "HuntingKnife",
		icon = Assets.Images.Knife,
		equippable = true,
	},
	Battery = {
		id = "Battery",
		name = "Batteries",
		description = "A pair of D-cell batteries. Restores half of the flashlight's charge.",
		model = "Battery",
		stackable = true,
		usable = true,
	},
	Bandage = {
		id = "Bandage",
		name = "Bandage",
		description = "Dirty, but it will stop the bleeding. Restores 40 health.",
		model = "Bandage",
		icon = Assets.Images.Medical,
		tint = Color3.fromRGB(220, 70, 70),
		stackable = true,
		usable = true,
	},
	HouseKey = {
		id = "HouseKey",
		name = "Rusty Padlock Key",
		description = "Opens the padlock chained across the front door.",
		model = "HouseKey",
		icon = Assets.Images.Key,
		tint = Color3.fromRGB(196, 150, 80),
		questItem = true,
	},
	Syringe = {
		id = "Syringe",
		name = "Sedative Syringe",
		description = "Veterinary sedative. Sneak up behind a cannibal and inject them to knock them out.",
		model = "Syringe",
		icon = Assets.Images.Medical,
		tint = Color3.fromRGB(120, 255, 140),
		stackable = true,
		equippable = true,
	},
	Engine = {
		id = "Engine",
		name = "Truck Engine",
		description = "The truck's motor. Heavy - you can't run while carrying it.",
		model = "EngineBlock",
		icon = Assets.Images.Wrench,
		heavy = true,
		questItem = true,
	},
	CarBattery = {
		id = "CarBattery",
		name = "Car Battery",
		description = "A 12V battery that still holds a charge.",
		model = "CarBattery",
		icon = Assets.Images.Wrench,
		questItem = true,
	},
	SparkPlugs = {
		id = "SparkPlugs",
		name = "Spark Plugs",
		description = "A box of spark plugs for the truck's engine.",
		model = "SparkPlugs",
		icon = Assets.Images.Wrench,
		questItem = true,
	},
	Tire = {
		id = "Tire",
		name = "Spare Wheel",
		description = "A muddy wheel that fits the truck.",
		model = "TireWheel",
		icon = Assets.Images.Wrench,
		heavy = true,
		questItem = true,
	},
	TruckKeys = {
		id = "TruckKeys",
		name = "Truck Keys",
		description = "Taken from the Butcher's belt. The rabbit foot is sticky.",
		model = "CarKeys",
		icon = Assets.Images.Key,
		tint = Color3.fromRGB(230, 200, 120),
		questItem = true,
	},
	Fuse = {
		id = "Fuse",
		name = "Fuse",
		description = "A ceramic cartridge fuse for the station's fuse box.",
		model = "Fuse",
		icon = Assets.Images.Wrench,
		questItem = true,
	},
	BoltCutters = {
		id = "BoltCutters",
		name = "Bolt Cutters",
		description = "Long-handled bolt cutters. They'll bite through a padlock or a chain.",
		model = "BoltCutters",
		icon = Assets.Images.Wrench,
		tint = Color3.fromRGB(220, 70, 60),
		questItem = true,
	},
	GasCan = {
		id = "GasCan",
		name = "Fuel Can",
		description = "Half full jerry can. Enough to run the generator.",
		model = "GasCan",
		icon = Assets.Images.Fuel,
		tint = Color3.fromRGB(230, 80, 60),
		heavy = true,
		questItem = true,
	},
}

Items.Defs = defs
Items.Order = {
	"Flashlight",
	"Knife",
	"Syringe",
	"Battery",
	"Bandage",
	"HouseKey",
	"BoltCutters",
	"TruckKeys",
	"Engine",
	"CarBattery",
	"SparkPlugs",
	"Tire",
	"Fuse",
	"GasCan",
}

function Items.get(id: string): ItemDef?
	return defs[id]
end

return Items

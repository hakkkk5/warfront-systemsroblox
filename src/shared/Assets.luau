--!strict
-- Roblox asset ids used by the game.
--
-- Models and icons were generated with ForgeGUI and published to the creator
-- account 1864017860 (@hakaaannnnnnnn). InsertService can only load models
-- owned by the experience owner, so publish the place from that account (or
-- re-publish the meshes to your group) for the meshes to appear. Anything that
-- fails to load falls back to a procedural model built from parts, so the
-- game is always playable.
--
-- Sizes are the target size in studs after import: `length` scales the longest
-- horizontal side, `height` scales the vertical size. `yaw` rotates the mesh
-- (degrees) if it was authored facing a different direction.

export type ModelSpec = {
	id: number,
	length: number?,
	height: number?,
	yaw: number?,
}

local Assets = {}

Assets.Models = {
	CrashedSedan = { id = 73193234568840, length = 16, yaw = 0 },
	PickupTruck = { id = 116288644494114, length = 18.5, yaw = 0 },
	EngineBlock = { id = 124503135770719, length = 3.2 },
	CarBattery = { id = 115821756774757, length = 1.7 },
	SparkPlugs = { id = 106943413747423, length = 1.3 },
	TireWheel = { id = 132952222251049, height = 3.1 },
	Syringe = { id = 79237926120495, length = 1.15 },
	CarKeys = { id = 98412590570036, length = 0.9 },
	HuntingKnife = { id = 84693353445664, length = 1.5 },
	ButcherTable = { id = 104341500262978, length = 8.5 },
	MeatHooks = { id = 102976782218646, length = 7 },
	PineTree = { id = 95887089293746, height = 46 },
	OakTree = { id = 111118553837182, height = 32 },
} :: { [string]: ModelSpec }

-- White silhouette icons (tinted in the UI).
Assets.Images = {
	Knife = "rbxassetid://135957404329279",
	Key = "rbxassetid://105618853597676",
	Padlock = "rbxassetid://89489125736718",
	Fuel = "rbxassetid://137127820385627",
	Wrench = "rbxassetid://91696769699169",
	Medical = "rbxassetid://128583940727945",
	Backpack = "rbxassetid://79963634133679",
	Skull = "rbxassetid://129915467150738",
	Gear = "rbxassetid://135791503730117",
	MapPin = "rbxassetid://79478009908933",
	Helicopter = "rbxassetid://78674533427506",
	Speech = "rbxassetid://129701412287354",
	Truck = "rbxassetid://81636993901645",
	House = "rbxassetid://85886816887234",
	Trophy = "rbxassetid://133883418784358",
}

-- Music: licensed tracks from the Roblox creator store (APM / DistroKid).
Assets.Music = {
	Menu = "rbxassetid://9041745502", -- 80s Horror Throwback Scary Creeper Bed
	House = "rbxassetid://138890398994853", -- Horror Cinematic Dark Scary Ambience
	Forest = "rbxassetid://98165789328752", -- Beneath the Dread Moon
	Tension = "rbxassetid://134959834418523", -- Liminal Space Creepy Music
	Station = "rbxassetid://133838630142849", -- Scary Place
	Chase = "rbxassetid://1848090337", -- Intense Chase
	Ending = "rbxassetid://1838635121", -- Sad End (Solo Piano)
}

-- Sound effects. Empty entries are skipped; fill them with your own uploads
-- (README lists ForgeGUI prompts that match each slot).
Assets.Sounds = {
	Rain = "rbxassetid://1516791621",
	Pickup = "rbxasset://sounds/electronicpingshort.wav",
	Whoosh = "rbxasset://sounds/swoosh.wav",
	KnifeDraw = "rbxasset://sounds/unsheath.wav",
	Slash = "rbxasset://sounds/swordslash.wav",
	Impact = "rbxasset://sounds/collide.wav",
	Heartbeat = "",
	Crash = "",
	Chop = "",
	DoorOpen = "",
	DoorLocked = "",
	Unlock = "",
	RopeCut = "",
	Inject = "",
	Growl = "",
	Scream = "",
	Jumpscare = "",
	EngineStart = "",
	EngineLoop = "",
	EngineFail = "",
	Explosion = "",
	Thunder = "",
	Wind = "",
	Chainsaw = "",
	Generator = "",
	Radio = "",
	HelicopterLoop = "",
	FlashlightClick = "",
	Repair = "",
	PageTurn = "",
}

return Assets

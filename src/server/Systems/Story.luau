--!strict
-- The story director: chapters, cutscenes, objectives, checkpoints and every
-- scripted event from the crash to the rescue helicopter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local HouseLayout = require(ReplicatedStorage.Shared.HouseLayout)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Util = require(ReplicatedStorage.Shared.Util)
local Build = require(script.Parent.Parent.World.Build)
local Props = require(script.Parent.Parent.World.Props)
local Terrain = require(script.Parent.Parent.World.Terrain)
local Cannibals = require(script.Parent.Cannibals)
local Cellar = require(script.Parent.Cellar)
local Chase = require(script.Parent.Chase)
local Doors = require(script.Parent.Doors)
local AssetService = require(script.Parent.AssetService)
local Interact = require(script.Parent.Interact)
local Inventory = require(script.Parent.Inventory)
local Pickups = require(script.Parent.Pickups)
local Hosts = require(script.Parent.Hosts)
local HouseLights = require(script.Parent.HouseLights)
local Investigation = require(script.Parent.Investigation)
local Crafting = require(script.Parent.Crafting)
local Polaroids = require(script.Parent.Polaroids)
local Finale = require(script.Parent.Finale)

local Story = {}

-- (new, old) every time the story moves on (Achievements)
Story.StageChanged = Signal.new() :: Signal.Signal<string, string>

-- fired once when the survivors reach the helicopter (Rewards pays out)
Story.Ended = Signal.new() :: Signal.Signal<>

export type Stage =
	"Waiting"
	| "Intro"
	| "Investigate"
	| "Captured"
	| "HouseEscape"
	| "Forest"
	| "Repair"
	| "Drive"
	| "Hunt"
	| "Power"
	| "Radio"
	| "Survive"
	| "Extraction"
	| "Downed"
	| "Wreck"
	| "Plant"
	| "Church"
	| "LastStand"
	| "Getaway"
	| "Ending"

local CHAPTERS: { [string]: { string } } = {
	Intro = { "PROLOGUE", "The Storm" },
	Investigate = { "CHAPTER I", "Investigate The House" },
	Captured = { "CHAPTER II", "They Know" },
	HouseEscape = { "CHAPTER II", "They Know" },
	Forest = { "CHAPTER III", "The Woods" },
	Repair = { "CHAPTER III", "The Woods" },
	Drive = { "CHAPTER IV", "Last Ride" },
	Hunt = { "CHAPTER V", "The Ranger Station" },
	Power = { "CHAPTER V", "The Ranger Station" },
	Radio = { "CHAPTER V", "The Ranger Station" },
	Survive = { "CHAPTER VI", "Rescue" },
	Extraction = { "CHAPTER VI", "Rescue" },
	Downed = { "CHAPTER VII", "Hard Landing" },
	Wreck = { "CHAPTER VII", "Hard Landing" },
	Plant = { "CHAPTER VIII", "Hollow Meats" },
	Church = { "CHAPTER IX", "Supper" },
	LastStand = { "CHAPTER IX", "Supper" },
	Getaway = { "CHAPTER IX", "Supper" },
	Ending = { "EPILOGUE", "Dawn" },
}

local PART_LABELS = {
	{ "Engine", "Truck engine (old barn, west)" },
	{ "CarBattery", "Car battery (hunter's camp, north)" },
	{ "SparkPlugs", "Spark plugs (doctor's trailer)" },
	{ "Tire", "Spare wheel (cemetery, east)" },
}

local stage: Stage = "Waiting"
local started = false
local house: any
local sites: any
local world: Folder

local flags = {
	keyFound = false,
	crowbarFound = false,
	boardsOff = false,
	frontDoorOpen = false,
	syringeFound = false,
	keysFound = false,
	installed = { Engine = false, CarBattery = false, SparkPlugs = false, Tire = false } :: { [string]: boolean },
	fuseIn = false,
	fueled = false,
	powerOn = false,
	surviveEnds = 0,
}

local storyRemote = Net.event("Story")
local cutsceneRemote = Net.event("Cutscene")
local subtitleRemote = Net.event("Subtitle")
local soundRemote = Net.event("Sound")
local timerRemote = Net.event("Timer")

local cutsceneDone: { [Player]: string } = {}
local currentCutscene: string? = nil
local cutsceneData: any = nil
local keyModel: Model? = nil
local crowbarModel: Model? = nil
local butcherKeysDropped = false
local helicopter: Model? = nil

---------------------------------------------------------------- helpers

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function anyPlayerWithin(position: Vector3, radius: number): Player?
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and not player:GetAttribute("InCutscene") and Util.flat(root.Position - position).Magnitude < radius then
			return player
		end
	end
	return nil
end

-- Snap a CFrame onto the terrain (spawn points away from flattened sites).
local function onGround(cf: CFrame): CFrame
	local p = cf.Position
	return Terrain.groundCFrame(p.X, p.Z)
end

local function teleportAll(cf: CFrame, anchored: boolean)
	for i, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			root.Anchored = anchored
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = cf * CFrame.new((i - 1) * 3, 0, 0)
		end
	end
end

function Story.say(speaker: string, text: string, duration: number?)
	subtitleRemote:FireAllClients(speaker, text, duration or 4)
end

---------------------------------------------------------------- objectives

type Objective = { text: string, done: boolean, optional: boolean? }

local function objectives(): { Objective }
	if Finale.handles(stage) then
		return Finale.objectives()
	end
	local list: { Objective } = {}
	local function add(text: string, done: boolean, optional: boolean?)
		table.insert(list, { text = text, done = done, optional = optional })
	end
	if stage == "Investigate" then
		return Investigation.objectives()
	end
	if stage == "Intro" or stage == "Captured" then
		add("...", false)
	elseif stage == "HouseEscape" then
		add("Find something to pry the boards off the front door", flags.crowbarFound or flags.boardsOff)
		add("Pry the boards off (it will be loud)", flags.boardsOff)
		add("Find the key to the padlock", flags.keyFound)
		add("Escape through the front door", flags.frontDoorOpen)
		for _, o in Cellar.objectives() do
			table.insert(list, o)
		end
	elseif stage == "Forest" then
		add("Get away from the house", true)
		add("Follow the logging road east to the old truck in the clearing", false)
		for _, o in Cellar.objectives() do
			if not o.done then
				table.insert(list, o)
			end
		end
	elseif stage == "Repair" then
		local count = 0
		for _, entry in PART_LABELS do
			local id, label = entry[1], entry[2]
			local done = flags.installed[id]
			if done then
				count += 1
			end
			local holding = Inventory.holder(id) ~= nil
			add(label .. (if done then " - installed" elseif holding then " - install it at the truck" else ""), done)
		end
		add("Find a sedative syringe", flags.syringeFound)
		add("Sneak up on the Butcher and take his truck keys", flags.keysFound)
		if count == 4 and flags.keysFound then
			add("Get in the truck and drive!", false)
		end
	elseif stage == "Drive" then
		add("Drive!", false)
	elseif stage == "Hunt" then
		add("RUN! Follow the marker to the ranger station", false)
		add("Dodge the red circles and the falling trees", false)
	elseif stage == "Power" then
		add("Find a fuse (fire lookout tower)", flags.fuseIn or Inventory.holder("Fuse") ~= nil)
		add("Find fuel (tool shed)", flags.fueled or Inventory.holder("GasCan") ~= nil)
		add("Replace the fuse in the utility room", flags.fuseIn)
		add("Refuel the generator", flags.fueled)
		add("Start the generator (it will be loud)", flags.powerOn)
	elseif stage == "Radio" then
		add("Call for help on the office radio", false)
	elseif stage == "Survive" then
		add("Survive until the rescue helicopter arrives", false)
		add("Hide in the lockers if they get inside", false, true)
	elseif stage == "Extraction" then
		add("Get to the helicopter!", false)
	end
	return list
end

-- Where the story wants you to go next, shown on screen with its distance.
-- Only for the big "go there" steps; searching stays up to you (and H).
local function goal(): (Vector3?, string?)
	if Finale.handles(stage) then
		return Finale.goal()
	end
	if stage == "HouseEscape" then
		if flags.crowbarFound and not flags.boardsOff then
			return house.frontDoor.center, "Pry the boards off"
		end
		if flags.keyFound and flags.boardsOff and not flags.frontDoorOpen then
			return house.frontDoor.center, "Front door"
		end
	elseif stage == "Forest" then
		return sites.truckCF.Position, "The old truck"
	elseif stage == "Hunt" then
		local next = Chase.goal()
		if next then
			return next, "RUN!"
		end
		return sites.station.center, "Ranger station"
	elseif stage == "Radio" or stage == "Survive" then
		return sites.station.center, "Ranger station"
	elseif stage == "Extraction" then
		return sites.helipad.Position, "Helipad"
	end
	return nil, nil
end

function Story.broadcast(player: Player?)
	local chapter = CHAPTERS[stage] or { "", "" }
	local goalPos, goalLabel = goal()
	local payload = {
		stage = stage,
		chapter = chapter[1],
		title = chapter[2],
		objectives = objectives(),
		goal = goalPos,
		goalLabel = goalLabel,
	}
	if player then
		storyRemote:FireClient(player, payload)
	else
		storyRemote:FireAllClients(payload)
	end
end

local function setStage(new: Stage)
	local old = stage
	stage = new
	workspace:SetAttribute("Stage", new)
	Story.broadcast()
	Story.StageChanged:Fire(new, old)
end

function Story.stage(): Stage
	return stage
end

function Story.checkpoint(): CFrame
	if Finale.handles(stage) then
		return Finale.checkpoint()
	end
	if stage == "Investigate" then
		return Investigation.spawnCF()
	elseif stage == "Waiting" or stage == "Intro" or stage == "Captured" or stage == "HouseEscape" then
		return house.spawnInside
	elseif stage == "Forest" then
		return house.spawnPorch
	elseif stage == "Repair" or stage == "Drive" then
		return sites.checkpoints.Repair
	elseif stage == "Hunt" then
		return sites.checkpoints.Hunt
	end
	return sites.checkpoints.Station
end

---------------------------------------------------------------- cutscenes

local function playCutscene(name: string, data: any, timeout: number)
	currentCutscene = name
	cutsceneData = data
	table.clear(cutsceneDone)
	Cannibals.setPaused(true)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("InCutscene", true)
	end
	cutsceneRemote:FireAllClients(name, data)
	local started = os.clock()
	while os.clock() - started < timeout do
		local waiting = false
		for _, player in Players:GetPlayers() do
			if player.Character and cutsceneDone[player] ~= name then
				waiting = true
			end
		end
		if not waiting and os.clock() - started > 1 then
			break
		end
		task.wait(0.25)
	end
	for _, player in Players:GetPlayers() do
		player:SetAttribute("InCutscene", false)
	end
	currentCutscene = nil
	Cannibals.setPaused(false)
end

-- Late joiners get the cutscene that is currently running.
-- Everyone carries a flashlight from the start (late joiners too).
local function giveFlashlight(player: Player)
	if not Inventory.has(player, "Flashlight") then
		Inventory.add(player, "Flashlight", 1, true)
		Interact.notify(player, "You have a flashlight - press F", "item")
	end
end

function Story.syncPlayer(player: Player)
	if started then
		giveFlashlight(player)
	end
	Story.broadcast(player)
	if currentCutscene then
		player:SetAttribute("InCutscene", true)
		cutsceneRemote:FireClient(player, currentCutscene, cutsceneData)
	end
end

---------------------------------------------------------------- world population

local function spawnHouseItems()
	local spots = house.spots
	local items = Build.folder(world, "Items")
	-- everyone starts with a flashlight now; a spare battery lies where it was
	Pickups.spawn("Battery", spots.Flashlight, items)
	Pickups.spawn("Syringe", spots.Syringe, items, {
		onPicked = function()
			flags.syringeFound = true
		end,
	})
	Pickups.spawn("Bandage", spots.Bandage, items)
	Pickups.spawn("Battery", spots.BatteryKitchen, items)
	Pickups.spawn("Battery", spots.BatteryLiving, items)
	Pickups.note("Ledger", spots.NoteLedger, items)
	Pickups.note("Diary", spots.NoteDiary, items)
	Pickups.note("Drawing", spots.NoteDrawing, items)
	Pickups.note("Clipping", spots.NoteClipping, items)
	-- the wings and the attic
	Pickups.spawn("Battery", spots.BatteryParlor, items)
	Pickups.spawn("Battery", spots.BatteryGuest, items)
	Pickups.spawn("Bandage", spots.BandageMudroom, items)
	Pickups.spawn("Syringe", spots.SyringeWorkshop, items, {
		onPicked = function()
			flags.syringeFound = true
		end,
	})
	Pickups.note("PianoNote", spots.NotePiano, items)
	Pickups.note("GuestDiary", spots.NoteGuest, items)
	Pickups.note("SewingList", spots.NoteSewing, items)
	Pickups.note("AtticLetter", spots.NoteAttic, items)
end

-- After the reveal they nail the front door shut from inside: pry the boards
-- off with a crowbar (hidden somewhere in the wings or the attic, different
-- every night), and it is loud enough to bring the whole family.
local function boardFrontDoor()
	local door = house.frontDoor
	local folder = Build.folder(world, "FrontDoorBoards")
	local inside = house.origin * CFrame.new(HouseLayout.at(0, 0, -23.1))
	local boards: { BasePart } = {}
	for i, y in { 2.4, 4.8, 7.2 } do
		local tilt = math.rad(({ -9, 6, -4 })[i])
		table.insert(boards, Build.part(folder, Vector3.new(6.4, 0.7, 0.3), inside * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, tilt), Color3.fromRGB(92, 72, 52), Enum.Material.WoodPlanks))
	end
	Doors.setBlocked(door, "They nailed it shut from inside. I need something to pry these boards off.")
	Interact.add(boards[2], {
		action = "Pry off the boards",
		object = "Front door",
		hold = 2.5,
		distance = 7,
		canUse = function(player)
			if not Inventory.has(player, "Crowbar") then
				soundRemote:FireClient(player, "DoorLocked")
				return false, "My hands won't do it. A crowbar, a claw hammer... anything."
			end
			return true
		end,
		onUse = function(_, prompt)
			prompt:Destroy()
			flags.boardsOff = true
			Doors.setBlocked(door, nil)
			soundRemote:FireAllClients("Chop", door.center)
			Cannibals.noise(door.center, 150)
			for _, b in boards do
				b.Anchored = false
				b.AssemblyLinearVelocity = house.origin.LookVector * 6 + Vector3.new(0, 4, 0)
				task.delay(8, function()
					b:Destroy()
				end)
			end
			Story.say("You", if flags.keyFound then "Too loud... they heard that. The padlock, NOW!" else "Too loud... they heard that. Now the padlock key.", 4)
			Story.broadcast()
		end,
	})
end

local function spawnCrowbar()
	if crowbarModel then
		return
	end
	local spot = house.crowbarSpots[math.random(1, #house.crowbarSpots)]
	crowbarModel = Pickups.spawn("Crowbar", spot, Build.folder(world, "Crowbar"), {
		onPicked = function()
			flags.crowbarFound = true
			Story.say("You", "A crowbar. The boards on the front door...", 3)
			Story.broadcast()
		end,
	})
end

-- The padlock key only turns up once the hosts drop the act (reveal),
-- so nobody can walk out of the front door during Chapter 1.
local function spawnHouseKey()
	if keyModel then
		return
	end
	local keySpot = house.keySpots[math.random(1, #house.keySpots)]
	keyModel = Pickups.spawn("HouseKey", keySpot, Build.folder(world, "HouseKey"), {
		onPicked = function(player)
			flags.keyFound = true
			Story.broadcast()
			Story.say("You", "The padlock key... the front door.", 3)
			soundRemote:FireClient(player, "Unlock")
		end,
	})
end

local function spawnForestItems()
	local spots = sites.spots
	local items = Build.folder(world, "ForestItems")
	local function partPicked(name: string)
		return function()
			Story.broadcast()
			if name == "Engine" then
				Cannibals.noise(spots.Engine.Position, 160)
				Story.say("You", "Heavy... and loud. I need to be careful.", 3)
			end
		end
	end
	Pickups.spawn("Engine", spots.Engine, items, { onPicked = partPicked("Engine") })
	Pickups.spawn("CarBattery", spots.CarBattery, items, { onPicked = partPicked("CarBattery") })
	Pickups.spawn("SparkPlugs", spots.SparkPlugs, items, { onPicked = partPicked("SparkPlugs") })
	Pickups.spawn("Tire", spots.Tire, items, { onPicked = partPicked("Tire") })
	for _, key in { "Syringe1", "Syringe2" } do
		Pickups.spawn("Syringe", spots[key], items, {
			onPicked = function()
				flags.syringeFound = true
				Story.broadcast()
			end,
		})
	end
	Pickups.spawn("Bandage", spots.CampBandage, items)
	Pickups.spawn("Battery", spots.BarnBattery, items)
	Pickups.spawn("Battery", spots.TrailerBattery, items)
	Pickups.note("BarnNote", spots.NoteBarn, items)
	Pickups.note("HunterLog", spots.NoteCamp, items)
	Pickups.note("DoctorNote", spots.NoteDoctor, items)
	-- station supplies
	Pickups.spawn("Fuse", spots.Fuse, items, { onPicked = function() Story.broadcast() end })
	Pickups.spawn("GasCan", spots.GasCan, items, { onPicked = function() Story.broadcast() end })
	Pickups.note("RangerLog", spots.NoteRanger, items)
	Pickups.spawn("Battery", spots.StationBattery, items)
	Pickups.spawn("Bandage", spots.StationBandage, items)
end

-- Junk for the workbenches and things to throw: around the house from the
-- start, at the sites in the woods and the station, rocks on the ground.
local function spawnJunk()
	local folder = Build.folder(world, "Junk")
	local houseJunk = { "Bottle", "Bottle", "Bottle", "Rag", "Rag", "Moonshine", "Moonshine", "Tape", "Tape", "AlarmClock", "AlarmClock", "Bottle" }
	local free = table.clone(house.junkSpots) :: { CFrame }
	for _, item in houseJunk do
		if #free == 0 then
			break
		end
		local spot = table.remove(free, math.random(1, #free)) :: CFrame
		Pickups.spawn(item, spot, folder, { yaw = math.random() * math.pi * 2 })
	end
	local s = sites.spots
	local woods: { { item: string, spot: CFrame?, dx: number } } = {
		{ item = "Bottle", spot = s.NoteBarn, dx = 1.4 },
		{ item = "Rag", spot = s.BarnBattery, dx = -1.2 },
		{ item = "Moonshine", spot = s.NoteCamp, dx = 1.3 },
		{ item = "Bottle", spot = s.CampBandage, dx = -1.2 },
		{ item = "Tape", spot = s.TrailerBattery, dx = 1.2 },
		{ item = "AlarmClock", spot = s.NoteDoctor, dx = -1.4 },
		{ item = "Moonshine", spot = s.StationBattery, dx = 1.2 },
		{ item = "Rag", spot = s.StationBandage, dx = -1.2 },
		{ item = "Bottle", spot = s.NoteRanger, dx = 1.3 },
	}
	for _, entry in woods do
		if entry.spot then
			Pickups.spawn(entry.item, entry.spot * CFrame.new(entry.dx, 0, 0), folder)
		end
	end
	-- rocks in a ring around the clearings
	for _, center in { sites.truckCF.Position, s.CampBandage.Position, s.Tire.Position } do
		for _ = 1, 4 do
			local a = math.random() * math.pi * 2
			local r = 10 + math.random() * 8
			local x, z = center.X + math.cos(a) * r, center.Z + math.sin(a) * r
			Pickups.spawn("Rock", CFrame.new(x, Terrain.groundY(x, z) + 0.05, z), folder, { yaw = a })
		end
	end
end

-- The family album (Polaroids): seven in the farmhouse, five out in the
-- valley; the last one is at the end of the road.
local function placePolaroids()
	local folder = Build.folder(world, "Polaroids")
	for id, cf in house.polaroidSpots do
		Polaroids.place(id, cf, folder)
	end
	local s = sites.spots
	Polaroids.place("P03", s.NoteBarn * CFrame.new(-1.3, 0, 0.3), folder)
	Polaroids.place("P04", s.NoteCamp * CFrame.new(-1.2, 0, 0.2), folder)
	Polaroids.place("P07", s.NoteDoctor * CFrame.new(1.3, 0, -0.2), folder)
	Polaroids.place("P09", s.Tire * CFrame.new(2.2, 0, 1.4), folder)
	Polaroids.place("P10", s.NoteRanger * CFrame.new(-1.3, 0, 0.2), folder)
end

---------------------------------------------------------------- truck

local function allInstalled(): boolean
	for _, v in flags.installed do
		if not v then
			return false
		end
	end
	return true
end

-- An installed part shows up on the truck: it drops into its slot.
local function showInstalled(id: string)
	local def = Items.get(id)
	local slot = sites.truckSlots[id]
	if not def or not slot or slot.Parent == nil then
		return
	end
	local model = AssetService.create(def.model)
	model.Name = "Installed_" .. id
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
		end
	end
	-- the wheel stands up on its hub; everything else sits in the bay
	local target = if id == "Tire" then slot.CFrame * CFrame.Angles(0, 0, math.rad(90)) else slot.CFrame * CFrame.new(0, -0.6, 0)
	local lifted = target * CFrame.new(0, 3, 0)
	model:PivotTo(lifted)
	model.Parent = slot.Parent
	local value = Instance.new("CFrameValue")
	value.Value = lifted
	value.Changed:Connect(function(cf)
		model:PivotTo(cf)
	end)
	local tween = TweenService:Create(value, TweenInfo.new(0.7, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Value = target })
	tween.Completed:Once(function()
		value:Destroy()
	end)
	tween:Play()
end

-- Puts in every part this player carries that the truck still needs.
local function installCarried(player: Player): number
	local count = 0
	for _, entry in PART_LABELS do
		local id = entry[1]
		if not flags.installed[id] and Inventory.has(player, id) and Inventory.remove(player, id) then
			flags.installed[id] = true
			count += 1
			task.delay((count - 1) * 0.45, showInstalled, id)
			local def = Items.get(id)
			Interact.notifyAll((if def then def.name else id) .. " installed.", "item")
		end
	end
	if count > 0 then
		local bay = sites.truckSlots.Engine
		soundRemote:FireAllClients("Repair", bay.Position)
		Cannibals.noise(bay.Position, 70)
		Story.broadcast()
		if allInstalled() then
			Story.say("You", if flags.keysFound then "That's everything. Time to go." else "It's fixed. Now I just need the keys...", 3.5)
		end
	end
	return count
end

local function missingParts(): string
	local missing = {}
	for _, entry in PART_LABELS do
		if not flags.installed[entry[1]] then
			table.insert(missing, entry[2])
		end
	end
	return table.concat(missing, ", ")
end

local function setupTruck()
	-- one prompt for the whole repair (one per slot meant only the nearest
	-- showed, usually the wrong one, so parts seemed impossible to fit)
	local repairPrompt: ProximityPrompt? = nil
	repairPrompt = Interact.add(sites.truckSlots.Engine, {
		action = "Repair",
		object = "Pickup Truck",
		hold = 2,
		distance = 11,
		canUse = function(player)
			if allInstalled() then
				return false, "It's all fixed. Find the keys and drive."
			end
			for _, entry in PART_LABELS do
				if not flags.installed[entry[1]] and Inventory.has(player, entry[1]) then
					return true
				end
			end
			return false, "Still missing: " .. missingParts()
		end,
		onUse = function(player)
			installCarried(player)
			local prompt = repairPrompt
			if prompt and allInstalled() then
				prompt.Enabled = false
			end
		end,
	})

	Interact.add(sites.truckDoor, {
		action = "Drive",
		object = "Pickup Truck",
		hold = 1,
		distance = 8,
		canUse = function(player)
			if stage ~= "Repair" and stage ~= "Forest" then
				return false, nil
			end
			if not allInstalled() then
				local missing = {}
				for _, entry in PART_LABELS do
					if not flags.installed[entry[1]] then
						local def = Items.get(entry[1])
						table.insert(missing, if def then def.name else entry[1])
					end
				end
				return false, "It won't run. Missing: " .. table.concat(missing, ", ")
			end
			if not Inventory.has(player, "TruckKeys") then
				return false, "It's locked. The Butcher has the keys."
			end
			return true
		end,
		onUse = function()
			task.spawn(Story.startDrive)
		end,
	})
end

local function onSedated(c: Cannibals.Cannibal, player: Player)
	if c.hasKeys and not butcherKeysDropped then
		butcherKeysDropped = true
		c.hasKeys = false
		local belt = c.model:FindFirstChild("BeltKeys", true)
		if belt then
			belt:Destroy()
		end
		local drop = CFrame.new(c.root.Position + c.root.CFrame.RightVector * 2.5)
		local y = Terrain.groundY(drop.Position.X, drop.Position.Z)
		Pickups.spawn("TruckKeys", CFrame.new(drop.Position.X, y + 0.1, drop.Position.Z), world, {
			onPicked = function()
				flags.keysFound = true
				Story.broadcast()
				Story.say("You", "Got them. Now get back to the truck before he wakes up.", 3.5)
			end,
		})
		Interact.notify(player, "The keys fell from his belt!", "item")
	end
end

---------------------------------------------------------------- chapter transitions

-- After the reveal the two of them start outside, circling the house. They
-- come in once they know where you are (a noise, a glimpse through a window)
-- or after a while, crashing in through the back.
local function spawnHouseCannibals()
	local outside: { Vector3 } = {}
	-- a ring outside the walls (house plan, HouseLayout), wings included
	for _, p in {
		Vector2.new(0, -37),
		Vector2.new(-50, -31),
		Vector2.new(-75, 0),
		Vector2.new(-50, 31),
		Vector2.new(0, 35),
		Vector2.new(50, 31),
		Vector2.new(75, 0),
		Vector2.new(50, -31),
	} do
		local w = house.origin * CFrame.new(HouseLayout.at(p.X, 0, p.Y))
		table.insert(outside, Vector3.new(w.X, Terrain.groundY(w.X, w.Z), w.Z))
	end
	local otherWay: { Vector3 } = {}
	for i = #outside, 1, -1 do
		table.insert(otherWay, outside[i])
	end
	local butcher = Cannibals.spawn("Butcher", CFrame.new(outside[1]), { patrol = outside })
	local brother = Cannibals.spawn("Brother", CFrame.new(otherWay[2]), { patrol = otherWay })
	local difficulty = workspace:GetAttribute("Difficulty")
	local wait = if difficulty == "Easy" then 75 elseif difficulty == "Hard" then 40 elseif difficulty == "Nightmare" then 25 else 55
	task.spawn(function()
		local deadline = os.clock() + wait
		while stage == "HouseEscape" and os.clock() < deadline do
			task.wait(0.5)
			local alerted = false
			for _, c in { butcher, brother } do
				if c.alive and c.state ~= "Patrol" and c.state ~= "Idle" then
					alerted = true
				end
			end
			if alerted then
				break
			end
		end
		if stage ~= "HouseEscape" then
			return
		end
		local backDoor = (house.origin * CFrame.new(HouseLayout.at(1, 4, 23))).Position
		soundRemote:FireAllClients("Impact", backDoor)
		soundRemote:FireAllClients("DoorOpen", backDoor)
		soundRemote:FireAllClients("Growl", backDoor)
		Story.say("You", "The back door just crashed in... they're inside the house.", 4)
		if butcher.alive then
			Cannibals.relocate(butcher, CFrame.new(house.groundPatrol[1]), house.groundPatrol)
		end
		if brother.alive then
			Cannibals.relocate(brother, CFrame.new(house.upperPatrol[1]), house.upperPatrol)
		end
	end)
	return butcher
end

local function enterForest()
	setStage("Forest")
	Story.say("You", "I'm out! There was an old pickup in a clearing up the logging road... if it still runs, that's my way out.", 5)
	-- the Butcher heads into the woods; the brother stays in the house
	local butcher = Cannibals.find("Butcher")
	if butcher then
		local route = sites.patrols.Butcher
		Cannibals.relocate(butcher, CFrame.new(route[1]), route)
	end
	Cannibals.spawn("Hunter", CFrame.new(sites.patrols.Hunter[1]), { patrol = sites.patrols.Hunter })
	Cannibals.spawn("Scavenger", CFrame.new(sites.patrols.Scavenger[1]), { patrol = sites.patrols.Scavenger })
end

local function enterRepair()
	playCutscene("TruckFound", { truck = sites.truckCF }, 14)
	setStage("Repair")
	Story.say("You", "The engine's gone... battery, plugs, a wheel. And that butcher had keys on his belt.", 5)
end

-- End of the chase: in through the station door, slam it, bolt it. The
-- monster pounds on it and then goes quiet... for now.
local enterPower: () -> () = function() end
local function reachStation()
	if stage ~= "Hunt" then
		return
	end
	local door = sites.station.door
	Cannibals.setPaused(true)
	Doors.setOpen(door, false)
	playCutscene("DoorLock", { door = door.hinge, center = sites.station.center }, 28)
	teleportAll(sites.checkpoints.Station, false)
	Cannibals.setPaused(false)
	-- it lost you behind the door; they all fall back to circling the station
	for _, c in Cannibals.all() do
		c.speedMult = 1
	end
	enterPower()
end

-- The siege: the monster smashes the station door in.
local function breakStationDoor()
	local door = sites.station.door
	local inward = (sites.station.center - door.center).Unit
	door.locked = true -- it's gone, there's nothing left to open
	for _, entry in door.parts do
		local p = entry.part
		p.Anchored = false
		p.CanCollide = true
		p.AssemblyLinearVelocity = inward * 55 + Vector3.new(math.random(-8, 8), 18, math.random(-8, 8))
		p.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
		task.delay(8, function()
			p:Destroy()
		end)
	end
	if door.prompt then
		(door.prompt :: ProximityPrompt).Enabled = false
	end
	soundRemote:FireAllClients("Explosion", door.center)
	soundRemote:FireAllClients("Growl", door.center)
	Story.say("You", "THE DOOR! It's coming through the door!", 3.5)
	local butcher = Cannibals.find("Butcher")
	local outside = door.center - inward * 6
	if butcher then
		Cannibals.relocate(butcher, CFrame.new(Vector3.new(outside.X, Terrain.groundY(outside.X, outside.Z), outside.Z)), { sites.station.center })
		butcher.hunting = true
	else
		Cannibals.spawn("Butcher", CFrame.new(Vector3.new(outside.X, Terrain.groundY(outside.X, outside.Z), outside.Z)), { hunting = true })
	end
end

function Story.startDrive()
	if stage ~= "Repair" and stage ~= "Forest" then
		return
	end
	setStage("Drive")
	Inventory.remove(Inventory.holder("TruckKeys") or Players:GetPlayers()[1], "TruckKeys")
	local path = {}
	for _, p in Config.DrivePath do
		table.insert(path, p)
	end
	playCutscene("Drive", { truck = sites.truck, truckCF = sites.truckCF, path = path, wreck = sites.wreck }, 75)

	-- the truck burns where the engine blew
	local truck: Model = sites.truck
	truck:PivotTo(sites.wreck * CFrame.Angles(0, math.rad(25), math.rad(4)))
	for _, p in truck:GetDescendants() do
		if p:IsA("BasePart") then
			p.Color = p.Color:Lerp(Color3.fromRGB(20, 18, 16), 0.65)
		end
	end
	local fireAnchor = Build.part(world, Vector3.new(4, 2, 4), sites.wreck * CFrame.new(0, 4, -5), Color3.fromRGB(255, 90, 30), Enum.Material.Neon, {
		Transparency = 0.6,
		CanCollide = false,
	})
	Build.fire(fireAnchor, 12, true)

	Cannibals.clear()
	setStage("Hunt")
	teleportAll(Story.checkpoint(), false)
	local target = Players:GetPlayers()[1]
	local base = sites.wreck
	-- Jason comes out of the fire as the monster and runs you down to the
	-- ranger station (Chase.luau); the rest of the family is out in the trees
	local butcher = Cannibals.spawn("Butcher", onGround(base * CFrame.new(0, 0, 28)), { hunting = true, chase = target })
	Cannibals.spawn("Papa", onGround(base * CFrame.new(0, 0, 70)), { hunting = true })
	Cannibals.spawn("Kin", onGround(base * CFrame.new(-40, 0, 40)), { hunting = true })
	Story.say("You", "It's coming out of the fire... RUN! The ranger station - past the lookout tower!", 4)
	local waypoints: { Vector3 } = {}
	for _, p in { Vector2.new(330, 230), Vector2.new(280, 330), Vector2.new(340, 420), Vector2.new(420, 405), Vector2.new(470, 382) } do
		table.insert(waypoints, Vector3.new(p.X, Terrain.groundY(p.X, p.Y), p.Y))
	end
	Chase.start(world, waypoints, sites.station.door.center, butcher, function()
		task.spawn(reachStation)
	end, function()
		Story.broadcast()
	end)
end

enterPower = function()
	setStage("Power")
	Story.say("You", "Ranger station... no power. The log said the fuse is in the tower, fuel in the shed.", 5)
	for _, c in Cannibals.all() do
		c.hunting = false
		if c.state ~= "Chase" then
			Cannibals.relocate(c, CFrame.new(sites.patrols.Station[math.random(1, #sites.patrols.Station)]), sites.patrols.Station)
		end
	end
end

local function setupStation()
	local st = sites.station
	local fusePrompt = Interact.add(st.fuseBox, {
		action = "Replace Fuse",
		object = "Fuse Box",
		hold = 1.5,
		canUse = function(player)
			if flags.fuseIn then
				return false, "The fuse is in."
			end
			if not Inventory.has(player, "Fuse") then
				return false, "A fuse is blown. I need a replacement."
			end
			return true
		end,
		onUse = function(player, prompt)
			Inventory.remove(player, "Fuse")
			flags.fuseIn = true
			prompt.Enabled = false
			local lamp = st.fuseBox.Parent and st.fuseBox.Parent:FindFirstChild("FuseLamp")
			if lamp and lamp:IsA("BasePart") then
				lamp.Color = Color3.fromRGB(60, 255, 90)
			end
			Interact.notifyAll("Fuse replaced.", "item")
			Story.broadcast()
		end,
	})
	local _ = fusePrompt

	local genPrompt: ProximityPrompt
	genPrompt = Interact.add(st.generatorPart, {
		action = "Refuel",
		object = "Generator",
		hold = 2,
		canUse = function(player)
			if flags.powerOn then
				return false, "It's running."
			end
			if not flags.fueled then
				if not Inventory.has(player, "GasCan") then
					return false, "The tank is bone dry. I need fuel."
				end
				return true
			end
			if not flags.fuseIn then
				return false, "No point starting it with a blown fuse."
			end
			return true
		end,
		onUse = function(player)
			if not flags.fueled then
				Inventory.remove(player, "GasCan")
				flags.fueled = true
				genPrompt.ActionText = "Start"
				genPrompt.HoldDuration = 3
				soundRemote:FireAllClients("Repair", st.generatorPart.Position)
				Interact.notifyAll("Generator refueled.", "item")
				Story.broadcast()
				return
			end
			flags.powerOn = true
			genPrompt.Enabled = false
			soundRemote:FireAllClients("Generator", st.generatorPart.Position)
			for _, light in st.lights do
				light.Enabled = true
			end
			for _, lamp in st.lamps do
				lamp.Material = Enum.Material.Neon
				lamp.Color = Color3.fromRGB(255, 236, 200)
			end
			local panelLamp = st.generator:FindFirstChild("Lamp", true)
			if panelLamp and panelLamp:IsA("BasePart") then
				panelLamp.Color = Color3.fromRGB(60, 255, 90)
			end
			Cannibals.noise(st.center, 260)
			Story.say("You", "Power's on. They definitely heard that... the radio, now!", 4)
			setStage("Radio")
		end,
	})

	Interact.add(st.radio, {
		action = "Use Radio",
		object = "Field Radio",
		hold = 1,
		canUse = function()
			if stage ~= "Radio" then
				return false, if flags.powerOn then nil else "Dead. No power."
			end
			return true
		end,
		onUse = function()
			task.spawn(Story.startSurvive)
		end,
	})
end

local function spawnHelicopter()
	local heli = Props.Helicopter()
	heli.Name = "RescueHelicopter"
	local pad: CFrame = sites.helipad
	local landed = pad * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.rad(200), 0)
	local high = landed * CFrame.new(0, 140, 160)
	heli:PivotTo(high)
	heli.Parent = world
	helicopter = heli
	for _, lamp in sites.helipadLights do
		lamp.Material = Enum.Material.Neon
		lamp.Color = Color3.fromRGB(120, 255, 140)
		local light = lamp:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = true
		end
	end
	soundRemote:FireAllClients("HelicopterLoop", pad.Position)
	local rotor = heli:FindFirstChild("Rotor") :: Model?
	local rotorParts = {}
	if rotor then
		for _, p in rotor:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(rotorParts, { part = p, offset = heli:GetPivot():ToObjectSpace(p.CFrame) })
			end
		end
	end
	local mast = Vector3.new(0, 9.7, 0)
	local t0 = os.clock()
	local flight = 10
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not heli.Parent then
			conn:Disconnect()
			return
		end
		local t = math.min((os.clock() - t0) / flight, 1)
		local eased = 1 - (1 - t) ^ 3
		local body = high:Lerp(landed, eased)
		heli:PivotTo(body)
		local spin = CFrame.new(mast) * CFrame.Angles(0, os.clock() * 25, 0) * CFrame.new(-mast)
		for _, entry in rotorParts do
			entry.part.CFrame = body * spin * entry.offset
		end
	end)
end

function Story.startSurvive()
	if stage ~= "Radio" then
		return
	end
	playCutscene("Radio", { radio = sites.station.radio.CFrame }, 30)
	setStage("Survive")
	flags.surviveEnds = os.clock() + Config.SurviveDuration
	-- a few seconds of quiet, then it comes through the door
	task.delay(7, function()
		if (stage :: Stage) == "Survive" then
			playCutscene("DoorBreak", { door = sites.station.door.hinge, center = sites.station.center }, 16)
			breakStationDoor()
		end
	end)
	local papa = Cannibals.find("Papa")
	if papa then
		papa.hunting = true
	end
	task.spawn(function()
		local nextWave = os.clock() + 8
		while (stage :: Stage) == "Survive" do
			local remaining = flags.surviveEnds - os.clock()
			timerRemote:FireAllClients(remaining)
			if remaining <= 0 then
				break
			end
			if os.clock() >= nextWave and #Cannibals.all() < 6 then
				nextWave = os.clock() + 22
				local spawn = sites.surviveSpawns[math.random(1, #sites.surviveSpawns)]
				Cannibals.spawn("Kin", spawn, { hunting = true })
				Story.say("Dispatch", "...hold on, we're inbound...", 2)
			end
			task.wait(1)
		end
		timerRemote:FireAllClients(nil)
		spawnHelicopter()
		setStage("Extraction")
		Story.say("Pilot", "Pinecrest Rescue on station! Get to the pad, NOW!", 4)
	end)
end

-- The very end (Finale: in the police car on Pinecrest's Main Street). The true
-- ending is everyone out: Ranger Ellis from the cellar and the pilot too.
local function startEnding(trueEnding: boolean)
	setStage("Ending")
	Story.Ended:Fire()
	local data = Finale.endingData(trueEnding)
	Cannibals.clear()
	playCutscene("Dawn", data, 32)
	Net.event("Ending"):FireAllClients(if trueEnding then "true" else "normal")
end

function Story.trueEnding(): boolean
	return Finale.trueEnding()
end

---------------------------------------------------------------- main sequence

-- End of Chapter 1: Jason and Michel drop the act and the hunt begins (the
-- house escape that follows is the existing Chapter 2 flow).
local function reveal()
	if stage ~= "Investigate" then
		return
	end
	Investigation.finish()
	Doors.unlock(house.slaughterDoor)
	playCutscene("TheyKnow", Investigation.revealData(), 30)
	setStage("HouseEscape")
	spawnHouseKey()
	spawnCrowbar()
	boardFrontDoor()
	Cellar.enable(Story.say, function()
		Story.broadcast()
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("SafeUntil", os.clock() + 8)
		Inventory.add(player, "Knife", 1, true)
	end
	spawnHouseCannibals()
	Story.say("You", "They know. The front door's padlocked and nailed shut... I need the key and something to pry it open. MOVE!", 5.5)
end

function Story.begin()
	if started then
		return
	end
	started = true
	for _, player in Players:GetPlayers() do
		giveFlashlight(player)
	end
	task.spawn(function()
		setStage("Intro")
		playCutscene("Crash", {
			sedan = sites.sedan,
			tree = sites.crashTree,
			truck = sites.truck,
			truckCF = sites.truckCF,
			house = house.origin,
		}, 75)

		-- Chapter 1: two friendly strangers pulled us out of the wreck. The
		-- slaughter room stays locked while they play nice.
		house.slaughterDoor.locked = true
		Doors.setOpen(house.slaughterDoor, false)
		setStage("Investigate")
		teleportAll(Investigation.spawnCF(), true)
		playCutscene("WakeUp", Investigation.wakeData(), 90)
		teleportAll(Investigation.spawnCF(), false)
		Story.say("You", "Where am I...? Everyone's alright... I think.", 3.5)
		Investigation.start(world, {
			say = Story.say,
			changed = function()
				Story.broadcast()
			end,
			onComplete = function()
				task.spawn(reveal)
			end,
		})
	end)
end

local function watcher()
	while true do
		task.wait(0.5)
		if stage == "HouseEscape" and flags.frontDoorOpen then
			-- outside once past the porch steps
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root then
					local localPos = HouseLayout.unmap(house.origin:PointToObjectSpace(root.Position))
					if localPos.Z < -36 or math.abs(localPos.X) > 72 or localPos.Z > 32 then
						enterForest()
						break
					end
				end
			end
		elseif stage == "Forest" then
			if anyPlayerWithin(sites.truckCF.Position, 34) then
				enterRepair()
			end
		elseif stage == "Hunt" then
			if not Chase.running() and anyPlayerWithin(sites.station.center, 48) then
				enterPower()
			end
		elseif stage == "Extraction" then
			if anyPlayerWithin(sites.helipad.Position, 16) then
				-- the rescue is not the end: on to the last act
				task.spawn(Finale.takeoff)
			end
		elseif Finale.handles(stage) then
			Finale.watch()
		end
	end
end

---------------------------------------------------------------- hints

function Story.hintTargets(): { Vector3 }
	local list: { Vector3 } = {}
	if Finale.handles(stage) then
		return Finale.hintTargets()
	end
	if stage == "Investigate" then
		return Investigation.hintTargets()
	elseif stage == "HouseEscape" then
		-- one thing at a time: the crowbar, then the key, then the door
		if not flags.crowbarFound and not flags.boardsOff and crowbarModel and crowbarModel.Parent then
			table.insert(list, crowbarModel:GetPivot().Position)
		elseif not flags.keyFound and keyModel and keyModel.Parent then
			table.insert(list, keyModel:GetPivot().Position)
		else
			table.insert(list, house.frontDoor.center)
		end
		for _, p in Cellar.hintTargets() do
			table.insert(list, p)
		end
	elseif stage == "Forest" then
		table.insert(list, sites.truckCF.Position)
	elseif stage == "Repair" then
		for _, entry in PART_LABELS do
			local id = entry[1]
			if not flags.installed[id] then
				if Inventory.holder(id) then
					table.insert(list, sites.truckSlots[id].Position)
				else
					local spot = sites.spots[id]
					if spot then
						table.insert(list, spot.Position)
					end
				end
			end
		end
		if not flags.keysFound then
			local butcher = Cannibals.find("Butcher")
			if butcher and Inventory.holder("Syringe") then
				table.insert(list, butcher.root.Position)
			elseif not Inventory.holder("Syringe") then
				table.insert(list, sites.spots.Syringe1.Position)
			end
		end
		if allInstalled() and flags.keysFound then
			list = { sites.truckDoor.Position }
		end
	elseif stage == "Hunt" or stage == "Radio" or stage == "Survive" then
		table.insert(list, sites.station.center)
	elseif stage == "Power" then
		if not flags.fuseIn then
			table.insert(list, if Inventory.holder("Fuse") then sites.station.fuseBox.Position else sites.spots.Fuse.Position)
		end
		if not flags.fueled then
			table.insert(list, if Inventory.holder("GasCan") then sites.station.generatorPart.Position else sites.spots.GasCan.Position)
		elseif flags.fuseIn then
			table.insert(list, sites.station.generatorPart.Position)
		end
	elseif stage == "Extraction" then
		table.insert(list, sites.helipad.Position)
	end
	return list
end

---------------------------------------------------------------- init

function Story.init(houseInfo: any, siteInfo: any, worldFolder: Folder, finaleSites: any)
	house = houseInfo
	sites = siteInfo
	world = worldFolder
	Finale.init({
		say = Story.say,
		broadcast = function()
			Story.broadcast()
		end,
		setStage = function(s: string)
			setStage(s :: any)
		end,
		playCutscene = playCutscene,
		teleportAll = teleportAll,
		helicopter = function()
			return helicopter
		end,
		finish = startEnding,
		world = worldFolder,
	}, finaleSites)

	-- front door hook
	house.frontDoor.onOpened = function()
		if not flags.frontDoorOpen then
			flags.frontDoorOpen = true
			if house.padlock then
				house.padlock:Destroy()
			end
			Story.broadcast()
		end
	end

	Hosts.publishTemplates()
	-- room lights + switches; the breaker only works once the act is over
	HouseLights.build(house.origin, world, function()
		return stage ~= "Investigate" and stage ~= "Intro"
	end)
	Investigation.prepare(house.origin, world)
	Cellar.build(house.origin, world, Investigation.hatch())
	spawnHouseItems()
	spawnForestItems()
	spawnJunk()
	placePolaroids()
	-- workbenches: the farmhouse workshop, and any bench a site has
	Crafting.addBenchAt(house.workbench, world, "Workbench")
	for _, d in world:GetDescendants() do
		if d.Name == "Workbench" and d:IsA("BasePart") then
			Crafting.addBench(d)
		end
	end
	setupTruck()
	setupStation()
	Cannibals.Sedated:Connect(onSedated)

	Inventory.Changed:Connect(function()
		Story.broadcast()
	end)
	-- someone left with a quest item: drop it where they stood so nobody
	-- else gets stuck without it
	Inventory.Lost:Connect(function(_player, carried, where)
		local spot = where or Story.checkpoint().Position
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = {}
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		params.FilterDescendantsInstances = ignore
		local i = 0
		for id, count in carried do
			local def = Items.get(id)
			if def and def.questItem and count > 0 and not (flags.installed[id] == true) then
				i += 1
				local offset = Vector3.new(math.cos(i * 2.1) * 2, 0, math.sin(i * 2.1) * 2)
				local hit = workspace:Raycast(spot + offset + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), params)
				local floor = if hit then hit.Position else spot + offset
				Pickups.spawn(id, CFrame.new(floor + Vector3.new(0, 0.3, 0)), world)
			end
		end
		if i > 0 then
			Interact.notifyAll("Someone dropped what they were carrying. It's still out there.", "warn")
			Story.broadcast()
		end
	end)

	Net.event("CutsceneDone").OnServerEvent:Connect(function(player, name)
		if typeof(name) == "string" then
			cutsceneDone[player] = name
		end
	end)
	Net.event("RequestHint").OnServerEvent:Connect(function(player)
		Net.event("Hint"):FireClient(player, Story.hintTargets())
	end)
	task.spawn(watcher)
end

return Story

--!strict
-- The story director: chapters, cutscenes, objectives, checkpoints and every
-- scripted event from the crash to the rescue helicopter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Build = require(script.Parent.Parent.World.Build)
local Props = require(script.Parent.Parent.World.Props)
local Terrain = require(script.Parent.Parent.World.Terrain)
local Cannibals = require(script.Parent.Cannibals)
local Doors = require(script.Parent.Doors)
local Interact = require(script.Parent.Interact)
local Inventory = require(script.Parent.Inventory)
local Pickups = require(script.Parent.Pickups)

local Story = {}

export type Stage =
	"Waiting"
	| "Intro"
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
	| "Ending"

local CHAPTERS: { [string]: { string } } = {
	Intro = { "PROLOGUE", "Hollow Road" },
	Captured = { "CHAPTER I", "The Butcher's House" },
	HouseEscape = { "CHAPTER I", "The Butcher's House" },
	Forest = { "CHAPTER II", "The Woods" },
	Repair = { "CHAPTER II", "The Woods" },
	Drive = { "CHAPTER III", "Last Ride" },
	Hunt = { "CHAPTER IV", "The Ranger Station" },
	Power = { "CHAPTER IV", "The Ranger Station" },
	Radio = { "CHAPTER IV", "The Ranger Station" },
	Survive = { "CHAPTER V", "Rescue" },
	Extraction = { "CHAPTER V", "Rescue" },
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
	frontDoorOpen = false,
	flashlightFound = false,
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
	local list: { Objective } = {}
	local function add(text: string, done: boolean, optional: boolean?)
		table.insert(list, { text = text, done = done, optional = optional })
	end
	if stage == "Intro" or stage == "Captured" then
		add("...", false)
	elseif stage == "HouseEscape" then
		add("Find a light source", flags.flashlightFound, true)
		add("Find the key to the padlock (upstairs?)", flags.keyFound)
		add("Escape through the front door", flags.frontDoorOpen)
	elseif stage == "Forest" then
		add("Get away from the house", true)
		add("Follow the logging road east to find a way out", false)
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
		add("RUN. Reach the ranger station to the north-east", false)
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

function Story.broadcast(player: Player?)
	local chapter = CHAPTERS[stage] or { "", "" }
	local payload = {
		stage = stage,
		chapter = chapter[1],
		title = chapter[2],
		objectives = objectives(),
	}
	if player then
		storyRemote:FireClient(player, payload)
	else
		storyRemote:FireAllClients(payload)
	end
end

local function setStage(new: Stage)
	stage = new
	workspace:SetAttribute("Stage", new)
	Story.broadcast()
end

function Story.stage(): Stage
	return stage
end

function Story.checkpoint(): CFrame
	if stage == "Waiting" or stage == "Intro" or stage == "Captured" or stage == "HouseEscape" then
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
function Story.syncPlayer(player: Player)
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
	Pickups.spawn("Flashlight", spots.Flashlight, items, {
		onPicked = function()
			flags.flashlightFound = true
			Story.broadcast()
		end,
	})
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
	local keySpot = house.keySpots[math.random(1, #house.keySpots)]
	keyModel = Pickups.spawn("HouseKey", keySpot, items, {
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

---------------------------------------------------------------- truck

local function allInstalled(): boolean
	for _, v in flags.installed do
		if not v then
			return false
		end
	end
	return true
end

local function setupTruck()
	for id, slot in sites.truckSlots do
		local def = Items.get(id)
		local label = if def then def.name else id
		Interact.add(slot, {
			action = "Install",
			object = label,
			hold = 2.5,
			distance = 9,
			canUse = function(player)
				if flags.installed[id] then
					return false, label .. " is already installed."
				end
				if not Inventory.has(player, id) then
					return false, "The truck is missing its " .. string.lower(label) .. "."
				end
				return true
			end,
			onUse = function(player, prompt)
				if Inventory.remove(player, id) then
					flags.installed[id] = true
					prompt.Enabled = false
					soundRemote:FireAllClients("Repair", slot.Position)
					Interact.notifyAll(label .. " installed.", "item")
					Cannibals.noise(slot.Position, 70)
					Story.broadcast()
					if allInstalled() then
						Story.say("You", if flags.keysFound then "That's everything. Time to go." else "It's fixed. Now I just need the keys...", 3.5)
					end
				end
			end,
		})
	end

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

local function spawnHouseCannibals()
	local butcher = Cannibals.spawn("Butcher", CFrame.new(house.groundPatrol[1]), { patrol = house.groundPatrol })
	Cannibals.spawn("Brother", CFrame.new(house.upperPatrol[1]), { patrol = house.upperPatrol })
	return butcher
end

local function enterForest()
	setStage("Forest")
	Story.say("You", "I'm out... I need to find a way out of these woods.", 3.5)
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
	Cannibals.spawn("Papa", onGround(base * CFrame.new(0, 0, 55)), { hunting = true, chase = target })
	Cannibals.spawn("Kin", onGround(base * CFrame.new(-40, 0, 40)), { hunting = true })
	Cannibals.spawn("Kin", onGround(base * CFrame.new(45, 0, 30)), { hunting = true })
	Story.say("Papa", "YOU BROKE MY TRUCK!", 3)
end

local function enterPower()
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

local function startEnding()
	setStage("Ending")
	playCutscene("Ending", { helicopter = helicopter, pad = sites.helipad }, 60)
	Cannibals.clear()
	Net.event("Ending"):FireAllClients()
end

---------------------------------------------------------------- main sequence

function Story.begin()
	if started then
		return
	end
	started = true
	task.spawn(function()
		setStage("Intro")
		playCutscene("Crash", {
			sedan = sites.sedan,
			tree = sites.crashTree,
			trapLog = sites.trapLog,
			house = house.origin,
		}, 60)

		setStage("Captured")
		teleportAll(house.chairSeat, true)
		local brother = house.actors.brother
		playCutscene("WakeUp", {
			eye = house.chairEye,
			seat = house.chairSeat,
			tableTop = house.tableTop,
			butcher = house.actors.butcher,
			brother = brother,
			exit = house.actors.exit,
			doorway = house.actors.doorway,
			knife = house.knife,
			chair = house.chair,
			body = house.body,
		}, 90)

		-- the ropes are cut, the knife is ours
		if house.knife then
			house.knife:Destroy()
		end
		for _, d in house.chair:GetDescendants() do
			if d.Name == "Rope" then
				d:Destroy()
			end
		end
		house.chair:SetAttribute("Mesh", "Chair")
		for _, player in Players:GetPlayers() do
			Inventory.add(player, "Knife", 1, true)
		end
		Doors.setOpen(house.slaughterDoor, false)
		setStage("HouseEscape")
		teleportAll(house.spawnInside, false)
		spawnHouseCannibals()
		Story.say("You", "I have to get out of here. That door was chained... I need a key.", 4)
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
					local localPos = house.origin:PointToObjectSpace(root.Position)
					if localPos.Z < -36 or math.abs(localPos.X) > 40 or localPos.Z > 32 then
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
			if anyPlayerWithin(sites.station.center, 48) then
				enterPower()
			end
		elseif stage == "Extraction" then
			if anyPlayerWithin(sites.helipad.Position, 16) then
				startEnding()
			end
		end
	end
end

---------------------------------------------------------------- hints

function Story.hintTargets(): { Vector3 }
	local list: { Vector3 } = {}
	if stage == "HouseEscape" then
		if not flags.keyFound and keyModel and keyModel.Parent then
			table.insert(list, keyModel:GetPivot().Position)
		else
			table.insert(list, house.frontDoor.center)
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

function Story.init(houseInfo: any, siteInfo: any, worldFolder: Folder)
	house = houseInfo
	sites = siteInfo
	world = worldFolder

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

	spawnHouseItems()
	spawnForestItems()
	setupTruck()
	setupStation()
	Cannibals.Sedated:Connect(onSedated)

	Inventory.Changed:Connect(function()
		Story.broadcast()
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

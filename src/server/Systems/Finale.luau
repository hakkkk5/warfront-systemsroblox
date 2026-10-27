--!strict
-- The last act, after the rescue helicopter (World/FinaleSites has the
-- places). Story hands over when everyone reaches the helicopter:
--
--   Downed     the helicopter is brought down over the woods (cutscene)
--   Wreck      CHAPTER VII  Hard Landing: search the wreck, the pilot is
--              gone; follow the drag marks to the plant
--   Plant      CHAPTER VIII Hollow Meats: throw the three breakers, find the
--              foreman's keycard, (cut the pilot down in cold storage), and
--              get through the mine door out back
--   Church     CHAPTER IX   Supper: you come up in the crypt under Pinecrest's
--              church; find the crypt key, climb the tower, ring the bell
--   LastStand  the bell brings the whole family: hold out until the state
--              police get there
--   Getaway    run for the cruiser on Main Street
--
-- The true ending needs Ranger Ellis (the cellar) and the pilot both saved.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Build = require(script.Parent.Parent.World.Build)
local FinaleSites = require(script.Parent.Parent.World.FinaleSites)
local Props = require(script.Parent.Parent.World.Props)
local Cannibals = require(script.Parent.Cannibals)
local Cellar = require(script.Parent.Cellar)
local Crafting = require(script.Parent.Crafting)
local Doors = require(script.Parent.Doors)
local Interact = require(script.Parent.Interact)
local Inventory = require(script.Parent.Inventory)
local Pickups = require(script.Parent.Pickups)
local Polaroids = require(script.Parent.Polaroids)

local Finale = {}

export type Objective = { text: string, done: boolean, optional: boolean? }

export type Ctx = {
	say: (speaker: string, text: string, duration: number?) -> (),
	broadcast: () -> (),
	setStage: (stage: string) -> (),
	playCutscene: (name: string, data: any, timeout: number) -> (),
	teleportAll: (cf: CFrame, anchored: boolean) -> (),
	helicopter: () -> Model?,
	finish: (trueEnding: boolean) -> (),
	world: Folder,
}

local STAGES = { Downed = true, Wreck = true, Plant = true, Church = true, LastStand = true, Getaway = true }
local HOLD_OUT = 90

local ctx: Ctx
local places: FinaleSites.Info
local stage = ""
local flags = {
	searched = false,
	breakers = { false, false, false },
	power = false,
	keycard = false,
	pilotFreed = false,
	mineOpen = false,
	cryptKey = false,
	cryptOpen = false,
	bellRung = false,
	holdUntil = 0,
	cruiser = false,
	finished = false,
}
local keycardModel: Model? = nil
local cryptKeyModel: Model? = nil
local cruiser: Model? = nil
local soundRemote = Net.event("Sound")

function Finale.handles(s: string): boolean
	return STAGES[s] == true
end

function Finale.trueEnding(): boolean
	return flags.pilotFreed and Cellar.rescued()
end

-- What the closing cutscene (Dawn) needs.
function Finale.endingData(trueEnding: boolean): any
	return { cruiser = cruiser, church = places.church.origin, trueEnding = trueEnding }
end

local function rootOf(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function anyWithin(position: Vector3, radius: number): boolean
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and (root.Position - position).Magnitude < radius then
			return true
		end
	end
	return false
end

local function setStage(s: string)
	stage = s
	ctx.setStage(s)
end

local function breakersDown(): number
	local n = 0
	for _, b in flags.breakers do
		if b then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------- objectives

function Finale.objectives(): { Objective }
	local list: { Objective } = {}
	local function add(text: string, done: boolean, optional: boolean?)
		table.insert(list, { text = text, done = done, optional = optional })
	end
	if stage == "Downed" then
		add("...", false)
	elseif stage == "Wreck" then
		add("Search the wreck", flags.searched)
		add("Follow the drag marks south", false)
	elseif stage == "Plant" then
		add(string.format("Throw the breakers (%d/3)", breakersDown()), flags.power)
		add("Find the foreman's keycard", flags.keycard or flags.mineOpen)
		add("Cut the pilot down in cold storage", flags.pilotFreed, true)
		add("Get through the mine door at the back", flags.mineOpen)
	elseif stage == "Church" then
		add("Find the key to the crypt gate", flags.cryptKey or flags.cryptOpen)
		add("Get out of the crypt", flags.cryptOpen)
		add("Climb the bell tower and ring the bell", flags.bellRung)
	elseif stage == "LastStand" then
		add("Hold out until the police get here", false)
	elseif stage == "Getaway" then
		add("Get to the police car on Main Street", false)
	end
	return list
end

function Finale.goal(): (Vector3?, string?)
	if stage == "Wreck" and flags.searched then
		return places.plant.gate, "Hollow Meats"
	elseif stage == "Plant" and flags.mineOpen then
		return places.plant.minePortal, "The mine"
	elseif stage == "Church" and flags.cryptOpen and not flags.bellRung then
		return places.church.bell.Position, "The bell"
	elseif stage == "Getaway" then
		return places.church.cruiser.Position, "Police car"
	end
	return nil, nil
end

function Finale.hintTargets(): { Vector3 }
	local list: { Vector3 } = {}
	if stage == "Wreck" then
		local heli = ctx.helicopter()
		if not flags.searched and heli then
			table.insert(list, heli:GetPivot().Position)
		else
			table.insert(list, places.plant.gate)
		end
	elseif stage == "Plant" then
		if not flags.power then
			for i, b in places.plant.breakers do
				if not flags.breakers[i] then
					table.insert(list, b.Position)
				end
			end
		elseif not flags.keycard and not flags.mineOpen and keycardModel and keycardModel.Parent then
			table.insert(list, keycardModel:GetPivot().Position)
		elseif not flags.mineOpen then
			table.insert(list, places.plant.mineDoor.center)
		else
			table.insert(list, places.plant.minePortal)
		end
	elseif stage == "Church" then
		if not flags.cryptKey and not flags.cryptOpen and cryptKeyModel and cryptKeyModel.Parent then
			table.insert(list, cryptKeyModel:GetPivot().Position)
		elseif not flags.cryptOpen then
			table.insert(list, places.church.cryptDoor.center)
		else
			table.insert(list, places.church.bell.Position)
		end
	elseif stage == "Getaway" then
		table.insert(list, places.church.cruiser.Position)
	end
	return list
end

function Finale.checkpoint(): CFrame
	if stage == "Downed" or stage == "Wreck" then
		return places.crash.spawns[1]
	elseif stage == "Plant" then
		return places.plant.checkpoint
	elseif stage == "Church" and not flags.cryptOpen then
		return places.church.cryptSpawns[1]
	end
	return places.church.checkpoint
end

---------------------------------------------------------------- Chapter VII

local function spawnFamily(kinds: { string }, patrol: { Vector3 }, hunting: boolean?)
	for i, kind in kinds do
		local start = patrol[((i - 1) * 3) % #patrol + 1]
		Cannibals.spawn(kind, CFrame.new(start + Vector3.new(0, 3, 0)), { patrol = patrol, hunting = hunting })
	end
end

local function crashHelicopter(heli: Model)
	heli:PivotTo(places.crash.wreck)
	for _, d in heli:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			if d.Name == "Rotor" or (d.Parent and d.Parent.Name == "Rotor") then
				d.CFrame = d.CFrame * CFrame.Angles(math.rad(math.random(-40, 40)), 0, math.rad(math.random(-30, 30))) + Vector3.new(0, -2, 0)
			end
		end
	end
	local main = heli.PrimaryPart or heli:FindFirstChildWhichIsA("BasePart", true)
	if not main then
		return
	end
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(40, 38, 36)
	smoke.Opacity = 0.35
	smoke.RiseVelocity = 8
	smoke.Size = 6
	smoke.Parent = main
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 8
	fire.Parent = main
	Interact.add(main, {
		action = "Search the wreck",
		object = "Helicopter",
		hold = 2,
		distance = 12,
		canUse = function()
			if flags.searched then
				return false, "Nothing else worth taking."
			end
			return true
		end,
		onUse = function(player)
			flags.searched = true
			Inventory.add(player, "FirstAidKit", 1)
			Inventory.add(player, "Battery", 1)
			Inventory.add(player, "Bottle", 1)
			ctx.say("You", "The pilot's seat is empty. Belt cut. Blood on the door... and drag marks, heading south.", 5)
			ctx.broadcast()
		end,
	})
end

function Finale.takeoff()
	if stage ~= "" then
		return
	end
	setStage("Downed")
	Net.event("Timer"):FireAllClients(nil)
	Cannibals.clear()
	local heli = ctx.helicopter()
	ctx.playCutscene("Downed", { helicopter = heli, crash = places.crash.wreck }, 30)
	if heli then
		crashHelicopter(heli)
	end
	ctx.teleportAll(places.crash.spawns[1], false)
	setStage("Wreck")
	for _, player in Players:GetPlayers() do
		player:SetAttribute("SafeUntil", os.clock() + 10)
	end
	ctx.say("You", "...everyone okay? Where's the pilot?", 3.5)
	-- the Hunter has followed the smoke
	spawnFamily({ "Hunter" }, places.crash.trail)
end

---------------------------------------------------------------- Chapter VIII

local function powerOn()
	flags.power = true
	for _, light in places.plant.lamps do
		light.Enabled = true
		local bulb = light.Parent
		if bulb and bulb:IsA("BasePart") then
			bulb.Material = Enum.Material.Neon
		end
	end
	Doors.unlock(places.plant.coldDoor)
	soundRemote:FireAllClients("Generator", places.plant.origin.Position)
	Cannibals.noise(places.plant.origin.Position, 220)
	ctx.say("You", "Lights. And every one of them heard that...", 4)
	ctx.broadcast()
end

local function setupPlant()
	local plant = places.plant
	local folder = Build.folder(ctx.world, "PlantItems")
	for i, panel in plant.breakers do
		Interact.add(panel, {
			action = "Throw the breaker",
			object = "Breaker",
			hold = 1.2,
			distance = 7,
			canUse = function()
				if flags.breakers[i] then
					return false, "Already thrown."
				end
				return true
			end,
			onUse = function()
				flags.breakers[i] = true
				soundRemote:FireAllClients("Repair", panel.Position)
				Cannibals.noise(panel.Position, 90)
				if breakersDown() >= 3 and not flags.power then
					powerOn()
				else
					ctx.say("You", string.format("Breaker %d of 3. Something's humming.", breakersDown()), 3)
					ctx.broadcast()
				end
			end,
		})
	end
	keycardModel = Pickups.spawn("Keycard", plant.keycardSpots[math.random(1, #plant.keycardSpots)], folder, {
		onPicked = function()
			flags.keycard = true
			ctx.say("You", "FOREMAN - ALL AREAS. The mine door out back.", 3.5)
			ctx.broadcast()
		end,
	})
	local junk = { "Bottle", "Rag", "Moonshine", "Tape", "AlarmClock" }
	for i, spot in plant.junkSpots do
		Pickups.spawn(junk[(i - 1) % #junk + 1], spot, folder)
	end
	local promptPart = plant.pilot:FindFirstChild("PilotPrompt")
	if promptPart and promptPart:IsA("BasePart") then
		Interact.add(promptPart, {
			action = "Cut him down",
			object = "The pilot",
			hold = 2.5,
			distance = 7,
			canUse = function(player)
				if not Inventory.has(player, "Knife") then
					return false, "I need something to cut the chains' rope with."
				end
				return true
			end,
			onUse = function(_, prompt)
				prompt:Destroy()
				flags.pilotFreed = true
				plant.pilot:Destroy()
				ctx.say("Pilot", "...you came back for me? I can walk. I'll make for the highway and flag down anyone I can. Go!", 5)
				ctx.broadcast()
			end,
		})
	end
	plant.mineDoor.onOpened = function()
		if not flags.mineOpen then
			flags.mineOpen = true
			ctx.say("You", "The mine. The letter said the tunnels run all the way to town.", 4)
			ctx.broadcast()
		end
	end
end

local function enterPlant()
	setStage("Plant")
	ctx.say("You", "HOLLOW MEATS. The plant from the photos... the trail goes right inside.", 4)
	spawnFamily({ "Butcher", "Brother", "Papa" }, places.plant.patrol)
end

---------------------------------------------------------------- Chapter IX

-- The bell: everyone in the county hears it, the family most of all. Hold
-- out until the police come.
local function ringBell()
	flags.bellRung = true
	soundRemote:FireAllClients("ChurchBell", places.church.bell.Position)
	ctx.say("You", "Every cop in the county will hear that. So will they.", 4)
	-- everyone comes, and doesn't stop coming
	for _, c in Cannibals.all() do
		c.hunting = true
	end
	Cannibals.noise(places.church.bell.Position, 2000)
	flags.holdUntil = os.clock() + HOLD_OUT
	setStage("LastStand")
end

local function setupChurch()
	local church = places.church
	local folder = Build.folder(ctx.world, "ChurchItems")
	cryptKeyModel = Pickups.spawn("CryptKey", church.cryptKeySpots[math.random(1, #church.cryptKeySpots)], folder, {
		onPicked = function()
			flags.cryptKey = true
			ctx.say("You", "The gate key. Quietly now.", 2.5)
			ctx.broadcast()
		end,
	})
	church.cryptDoor.onOpened = function()
		if not flags.cryptOpen then
			flags.cryptOpen = true
			ctx.broadcast()
		end
	end
	Polaroids.place("P13", church.polaroid, folder)
	Interact.add(church.bell, {
		action = "Ring the bell",
		object = "Church bell",
		hold = 3,
		distance = 9,
		canUse = function()
			return not flags.bellRung, if flags.bellRung then "It's still ringing in your ears." else nil
		end,
		onUse = ringBell,
	})
end

local function mineTransition()
	flags.mineOpen = false -- once
	Cannibals.clear()
	ctx.playCutscene("Mine", {}, 22)
	ctx.teleportAll(places.church.cryptSpawns[1], false)
	setStage("Church")
	for _, player in Players:GetPlayers() do
		player:SetAttribute("SafeUntil", os.clock() + 8)
	end
	ctx.say("You", "A crypt... under a church. We're in Pinecrest.", 3.5)
	spawnFamily({ "Butcher", "Brother", "Papa", "Hunter", "Scavenger", "Kin" }, places.church.patrol)
end

local function arriveCruiser()
	flags.cruiser = true
	Net.event("Timer"):FireAllClients(nil)
	local car = Props.PickupTruck()
	car.Name = "StatePoliceCruiser"
	car:PivotTo(places.church.cruiser)
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			if d.Color.R > 0.3 and d.Color.G < 0.3 then
				d.Color = Color3.fromRGB(30, 30, 34)
			end
		end
	end
	car.Parent = ctx.world
	cruiser = car
	local _, size = car:GetBoundingBox()
	local top = places.church.cruiser * CFrame.new(0, size.Y + 0.3, 0)
	local red = Build.part(car, Vector3.new(1.4, 0.5, 0.8), top * CFrame.new(-0.8, 0, 0), Color3.fromRGB(255, 30, 30), Enum.Material.Neon)
	local blue = Build.part(car, Vector3.new(1.4, 0.5, 0.8), top * CFrame.new(0.8, 0, 0), Color3.fromRGB(40, 80, 255), Enum.Material.Neon)
	for _, lamp in { red, blue } do
		local light = Instance.new("PointLight")
		light.Color = lamp.Color
		light.Range = 40
		light.Brightness = 3
		light.Parent = lamp
	end
	task.spawn(function()
		while car.Parent do
			for _, pair in { { red, blue }, { blue, red } } do
				(pair[1]:FindFirstChildOfClass("PointLight") :: PointLight).Enabled = true;
				(pair[2]:FindFirstChildOfClass("PointLight") :: PointLight).Enabled = false
				pair[1].Transparency = 0
				pair[2].Transparency = 0.7
				task.wait(0.35)
			end
		end
	end)
	soundRemote:FireAllClients("Siren", places.church.cruiser.Position)
	ctx.say("Trooper", "STATE POLICE! Anyone out there - to the car, NOW!", 4)
	setStage("Getaway")
end

---------------------------------------------------------------- per tick (Story's watcher)

function Finale.watch()
	if stage == "Wreck" then
		if anyWithin(places.plant.gate, 34) then
			enterPlant()
		end
	elseif stage == "Plant" then
		if flags.mineOpen and anyWithin(places.plant.minePortal, 8) then
			mineTransition()
		end
	elseif stage == "LastStand" then
		local left = flags.holdUntil - os.clock()
		Net.event("Timer"):FireAllClients(math.max(0, left))
		if left <= 0 and not flags.cruiser then
			arriveCruiser()
		end
	elseif stage == "Getaway" then
		if not flags.finished and cruiser and anyWithin(places.church.cruiser.Position, 10) then
			flags.finished = true
			ctx.finish(Finale.trueEnding())
		end
	end
end

-- The admin's skip (Story.adminSkip): on to the next part of the last act,
-- everyone moved there when it's somewhere else.
function Finale.adminSkip()
	if stage == "Wreck" then
		enterPlant()
		ctx.teleportAll(places.plant.checkpoint, false)
	elseif stage == "Plant" then
		mineTransition()
	elseif stage == "Church" then
		ringBell()
	elseif stage == "LastStand" then
		flags.holdUntil = os.clock() -- the police arrive now
	elseif stage == "Getaway" and not flags.finished then
		flags.finished = true
		ctx.finish(Finale.trueEnding())
	end
end

function Finale.init(context: Ctx, sites: FinaleSites.Info)
	ctx = context
	places = sites
	setupPlant()
	setupChurch()
	Crafting.addBenchAt(sites.plant.bench, context.world, "Workbench")
end

return Finale

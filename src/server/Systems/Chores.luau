--!strict
-- Chapter 1, part 2: "Make Yourself At Home". Once the house has been
-- searched, the hosts keep everyone busy with little requests - and every
-- one of them turns up something worse. Ten tasks, any order, shared by the
-- whole party:
--
--   set the dinner table         (plates from the china hutch)
--   bring Jason a beer           (from the fridge)
--   keep the fire going          (a log from the basket)
--   close the living room curtains
--   try the phone in the hall    (someone is breathing on the line)
--   set the grandfather clock    (to the time on the fridge note; it hides a tape)
--   find the bathroom cabinet key
--   open the toy chest           (with that key)
--   pull the plug in the bath    (something is at the bottom)
--   watch the tape               (in the living room VCR)
--
-- House-local coordinates as in House.luau (upper floor at y = 13).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local HouseLayout = require(ReplicatedStorage.Shared.HouseLayout)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Build = require(script.Parent.Parent.World.Build)
local Interact = require(script.Parent.Interact)
local Pickups = require(script.Parent.Pickups)

local Chores = {}

-- fired for each chore done (Rewards pays everyone in the house)
Chores.Completed = Signal.new() :: Signal.Signal<string>

local rgb = Color3.fromRGB
local M = Enum.Material
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local U = 13

type Say = (speaker: string, text: string, duration: number?) -> ()

export type Objective = { text: string, done: boolean, optional: boolean? }

local ORDER = {
	"table",
	"beer",
	"fire",
	"curtains",
	"phone",
	"clock",
	"key",
	"chest",
	"plug",
	"tape",
	-- the wings and the attic (HouseWings)
	"record",
	"radio",
	"tea",
	"pattern",
	"oil",
	"sheets",
	"guestbed",
	"album",
}
local LABELS: { [string]: string } = {
	table = "Help Michel set the dinner table",
	beer = "Bring Jason a beer from the fridge",
	fire = "Keep the fire going",
	curtains = "Close the living room curtains",
	phone = "Try the phone in the hallway",
	clock = "Set the grandfather clock to the right time",
	key = "Find the key in the bathroom cabinet",
	chest = "Open the toy chest in the kid's room",
	plug = "Pull the plug in the bathtub",
	tape = "Watch the tape in the living room VCR",
	record = "Put on Grandpa's record in the parlor",
	radio = "Tune the sunroom radio to the weather",
	tea = "Take Grandma her tea (sunroom, then her room upstairs)",
	pattern = "Fetch Michel's dress pattern from the sewing room",
	oil = "Bring Michel lamp oil from the workshop",
	sheets = "Hang the wet sheets up in the attic",
	guestbed = "Make up the bed in the guest room",
	album = "Find the photo album in the storage room",
}
-- how many unfinished chores the objective list shows at once
local SHOWN = 6

local origin = CFrame.new()
local folder: Folder? = nil
local say: Say = function() end
local changed: () -> () = function() end
local onAllDone: () -> () = function() end
local active = false
local done: { [string]: boolean } = {}
local carrying = { plates = false, beer = false, log = false, key = false, tape = false, tea = false, oil = false, sheets = false }
local spots: { [string]: Vector3 } = {}
local clockHour = 3
local CLOCK_TARGET = 7

-- a spot on the house plan, in the bigger house (with the furniture it
-- sits on; HouseLayout)
local function L(x: number, y: number, z: number): CFrame
	return origin * CF(HouseLayout.place(Vector3.new(x, y, z)))
end

local function sound(name: string, at: Vector3)
	Net.event("Sound"):FireAllClients(name, at)
end

local function count(): number
	local n = 0
	for _, id in ORDER do
		if done[id] then
			n += 1
		end
	end
	return n
end

local function complete(id: string, line: string?, speaker: string?)
	if done[id] then
		return
	end
	done[id] = true
	if line then
		say(speaker or "You", line, 4)
	end
	Interact.notifyAll(string.format("%s (%d/%d)", LABELS[id], count(), #ORDER), "item")
	Chores.Completed:Fire(id)
	changed()
	if count() >= #ORDER then
		task.delay(3, onAllDone)
	end
end

-- an invisible prompt holder (props stay whatever the house already shows)
local function anchor(name: string, cf: CFrame, size: Vector3?): Part
	local f = folder :: Folder
	local p = Build.part(f, size or Vector3.new(1.5, 1.5, 1.5), cf, rgb(255, 255, 255), M.SmoothPlastic, {
		Name = name,
		Transparency = 1,
		CanCollide = false,
	})
	spots[name] = p.Position
	return p
end

local allPrompts: { ProximityPrompt } = {}

-- hidden until the chores begin (Chores.start)
local function prompt(part: BasePart, action: string, object: string, opts: { hold: number?, canUse: ((Player) -> (boolean, string?))?, onUse: (Player) -> () }): ProximityPrompt
	local made = Interact.add(part, {
		action = action,
		object = object,
		hold = opts.hold or 0.5,
		distance = 7,
		canUse = function(player)
			if not active then
				return false, nil
			end
			if opts.canUse then
				return opts.canUse(player)
			end
			return true
		end,
		onUse = opts.onUse,
	})
	made.Enabled = false
	table.insert(allPrompts, made)
	return made
end

---------------------------------------------------------------- the tasks

local function buildTasks(f: Folder)
	-- 1. the dinner table: plates from the hutch, onto the table
	local hutch = anchor("Hutch", L(29.2, 3.2, -18), Vector3.new(1, 3, 5))
	prompt(hutch, "Take plates", "China hutch", {
		canUse = function()
			if done.table then
				return false, "The table is already set."
			end
			return true
		end,
		onUse = function()
			carrying.plates = true
			sound("Pickup", hutch.Position)
			say("You", "Six plates. There are only two of them... who are the other places for?", 4)
			changed()
		end,
	})
	local tableSpot = anchor("DinnerTable", L(19, 3.9, -12), Vector3.new(6, 1, 3))
	prompt(tableSpot, "Set the table", "Dinner table", {
		hold = 1.2,
		canUse = function()
			if done.table then
				return false, nil
			end
			if not carrying.plates then
				return false, "Michel wants the good plates from the china hutch."
			end
			return true
		end,
		onUse = function()
			for i = 0, 2 do
				for _, side in { -1, 1 } do
					Build.cylinder(f, 0.08, 1.3, L(14 + i * 5, 3.55, -12 + side * 1.6) * ANG(0, 0, rad(90)), rgb(232, 226, 210), M.SmoothPlastic, { CanCollide = false })
				end
			end
			sound("PageTurn", tableSpot.Position)
			complete("table", "Six places. Michel set out a bib at the head of the table... and a cleaver.", "You")
		end,
	})

	-- 2. a beer for Jason (handed over by talking to him; see Chores.onTalk)
	-- on the lower door, clear of the freezer clue above it
	local fridge = anchor("Fridge", L(-28, 2.6, 4), Vector3.new(0.6, 3, 2.6))
	local beerPrompt: ProximityPrompt
	beerPrompt = prompt(fridge, "Take a beer", "Fridge", {
		canUse = function()
			if done.beer then
				return false, "Jason has his beer."
			end
			if carrying.beer then
				return false, "I've already got one for him."
			end
			return true
		end,
		onUse = function()
			carrying.beer = true
			beerPrompt.Enabled = false -- so the fridge note can be read again
			sound("DoorOpen", fridge.Position)
			say("You", "Beer... and behind it, something wrapped in butcher's paper. It's still warm.", 4)
			changed()
		end,
	})

	-- 3. the fire: a log from the basket
	local basket = anchor("LogBasket", L(-28.8, 1, -12.4), Vector3.new(2, 2, 2))
	for i = 0, 4 do
		Build.cylinder(f, 2.2, 0.6, L(-28.8, 0.4 + (i // 3) * 0.55, -12.9 + (i % 3) * 0.5), rgb(84, 62, 44), M.Wood, { CanCollide = false })
	end
	Build.part(f, Vector3.new(2.4, 0.9, 2), L(-28.8, 0.45, -12.4), rgb(80, 64, 44), M.WoodPlanks, { CanCollide = false })
	prompt(basket, "Take a log", "Log basket", {
		canUse = function()
			if done.fire then
				return false, nil
			end
			return true
		end,
		onUse = function()
			carrying.log = true
			sound("Pickup", basket.Position)
			changed()
		end,
	})
	local hearth = anchor("Hearth", L(-29, 1.5, -6), Vector3.new(1.5, 3, 4))
	prompt(hearth, "Add a log", "Fireplace", {
		hold = 0.8,
		canUse = function()
			if done.fire then
				return false, "The fire's roaring."
			end
			if not carrying.log then
				return false, "Jason wants it kept going. There's a log basket by the wall."
			end
			return true
		end,
		onUse = function()
			for _, d in workspace:GetDescendants() do
				if d:IsA("Fire") then
					local holder = d.Parent
					if holder and holder:IsA("BasePart") and (holder.Position - hearth.Position).Magnitude < 5 then
						d.Size = 6
						d.Heat = 12
					end
				end
			end
			sound("Impact", hearth.Position)
			complete("fire", "There's something in the ashes. A belt buckle. And a tooth.", "You")
		end,
	})

	-- 4. the living room curtains (Michel insists)
	local closed = 0
	for _, x in { -20, -12 } do
		local window = anchor("Window" .. x, L(x, 6.2, -23.2), Vector3.new(4, 4, 0.5))
		local p: ProximityPrompt? = nil
		p = prompt(window, "Close curtains", "Window", {
			onUse = function()
				Build.part(f, Vector3.new(4.6, 5.2, 0.08), L(x, 6.3, -22.9), rgb(110, 40, 36), M.Fabric, { CanCollide = false })
				local me = p
				if me then
					me.Enabled = false
				end
				closed += 1
				if closed >= 2 then
					complete("curtains", "Just before the curtain closed... something was standing in the yard. Watching.", "You")
				end
			end,
		})
	end

	-- 5. the phone in the hall
	Build.part(f, Vector3.new(1.4, 3, 2.2), L(3.6, 1.5, -6), rgb(70, 50, 36), M.Wood)
	local phone = Build.part(f, Vector3.new(0.9, 0.45, 0.7), L(3.6, 3.25, -6), rgb(30, 28, 26), M.SmoothPlastic)
	spots.Phone = phone.Position
	prompt(phone, "Pick up the phone", "Telephone", {
		hold = 0.3,
		canUse = function()
			if done.phone then
				return false, "Dead. Just breathing."
			end
			return true
		end,
		onUse = function()
			sound("Radio", phone.Position)
			say("You", "Hello? Hello, is this the police—", 2.5)
			task.delay(2.8, function()
				say("???", "...(slow breathing)... we can hear you too.", 3.5)
			end)
			task.delay(6.5, function()
				complete("phone", "The line's coming from inside the house.", "You")
			end)
		end,
	})

	-- 6. the grandfather clock (the time is on the note on the fridge)
	-- on the side of the fridge, away from the beer prompt on its door
	Pickups.note("FridgeNote", L(-30, 5.2, 5.62) * ANG(rad(90), 0, 0), f)
	local clock = anchor("Clock", L(-3.2, 5, -17.5), Vector3.new(1, 4, 2))
	prompt(clock, "Move the hands", "Grandfather clock", {
		hold = 0.2,
		canUse = function()
			if done.clock then
				return false, string.format("It reads %d o'clock. It's ticking again.", CLOCK_TARGET)
			end
			return true
		end,
		onUse = function(player)
			clockHour = clockHour % 12 + 1
			sound("FlashlightClick", clock.Position)
			Interact.notify(player, string.format("The clock now reads %d o'clock.", clockHour), "info")
			if clockHour == CLOCK_TARGET then
				task.spawn(function()
					for _ = 1, CLOCK_TARGET do
						sound("Impact", clock.Position)
						task.wait(0.55)
					end
					carrying.tape = true
					say("You", "A drawer just slid out of the base. There's a VHS tape inside. It says 'GUESTS'.", 4.5)
					complete("clock")
				end)
			end
		end,
	})

	-- 7. the bathroom cabinet key
	local cabinet = anchor("Cabinet", L(-30.9, U + 5.6, 8), Vector3.new(0.6, 3, 2.6))
	prompt(cabinet, "Open cabinet", "Bathroom cabinet", {
		canUse = function()
			if done.key then
				return false, "Empty, except for pill bottles with other people's names."
			end
			return true
		end,
		onUse = function()
			carrying.key = true
			sound("DoorOpen", cabinet.Position)
			complete("key", "Pill bottles with strangers' names on them... and a little brass key on a ribbon.", "You")
		end,
	})

	-- 8. the toy chest in the kid's room
	local chest = anchor("ToyChest", L(26, U + 2.4, -22), Vector3.new(4, 1, 2.4))
	prompt(chest, "Unlock", "Toy chest", {
		hold = 0.8,
		canUse = function()
			if done.chest then
				return false, nil
			end
			if not carrying.key then
				return false, "Locked. A tiny brass keyhole."
			end
			return true
		end,
		onUse = function()
			sound("Unlock", chest.Position)
			Pickups.note("ChildNote", L(26, U + 2.35, -21.6) * ANG(0, rad(10), 0), f)
			complete("chest", "Toys... and a drawing, folded up very small.", "You")
		end,
	})

	-- 9. the bath
	local plug = anchor("Plug", L(-29.5, U + 2.2, 21.6), Vector3.new(1, 1, 1))
	prompt(plug, "Pull the plug", "Bathtub", {
		hold = 1.5,
		canUse = function()
			if done.plug then
				return false, nil
			end
			return true
		end,
		onUse = function()
			sound("Generator", plug.Position)
			-- the red water drains away
			local water = L(-26, U + 2.1, 21.6).Position
			for _, d in workspace:GetDescendants() do
				if d:IsA("BasePart") and d.Material == M.Glass and (d.Position - water).Magnitude < 1.5 then
					TweenService:Create(d, TweenInfo.new(4), { Size = Vector3.new(d.Size.X, 0.05, d.Size.Z), CFrame = d.CFrame * CF(0, -1.4, 0) }):Play()
				end
			end
			task.delay(4, function()
				Pickups.note("RingNote", L(-26, U + 0.9, 21.6), f)
				complete("plug", "Something's at the bottom of the tub. A wedding ring.", "You")
			end)
		end,
	})

	-- 10. the tape
	local vcr = anchor("VCR", L(-8.6, 2.3, -20), Vector3.new(1.5, 1, 3))
	prompt(vcr, "Play tape", "VCR", {
		hold = 0.6,
		canUse = function()
			if done.tape then
				return false, "Just static now."
			end
			if not carrying.tape then
				return false, "There's a tape deck under the TV. Nothing in it."
			end
			return true
		end,
		onUse = function()
			sound("Radio", vcr.Position)
			local lines = {
				{ "TV", "[Static. Then this room, years ago. A family of four on the sofa, smiling at the camera.]" },
				{ "Michel (on tape)", "Say hello to everybody, sweetheart. You're our guests now." },
				{ "TV", "[The father laughs. Behind him, Jason walks past with the cleaver.]" },
				{ "TV", "[The picture jumps. The same sofa. Empty. A stain on the cushion.]" },
				{ "Michel (on tape)", "...and then there's always room for more." },
			}
			task.spawn(function()
				for _, line in lines do
					say(line[1], line[2], 4.2)
					task.wait(4.4)
				end
				complete("tape", "They film it. They keep them like home movies.", "You")
			end)
		end,
	})

	---------------------------------------------------------------- the wings
	-- 11. Grandpa's record (parlor)
	local record = anchor("RecordPlayer", L(-38, 3.4, -4), Vector3.new(1.8, 0.8, 1.6))
	prompt(record, "Play the record", "Record player", {
		hold = 1,
		canUse = function()
			return not done.record, if done.record then "The needle's stuck in the last groove." else nil
		end,
		onUse = function()
			sound("Radio", record.Position)
			task.spawn(function()
				say("Record", "[A hymn, scratched and slow. Then a man's voice over it:]", 3.6)
				task.wait(3.8)
				say("Record", "\"...Sunday supper, Pinecrest church. Bring the whole family. Bring a guest.\"", 4.4)
				task.wait(4.6)
				complete("record", "Grandpa's voice. Michel hums along to it from the kitchen.", "You")
			end)
		end,
	})

	-- 12. the sunroom radio
	local radio = anchor("Radio", L(35, 3.5, -14), Vector3.new(2, 1.4, 1.2))
	prompt(radio, "Tune the radio", "Radio", {
		hold = 2,
		canUse = function()
			return not done.radio, if done.radio then "Just static." else nil
		end,
		onUse = function()
			sound("Radio", radio.Position)
			task.spawn(function()
				say("Radio", "...storm over the county tonight... state police are asking anyone on Hollow Road...", 4.4)
				task.wait(4.6)
				say("Radio", "...to stay in their vehicles. Do NOT accept assistance from-  [click]", 4)
				task.wait(4.2)
				complete("radio", "Someone turned the dial back. Nobody's in here.", "You")
			end)
		end,
	})

	-- 13. Grandma's tea: the cup from the sunroom, up to her room
	local teapot = anchor("Teapot", L(49.2, 3.6, -11.4), Vector3.new(1.2, 1, 1.2))
	prompt(teapot, "Take a cup of tea", "Tea set", {
		canUse = function()
			if done.tea then
				return false, "It's gone cold."
			end
			return not carrying.tea, if carrying.tea then "I've got the cup." else nil
		end,
		onUse = function()
			carrying.tea = true
			sound("Pickup", teapot.Position)
			say("Michel", "Grandma's room is at the top of the back stairs. She takes it with a lot of sugar.", 4.4)
			changed()
		end,
	})
	local grandma = anchor("Grandma", L(-60, U + 4, -6), Vector3.new(2.4, 3, 2.4))
	prompt(grandma, "Give her the tea", "Grandma", {
		hold = 0.6,
		canUse = function()
			if done.tea then
				return false, "She hasn't moved. She isn't going to."
			end
			if not carrying.tea then
				return false, "Grandma's asleep in her chair."
			end
			return true
		end,
		onUse = function()
			carrying.tea = false
			sound("Scream", grandma.Position)
			Net.event("Scare"):FireAllClients("lights")
			complete("tea", "Grandma...? Her skin is like paper. She's been dead for YEARS.", "You")
		end,
	})

	-- 14. the dress pattern, pinned to a dress form in the sewing room
	local form = anchor("DressForm", L(-51.5, U + 4.5, 20.4), Vector3.new(2, 3, 1.4))
	prompt(form, "Unpin the pattern", "Dress form", {
		hold = 1,
		canUse = function()
			return not done.pattern, nil
		end,
		onUse = function()
			sound("PageTurn", form.Position)
			Pickups.note("PatternNote", L(-51.5, U + 0.1, 19), f)
			complete("pattern", "The pattern's traced around a person. Lying down. Arms out.", "You")
		end,
	})

	-- 15. lamp oil from the workshop drums, for Michel
	local drums = anchor("OilDrums", L(42.6, 3.2, 22), Vector3.new(6, 2, 2.4))
	prompt(drums, "Fill a can of lamp oil", "Drums", {
		hold = 1.2,
		canUse = function()
			if done.oil then
				return false, "Michel has his oil."
			end
			return not carrying.oil, if carrying.oil then "The can's full." else nil
		end,
		onUse = function()
			carrying.oil = true
			sound("Repair", drums.Position)
			say("You", "Lamp oil... it smells like the cellar. Michel wanted this.", 3.2)
			changed()
		end,
	})

	-- 16. wet sheets from the mudroom, up the ladder to the attic line
	local tub = anchor("WashTub", L(-36, 3.8, 21.8), Vector3.new(3.6, 1, 3))
	prompt(tub, "Wring out the sheets", "Wash tub", {
		hold = 1.4,
		canUse = function()
			if done.sheets then
				return false, "Empty. The water is pink."
			end
			return not carrying.sheets, if carrying.sheets then "Got them." else nil
		end,
		onUse = function()
			carrying.sheets = true
			sound("Wind", tub.Position)
			say("Michel", "Attic. The ladder's in the upstairs hall. Mind the boards.", 3.6)
			changed()
		end,
	})
	local line = anchor("AtticLine", L(-6, 27.5, 3), Vector3.new(4, 2, 1))
	prompt(line, "Hang the sheets", "Washing line", {
		hold = 1.6,
		canUse = function()
			if done.sheets then
				return false, nil
			end
			if not carrying.sheets then
				return false, "A washing line, strung between the rafters."
			end
			return true
		end,
		onUse = function()
			carrying.sheets = false
			sound("Wind", line.Position)
			Net.event("Scare"):FireAllClients("whisper")
			complete("sheets", "There's a shape under the next sheet along. Standing very still.", "You")
		end,
	})

	-- 17. the guest bed
	local bed = anchor("GuestBed", L(56, U + 3.2, -17), Vector3.new(6, 1, 6))
	prompt(bed, "Make the bed", "Guest bed", {
		hold = 2,
		canUse = function()
			return not done.guestbed, nil
		end,
		onUse = function()
			sound("PageTurn", bed.Position)
			complete("guestbed", "The mattress is new. The stain underneath it isn't.", "You")
		end,
	})

	-- 18. the photo album, buried in the storage room boxes
	local boxes = anchor("Album", L(40, U + 2.6, 17.2), Vector3.new(4, 2, 3))
	prompt(boxes, "Dig through the boxes", "Boxes", {
		hold = 2.2,
		canUse = function()
			return not done.album, nil
		end,
		onUse = function()
			sound("PageTurn", boxes.Position)
			Pickups.note("GuestAlbum", L(38.5, U + 0.1, 15), f)
			complete("album", "An album. Every page a different guest. The last page is blank... waiting.", "You")
		end,
	})
end

---------------------------------------------------------------- api

function Chores.build(houseOrigin: CFrame, parent: Instance)
	origin = houseOrigin
	local f = Build.folder(parent, "Chores")
	folder = f
	buildTasks(f)
end

function Chores.start(sayFn: Say, changedFn: () -> (), allDone: () -> ())
	say = sayFn
	changed = changedFn
	onAllDone = allDone
	active = true
	for _, p in allPrompts do
		if p.Parent then
			p.Enabled = true
		end
	end
	say("Michel", "Since you're up and about... would you lend us a hand before supper?", 4.5)
	changed()
end

function Chores.stop()
	active = false
	for _, p in allPrompts do
		if p.Parent then
			p.Enabled = false
		end
	end
end

-- Talking to Jason with a beer hands it over. Returns true if it did.
function Chores.onTalk(name: string): boolean
	if active and name == "Jason" and carrying.beer and not done.beer then
		complete("beer", "Good. You're learning how we do things here.", "Jason")
		return true
	end
	if active and name == "Michel" and carrying.oil and not done.oil then
		carrying.oil = false
		complete("oil", "Bless you. The lamps in the cellar drink it up... we keep them lit for the guests.", "Michel")
		return true
	end
	return false
end

-- A running count, then the next few chores still to do (eighteen lines
-- would fill the screen).
function Chores.objectives(): { Objective }
	local list: { Objective } = {}
	table.insert(list, { text = string.format("Lend a hand before supper (%d/%d)", count(), #ORDER), done = count() >= #ORDER })
	local shown = 0
	for _, id in ORDER do
		if not done[id] and shown < SHOWN then
			table.insert(list, { text = LABELS[id], done = false })
			shown += 1
		end
	end
	return list
end

function Chores.allDone(): boolean
	return count() >= #ORDER
end

function Chores.hintTargets(): { Vector3 }
	local list: { Vector3 } = {}
	local function add(name: string)
		local p = spots[name]
		if p then
			table.insert(list, p)
		end
	end
	if not done.table then
		add(if carrying.plates then "DinnerTable" else "Hutch")
	end
	if not done.beer and not carrying.beer then
		add("Fridge")
	end
	if not done.fire then
		add(if carrying.log then "Hearth" else "LogBasket")
	end
	if not done.phone then
		add("Phone")
	end
	if not done.clock then
		add("Clock")
	end
	if not done.key then
		add("Cabinet")
	elseif not done.chest then
		add("ToyChest")
	end
	if not done.plug then
		add("Plug")
	end
	if not done.tape and carrying.tape then
		add("VCR")
	end
	if not done.record then
		add("RecordPlayer")
	end
	if not done.radio then
		add("Radio")
	end
	if not done.tea then
		add(if carrying.tea then "Grandma" else "Teapot")
	end
	if not done.pattern then
		add("DressForm")
	end
	if not done.oil and not carrying.oil then
		add("OilDrums")
	end
	if not done.sheets then
		add(if carrying.sheets then "AtticLine" else "WashTub")
	end
	if not done.guestbed then
		add("GuestBed")
	end
	if not done.album then
		add("Album")
	end
	return list
end

return Chores

--!strict
-- Chapter 1 - "Investigate The House". After the crash the players wake up
-- on Jason and Michel's sofa. The hosts are all smiles; the house is not.
-- Explore the rooms, talk to both of them and find five of the seven clues
-- (missing posters, bloody clothing, a newspaper, scratched family photos,
-- teeth in a drawer, the padlocked basement hatch, the freezer). Progress is shared by
-- everyone in the server. When the chapter is done, onComplete fires.
--
-- House-local coordinates as in House.luau (origin = centre of the ground
-- floor, floor top at y = 0, front door facing -Z, upper floor at y = 13).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Build = require(script.Parent.Parent.World.Build)
local Hosts = require(script.Parent.Hosts)
local Chores = require(script.Parent.Chores)
local HouseLights = require(script.Parent.HouseLights)
local Interact = require(script.Parent.Interact)

local Investigation = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local U = 13

export type Objective = { text: string, done: boolean, optional: boolean? }

type Options = {
	say: (speaker: string, text: string, duration: number?) -> (),
	changed: () -> (),
	onComplete: () -> (),
}

type Clue = { id: string, position: Vector3, found: boolean, comment: string }

local origin = CFrame.new()
local opts: Options? = nil
local active = false
local completed = false
local clues: { Clue } = {}
local visited: { [string]: boolean } = {}
local talked: { [string]: boolean } = {}
local lineIndex: { [string]: number } = {}
local hatchPosition = Vector3.zero
local hatchPart: BasePart? = nil
local onClueFound: () -> () = function() end -- set in the tension section

local NEEDED = 5

local function L(x: number, y: number, z: number): CFrame
	return origin * CF(x, y, z)
end

local function foundCount(): number
	local n = 0
	for _, c in clues do
		if c.found then
			n += 1
		end
	end
	return n
end

local function wasFound(id: string): boolean
	for _, c in clues do
		if c.id == id then
			return c.found
		end
	end
	return false
end

---------------------------------------------------------------- dialogue

local LINES: { [string]: { { string } } } = {
	Jason = {
		{
			"Feeling better? There's stew on the stove. Help yourself, it's fresh.",
			"That pine's taken out three cars this year. Terrible bend in the road.",
			"Storm'll pass by morning. Always does.",
		},
		{
			"You're wandering an awful lot for someone with a concussion.",
			"Michel's a light sleeper. Try not to open too many doors.",
			"Hungry yet? You look... hungry.",
		},
		{
			"Find anything interesting up there?",
			"Funny. Folks who snoop around usually end up staying a while longer.",
			"Sit down. You'll feel much better once you've eaten.",
		},
	},
	Michel = {
		{
			"Phone line's down. The storm took it. We'll drive you to town at first light.",
			"Make yourself at home. We don't get many visitors out here.",
			"Mind the basement. It floods when it rains like this.",
		},
		{
			"Don't mind the smell. We butcher our own meat out here.",
			"Jason doesn't like guests going through his things.",
			"That hatch in the kitchen? Just the cellar. Nothing down there but meat.",
		},
		{
			"You've been busy.",
			"You really should be resting.",
			"Jason! ...Our guest is feeling better.",
		},
	},
}

local function talk(_player: Player, name: string)
	local o = opts
	if not o or not active then
		return
	end
	if Chores.onTalk(name) then
		return -- handed Jason his beer
	end
	local n = foundCount()
	local tier = if n >= 4 then 3 elseif n >= 2 then 2 else 1
	local lines = LINES[name][tier]
	local i = (lineIndex[name] or 0) % #lines + 1
	lineIndex[name] = i
	local text = lines[i]
	if name == "Michel" and tier == 3 and wasFound("ClueTeeth") and i == 3 then
		text = "...You found the teeth, didn't you."
	end
	o.say(name, text, 4)
	if not talked[name] then
		talked[name] = true
		o.changed()
	end
end

---------------------------------------------------------------- clues

local function buildClues(parent: Instance)
	local folder = Build.folder(parent, "Clues")
	local noteRemote = Net.event("Note")
	local soundRemote = Net.event("Sound")
	local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, extra: { [string]: any }?): Part
		return Build.part(folder, size, cf, color, material, extra)
	end
	local function text(p: BasePart, face: Enum.NormalId, body: string, color: Color3)
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(p.Size.X * 60, p.Size.Z * 60)
		gui.Parent = p
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.SpecialElite
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = body
		label.Parent = gui
	end
	local function clue(id: string, carrier: BasePart, object: string, comment: string)
		local entry: Clue = { id = id, position = carrier.Position, found = false, comment = comment }
		table.insert(clues, entry)
		Interact.add(carrier, {
			action = "Examine",
			object = object,
			distance = 7,
			onUse = function(player)
				soundRemote:FireClient(player, "PageTurn")
				noteRemote:FireClient(player, id)
				local o = opts
				if not entry.found and active and o then
					entry.found = true
					o.say("You", entry.comment, 4)
					onClueFound()
					o.changed()
				end
			end,
		})
	end

	-- living room: the local paper on the coffee table
	local paper = part(Vector3.new(1.6, 0.05, 1.1), L(-25, 1.98, -7.9) * ANG(0, 0.3, 0), rgb(222, 216, 198), M.SmoothPlastic, { CanCollide = false })
	text(paper, Enum.NormalId.Top, "PINECREST GAZETTE\nSIX VANISH ON HOLLOW ROAD", rgb(30, 26, 24))
	clue("ClueNewspaper", paper, "Newspaper", "Six people. On this road. And they 'help travellers'...")

	-- dining room: a stack of missing posters at the end of the table
	local posters = part(Vector3.new(1.3, 0.16, 1.7), L(25.4, 3.58, -12.4) * ANG(0, -0.2, 0), rgb(236, 230, 214), M.SmoothPlastic, { CanCollide = false })
	text(posters, Enum.NormalId.Top, "MISSING", rgb(170, 30, 26))
	part(Vector3.new(1.1, 0.02, 0.08), posters.CFrame * CF(0, 0.09, 0) * ANG(0, 0.6, 0), rgb(200, 20, 16), M.SmoothPlastic, { CanCollide = false })
	part(Vector3.new(1.1, 0.02, 0.08), posters.CFrame * CF(0, 0.09, 0) * ANG(0, -0.6, 0), rgb(200, 20, 16), M.SmoothPlastic, { CanCollide = false })
	clue("ClueMissing", posters, "Missing posters", "These are the faces from the gas station board... all crossed out.")

	-- trophy room: a deputy's jacket on the pile of belongings
	local jacket = part(Vector3.new(1.9, 0.35, 1.4), L(13, U + 1.65, 21.2) * ANG(0, 0.4, 0.05), rgb(70, 86, 120), M.Fabric, { CanCollide = false })
	for i = 0, 2 do
		part(Vector3.new(0.5 + i * 0.2, 0.02, 0.4), jacket.CFrame * CF(-0.4 + i * 0.35, 0.18, 0.1 - i * 0.2), rgb(90, 10, 8), M.Glass, {
			CanCollide = false,
			Transparency = 0.15,
		})
	end
	clue("ClueClothes", jacket, "Bloody jacket", "A deputy's jacket. Soaked in blood.")

	-- master bedroom: family photos with the faces scratched out
	for i, x in { -13.3, -11.1 } do
		local frame = part(Vector3.new(0.9, 1.1, 0.08), L(x, U + 3.95, -22.45) * ANG(rad(-8), (i - 1.5) * 0.3, 0), rgb(110, 82, 50), M.Wood, { CanCollide = false })
		local photo = part(Vector3.new(0.7, 0.9, 0.02), frame.CFrame * CF(0, 0, 0.05), rgb(190, 176, 150), M.SmoothPlastic, { CanCollide = false })
		text(photo, Enum.NormalId.Back, "XX  XX", rgb(60, 20, 18))
		if i == 1 then
			clue("CluePhotos", frame, "Family photos", "Everyone's face is scratched out but theirs... is that MY car?")
		end
	end

	-- kitchen: a drawer left open, full of teeth
	local drawer = part(Vector3.new(2.4, 0.5, 1.4), L(-13, 2.85, 20.5), rgb(86, 70, 54), M.Wood, { CanCollide = false })
	local rng = Random.new(77)
	for _ = 1, 14 do
		part(Vector3.new(0.1, 0.13, 0.1), drawer.CFrame * CF(rng:NextNumber(-1, 1), 0.3, rng:NextNumber(-0.5, 0.5)), rgb(232, 226, 205), M.SmoothPlastic, {
			CanCollide = false,
		})
	end
	clue("ClueTeeth", drawer, "Kitchen drawer", "Teeth. Human teeth. Some still have fillings.")

	-- kitchen floor: the padlocked hatch down to the basement
	local hatch = part(Vector3.new(4, 0.16, 4), L(-10, 0.08, 9), rgb(70, 52, 38), M.WoodPlanks, { Name = "BasementHatch" })
	for _, z in { -1.2, 1.2 } do
		part(Vector3.new(4.1, 0.05, 0.3), hatch.CFrame * CF(0, 0.1, z), rgb(50, 50, 52), M.CorrodedMetal, { CanCollide = false })
	end
	part(Vector3.new(0.5, 0.6, 0.25), hatch.CFrame * CF(1.5, 0.35, 0), rgb(120, 110, 70), M.Metal, { CanCollide = false })
	part(Vector3.new(3, 0.08, 0.12), hatch.CFrame * CF(0.2, 0.14, 0.2) * ANG(0, 0.4, 0), rgb(80, 80, 82), M.Metal, { CanCollide = false })
	local mist = Instance.new("Smoke")
	mist.Color = rgb(170, 180, 190)
	mist.Opacity = 0.06
	mist.RiseVelocity = 0.5
	mist.Size = 1.5
	mist.Parent = hatch
	clue("ClueHatch", hatch, "Basement hatch", "'Don't go in the basement.' Right. Something scratched this from the inside.")
	hatchPosition = hatch.Position
	hatchPart = hatch

	-- kitchen fridge: freezer packages with names on them
	local fridgeDoor = part(Vector3.new(0.2, 6.4, 3), L(-28.2, 4, 4), rgb(210, 206, 190), M.Metal, { CanCollide = false })
	part(Vector3.new(0.25, 1.6, 0.2), fridgeDoor.CFrame * CF(0.1, 0.6, 1.1), rgb(150, 150, 150), M.Metal, { CanCollide = false })
	clue("ClueFridge", fridgeDoor, "Fridge", "Those aren't pork chops. Those packages have NAMES on them.")

	-- the stew on the stove, as offered
	local stew = part(Vector3.new(1.3, 0.3, 1.3), L(-9, 5.15, 22), rgb(120, 54, 30), M.SmoothPlastic, { CanCollide = false, Transparency = 0.2 })
	local eaten: { [Player]: boolean } = {}
	Interact.add(stew, {
		action = "Eat",
		object = "Stew",
		distance = 7,
		onUse = function(player)
			local o = opts
			if not o then
				return
			end
			if eaten[player] then
				o.say("You", "No. I'm not touching that again.", 3)
				return
			end
			eaten[player] = true
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 15)
			end
			if wasFound("ClueTeeth") or wasFound("ClueFridge") then
				o.say("You", "...I know what this is. I'm going to be sick.", 4)
			else
				o.say("You", "Mm... it's good. Sweet. Almost like pork... what kind of meat is this?", 4.5)
			end
		end,
	})
end

---------------------------------------------------------------- tension

-- The house reacts as the clues pile up: the lights stutter, the hosts stop
-- to stare, and something under the kitchen floor starts knocking.
local KNOCK_LINES = {
	"...is someone up there...?",
	"...please... please get me out...",
	"...don't eat the stew...",
	"...they're coming back... hide...",
}

local function knockLoop()
	local soundRemote = Net.event("Sound")
	local line = 0
	while active do
		task.wait(math.random(28, 45))
		local o = opts
		if not active or not o or foundCount() < 3 then
			continue
		end
		local near = false
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - hatchPosition).Magnitude < 24 then
				near = true
			end
		end
		if near then
			for _ = 1, 3 do
				soundRemote:FireAllClients("Impact", hatchPosition)
				task.wait(0.4)
			end
			line = line % #KNOCK_LINES + 1
			o.say("???", KNOCK_LINES[line], 3.5)
		end
	end
end

onClueFound = function()
	local n = foundCount()
	Hosts.setSuspicion(if n >= 4 then 2 elseif n >= 2 then 1 else 0)
	if n >= 3 then
		HouseLights.flicker()
	end
end

---------------------------------------------------------------- rooms

local ROOMS: { [string]: (v: Vector3) -> boolean } = {
	living = function(v)
		return v.Y < 12 and v.X < -5 and v.Z < 0
	end,
	kitchen = function(v)
		return v.Y < 12 and v.X < -5 and v.Z > 0
	end,
	upstairs = function(v)
		return v.Y > 12
	end,
	master = function(v)
		return v.Y > 12 and v.X < -5 and v.Z < 0
	end,
	kids = function(v)
		return v.Y > 12 and v.X > 5 and v.Z < 0
	end,
}

local ROOM_CENTERS: { [string]: Vector3 } = {
	kitchen = Vector3.new(-18, 3, 12),
	upstairs = Vector3.new(0, U + 3, -4),
	master = Vector3.new(-18, U + 3, -12),
	kids = Vector3.new(18, U + 3, -12),
}

local function done(): boolean
	return visited.living == true
		and visited.kitchen == true
		and visited.upstairs == true
		and visited.master == true
		and visited.kids == true
		and talked.Jason == true
		and talked.Michel == true
		and foundCount() >= NEEDED
end

-- Supper's ready: the reveal plays once someone walks into the dining room
-- (or after a while anyway).
local dinnerCalled = false
local function callDinner()
	local o = opts
	if dinnerCalled or not active or not o then
		return
	end
	dinnerCalled = true
	o.say("Jason", "Supper's ready! Everybody to the dining room. Now.", 4.5)
	o.changed()
	task.spawn(function()
		local deadline = os.clock() + 120
		while active and os.clock() < deadline do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local v = origin:PointToObjectSpace(root.Position)
					if v.Y < 12 and v.X > 5 and v.X < 32 and v.Z < 0 and v.Z > -24 then
						deadline = 0
					end
				end
			end
		end
		if active then
			Chores.stop()
			active = false
			o.onComplete()
		end
	end)
end

local function checkComplete()
	local o = opts
	if completed or not active or not o or not done() then
		return
	end
	completed = true
	task.spawn(function()
		task.wait(4.5)
		o.say("You", "Whatever they're hiding is under that hatch... and Jason keeps a ring of keys on his belt.", 5)
		task.wait(5.5)
		if active then
			-- part 2: "Make Yourself At Home"
			Chores.start(o.say, o.changed, callDinner)
		end
	end)
end

---------------------------------------------------------------- api

-- Where everyone comes to after the crash: by the sofa, facing the fire.
function Investigation.spawnCF(): CFrame
	return CFrame.lookAt((origin * CF(-22.5, 3, -6)).Position, (origin * CF(-30, 3, -6)).Position)
end

-- Data for the wake-up cutscene.
function Investigation.wakeData(): { [string]: any }
	return {
		eye = CFrame.lookAt((origin * CF(-20.6, 3.9, -6)).Position, (origin * CF(-28, 2.6, -6)).Position),
		jason = CFrame.lookAt((origin * CF(-25.5, 0, -9.6)).Position, (origin * CF(-20.6, 0, -6)).Position),
		michel = CFrame.lookAt((origin * CF(-24.4, 0, -2.6)).Position, (origin * CF(-20.6, 0, -6)).Position),
		exit = origin * CF(-3.5, 0, -11.5),
		doorway = origin * CF(-6.5, 0, -11.5),
	}
end

-- Data for the reveal: the two of them at the front door, seen from the hall.
function Investigation.revealData(): { [string]: any }
	return {
		camera = CFrame.lookAt((origin * CF(1.5, 4.6, -6)).Position, (origin * CF(0, 4.2, -18)).Position),
		jason = CFrame.lookAt((origin * CF(-1.2, 0, -18.5)).Position, (origin * CF(0, 0, -6)).Position),
		michel = CFrame.lookAt((origin * CF(1.6, 0, -17.5)).Position, (origin * CF(0, 0, -6)).Position),
	}
end

-- The padlocked kitchen hatch (the cellar opens it after the reveal).
function Investigation.hatch(): BasePart?
	return hatchPart
end

function Investigation.prepare(houseOrigin: CFrame, parent: Instance)
	origin = houseOrigin
	buildClues(parent)
	Chores.build(houseOrigin, parent)
end

function Investigation.start(parent: Instance, options: Options)
	opts = options
	active = true
	completed = false
	HouseLights.setPower(true)
	Hosts.setSuspicion(0)
	task.spawn(knockLoop)
	-- (x, pause, z): they linger in rooms and walk straight through doorways
	local V = Vector3.new
	Hosts.spawn(origin, parent, {
		Jason = {
			V(-9, 1, 19),
			V(-18, 1, 8.4),
			V(-6.5, 0, 4.5),
			V(-3.5, 0, 4.5),
			V(0, 1, -3),
			V(3.5, 0, -11.5),
			V(6.5, 0, -11.5),
			V(12, 1, -17),
			V(6.5, 0, -11.5),
			V(3.5, 0, -11.5),
			V(0, 0, -3),
			V(-3.5, 0, 4.5),
			V(-6.5, 0, 4.5),
		},
		Michel = {
			V(-26, 1, -12.5),
			V(-12, 1, -16),
			V(-6.5, 0, -11.5),
			V(-3.5, 0, -11.5),
			V(0, 1, -18),
			V(-3.5, 0, -11.5),
			V(-6.5, 0, -11.5),
			V(-18, 1, -14),
		},
	}, talk)
	task.spawn(function()
		while active do
			local changed = false
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local v = origin:PointToObjectSpace(root.Position)
					if math.abs(v.X) < 33 and math.abs(v.Z) < 25 and v.Y > -2 and v.Y < 27 then
						for name, inside in ROOMS do
							if not visited[name] and inside(v) then
								visited[name] = true
								changed = true
							end
						end
					end
				end
			end
			if changed then
				options.changed()
				checkComplete()
			end
			task.wait(0.5)
		end
	end)
	-- the other checks happen when something is found or someone talks
	local inner = options.changed
	options.changed = function()
		inner()
		checkComplete()
	end
end

function Investigation.finish()
	active = false
	Hosts.remove()
	HouseLights.setPower(false) -- they cut the power
end

function Investigation.objectives(): { Objective }
	local list: { Objective } = {}
	local function add(text: string, isDone: boolean)
		table.insert(list, { text = text, done = isDone })
	end
	if completed then
		-- part 2: the hosts' little requests, then supper
		if dinnerCalled then
			add("Go to the dining room for supper", false)
			return list
		end
		for _, o in Chores.objectives() do
			table.insert(list, o)
		end
		return list
	end
	add("Explore the living room", visited.living == true)
	add("Explore the kitchen", visited.kitchen == true)
	add("Explore upstairs", visited.upstairs == true)
	add("Search the bedrooms", visited.master == true and visited.kids == true)
	add("Speak to Jason", talked.Jason == true)
	add("Speak to Michel", talked.Michel == true)
	add(string.format("Find suspicious clues (%d/%d)", math.min(foundCount(), NEEDED), NEEDED), foundCount() >= NEEDED)
	return list
end

function Investigation.hintTargets(): { Vector3 }
	local list: { Vector3 } = {}
	if completed then
		if dinnerCalled then
			table.insert(list, (origin * CF(18, 3, -12)).Position)
			return list
		end
		return Chores.hintTargets()
	end
	if foundCount() < NEEDED then
		for _, c in clues do
			if not c.found then
				table.insert(list, c.position)
			end
		end
	end
	for name, center in ROOM_CENTERS do
		if not visited[name] then
			table.insert(list, (origin * CF(center)).Position)
		end
	end
	for _, name in { "Jason", "Michel" } do
		if not talked[name] then
			local pos = Hosts.position(name)
			if pos then
				table.insert(list, pos)
			end
		end
	end
	return list
end

return Investigation

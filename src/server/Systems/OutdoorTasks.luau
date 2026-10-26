--!strict
-- Things to do out in the woods, round the places the story sends you: a
-- cooler at the hunter's camp, the medicine cabinet in the doctor's trailer,
-- a fresh grave, the binoculars up the lookout tower... Each is worth doing:
-- the first time you do one it gives you supplies or Teeth, it always tells
-- you something, and some answer back (a scare, just for you). The outdoor
-- twin of HouseExtras.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Build = require(script.Parent.Parent.World.Build)
local Terrain = require(script.Parent.Parent.World.Terrain)
local Interact = require(script.Parent.Interact)
local Inventory = require(script.Parent.Inventory)
local Profiles = require(script.Parent.Profiles)

local OutdoorTasks = {}

local rgb = Color3.fromRGB

type Task = {
	site: string, -- Config.Sites (or "Lake")
	angle: number, -- where round the site, in degrees
	action: string,
	object: string,
	lines: { string },
	item: string?, -- what you find (the first time)
	teeth: number?, -- or Teeth
	scare: string?,
	chance: number?,
	hold: number?,
	prop: "crate" | "post" | "mound",
}

local TASKS: { Task } = {
	{ site = "Camp", angle = 20, action = "Search the cooler", object = "Cooler", item = "Battery", prop = "crate", lines = { "Ice, long melted. Under it, batteries in a freezer bag." } },
	{ site = "Camp", angle = 200, action = "Check the trail camera", object = "Trail camera", teeth = 4, prop = "post", scare = "behind", chance = 0.6, lines = { "The last photo is of you. Taken from behind, a minute ago." } },
	{ site = "Trailer", angle = 90, action = "Search the medicine cabinet", object = "Medicine cabinet", item = "Bandage", prop = "crate", lines = { "Bandages, and a prescription made out to a man missing since 2019." } },
	{ site = "Barn", angle = 140, action = "Pull down the hay", object = "Hay bale", item = "Rag", prop = "crate", scare = "breath", chance = 0.4, lines = { "Old rags, stiff with something dark. Good for a molotov." } },
	{ site = "Cemetery", angle = 60, action = "Read the newest headstone", object = "Headstone", teeth = 4, prop = "post", scare = "whisper", chance = 0.7, lines = { "Tonight's date. No name carved yet." } },
	{ site = "Cemetery", angle = 250, action = "Dig at the fresh grave", object = "Fresh grave", item = "Bottle", hold = 2, prop = "mound", scare = "jumpscare", chance = 0.25, lines = { "A bottle in the dirt. And, under it, a hand." } },
	{ site = "Wreck", angle = 0, action = "Search the glovebox", object = "Glovebox", item = "Tape", prop = "crate", lines = { "Duct tape, and a road map with the farmhouse circled in red." } },
	{ site = "Station", angle = 300, action = "Read the ranger's log", object = "Ranger's log", teeth = 4, prop = "post", lines = { "The last entry is just the word 'smoke', written over and over." } },
	{ site = "Tower", angle = 120, action = "Use the binoculars", object = "Binoculars", teeth = 4, prop = "post", scare = "footsteps", chance = 0.6, lines = { "Far off, by the farmhouse, a lantern swings. It's coming this way." } },
	{ site = "Shed", angle = 180, action = "Search the toolbox", object = "Toolbox", item = "Tape", prop = "crate", lines = { "Rusted wrenches, and half a roll of tape." } },
	{ site = "Lake", angle = 30, action = "Look into the water", object = "The lake", teeth = 4, prop = "post", scare = "behind", chance = 0.5, lines = { "Your reflection takes a moment to follow you." } },
	{ site = "Truck", angle = 160, action = "Search the toolbag", object = "Toolbag", item = "Battery", prop = "crate", lines = { "A flashlight with a dead bulb, and its batteries. Still good." } },
}

-- Somewhere round the site's edge, clear of buildings and out of the water.
local function spot(center: Vector2, radius: number, angle: number, folder: Instance): CFrame?
	local params = OverlapParams.new()
	params.RespectCanCollide = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	for step = 0, 7 do
		local a = math.rad(angle + step * 45)
		for _, r in { radius * 0.75, radius + 4, radius * 0.5 } do
			local x, z = center.X + math.cos(a) * r, center.Y + math.sin(a) * r
			if not Terrain.isWater(x, z) then
				local cf = Terrain.groundCFrame(x, z, -a)
				if #workspace:GetPartBoundsInBox(cf + Vector3.new(0, 2, 0), Vector3.new(4, 3, 4), params) == 0 then
					return cf
				end
			end
		end
	end
	return nil
end

local function makeProp(folder: Instance, kind: string, cf: CFrame, name: string): BasePart
	local wood = rgb(84, 64, 46)
	if kind == "post" then
		Build.part(folder, Vector3.new(0.5, 3.4, 0.5), cf * CFrame.new(0, 1.7, 0), rgb(70, 56, 44), Enum.Material.Wood)
		return Build.part(folder, Vector3.new(1.8, 1.2, 0.3), cf * CFrame.new(0, 3.2, -0.3), wood, Enum.Material.WoodPlanks, { Name = name })
	elseif kind == "mound" then
		return Build.part(folder, Vector3.new(3.4, 1, 6), cf * CFrame.new(0, 0.3, 0), rgb(60, 46, 34), Enum.Material.Ground, { Name = name })
	end
	return Build.part(folder, Vector3.new(2.2, 1.6, 1.6), cf * CFrame.new(0, 0.8, 0), wood, Enum.Material.WoodPlanks, { Name = name })
end

function OutdoorTasks.build(world: Instance)
	local folder = Build.folder(world, "OutdoorTasks")
	local subtitle = Net.event("Subtitle")
	local scare = Net.event("Scare")
	local done: { [Player]: { [number]: boolean } } = {}
	for i, t in TASKS do
		local site = if t.site == "Lake" then Config.Lake else Config.Sites[t.site]
		if not site then
			continue
		end
		local radius = if t.site == "Lake" then site.radius + 10 else site.radius
		local cf = spot(site.pos, radius, t.angle, folder)
		if not cf then
			continue
		end
		local anchor = makeProp(folder, t.prop, cf, t.object)
		Interact.add(anchor, {
			action = t.action,
			object = t.object,
			hold = t.hold or 0.6,
			distance = 7,
			onUse = function(player)
				subtitle:FireClient(player, "You", t.lines[math.random(1, #t.lines)], 4.5)
				local mine = done[player] or {}
				done[player] = mine
				if not mine[i] then
					mine[i] = true
					if t.item then
						Inventory.add(player, t.item, 1)
					end
					Profiles.award(player, t.teeth or 2, "Scavenging")
				end
				if t.scare and math.random() < (t.chance or 1) then
					task.delay(1.4, function()
						if player.Parent then
							scare:FireClient(player, t.scare)
						end
					end)
				end
			end,
		})
	end
	Players.PlayerRemoving:Connect(function(player)
		done[player] = nil
	end)
end

return OutdoorTasks

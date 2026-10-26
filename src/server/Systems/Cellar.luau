--!strict
-- The cellar under the kitchen hatch: the knocking from Chapter 1. After the
-- reveal a pair of bolt cutters turns up in the trophy room. They cut the
-- hatch padlock; down the ladder, Ranger Tom Ellis (the missing ranger from
-- the paper) is chained to the pipes. Cut him loose and he follows you; get
-- him out of the house and he goes for help (counts toward the true ending).
-- Hide down there too long and one of the family comes down the ladder.
--
-- House-local coordinates as in House.luau. The room spans x -30..-6,
-- z 1..23, floor at y = -10; the hatch hole is x -12..-8, z 7..11.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local HouseLayout = require(ReplicatedStorage.Shared.HouseLayout)
local Build = require(script.Parent.Parent.World.Build)
local Props = require(script.Parent.Parent.World.Props)
local AssetService = require(script.Parent.AssetService)
local Cannibals = require(script.Parent.Cannibals)
local Doors = require(script.Parent.Doors)
local Interact = require(script.Parent.Interact)
local Inventory = require(script.Parent.Inventory)
local Pickups = require(script.Parent.Pickups)

local Cellar = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local U = 13
local FLOOR = -10

type Say = (speaker: string, text: string, duration: number?) -> ()

local origin = CFrame.new()
local folder: Folder? = nil
local hatch: BasePart? = nil
local say: Say = function() end
local changed: () -> () = function() end

local state = {
	enabled = false,
	cuttersTaken = false,
	hatchOpen = false,
	freed = false,
	rescued = false,
	gone = false, -- left for help (or never freed)
}
local cuttersPickup: Model? = nil
local tom: { model: Model, humanoid: Humanoid, root: BasePart, chains: { BasePart } }? = nil
local loiter: { [Player]: number } = {}

-- The cellar keeps its size under the (bigger) kitchen: it is laid out on
-- the house plan and moved with the hatch (HouseLayout).
local HATCH = Vector3.new(-10, 0, 9)
local SHIFT = HouseLayout.point(HATCH) - HATCH

local function L(x: number, y: number, z: number): CFrame
	return origin * CF(Vector3.new(x, y, z) + SHIFT)
end

local function localPos(p: Vector3): Vector3
	return origin:PointToObjectSpace(p) - SHIFT
end

local function inCellar(p: Vector3): boolean
	local v = localPos(p)
	return v.Y < -2.5 and v.X > -31 and v.X < -5 and v.Z > 0 and v.Z < 24
end

local function insideHouse(p: Vector3): boolean
	local v = HouseLayout.unmap(origin:PointToObjectSpace(p))
	return math.abs(v.X) < 33 and v.Z > -25 and v.Z < 25
end

---------------------------------------------------------------- the room

local function buildRoom(parent: Folder)
	local stone = rgb(74, 70, 64)
	local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, extra: { [string]: any }?): Part
		return Build.part(parent, size, cf, color, material, extra)
	end
	-- dig it out (the house's foundation already leaves the space)
	pcall(function()
		workspace.Terrain:FillBlock(L(-18, -5.4, 12), Vector3.new(26, 11.6, 24), Enum.Material.Air)
	end)
	part(Vector3.new(25, 1, 23), L(-18, FLOOR - 0.5, 12), rgb(64, 62, 58), M.Concrete)
	local walls: { { size: Vector3, cf: CFrame } } = {
		{ size = Vector3.new(25, 10.4, 1), cf = L(-18, -5.2, 0.5) },
		{ size = Vector3.new(25, 10.4, 1), cf = L(-18, -5.2, 23.5) },
		{ size = Vector3.new(1, 10.4, 23), cf = L(-30.5, -5.2, 12) },
		{ size = Vector3.new(1, 10.4, 23), cf = L(-5.5, -5.2, 12) },
	}
	for _, w in walls do
		part(w.size, w.cf, stone, M.Cobblestone)
	end
	-- rusty pipes along the ceiling, dripping into the floodwater
	for i, z in { 4, 13.5, 21.8 } do
		Build.cylinder(parent, 24, 0.6, L(-18, -1.1 - i * 0.1, z), rgb(96, 60, 40), M.CorrodedMetal)
	end
	part(Vector3.new(14, 0.08, 9), L(-21, FLOOR + 0.04, 9), rgb(30, 34, 30), M.Glass, { CanCollide = false, Transparency = 0.35, Reflectance = 0.25 })
	part(Vector3.new(6, 0.08, 5), L(-12, FLOOR + 0.04, 19), rgb(30, 34, 30), M.Glass, { CanCollide = false, Transparency = 0.35, Reflectance = 0.25 })
	-- the ladder down from the hatch
	Build.ladder(parent, Vector3.new(2, 10, 2), L(-10, FLOOR + 5, 10), rgb(80, 64, 46), M.Wood)
	-- one bulb on a wire, mostly off
	Build.bulb(parent, L(-18, -1.6, 12), rgb(255, 170, 110), 0.5, 22, true)
	-- what the family keeps down here
	local rng = Random.new(31)
	local hooks = AssetService.create("MeatHooks")
	local _, hookSize = hooks:GetBoundingBox()
	hooks:PivotTo(L(-22, -0.4 - hookSize.Y, 5))
	hooks.Parent = parent
	for i = 0, 2 do
		local barrel = Props.Barrel(rng :: any)
		barrel:PivotTo(L(-28.6, FLOOR, 2.5 + i * 2.6))
		barrel.Parent = parent
	end
	for i = 0, 3 do
		local crate = Props.Crate(rng :: any)
		crate:PivotTo(L(-8 - (i % 2) * 3.2, FLOOR + (i // 2) * 3, 21.5) * ANG(0, rad(rng:NextNumber(-10, 10)), 0))
		crate.Parent = parent
	end
	local cage = Props.Cage()
	cage:PivotTo(L(-27, FLOOR, 19))
	cage.Parent = parent
	local chair = Props.Chair(true)
	chair:PivotTo(L(-16, FLOOR, 4.5) * ANG(0, rad(160), 0))
	chair.Parent = parent
	for i = 0, 1 do
		local bag = Props.BodyBag(rng :: any)
		bag:PivotTo(L(-25 + i * 1.2, FLOOR + i * 1.3, 12) * ANG(0, rad(90 + i * 20), 0))
		bag.Parent = parent
	end
	-- tally marks scratched into the north wall, and a note under them
	for i = 0, 13 do
		part(Vector3.new(0.08, 0.9, 0.05), L(-19.5 + i * 0.32, -5.8, 22.97) * ANG(0, 0, if i % 5 == 4 then rad(70) else 0), rgb(150, 140, 120), M.SmoothPlastic, { CanCollide = false })
	end
	Pickups.note("TomTally", L(-18.5, FLOOR + 0.05, 21.6) * ANG(0, rad(15), 0), parent)
	Pickups.spawn("Bandage", L(-28.6, FLOOR + 3.05, 5.1), parent)
	Pickups.spawn("Battery", L(-8, FLOOR + 3.05, 21.5), parent)
end

---------------------------------------------------------------- Tom

local function buildTom(parent: Folder)
	local desc = Instance.new("HumanoidDescription")
	local skin = rgb(196, 150, 116)
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = rgb(150, 132, 92) -- ranger khaki, filthy
	desc.LeftLegColor = rgb(56, 66, 48)
	desc.RightLegColor = rgb(56, 66, 48)
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)
	if not (ok and rig) then
		return
	end
	rig.Name = "Tom Ellis"
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.WalkSpeed = 15
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "NPC"
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	-- chained by the wrists to the pipe, arms up
	local torso = rig:FindFirstChild("Torso")
	if torso then
		for _, name in { "Right Shoulder", "Left Shoulder" } do
			local motor = torso:FindFirstChild(name)
			if motor and motor:IsA("Motor6D") then
				motor.C0 = motor.C0 * ANG(0, 0, if name == "Right Shoulder" then rad(160) else rad(-160))
			end
		end
	end
	rig:PivotTo(L(-22.5, FLOOR + 3, 22) * ANG(0, 0, 0))
	root.Anchored = true
	rig.Parent = parent
	rig:SetAttribute("AnimForce", "none")
	rig:SetAttribute("AnimWalk", "Walk1")
	rig:SetAttribute("AnimRun", "Run1")
	rig:SetAttribute("AnimRunAt", 11)
	Build.tag(rig, "KeyframeAnimated")
	local chains: { BasePart } = {}
	for _, x in { -0.9, 0.9 } do
		for i = 0, 4 do
			table.insert(chains, Build.part(parent, Vector3.new(0.18, 0.4, 0.12), L(-22.5 + x * (1 - i * 0.12), -1.4 - i * 0.42, 22.4) * ANG(0, if i % 2 == 0 then 0 else rad(90), 0), rgb(90, 86, 80), M.Metal, { CanCollide = false }))
		end
	end
	tom = { model = rig, humanoid = humanoid, root = root, chains = chains }

	Interact.add(root, {
		action = "Cut chains",
		object = "Tom Ellis",
		hold = 1.5,
		distance = 8,
		once = true,
		canUse = function(player)
			if not Inventory.has(player, "BoltCutters") then
				say("Tom", "...please... the chains... find something to cut them...", 3.5)
				return false, "His wrists are chained to the pipe. I need something to cut them."
			end
			return true
		end,
		onUse = function()
			local t = tom
			if not t then
				return
			end
			state.freed = true
			for _, c in t.chains do
				c:Destroy()
			end
			Net.event("Sound"):FireAllClients("Unlock", t.root.Position)
			if torso then
				for _, name in { "Right Shoulder", "Left Shoulder" } do
					local motor = torso:FindFirstChild(name)
					if motor and motor:IsA("Motor6D") then
						motor.C0 = motor.C0 * ANG(0, 0, if name == "Right Shoulder" then rad(-160) else rad(160))
					end
				end
			end
			t.model:SetAttribute("AnimForce", nil)
			t.root.Anchored = false
			pcall(function()
				t.root:SetNetworkOwner(nil)
			end)
			say("Tom", "You came back for me... I'm Tom Ellis, the ranger. Get me out of this house and I'll bring help.", 5)
			changed()
		end,
	})
end

-- Tom follows the nearest living player; the ladder is climbed by hand.
local function nearestPlayer(from: Vector3): (Player?, BasePart?)
	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestD = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			local d = (root.Position - from).Magnitude
			if d < bestD then
				bestD = d
				best = player
				bestRoot = root
			end
		end
	end
	return best, bestRoot
end

local climbing = false
local function climbOut()
	local t = tom
	if not t or climbing then
		return
	end
	climbing = true
	t.root.Anchored = true
	t.model:SetAttribute("AnimForce", "idle")
	local value = Instance.new("CFrameValue")
	value.Value = t.root.CFrame
	value.Changed:Connect(function(cf)
		t.root.CFrame = cf
	end)
	local up = TweenService:Create(value, TweenInfo.new(2.2, Enum.EasingStyle.Sine), { Value = L(-10, 1.2, 8.8) })
	up:Play()
	up.Completed:Wait()
	local out = TweenService:Create(value, TweenInfo.new(0.6), { Value = L(-10, 3.2, 5.4) })
	out:Play()
	out.Completed:Wait()
	value:Destroy()
	t.model:SetAttribute("AnimForce", nil)
	t.root.Anchored = false
	pcall(function()
		t.root:SetNetworkOwner(nil)
	end)
	climbing = false
end

local function leaveForHelp()
	local t = tom
	if not t or state.gone then
		return
	end
	state.rescued = true
	state.gone = true
	say("Tom", "I know these woods better than they do. I'll get to the highway and bring the state police. Go, get to the ranger station!", 6)
	Interact.notifyAll("Tom Ellis is going for help.", "item")
	changed()
	task.spawn(function()
		local away = t.root.Position + (t.root.Position - origin.Position).Unit * 60
		t.humanoid:MoveTo(Vector3.new(away.X, t.root.Position.Y, away.Z))
		task.wait(8)
		t.model:Destroy()
		tom = nil
	end)
end

local function step()
	local t = tom
	if not t or not state.freed or state.gone or climbing then
		return
	end
	local pos = t.root.Position
	if not insideHouse(pos) then
		leaveForHelp()
		return
	end
	local leader, leaderRoot = nearestPlayer(pos)
	if not leader or not leaderRoot then
		t.humanoid:MoveTo(pos)
		return
	end
	local target = leaderRoot.Position
	if inCellar(pos) and not inCellar(target) then
		-- head for the ladder, then up
		local foot = L(-10, FLOOR, 8.6).Position
		if (Vector3.new(pos.X, foot.Y, pos.Z) - foot).Magnitude < 3 then
			task.spawn(climbOut)
		else
			t.humanoid:MoveTo(foot)
		end
		return
	end
	if not inCellar(pos) and inCellar(target) then
		t.humanoid:MoveTo(L(-10, 0, 5).Position) -- wait by the hatch
		return
	end
	local d = (target - pos).Magnitude
	if d > 80 then
		-- left behind: catch up out of sight
		t.root.CFrame = leaderRoot.CFrame * CF(0, 0, 9)
	elseif d > 7 then
		Doors.openNear(pos, 6)
		t.humanoid:MoveTo(target - (target - pos).Unit * 4)
	else
		t.humanoid:MoveTo(pos)
	end
end

---------------------------------------------------------------- the family checks the cellar

local function patrolCellar()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and inCellar(root.Position) then
			loiter[player] = loiter[player] or now
			if now - loiter[player] > 45 then
				loiter[player] = now + 30 -- once in a while, not constantly
				local list = Cannibals.all()
				local pick = list[math.random(math.max(#list, 1))]
				if pick and pick.alive and pick.state ~= "Chase" and pick.state ~= "Sedated" then
					Net.event("Sound"):FireAllClients("DoorOpen", L(-10, 0, 9).Position)
					Net.event("Sound"):FireAllClients("Growl", L(-10, -2, 9).Position)
					Cannibals.relocate(pick, L(-10, FLOOR, 6), {
						L(-10, FLOOR, 6).Position,
						L(-20, FLOOR, 8).Position,
						L(-26, FLOOR, 16).Position,
						L(-14, FLOOR, 18).Position,
					})
					Interact.notify(player, "Something is coming down the ladder...", "warn")
				end
			end
		else
			loiter[player] = nil
		end
	end
end

---------------------------------------------------------------- api

function Cellar.build(houseOrigin: CFrame, parent: Instance, hatchPart: BasePart?)
	origin = houseOrigin
	hatch = hatchPart
	local f = Build.folder(parent, "Cellar")
	folder = f
	buildRoom(f)
	buildTom(f)
	task.spawn(function()
		while true do
			task.wait(0.3)
			if state.enabled then
				step()
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			if state.enabled and not state.gone then
				patrolCellar()
			end
		end
	end)
end

local function openHatch()
	local h = hatch
	if not h or state.hatchOpen then
		return
	end
	state.hatchOpen = true
	-- the padlock, chain and straps go; the hatch swings up on its edge
	local holder = h.Parent
	if holder then
		for _, d in holder:GetChildren() do
			if d ~= h and d:IsA("BasePart") and (d.Position - h.Position).Magnitude < 3.2 and d.Size.Magnitude < 5 then
				d:Destroy()
			end
		end
	end
	for _, d in h:GetChildren() do
		if d:IsA("ProximityPrompt") or d:IsA("Smoke") then
			d:Destroy()
		end
	end
	h.CanCollide = false
	local hinge = L(-10, 0.08, 7)
	local offset = hinge:ToObjectSpace(h.CFrame)
	TweenService:Create(h, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = hinge * ANG(rad(-100), 0, 0) * offset }):Play()
	Net.event("Sound"):FireAllClients("DoorOpen", h.Position)
	Cannibals.noise(h.Position, 60)
	say("You", "It's open. There's a ladder... and someone breathing down there.", 4)
	changed()
end

-- After the reveal: the bolt cutters appear upstairs and the hatch can be cut.
function Cellar.enable(sayFn: Say, onChanged: () -> ())
	if state.enabled then
		return
	end
	state.enabled = true
	say = sayFn
	changed = onChanged
	local f = folder
	if f then
		cuttersPickup = Pickups.spawn("BoltCutters", L(22, U + 3.3, 21.5) * ANG(0, rad(30), 0), f, {
			onPicked = function()
				state.cuttersTaken = true
				say("You", "Bolt cutters. That padlock on the kitchen hatch...", 3.5)
				changed()
			end,
		})
	end
	local h = hatch
	if h then
		for _, d in h:GetChildren() do
			if d:IsA("ProximityPrompt") then
				d:Destroy() -- the clue prompt; the hatch is a way in now
			end
		end
		Interact.add(h, {
			action = "Cut padlock",
			object = "Cellar hatch",
			hold = 1.5,
			distance = 7,
			once = true,
			canUse = function(player)
				if not Inventory.has(player, "BoltCutters") then
					return false, "A heavy padlock. Something's knocking underneath. I need something to cut it."
				end
				return true
			end,
			onUse = function()
				openHatch()
			end,
		})
	end
end

export type Objective = { text: string, done: boolean, optional: boolean? }

function Cellar.objectives(): { Objective }
	local list: { Objective } = {}
	if not state.enabled or (state.gone and not state.rescued) then
		return list
	end
	local function add(text: string, done: boolean)
		table.insert(list, { text = text, done = done, optional = true })
	end
	add("Find something to cut the cellar padlock", state.cuttersTaken or state.hatchOpen)
	if state.cuttersTaken or state.hatchOpen then
		add("Open the cellar hatch in the kitchen", state.hatchOpen)
	end
	if state.hatchOpen then
		add("Free whoever is knocking", state.freed)
	end
	if state.freed then
		add("Get Tom Ellis out of the house", state.rescued)
	end
	return list
end

function Cellar.hintTargets(): { Vector3 }
	local list: { Vector3 } = {}
	if not state.enabled or state.gone then
		return list
	end
	local pickup = cuttersPickup
	if not state.cuttersTaken and pickup and pickup.Parent then
		table.insert(list, pickup:GetPivot().Position)
	elseif not state.hatchOpen and hatch then
		table.insert(list, (hatch :: BasePart).Position)
	elseif not state.freed and tom then
		table.insert(list, (tom :: any).root.Position)
	end
	return list
end

function Cellar.rescued(): boolean
	return state.rescued
end

return Cellar

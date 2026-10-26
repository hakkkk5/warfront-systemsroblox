--!strict
-- Out in the woods, one of the family waits up a tree. Now and then, ahead
-- of someone walking outdoors, it crouches among the branches of a tree on
-- their way (a dark shape, two dull eyes, a creak as they get close), and
-- when they pass underneath it drops on them and gives chase. If nobody
-- comes by it climbs back down out of sight; after a chase it goes back to
-- the trees. One at a time, more often the harder the night.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Cannibals = require(script.Parent.Cannibals)

local Ambush = {}

local KIND = "Kin"
local OUTDOORS: { [string]: boolean } = { Forest = true, Repair = true, Hunt = true, Power = true, Radio = true, Survive = true }
local GAPS: { [string]: number } = { Easy = 240, Normal = 150, Hard = 110, Nightmare = 80 }
local DROP_RANGE = 9 -- straight under it, near enough
local WAIT_FOR = 25 -- a perch nobody walks under
local CHASE_FOR = 45

local soundRemote = Net.event("Sound")
local trees: Instance? = nil
local nextAmbush = 0
local busy = false

local function outdoorsAt(pos: Vector3): boolean
	local house = Config.Sites.House
	return (Vector2.new(pos.X, pos.Z) - house.pos).Magnitude > house.radius
end

-- A tree ahead of the player, 18-45 studs along the way they're walking.
local function treeAhead(root: BasePart): Model?
	local folder = trees
	if not folder then
		return nil
	end
	local heading = Util.flat(root.AssemblyLinearVelocity)
	if heading.Magnitude < 4 then
		return nil
	end
	heading = heading.Unit
	local best: Model? = nil
	local bestScore = -math.huge
	for _, tree in folder:GetChildren() do
		if tree:IsA("Model") then
			local to = Util.flat(tree:GetPivot().Position - root.Position)
			local d = to.Magnitude
			if d > 18 and d < 45 then
				local along = heading:Dot(to.Unit)
				if along > 0.8 and along - d / 200 > bestScore then
					best, bestScore = tree, along - d / 200
				end
			end
		end
	end
	return best
end

-- The shape up in the branches: the family's template, still, crouched
-- against the trunk and facing the way the player will come.
local function perch(tree: Model, facing: Vector3): (Model?, CFrame)
	local templates = ReplicatedStorage:FindFirstChild("CannibalTemplates")
	local template = templates and templates:FindFirstChild(KIND)
	local base = tree:GetPivot()
	local height = tree:GetExtentsSize().Y
	local at = base.Position + Vector3.new(0, math.clamp(height * 0.42, 11, 20), 0)
	local cf = CFrame.lookAt(at, Vector3.new(facing.X, at.Y, facing.Z)) * CFrame.new(0, 0, -1.2)
	if not (template and template:IsA("Model")) then
		return nil, cf
	end
	local shape = template:Clone()
	for _, p in shape:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
		end
	end
	shape:PivotTo(cf * CFrame.Angles(math.rad(-25), 0, 0))
	shape.Name = "Perched"
	shape.Parent = workspace
	return shape, cf
end

local function ambush(player: Player, tree: Model)
	busy = true
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		busy = false
		return
	end
	local shape, cf = perch(tree, root.Position)
	local treePos = tree:GetPivot().Position
	local started = os.clock()
	local creaked = false
	local dropped = false
	while os.clock() - started < WAIT_FOR do
		task.wait(0.15)
		local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not (r and r:IsA("BasePart")) or player:GetAttribute("Hidden") then
			break
		end
		local d = Util.flat(r.Position - treePos).Magnitude
		if not creaked and d < 24 then
			creaked = true
			soundRemote:FireAllClients("DoorOpen", cf.Position) -- a branch creaks
		end
		if d < DROP_RANGE then
			dropped = true
			break
		end
	end
	if shape then
		shape:Destroy()
	end
	if not dropped then
		busy = false
		nextAmbush = os.clock() + 30
		return
	end
	-- it drops
	soundRemote:FireAllClients("Scream", cf.Position)
	local c = Cannibals.spawn(KIND, cf - Vector3.new(0, 3.5, 0), { chase = player })
	local chaseStart = os.clock()
	local lostSince: number? = nil
	while c.alive and os.clock() - chaseStart < CHASE_FOR do
		task.wait(0.5)
		if c.state == "Chase" then
			lostSince = nil
		else
			lostSince = lostSince or os.clock()
			if os.clock() - (lostSince :: number) > 10 then
				break
			end
		end
	end
	-- back up into the trees, out of sight
	if c.alive and c.state ~= "Sedated" then
		Cannibals.remove(c)
	elseif c.alive then
		task.delay(60, function()
			if c.alive then
				Cannibals.remove(c)
			end
		end)
	end
	busy = false
	nextAmbush = os.clock() + (GAPS[Difficulty.current()] or 150)
end

local function tick()
	local stage = workspace:GetAttribute("Stage")
	if busy or not OUTDOORS[stage or ""] or os.clock() < nextAmbush then
		return
	end
	local candidates: { Player } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and outdoorsAt(root.Position)
			and not player:GetAttribute("Hidden") and not player:GetAttribute("InCutscene") and player:GetAttribute("Chased") ~= true
		then
			table.insert(candidates, player)
		end
	end
	if #candidates == 0 then
		return
	end
	local player = candidates[math.random(#candidates)]
	local root = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
	local tree = treeAhead(root)
	if tree then
		task.spawn(ambush, player, tree)
	end
end

function Ambush.init(world: Instance)
	trees = world:FindFirstChild("Trees", true)
	-- the first one a while into being outdoors
	nextAmbush = os.clock() + 60
	workspace:GetAttributeChangedSignal("Stage"):Connect(function()
		if OUTDOORS[workspace:GetAttribute("Stage") or ""] then
			nextAmbush = math.max(nextAmbush, os.clock() + 45)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(3)
			xpcall(tick, function(err)
				warn("[Ambush] " .. tostring(err))
			end)
		end
	end)
end

return Ambush

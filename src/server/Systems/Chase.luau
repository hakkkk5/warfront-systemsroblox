--!strict
-- The chase after the truck blows up. Jason comes out of the fire as the
-- monster and runs you down through the woods to the ranger station:
--
--   * adrenaline: everyone runs at full speed, no stamina limit
--   * the monster is kept right behind whoever is closest (rubber band)
--   * corrupted spikes burst out of the ground where you are about to run,
--     after a red warning circle
--   * burning trees come down across the path after a red warning strip,
--     and lie there as burning obstacles
--   * a marked route; the chase ends when someone reaches the station door
--
-- Clients draw the warnings, spikes and trees (ChaseFX.luau); the server
-- decides where and who gets hurt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Build = require(script.Parent.Parent.World.Build)
local Terrain = require(script.Parent.Parent.World.Terrain)
local Cannibals = require(script.Parent.Cannibals)

local Chase = {}

local SPIKE_DELAY = 0.9
local SPIKE_RADIUS = 3.8
local SPIKE_DAMAGE = 22
local TREE_DELAY = 1.25
local TREE_LENGTH = 18
local TREE_DAMAGE = 30

local fx = Net.event("ChaseFX")
local hurtRemote = Net.event("Hurt")

local running = false
local route: { Vector3 } = {}
local routeIndex = 1
local finish: Vector3 = Vector3.zero
local monster: Cannibals.Cannibal? = nil
local parent: Instance = workspace
local progress: () -> () = function() end

local function ground(x: number, z: number): Vector3
	return Vector3.new(x, Terrain.groundY(x, z), z)
end

local function alivePlayers(): { { player: Player, root: BasePart, humanoid: Humanoid } }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			table.insert(list, { player = player, root = root, humanoid = humanoid })
		end
	end
	return list
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function hurt(player: Player, humanoid: Humanoid, root: BasePart, amount: number, from: Vector3, launch: Vector3)
	if player:GetAttribute("AdminGod") then
		return
	end
	player:SetAttribute("LastAttacker", "Butcher")
	humanoid:TakeDamage(amount)
	hurtRemote:FireClient(player, amount, from)
	root.AssemblyLinearVelocity += launch
end

-- Spikes where someone is about to be.
local function spikes()
	local players = alivePlayers()
	if #players == 0 then
		return
	end
	local who = players[math.random(#players)]
	local v = flat(who.root.AssemblyLinearVelocity)
	local ahead = who.root.Position + v * 1.0 + Vector3.new(math.random(-5, 5), 0, math.random(-5, 5))
	local spot = ground(ahead.X, ahead.Z)
	fx:FireAllClients("spike", spot, SPIKE_DELAY)
	task.delay(SPIKE_DELAY, function()
		if not running then
			return
		end
		for _, p in alivePlayers() do
			if flat(p.root.Position - spot).Magnitude < SPIKE_RADIUS and math.abs(p.root.Position.Y - spot.Y) < 8 then
				hurt(p.player, p.humanoid, p.root, SPIKE_DAMAGE, spot, Vector3.new(0, 55, 0))
			end
		end
	end)
end

-- A burning tree comes down across the path ahead.
local function fallingTree()
	local players = alivePlayers()
	if #players == 0 then
		return
	end
	local who = players[math.random(#players)]
	local v = flat(who.root.AssemblyLinearVelocity)
	local dir = if v.Magnitude > 2 then v.Unit else flat(who.root.CFrame.LookVector).Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local side = if math.random() < 0.5 then 1 else -1
	local landing = who.root.Position + dir * math.random(26, 38)
	local base = ground(landing.X + right.X * side * TREE_LENGTH / 2, landing.Z + right.Z * side * TREE_LENGTH / 2)
	local fall = -right * side -- it falls across the path
	fx:FireAllClients("tree", base, fall, TREE_LENGTH, TREE_DELAY)
	task.delay(TREE_DELAY, function()
		if not running then
			return
		end
		local tip = base + fall * TREE_LENGTH
		for _, p in alivePlayers() do
			-- distance from the trunk's line
			local rel = flat(p.root.Position - base)
			local along = math.clamp(rel:Dot(fall), 0, TREE_LENGTH)
			local closest = flat(base) + fall * along
			if (flat(p.root.Position) - closest).Magnitude < 3 then
				hurt(p.player, p.humanoid, p.root, TREE_DAMAGE, closest, Vector3.new(0, 30, 0))
			end
		end
		-- the trunk lies there, burning, for a while: something to get around
		local mid = (base + tip) / 2
		local log = Build.cylinder(parent, TREE_LENGTH, 2.2, CFrame.lookAt(mid + Vector3.new(0, 1.1, 0), tip + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(40, 28, 20), Enum.Material.Wood)
		log.Transparency = 1 -- the clients draw the burning tree
		task.delay(10, function()
			log:Destroy()
		end)
	end)
end

-- Keep the monster right on the closest player's heels.
local function direct()
	local c = monster
	if not c or not c.alive then
		return
	end
	local players = alivePlayers()
	local best = nil
	local bestD = math.huge
	for _, p in players do
		local d = (p.root.Position - c.root.Position).Magnitude
		if d < bestD then
			bestD = d
			best = p
		end
	end
	if not best then
		return
	end
	if bestD > 55 then
		-- fell behind: it comes out of the trees right behind them
		local back = flat(best.root.Position) - flat(best.root.AssemblyLinearVelocity).Unit * 26
		if back.X ~= back.X then
			back = flat(best.root.Position) - flat(best.root.CFrame.LookVector) * 26
		end
		local g = ground(back.X, back.Z)
		c.root.CFrame = CFrame.new(g + Vector3.new(0, 4, 0))
		Net.event("Sound"):FireAllClients("Growl", g)
	end
	-- as fast as you, a touch faster if you slow down
	c.speedMult = if bestD > 22 then 1.75 elseif bestD > 10 then 1.55 else 1.3
	c.hunting = true
end

local function advanceRoute()
	for _, p in alivePlayers() do
		local target = route[routeIndex]
		if target and flat(p.root.Position - target).Magnitude < 18 and routeIndex < #route then
			routeIndex += 1
			progress()
		end
	end
end

-- route: waypoints to the station; finishAt: the station door; onArrive
-- fires once when someone gets there.
function Chase.start(folder: Instance, waypoints: { Vector3 }, finishAt: Vector3, butcher: Cannibals.Cannibal?, onArrive: () -> (), onProgress: () -> ())
	if running then
		return
	end
	running = true
	parent = folder
	route = waypoints
	routeIndex = 1
	finish = finishAt
	monster = butcher
	progress = onProgress
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Adrenaline", true)
	end
	local difficulty = workspace:GetAttribute("Difficulty")
	local spikeGap = if difficulty == "Easy" then 2.6 elseif difficulty == "Hard" then 1.4 elseif difficulty == "Nightmare" then 1.0 else 1.9
	local treeGap = if difficulty == "Easy" then 7 elseif difficulty == "Hard" then 4.5 elseif difficulty == "Nightmare" then 3.5 else 5.5
	task.spawn(function()
		local nextSpike = os.clock() + 2.5
		local nextTree = os.clock() + 4
		while running do
			task.wait(0.1)
			local now = os.clock()
			direct()
			advanceRoute()
			if now >= nextSpike then
				nextSpike = now + spikeGap * (0.75 + math.random() * 0.5)
				spikes()
			end
			if now >= nextTree then
				nextTree = now + treeGap * (0.75 + math.random() * 0.5)
				fallingTree()
			end
			for _, p in alivePlayers() do
				if flat(p.root.Position - finish).Magnitude < 12 then
					Chase.stop()
					task.spawn(onArrive)
					break
				end
			end
		end
	end)
end

function Chase.stop()
	running = false
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Adrenaline", nil)
	end
	local c = monster
	if c then
		c.speedMult = 1
	end
	monster = nil
end

function Chase.running(): boolean
	return running
end

-- The next point on the marked route (for the on-screen goal marker).
function Chase.goal(): Vector3?
	if not running then
		return nil
	end
	return route[routeIndex] or finish
end

return Chase

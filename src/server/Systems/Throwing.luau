--!strict
-- Throwing what you hold (Items: throwable). Bottles smash and rocks thud
-- where they land, and the family goes to look; a molotov sets the ground on
-- fire and knocks down anyone of them standing in it; a noise trap starts
-- ringing a few seconds after it lands, and keeps at it.
--
-- The client sends its aim (the camera's look); the server checks the held
-- item and flies it, raycasting the arc each frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local AssetService = require(script.Parent.AssetService)
local Cannibals = require(script.Parent.Cannibals)
local Inventory = require(script.Parent.Inventory)

local Throwing = {}

-- (player) a throw landed where one of the family heard it
Throwing.Distracted = Signal.new() :: Signal.Signal<Player>
-- (player) a molotov knocked one of them down
Throwing.Burned = Signal.new() :: Signal.Signal<Player>

local SPEED = 78
local LIFT = 12
local GRAVITY = Vector3.new(0, -110, 0)
local MAX_TIME = 4
local COOLDOWN = 0.7
local FIRE_TIME = 8
local FIRE_RADIUS = 6.5
local STUN_TIME = 6
local TRAP_DELAY = 4
local TRAP_RINGS = 6

local lastThrow: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local folder: Folder

local soundRemote = Net.event("Sound")

local function sound(name: string, at: Vector3)
	soundRemote:FireAllClients(name, at)
end

local function canThrow(player: Player): boolean
	if player:GetAttribute("InCutscene") or player:GetAttribute("Hidden") or player:GetAttribute("Struggling") then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function shards(at: Vector3)
	for _ = 1, 6 do
		local p = Instance.new("Part")
		p.Size = Vector3.new(0.18, 0.04, 0.12)
		p.Material = Enum.Material.Glass
		p.Color = Color3.fromRGB(90, 130, 90)
		p.Transparency = 0.3
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = CFrame.new(at + Vector3.new(0, 0.3, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		p.AssemblyLinearVelocity = Vector3.new(math.random(-8, 8), math.random(4, 9), math.random(-8, 8))
		p.Parent = folder
		task.delay(4, function()
			p:Destroy()
		end)
	end
end

local function fire(player: Player, at: Vector3)
	local patch = Instance.new("Part")
	patch.Name = "MolotovFire"
	patch.Shape = Enum.PartType.Cylinder
	patch.Size = Vector3.new(0.2, FIRE_RADIUS * 2, FIRE_RADIUS * 2)
	patch.CFrame = CFrame.new(at + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	patch.Anchored = true
	patch.CanCollide = false
	patch.CanQuery = false
	patch.Material = Enum.Material.Neon
	patch.Color = Color3.fromRGB(255, 110, 30)
	patch.Transparency = 0.55
	patch.Parent = folder
	for i = 1, 3 do
		local a = Instance.new("Attachment")
		a.Position = Vector3.new(0, (i - 2) * 2.4, (i % 2) * 2 - 1)
		a.Parent = patch
		local f = Instance.new("Fire")
		f.Size = 6
		f.Heat = 9
		f.Color = Color3.fromRGB(255, 120, 40)
		f.SecondaryColor = Color3.fromRGB(255, 40, 10)
		f.Parent = a
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Brightness = 3
	light.Range = 26
	light.Parent = patch
	task.spawn(function()
		local ends = os.clock() + FIRE_TIME
		while os.clock() < ends do
			for _, c in Cannibals.all() do
				if (c.root.Position - at).Magnitude < FIRE_RADIUS and Cannibals.stun(c, STUN_TIME) then
					Throwing.Burned:Fire(player)
				end
			end
			for _, other in Players:GetPlayers() do
				local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
				if root and root:IsA("BasePart") and humanoid and (root.Position - at).Magnitude < FIRE_RADIUS - 1.5 then
					humanoid:TakeDamage(4)
				end
			end
			task.wait(0.4)
		end
		light.Brightness = 0.5
		for _, d in patch:GetDescendants() do
			if d:IsA("Fire") then
				d.Enabled = false
			end
		end
		task.wait(2)
		patch:Destroy()
	end)
end

local function trap(at: Vector3)
	local model = AssetService.create("NoiseTrap")
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, math.random() * 6, 0))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	model.Parent = folder
	task.spawn(function()
		task.wait(TRAP_DELAY)
		for _ = 1, TRAP_RINGS do
			if not model.Parent then
				return
			end
			sound("AlarmBell", at)
			Cannibals.noise(at, 130)
			task.wait(2)
		end
		task.wait(1)
		model:Destroy()
	end)
end

local function impact(player: Player, id: string, at: Vector3)
	local def = Items.get(id)
	local radius = (def and def.noise) or 50
	if id ~= "NoiseTrap" and #Cannibals.listeners(at, radius) > 0 then
		Throwing.Distracted:Fire(player)
	end
	if id == "Bottle" then
		sound("GlassBreak", at)
		shards(at)
		Cannibals.noise(at, radius)
	elseif id == "Rock" then
		sound("Impact", at)
		Cannibals.noise(at, radius)
	elseif id == "Molotov" then
		sound("GlassBreak", at)
		Cannibals.noise(at, radius)
		fire(player, at)
	elseif id == "NoiseTrap" then
		if #Cannibals.listeners(at, 130) > 0 then
			Throwing.Distracted:Fire(player)
		end
		trap(at)
	end
end

-- Flies the item along its arc; lands on the first thing it hits.
local function fly(player: Player, id: string, from: Vector3, velocity: Vector3)
	local model = AssetService.create((Items.get(id) :: Items.ItemDef).model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	model.Parent = folder
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	local pos, vel = from, velocity
	local started = os.clock()
	local spin = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt: number)
		vel += GRAVITY * dt
		local step = vel * dt
		local hit = workspace:Raycast(pos, step, params)
		if hit or os.clock() - started > MAX_TIME then
			conn:Disconnect()
			model:Destroy()
			local at = if hit then hit.Position + hit.Normal * 0.2 else pos
			impact(player, id, at)
			return
		end
		pos += step
		spin += dt * 12
		model:PivotTo(CFrame.new(pos) * CFrame.Angles(spin, spin * 0.6, 0))
	end)
end

local function throw(player: Player, aim: any)
	if typeof(aim) ~= "Vector3" or aim.Magnitude < 0.5 or aim ~= aim then
		return
	end
	local now = os.clock()
	if now - (lastThrow[player] or 0) < COOLDOWN or not canThrow(player) then
		return
	end
	local id = Inventory.equipped(player)
	local def = id and Items.get(id)
	if not id or not def or not def.throwable or not Inventory.remove(player, id, 1) then
		return
	end
	lastThrow[player] = now
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local dir = aim.Unit
	sound("Whoosh", head.Position)
	fly(player, id, head.Position + dir * 1.6, dir * SPEED + Vector3.new(0, LIFT, 0))
end

function Throwing.init()
	folder = Instance.new("Folder")
	folder.Name = "Thrown"
	folder.Parent = workspace
	Net.event("Throw").OnServerEvent:Connect(throw)
end

return Throwing

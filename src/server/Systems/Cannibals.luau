--!strict
-- Cannibal NPCs: rig construction, perception (sight cone + hearing),
-- patrol / investigate / chase / search behaviour, attacks, sedation and
-- dragging players out of hiding spots.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Util = require(ReplicatedStorage.Shared.Util)
local Props = require(script.Parent.Parent.World.Props)
local Doors = require(script.Parent.Doors)
local Hiding = require(script.Parent.Hiding)
local Interact = require(script.Parent.Interact)
local Inventory = require(script.Parent.Inventory)

local Cannibals = {}

local rgb = Color3.fromRGB
local TUNE = Config.Cannibal

export type KindSpec = {
	display: string,
	height: number,
	width: number,
	skin: Color3,
	shirt: Color3,
	pants: Color3,
	walk: number,
	run: number,
	damage: number,
	weapon: string, -- "Cleaver" | "Chainsaw"
	mask: string, -- "Sack" | "Stitched" | "Skin"
	apron: boolean?,
	lantern: boolean?,
	keys: boolean?,
}

local KINDS: { [string]: KindSpec } = {
	Butcher = {
		display = "Jason",
		height = 1.15,
		width = 1.3,
		skin = rgb(190, 150, 128),
		shirt = rgb(132, 120, 100),
		pants = rgb(46, 42, 38),
		walk = 8.5,
		run = 16.5,
		damage = 38,
		weapon = "Cleaver",
		mask = "Sack",
		apron = true,
		keys = true,
	},
	Brother = {
		display = "Michel",
		height = 1.02,
		width = 0.9,
		skin = rgb(206, 176, 156),
		shirt = rgb(90, 84, 70),
		pants = rgb(54, 50, 60),
		walk = 9,
		run = 17.5,
		damage = 30,
		weapon = "Cleaver",
		mask = "Stitched",
	},
	Hunter = {
		display = "The Hunter",
		height = 1.08,
		width = 1.05,
		skin = rgb(176, 140, 116),
		shirt = rgb(70, 76, 52),
		pants = rgb(52, 46, 36),
		walk = 8.5,
		run = 17,
		damage = 32,
		weapon = "Cleaver",
		mask = "Sack",
		lantern = true,
	},
	Scavenger = {
		display = "The Scavenger",
		height = 0.95,
		width = 0.85,
		skin = rgb(200, 168, 146),
		shirt = rgb(110, 60, 46),
		pants = rgb(40, 40, 44),
		walk = 9.5,
		run = 18,
		damage = 26,
		weapon = "Cleaver",
		mask = "Stitched",
	},
	Papa = {
		display = "Papa",
		height = 1.25,
		width = 1.4,
		skin = rgb(184, 146, 120),
		shirt = rgb(100, 94, 82),
		pants = rgb(36, 34, 32),
		walk = 8,
		run = 18.5,
		damage = 55,
		weapon = "Chainsaw",
		mask = "Skin",
		apron = true,
	},
	Kin = {
		display = "Kin",
		height = 1,
		width = 1,
		skin = rgb(196, 162, 140),
		shirt = rgb(84, 70, 56),
		pants = rgb(44, 42, 40),
		walk = 9,
		run = 17.5,
		damage = 30,
		weapon = "Cleaver",
		mask = "Sack",
	},
}
Cannibals.Kinds = KINDS

-- Locomotion (idle / walk / run) is played on every client by
-- KeyframeAnimator from the rig's speed; the server only plays the swing.
local ANIMS: { [string]: string } = {
	attack = "rbxassetid://129967390",
}

export type State = "Patrol" | "Idle" | "Investigate" | "Chase" | "Search" | "Sedated" | "Grab" | "Paused"

export type Cannibal = {
	kind: string,
	spec: KindSpec,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	head: BasePart,
	state: State,
	stateTime: number,
	patrol: { Vector3 },
	patrolIndex: number,
	waitUntil: number,
	target: Player?,
	lastSeenPos: Vector3?,
	lastSeenTime: number,
	investigatePos: Vector3?,
	searchUntil: number,
	searchPoint: Vector3?,
	detection: { [Player]: number },
	path: Path,
	waypoints: { PathWaypoint }?,
	wpIndex: number,
	moveGoal: Vector3?,
	lastPathTime: number,
	attackReady: number,
	attacking: boolean,
	sedatedUntil: number,
	hasKeys: boolean,
	hunting: boolean,
	alive: boolean,
	eyes: { BasePart },
	tracks: { [string]: AnimationTrack },
	currentTrack: string?,
	stuckSince: number?,
	lastPos: Vector3,
	prompt: ProximityPrompt?,
	nextHunt: number,
	struggling: boolean,
	speedMult: number, -- the chase director pushes it to keep up
}

local folder = Instance.new("Folder")
folder.Name = "Cannibals"
folder.Parent = workspace

local list: { Cannibal } = {}
local paused = false

local hurtRemote = Net.event("Hurt")
local soundRemote = Net.event("Sound")

-- (cannibal, player) fired when a cannibal is sedated
Cannibals.Sedated = Signal.new() :: Signal.Signal<Cannibal, Player>

---------------------------------------------------------------- rigs

local function weldTo(part: BasePart, to: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
end

local function attachModel(model: Model, to: BasePart, cf: CFrame, parent: Instance)
	model:PivotTo(cf)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			weldTo(p, to)
		end
	end
	model.Parent = parent
end

local function addPart(parent: Instance, to: BasePart, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	weldTo(p, to)
	return p
end

local function buildR6(spec: KindSpec): Model
	local rig = Instance.new("Model")
	local s = spec.height
	local function limb(name: string, size: Vector3, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * s
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = rig
		return p
	end
	local root = limb("HumanoidRootPart", Vector3.new(2, 2, 1), spec.shirt)
	root.Transparency = 1
	local torso = limb("Torso", Vector3.new(2 * spec.width, 2, 1), spec.shirt)
	local head = limb("Head", Vector3.new(2, 1, 1), spec.skin)
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = head
	local la = limb("Left Arm", Vector3.new(1, 2, 1), spec.skin)
	local ra = limb("Right Arm", Vector3.new(1, 2, 1), spec.skin)
	local ll = limb("Left Leg", Vector3.new(1, 2, 1), spec.pants)
	local rl = limb("Right Leg", Vector3.new(1, 2, 1), spec.pants)

	local function motor(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = c0
		m.C1 = c1
		m.MaxVelocity = 0.1
		m.Parent = p0
	end
	local w = spec.width
	motor("RootJoint", root, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Neck", torso, head, CFrame.new(0, s, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5 * s, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Right Shoulder", torso, ra, CFrame.new(w * s, 0.5 * s, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5 * s, 0.5 * s, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Shoulder", torso, la, CFrame.new(-w * s, 0.5 * s, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5 * s, 0.5 * s, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Right Hip", torso, rl, CFrame.new(s, -s, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5 * s, s, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Hip", torso, ll, CFrame.new(-s, -s, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5 * s, s, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 0
	humanoid.Parent = rig
	rig.PrimaryPart = root
	root.CFrame = CFrame.new(0, 3 * s, 0)
	torso.CFrame = root.CFrame
	return rig
end

local function createRig(spec: KindSpec): Model
	local desc = Instance.new("HumanoidDescription")
	desc.HeightScale = spec.height
	desc.WidthScale = spec.width
	desc.DepthScale = (spec.width + 1) / 2
	desc.HeadScale = 1
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	desc.HeadColor = spec.skin
	desc.LeftArmColor = spec.skin
	desc.RightArmColor = spec.skin
	desc.TorsoColor = spec.shirt
	desc.LeftLegColor = spec.pants
	desc.RightLegColor = spec.pants
	-- R6 like the players, so the baked R6 run/walk/idle clips fit
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)
	if ok and result then
		if spec.height ~= 1 then
			pcall(function()
				result:ScaleTo(spec.height)
			end)
		end
		return result
	end
	warn("[Cannibals] R6 rig unavailable, using the block fallback: " .. tostring(result))
	return buildR6(spec)
end

local function dress(rig: Model, spec: KindSpec, kind: string): { BasePart }
	local head = rig:FindFirstChild("Head") :: BasePart
	local torso = (rig:FindFirstChild("UpperTorso") or rig:FindFirstChild("Torso")) :: BasePart
	local lower = (rig:FindFirstChild("LowerTorso") or torso) :: BasePart
	local rightHand = (rig:FindFirstChild("RightHand") or rig:FindFirstChild("Right Arm")) :: BasePart
	local leftHand = (rig:FindFirstChild("LeftHand") or rig:FindFirstChild("Left Arm")) :: BasePart
	local gear = Instance.new("Model")
	gear.Name = "Gear"
	gear.Parent = rig

	for _, d in head:GetChildren() do
		if d:IsA("Decal") then
			d:Destroy()
		end
	end

	local eyes: { BasePart } = {}
	local hs = head.Size
	if head:FindFirstChildOfClass("SpecialMesh") then
		-- R6 head: a 2x1x1 part showing a rounder mesh about 1.2 across
		local k = head.Size.Y * 1.2
		hs = Vector3.new(k, k, k)
	end
	local hcf = head.CFrame
	local maskSize = Vector3.new(hs.X * 1.18, hs.Y * 1.22, hs.Z * 1.18)

	local maskGroup: Instance = gear
	if spec.mask == "Sack" then
		-- grouped so clients can swap in the Blender sack mask (MeshLibrary)
		local sackModel = Instance.new("Model")
		maskGroup = sackModel
		sackModel.Name = "SackMask"
		sackModel.Parent = gear
		local sack = addPart(sackModel, head, maskSize, hcf * CFrame.new(0, 0.05, 0), rgb(138, 112, 78), Enum.Material.Fabric)
		sack.Name = "Mask"
		addPart(sackModel, head, Vector3.new(maskSize.X * 0.5, 0.35, maskSize.Z * 0.5), hcf * CFrame.new(0, maskSize.Y / 2 + 0.1, 0) * CFrame.Angles(0, 0.4, 0.15), rgb(120, 98, 68), Enum.Material.Fabric)
		addPart(sackModel, head, Vector3.new(maskSize.X * 1.04, 0.16, maskSize.Z * 1.04), hcf * CFrame.new(0, -maskSize.Y / 2 + 0.15, 0), rgb(170, 150, 108), Enum.Material.Fabric)
		sackModel.WorldPivot = hcf * CFrame.new(0, 0.05, 0)
		sackModel:SetAttribute("Mesh", "SackMask")
		game:GetService("CollectionService"):AddTag(sackModel, "BlenderMesh")
	elseif spec.mask == "Stitched" then
		local mask = addPart(gear, head, maskSize * Vector3.new(1, 0.95, 1), hcf, rgb(214, 186, 160), Enum.Material.Leather)
		mask.Name = "Mask"
		for i = -2, 2 do
			addPart(gear, head, Vector3.new(0.05, maskSize.Y * 0.9, 0.05), hcf * CFrame.new(i * 0.18, 0, -maskSize.Z / 2 - 0.01) * CFrame.Angles(0, 0, i * 0.2), rgb(40, 24, 20), Enum.Material.Fabric)
		end
	else -- "Skin": pale patchwork with a wide grin
		local mask = addPart(gear, head, maskSize, hcf, rgb(222, 196, 172), Enum.Material.Leather)
		mask.Name = "Mask"
		addPart(gear, head, Vector3.new(maskSize.X * 0.55, 0.12, 0.05), hcf * CFrame.new(0, -0.32, -maskSize.Z / 2 - 0.01), rgb(60, 14, 12), Enum.Material.SmoothPlastic)
		addPart(gear, head, Vector3.new(maskSize.X * 1.1, 0.7, maskSize.Z * 1.1), hcf * CFrame.new(0, maskSize.Y / 2 + 0.2, 0), rgb(52, 44, 36), Enum.Material.Fabric)
	end

	-- eye holes with a faint glow that brightens during a chase
	for _, x in { -0.22, 0.22 } do
		local hole = addPart(maskGroup, head, Vector3.new(0.26, 0.22, 0.06), hcf * CFrame.new(x * hs.X / 1.2, 0.12, -maskSize.Z / 2 - 0.02), rgb(8, 6, 6), Enum.Material.SmoothPlastic)
		hole.Name = "EyeHole"
		local eye = addPart(maskGroup, head, Vector3.new(0.1, 0.08, 0.04), hcf * CFrame.new(x * hs.X / 1.2, 0.12, -maskSize.Z / 2 - 0.05), rgb(255, 40, 30), Enum.Material.Neon)
		eye.Name = "Eye"
		eye:SetAttribute("KeepVisible", true)
		eye.Transparency = 0.85
		table.insert(eyes, eye)
	end

	if spec.apron then
		local ts = torso.Size
		local apron = addPart(gear, torso, Vector3.new(ts.X * 0.85, ts.Y * 1.7, 0.12), torso.CFrame * CFrame.new(0, -ts.Y * 0.3, -ts.Z / 2 - 0.07), rgb(64, 46, 34), Enum.Material.Leather)
		apron.Name = "Apron"
		local rng = Random.new()
		for _ = 1, 5 do
			addPart(gear, torso, Vector3.new(rng:NextNumber(0.2, 0.6), rng:NextNumber(0.2, 0.7), 0.02), apron.CFrame * CFrame.new(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-1, 0.6), -0.07), rgb(80, 8, 8), Enum.Material.Glass)
		end
	end

	-- weapon in the right hand, blade pointing forward / down
	local handCF = rightHand.CFrame * CFrame.new(0, -rightHand.Size.Y / 2, 0)
	if spec.weapon == "Chainsaw" then
		local saw = Props.Chainsaw()
		attachModel(saw, rightHand, handCF * CFrame.Angles(0, 0, 0) * CFrame.new(0, -0.45, 0.4), gear)
	else
		local cleaver = Props.Cleaver()
		attachModel(cleaver, rightHand, handCF * CFrame.Angles(math.pi * 0.55, 0, 0) * CFrame.new(0, -0.3, 0), gear)
	end

	if spec.lantern then
		local lantern = Props.Lantern()
		attachModel(lantern, leftHand, leftHand.CFrame * CFrame.new(0, -leftHand.Size.Y / 2 - 1.1, 0), gear)
	end

	if spec.keys then
		local keys = Props.CarKeys()
		keys.Name = "BeltKeys"
		attachModel(keys, lower, lower.CFrame * CFrame.new(lower.Size.X / 2 + 0.05, 0, -0.1) * CFrame.Angles(0, 0, math.rad(90)), gear)
		for _, p in keys:GetDescendants() do
			if p:IsA("BasePart") and p.Size.X > 0.3 then
				p.Material = Enum.Material.Neon
				p.Color = rgb(255, 210, 120)
			end
		end
	end

	-- Clients dress the rig in its Blender body (CannibalSkins, meshes from
	-- tools/blender/build_monsters.py). That body brings its own mask and
	-- apron, so the pieces above are costume to hide under it; the weapon and
	-- lantern are held items, put away when the claws come out.
	for _, child in gear:GetChildren() do
		local name = child.Name
		if name == "Cleaver" or name == "Chainsaw" or name == "Lantern" then
			child:SetAttribute("Held", true)
		elseif name ~= "BeltKeys" and name ~= "Eye" then
			child:SetAttribute("Costume", true)
		end
	end
	rig:SetAttribute("Skin", kind)
	rig:SetAttribute("SkinScale", spec.height)
	CollectionService:AddTag(rig, "CannibalSkin")

	return eyes
end

-- Visual-only copies used by client cutscenes and jumpscares.
function Cannibals.publishTemplates()
	local templates = Instance.new("Folder")
	templates.Name = "CannibalTemplates"
	for kind, spec in KINDS do
		local rig = createRig(spec)
		dress(rig, spec, kind)
		rig.Name = kind
		for _, p in rig:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanCollide = false
			elseif p:IsA("Script") then
				p:Destroy()
			end
		end
		rig.Parent = templates
	end
	templates.Parent = ReplicatedStorage
end

---------------------------------------------------------------- animation

-- Clients pick idle / walk / run from the rig's speed (KeyframeAnimator);
-- the server only tells them when to stop (sedated, lying on the floor).
local function setAnim(c: Cannibal, name: string, _speed: number?)
	if c.currentTrack == name then
		return
	end
	c.currentTrack = name
	c.model:SetAttribute("AnimForce", if name == "none" then "none" else nil)
end

local function updateLocomotionAnim(c: Cannibal)
	local speed = Util.flat(c.root.AssemblyLinearVelocity).Magnitude
	if c.state == "Sedated" then
		setAnim(c, "none")
	elseif speed < 0.8 then
		setAnim(c, "idle")
	elseif speed > c.spec.walk * 1.3 then
		setAnim(c, "run", speed / 16)
	else
		setAnim(c, "walk", speed / 9)
	end
end

---------------------------------------------------------------- movement

local function moveTo(c: Cannibal, goal: Vector3, speed: number)
	c.humanoid.WalkSpeed = speed * c.speedMult
	local now = os.clock()
	local needPath = c.moveGoal == nil
		or (c.moveGoal :: Vector3 - goal).Magnitude > 5
		or now - c.lastPathTime > 2.2
		or c.waypoints == nil

	if needPath then
		c.moveGoal = goal
		c.lastPathTime = now
		local ok = pcall(function()
			c.path:ComputeAsync(c.root.Position, goal)
		end)
		if ok and c.path.Status == Enum.PathStatus.Success then
			c.waypoints = c.path:GetWaypoints()
			c.wpIndex = 2
		else
			c.waypoints = nil
			c.humanoid:MoveTo(goal)
			return
		end
	end

	local wps = c.waypoints
	if not wps then
		c.humanoid:MoveTo(goal)
		return
	end
	local wp = wps[c.wpIndex]
	while wp and Util.flat(wp.Position - c.root.Position).Magnitude < 2.6 do
		c.wpIndex += 1
		wp = wps[c.wpIndex]
	end
	if wp then
		c.humanoid:MoveTo(wp.Position)
	else
		c.humanoid:MoveTo(goal)
	end
end

local function stop(c: Cannibal)
	c.humanoid:MoveTo(c.root.Position)
	c.waypoints = nil
	c.moveGoal = nil
end

local function arrived(c: Cannibal, pos: Vector3, radius: number): boolean
	return Util.flat(pos - c.root.Position).Magnitude < radius
end

---------------------------------------------------------------- perception

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true

local function refreshLosFilter()
	local exclude: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	losParams.FilterDescendantsInstances = exclude
end

local function lineOfSight(from: Vector3, to: Vector3): boolean
	local dir = to - from
	local result = workspace:Raycast(from, dir, losParams)
	if not result then
		return true
	end
	-- glass-like or see-through parts never block sight
	local inst = result.Instance
	return inst.Transparency > 0.6
end

local function playerParts(player: Player): (Model?, Humanoid?, BasePart?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = character:FindFirstChild("Head") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not root or not head then
		return nil, nil, nil, nil
	end
	return character, humanoid, root, head
end

local function visibility(player: Player): number
	local v = 1
	if player:GetAttribute("Crouching") then
		v *= 0.55
	end
	if player:GetAttribute("Flashlight") then
		v *= 1.45
	end
	if player:GetAttribute("Sprinting") then
		v *= 1.15
	end
	return v
end

local function setState(c: Cannibal, state: State)
	if c.state == state then
		return
	end
	c.state = state
	c.stateTime = os.clock()
	c.model:SetAttribute("State", state)
	local glow = state == "Chase" or state == "Grab"
	for _, eye in c.eyes do
		eye.Transparency = if glow then 0.05 else 0.85
	end
	if state ~= "Chase" and state ~= "Grab" then
		c.target = nil
	end
end

local function startChase(c: Cannibal, player: Player)
	local wasChasing = c.state == "Chase"
	c.target = player
	setState(c, "Chase")
	c.target = player
	if not wasChasing then
		soundRemote:FireAllClients("Growl", c.head.Position)
	end
end

function Cannibals.noise(position: Vector3, radius: number)
	for _, c in list do
		if c.alive and (c.state == "Patrol" or c.state == "Idle" or c.state == "Search" or c.state == "Investigate") then
			if (c.root.Position - position).Magnitude < radius then
				c.investigatePos = position
				setState(c, "Investigate")
			end
		end
	end
end

---------------------------------------------------------------- combat

-- Just respawned: the family ignores the player for a few seconds.
local function isSafe(player: Player): boolean
	local untilTime = player:GetAttribute("SafeUntil")
	return typeof(untilTime) == "number" and os.clock() < untilTime
end

local function attack(c: Cannibal, player: Player)
	if c.attacking then
		return
	end
	c.attacking = true
	c.attackReady = os.clock() + TUNE.AttackCooldown
	stop(c)
	local track = c.tracks.attack
	if track then
		track:Play(0.1, 1, 1.3)
		-- let the swing show instead of the client walk cycle
		c.model:SetAttribute("AnimBusy", true)
		task.delay(math.max(track.Length / 1.3, 0.5), function()
			c.model:SetAttribute("AnimBusy", nil)
		end)
	end
	soundRemote:FireAllClients("Slash", c.head.Position)
	task.wait(TUNE.AttackWindup)
	local _, humanoid, root = playerParts(player)
	if humanoid and root and c.alive and c.state == "Chase" and not player:GetAttribute("Hidden") and not isSafe(player) then
		local offset = root.Position - c.root.Position
		if offset.Magnitude < TUNE.HitRange then
			player:SetAttribute("LastAttacker", c.kind)
			humanoid:TakeDamage(c.spec.damage)
			hurtRemote:FireClient(player, c.spec.damage, c.root.Position)
			root.AssemblyLinearVelocity += Util.flat(offset).Unit * 30 + Vector3.new(0, 12, 0)
		end
	end
	task.wait(0.35)
	c.attacking = false
end

-- Drag the player out of their hiding spot.
local function grab(c: Cannibal, player: Player)
	local spot = Hiding.spotOf(player)
	if not spot then
		setState(c, "Search")
		return
	end
	if not arrived(c, spot.position, 4.5) then
		moveTo(c, spot.exit.Position, c.spec.run)
		return
	end
	stop(c)
	Hiding.leave(player, true)
	local _, humanoid, root = playerParts(player)
	if humanoid and root then
		root.CFrame = c.root.CFrame * CFrame.new(0, 0, -3) * CFrame.Angles(0, math.pi, 0)
		player:SetAttribute("LastAttacker", c.kind)
		humanoid.Health = 0
	end
	setState(c, "Search")
end

---------------------------------------------------------------- sedation

function Cannibals.trySedate(c: Cannibal, player: Player): (boolean, string?)
	if c.state == "Sedated" or not c.alive then
		return false, nil
	end
	if not Inventory.has(player, "Syringe") then
		return false, "You need a sedative syringe."
	end
	local _, _, root = playerParts(player)
	if not root then
		return false, nil
	end
	if c.state == "Chase" and c.target == player and os.clock() - c.lastSeenTime < 1.5 then
		return false, "It sees you coming! Lose it, then sneak up from behind."
	end
	local toPlayer = Util.flat(root.Position - c.root.Position)
	if toPlayer.Magnitude > 0.1 and c.root.CFrame.LookVector:Dot(toPlayer.Unit) > 0.3 then
		return false, "Get behind it first."
	end
	return true, nil
end

function Cannibals.sedate(c: Cannibal, player: Player?)
	setState(c, "Sedated")
	c.sedatedUntil = os.clock() + TUNE.SedateTime
	stop(c)
	c.humanoid.PlatformStand = true
	c.root.AssemblyLinearVelocity = c.root.CFrame.LookVector * 8 + Vector3.new(0, 4, 0)
	c.root.AssemblyAngularVelocity = c.root.CFrame.RightVector * -4
	if c.prompt then
		c.prompt.Enabled = false
	end
	soundRemote:FireAllClients("Inject", c.root.Position)
	if player then
		Cannibals.Sedated:Fire(c, player)
	end
end

-- Knocked off their feet for a few seconds (a molotov): sedation, but short
-- and without the keys prompt. Returns false if it was already down.
function Cannibals.stun(c: Cannibal, seconds: number): boolean
	if not c.alive or c.state == "Sedated" then
		return false
	end
	setState(c, "Sedated")
	c.sedatedUntil = os.clock() + seconds
	stop(c)
	c.humanoid.PlatformStand = true
	c.root.AssemblyLinearVelocity = Vector3.new(0, 6, 0) - c.root.CFrame.LookVector * 6
	if c.prompt then
		c.prompt.Enabled = false
	end
	soundRemote:FireAllClients("Scream", c.root.Position)
	return true
end

-- Sends one of them to look around a spot (the fear director's nudge), if
-- it isn't busy chasing or down.
function Cannibals.investigate(c: Cannibal, position: Vector3): boolean
	if not c.alive or not (c.state == "Patrol" or c.state == "Idle" or c.state == "Search") then
		return false
	end
	c.investigatePos = position
	setState(c, "Investigate")
	return true
end

-- The ones that would come to a noise at `position` (not chasing anyone).
function Cannibals.listeners(position: Vector3, radius: number): { Cannibal }
	local found: { Cannibal } = {}
	for _, c in list do
		if c.alive and (c.state == "Patrol" or c.state == "Idle" or c.state == "Search" or c.state == "Investigate") then
			if (c.root.Position - position).Magnitude < radius then
				table.insert(found, c)
			end
		end
	end
	return found
end

---------------------------------------------------------------- the struggle
-- Trying to inject one that's chasing you starts a fight-back: the client
-- plays a close-up and shows keys to hit (W A S D, or buttons on a phone).
-- Hit them all in time and the needle goes in; miss and you get slammed.

local struggleRemote = Net.event("Struggle")
local resultRemote = Net.event("StruggleResult")
local pendingStruggles: { [number]: { player: Player, c: Cannibal, started: number, count: number, window: number, done: boolean, success: boolean } } = {}
local nextStruggleId = 0

local STRUGGLE_KEYS = { "W", "A", "S", "D" }

function Cannibals.struggle(c: Cannibal, player: Player)
	if c.struggling or not c.alive or c.state == "Sedated" then
		return
	end
	local _, humanoid, root = playerParts(player)
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	c.struggling = true
	stop(c)
	player:SetAttribute("Struggling", true)
	local difficulty = workspace:GetAttribute("Difficulty")
	local count = if difficulty == "Easy" then 4 elseif difficulty == "Hard" then 6 elseif difficulty == "Nightmare" then 7 else 5
	local window = if difficulty == "Easy" then 1.5 elseif difficulty == "Hard" then 1.0 elseif difficulty == "Nightmare" then 0.85 else 1.2
	local keys = {}
	for i = 1, count do
		local key = STRUGGLE_KEYS[math.random(#STRUGGLE_KEYS)]
		if i > 1 and key == keys[i - 1] and math.random() < 0.6 then
			key = STRUGGLE_KEYS[math.random(#STRUGGLE_KEYS)]
		end
		keys[i] = key
	end
	nextStruggleId += 1
	local id = nextStruggleId
	local entry = { player = player, c = c, started = os.clock(), count = count, window = window, done = false, success = false }
	pendingStruggles[id] = entry
	-- face each other, close
	local toPlayer = Util.flat(root.Position - c.root.Position)
	if toPlayer.Magnitude > 0.1 then
		c.root.CFrame = CFrame.lookAt(c.root.Position, c.root.Position + toPlayer.Unit)
	end
	soundRemote:FireAllClients("Growl", c.head.Position)
	struggleRemote:FireClient(player, { id = id, keys = keys, window = window, cannibal = c.model, kind = c.kind })

	local deadline = os.clock() + count * window + 4
	while not entry.done and os.clock() < deadline and player.Parent do
		task.wait(0.05)
	end
	pendingStruggles[id] = nil
	player:SetAttribute("Struggling", nil)
	c.struggling = false
	if not c.alive then
		return
	end
	if entry.success and Inventory.remove(player, "Syringe") then
		Cannibals.sedate(c, player)
		Interact.notify(player, c.spec.display .. " goes down. The syringe is empty.", "item")
	else
		-- slammed: hurt, thrown back, and it comes straight back at you
		local _, h2, r2 = playerParts(player)
		if h2 and r2 and h2.Health > 0 then
			player:SetAttribute("LastAttacker", c.kind)
			h2:TakeDamage(c.spec.damage * 0.8)
			hurtRemote:FireClient(player, c.spec.damage * 0.8, c.root.Position)
			r2.AssemblyLinearVelocity += Util.flat(r2.Position - c.root.Position).Unit * 45 + Vector3.new(0, 14, 0)
		end
		c.attackReady = os.clock() + 1.5
		c.detection[player] = 1
		c.lastSeenTime = os.clock()
		startChase(c, player)
	end
end

local function wake(c: Cannibal)
	c.humanoid.PlatformStand = false
	c.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	if c.prompt then
		c.prompt.Enabled = true
	end
	c.searchPoint = nil
	c.lastSeenPos = c.root.Position
	c.searchUntil = os.clock() + TUNE.SearchTime
	setState(c, "Search")
	soundRemote:FireAllClients("Growl", c.head.Position)
end

---------------------------------------------------------------- brain

local function perceive(c: Cannibal, dt: number): (Player?, number)
	local best: Player? = nil
	local bestDetection = 0
	local now = os.clock()
	local look = c.root.CFrame.LookVector
	local cosView = math.cos(math.rad(TUNE.ViewAngle))
	for _, player in Players:GetPlayers() do
		local _, humanoid, root, head = playerParts(player)
		local d = c.detection[player] or 0
		if humanoid and root and head and not player:GetAttribute("InCutscene") and not isSafe(player) then
			if player:GetAttribute("Hidden") then
				d = math.max(0, d - TUNE.DetectDecay * dt)
			else
				local toHead = head.Position - c.head.Position
				local dist = toHead.Magnitude
				local vis = visibility(player)
				local range = math.min(TUNE.ViewRange * vis, 110)
				local seen = false
				if dist < range then
					local inCone = dist < TUNE.ProximitySense or look:Dot(Util.flat(toHead).Unit) > cosView
					if inCone and lineOfSight(c.head.Position, head.Position) then
						seen = true
					end
				end
				if seen then
					local closeness = 1 - dist / range
					d += (TUNE.DetectRate * vis * math.sqrt(closeness) + (if dist < 16 then 0.9 else 0)) * dt
					if c.target == player then
						c.lastSeenPos = root.Position
						c.lastSeenTime = now
					end
				else
					d = math.max(0, d - TUNE.DetectDecay * dt)
				end
				-- hearing
				local speed = Util.flat(root.AssemblyLinearVelocity).Magnitude
				local crouching = player:GetAttribute("Crouching") == true
				if not seen and c.state ~= "Chase" and c.state ~= "Grab" and not crouching then
					if (player:GetAttribute("Sprinting") and dist < TUNE.HearSprint) or (speed > 4 and dist < TUNE.HearWalk) then
						c.investigatePos = root.Position
						if c.state ~= "Investigate" then
							setState(c, "Investigate")
						end
					end
				end
			end
			d = math.clamp(d, 0, 1.2)
		else
			d = 0
		end
		c.detection[player] = d
		if d > bestDetection then
			bestDetection = d
			best = player
		end
	end
	return best, bestDetection
end

local function think(c: Cannibal, dt: number)
	local now = os.clock()
	if c.struggling then
		return -- locked in a syringe struggle with someone
	end
	if c.state == "Sedated" then
		if now >= c.sedatedUntil then
			wake(c)
		end
		return
	end
	if paused then
		if c.state ~= "Paused" then
			stop(c)
		end
		return
	end

	Doors.openNear(c.root.Position, 6)

	local best, detection = perceive(c, dt)
	if best and detection >= 1 and c.state ~= "Grab" then
		if c.state ~= "Chase" or c.target ~= best then
			if c.state ~= "Chase" then
				c.lastSeenTime = now
			end
			startChase(c, best)
		end
	end

	-- hunters always drift toward the nearest player
	if c.hunting and c.state ~= "Chase" and c.state ~= "Grab" and now > c.nextHunt then
		c.nextHunt = now + 7
		local nearest: Vector3? = nil
		local nd = math.huge
		for _, player in Players:GetPlayers() do
			local _, _, root = playerParts(player)
			if root and not player:GetAttribute("InCutscene") and not isSafe(player) then
				local d = (root.Position - c.root.Position).Magnitude
				if d < nd then
					nd = d
					nearest = root.Position
				end
			end
		end
		if nearest then
			local jitter = Vector3.new(math.random(-12, 12), 0, math.random(-12, 12))
			c.investigatePos = nearest + jitter
			setState(c, "Investigate")
		end
	end

	local state = c.state
	if state == "Chase" then
		local target = c.target
		local humanoid: Humanoid?, root: BasePart? = nil, nil
		if target then
			local _, h, r = playerParts(target)
			humanoid, root = h, r
		end
		if not target or not humanoid or not root then
			c.searchUntil = now + TUNE.SearchTime
			setState(c, "Search")
			return
		end
		if target:GetAttribute("Hidden") then
			local hiddenAt = (target:GetAttribute("HiddenAt") :: number?) or 0
			local spot = Hiding.spotOf(target)
			if spot and hiddenAt - c.lastSeenTime < 0.9 and (spot.position - c.root.Position).Magnitude < 28 then
				setState(c, "Grab")
				c.target = target
			else
				c.searchUntil = now + TUNE.SearchTime
				c.detection[target] = 0.2
				setState(c, "Search")
			end
			return
		end
		if now - c.lastSeenTime > TUNE.LoseSightTime then
			c.searchUntil = now + TUNE.SearchTime
			c.detection[target] = 0.2
			setState(c, "Search")
			return
		end
		local goal = if now - c.lastSeenTime < 0.4 then root.Position else (c.lastSeenPos or root.Position)
		local dist = (root.Position - c.root.Position).Magnitude
		if dist < TUNE.AttackRange and now >= c.attackReady and now - c.lastSeenTime < 0.4 then
			task.spawn(attack, c, target)
		elseif not c.attacking then
			if dist < 22 and now - c.lastSeenTime < 0.4 then
				c.waypoints = nil
				c.humanoid.WalkSpeed = c.spec.run
				c.humanoid:MoveTo(goal)
			else
				moveTo(c, goal, c.spec.run)
			end
		end
	elseif state == "Grab" then
		local target = c.target
		if target then
			grab(c, target)
		else
			setState(c, "Search")
		end
	elseif state == "Investigate" then
		local pos = c.investigatePos
		if not pos then
			setState(c, "Patrol")
			return
		end
		if arrived(c, pos, 4) or now - c.stateTime > 25 then
			c.lastSeenPos = pos
			c.searchUntil = now + TUNE.SearchTime * 0.6
			c.searchPoint = nil
			setState(c, "Search")
		else
			moveTo(c, pos, c.spec.walk * 1.35)
		end
	elseif state == "Search" then
		if now > c.searchUntil then
			setState(c, "Patrol")
			return
		end
		local center = c.lastSeenPos or c.root.Position
		if not c.searchPoint or arrived(c, c.searchPoint :: Vector3, 3.5) then
			c.searchPoint = center + Vector3.new(math.random(-12, 12), 0, math.random(-12, 12))
		end
		moveTo(c, c.searchPoint :: Vector3, c.spec.walk * 1.15)
	elseif state == "Idle" then
		stop(c)
		if now > c.waitUntil then
			setState(c, "Patrol")
		end
	elseif state == "Patrol" then
		if #c.patrol == 0 then
			stop(c)
			return
		end
		local goal = c.patrol[c.patrolIndex]
		if arrived(c, goal, 4) then
			c.patrolIndex = c.patrolIndex % #c.patrol + 1
			c.waitUntil = now + math.random(10, 35) / 10
			setState(c, "Idle")
		else
			moveTo(c, goal, c.spec.walk)
		end
	elseif state == "Paused" then
		setState(c, "Patrol")
	end

	-- unstick
	local moved = (c.root.Position - c.lastPos).Magnitude
	c.lastPos = c.root.Position
	local wantsMove = c.state ~= "Idle" and not c.attacking
	if wantsMove and moved < 0.08 then
		c.stuckSince = c.stuckSince or now
		if now - (c.stuckSince :: number) > 1.6 then
			c.stuckSince = nil
			c.lastPathTime = 0
			c.humanoid.Jump = true
		end
	else
		c.stuckSince = nil
	end
end

local function updatePlayerAttributes()
	for _, player in Players:GetPlayers() do
		local maxD = 0
		local chased = false
		for _, c in list do
			if c.alive then
				maxD = math.max(maxD, c.detection[player] or 0)
				if (c.state == "Chase" or c.state == "Grab") and c.target == player then
					chased = true
				end
			end
		end
		player:SetAttribute("Detection", math.min(maxD, 1))
		player:SetAttribute("Chased", chased)
	end
end

---------------------------------------------------------------- spawning

export type SpawnOptions = {
	patrol: { Vector3 }?,
	hunting: boolean?,
	chase: Player?,
}

function Cannibals.spawn(kind: string, cf: CFrame, opts: SpawnOptions?): Cannibal
	local o: SpawnOptions = opts or {}
	local spec = KINDS[kind]
	local rig = createRig(spec)
	rig.Name = spec.display
	local eyes = dress(rig, spec, kind)
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = rig:FindFirstChild("Head") :: BasePart
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = spec.walk
	humanoid.AutoJumpEnabled = true

	for _, p in rig:GetDescendants() do
		if p:IsA("BasePart") then
			p.CollisionGroup = "NPC"
		end
	end

	rig:PivotTo(cf + Vector3.new(0, 3.5 * spec.height, 0))
	rig.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local tracks: { [string]: AnimationTrack } = {}
	for name, id in ANIMS do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if ok and track then
			track.Priority = if name == "attack" then Enum.AnimationPriority.Action else Enum.AnimationPriority.Movement
			track.Looped = name ~= "attack"
			tracks[name] = track
		end
	end

	local c: Cannibal = {
		kind = kind,
		spec = spec,
		model = rig,
		humanoid = humanoid,
		root = root,
		head = head,
		state = "Patrol",
		stateTime = os.clock(),
		patrol = o.patrol or {},
		patrolIndex = 1,
		waitUntil = 0,
		target = nil,
		lastSeenPos = nil,
		lastSeenTime = 0,
		investigatePos = nil,
		searchUntil = 0,
		searchPoint = nil,
		detection = {},
		path = PathfindingService:CreatePath({
			AgentRadius = 2.2,
			AgentHeight = 6 * spec.height,
			AgentCanJump = false,
			AgentCanClimb = false,
			WaypointSpacing = 5,
			Costs = { Water = math.huge },
		}),
		waypoints = nil,
		wpIndex = 1,
		moveGoal = nil,
		lastPathTime = 0,
		attackReady = 0,
		attacking = false,
		sedatedUntil = 0,
		hasKeys = spec.keys == true,
		hunting = o.hunting == true,
		alive = true,
		eyes = eyes,
		tracks = tracks,
		currentTrack = nil,
		stuckSince = nil,
		lastPos = root.Position,
		prompt = nil,
		nextHunt = 0,
		struggling = false,
		speedMult = 1,
	}
	rig:SetAttribute("Kind", kind)
	rig:SetAttribute("State", "Patrol")
	-- the family's own gait: the heavier walk and the long-stride run
	rig:SetAttribute("AnimWalk", "Walk2")
	rig:SetAttribute("AnimRun", "Run3")
	rig:SetAttribute("AnimRunAt", spec.walk * 1.3)
	rig:SetAttribute("AnimWalkRef", 10)
	rig:SetAttribute("AnimRunRef", 18)
	CollectionService:AddTag(rig, "KeyframeAnimated")

	-- sedation prompt on the back of the torso
	local torso = (rig:FindFirstChild("UpperTorso") or rig:FindFirstChild("Torso")) :: BasePart
	c.prompt = Interact.add(torso, {
		action = "Inject Sedative",
		object = spec.display,
		hold = 0.5,
		distance = 6.5,
		canUse = function(player)
			if not Inventory.has(player, "Syringe") then
				return false, "You need a sedative syringe."
			end
			if c.state == "Sedated" or c.struggling then
				return false, nil
			end
			return true
		end,
		onUse = function(player)
			local ok, message = Cannibals.trySedate(c, player)
			if ok and Inventory.remove(player, "Syringe") then
				-- sneaked up from behind: straight in
				Cannibals.sedate(c, player)
				Interact.notify(player, spec.display .. " collapses.", "item")
			elseif c.state == "Chase" or c.state == "Grab" then
				-- face to face: fight for it
				task.spawn(Cannibals.struggle, c, player)
			elseif message then
				Interact.notify(player, message, "warn")
			end
		end,
	})

	table.insert(list, c)
	if o.chase then
		c.detection[o.chase] = 1
		c.lastSeenTime = os.clock()
		startChase(c, o.chase)
	end

	task.spawn(function()
		local last = os.clock()
		while c.alive and rig.Parent do
			task.wait(0.12)
			local now = os.clock()
			xpcall(think, function(err)
				warn("[Cannibals] " .. tostring(err) .. "\n" .. debug.traceback())
			end, c, now - last)
			last = now
			updateLocomotionAnim(c)
		end
	end)

	return c
end

function Cannibals.remove(c: Cannibal)
	c.alive = false
	local i = table.find(list, c)
	if i then
		table.remove(list, i)
	end
	c.model:Destroy()
end

function Cannibals.clear()
	for _, c in table.clone(list) do
		Cannibals.remove(c)
	end
end

function Cannibals.all(): { Cannibal }
	return list
end

function Cannibals.find(kind: string): Cannibal?
	for _, c in list do
		if c.kind == kind then
			return c
		end
	end
	return nil
end

function Cannibals.setPaused(value: boolean)
	paused = value
	if value then
		for _, c in list do
			if c.state ~= "Sedated" then
				stop(c)
				c.state = "Paused"
				c.target = nil
				c.detection = {}
			end
		end
	end
end

-- Teleport a cannibal to a new patrol route (used between chapters).
function Cannibals.relocate(c: Cannibal, cf: CFrame, patrol: { Vector3 })
	stop(c)
	c.humanoid.PlatformStand = false
	c.model:PivotTo(cf + Vector3.new(0, 3.5 * c.spec.height, 0))
	c.patrol = patrol
	c.patrolIndex = 1
	c.detection = {}
	setState(c, "Patrol")
	c.lastPos = c.root.Position
end

function Cannibals.forgetPlayer(player: Player)
	for _, c in list do
		c.detection[player] = 0
		if c.target == player and c.state ~= "Sedated" then
			c.searchUntil = os.clock() + 4
			setState(c, "Search")
		end
	end
end

-- Send anyone near a respawn point off to the far end of their patrol, so a
-- player who just woke up isn't caught again on the spot.
function Cannibals.retreatFrom(position: Vector3, radius: number)
	for _, c in list do
		if c.alive and c.state ~= "Sedated" and (c.root.Position - position).Magnitude < radius then
			c.target = nil
			table.clear(c.detection)
			if #c.patrol > 0 then
				local far, farDistance = 1, -1
				for i, point in c.patrol do
					local d = (point - position).Magnitude
					if d > farDistance then
						far, farDistance = i, d
					end
				end
				c.patrolIndex = far
			end
			setState(c, "Patrol")
		end
	end
end

function Cannibals.init()
	resultRemote.OnServerEvent:Connect(function(player, id, success)
		if typeof(id) ~= "number" then
			return
		end
		local entry = pendingStruggles[id]
		if not entry or entry.player ~= player or entry.done then
			return
		end
		-- no faster than a person can hit the keys, no slower than the windows allow
		local elapsed = os.clock() - entry.started
		entry.success = success == true and elapsed >= entry.count * 0.18 and elapsed <= entry.count * entry.window + 3.5
		entry.done = true
	end)
	task.spawn(function()
		while true do
			refreshLosFilter()
			updatePlayerAttributes()
			task.wait(0.2)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, c in list do
			c.detection[player] = nil
			if c.target == player then
				c.target = nil
			end
		end
	end)
end

return Cannibals

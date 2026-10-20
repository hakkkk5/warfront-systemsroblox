--!strict
-- Jason and Michel as they want to be seen: two friendly men who pulled you
-- out of the wreck. Until the reveal they wander the ground floor, stop to
-- chat when you talk to them, and get less friendly the more you find.
--
-- Hosts.publishTemplates() puts unmasked copies in ReplicatedStorage
-- (HostTemplates) for the cutscenes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Doors = require(script.Parent.Doors)
local Interact = require(script.Parent.Interact)

local Hosts = {}

local rgb = Color3.fromRGB
local CF = CFrame.new

type Spec = {
	height: number,
	width: number,
	skin: Color3,
	shirt: Color3,
	pants: Color3,
	cap: Color3?,
	glasses: boolean?,
	apron: boolean?,
}

local SPECS: { [string]: Spec } = {
	Jason = {
		height = 1.12,
		width = 1.15,
		skin = rgb(214, 170, 140),
		shirt = rgb(150, 52, 40),
		pants = rgb(52, 62, 86),
		cap = rgb(70, 90, 60),
	},
	Michel = {
		height = 1.04,
		width = 1,
		skin = rgb(226, 190, 160),
		shirt = rgb(120, 120, 112),
		pants = rgb(60, 52, 44),
		glasses = true,
		apron = true,
	},
}

type Host = {
	name: string,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	route: { Vector3 },
	pauses: { boolean },
	index: number,
	waitUntil: number,
	busyUntil: number,
	faceTarget: Vector3?,
}

local hosts: { [string]: Host } = {}
local generation = 0 -- bumps on spawn/remove so only one update loop runs
local suspicion = 0 -- 0 friendly, 1 they stop to watch you, 2 they stare from further away

local function tagForAnimation(model: Model)
	-- idle / walk animations are played by every client (KeyframeAnimator)
	model:SetAttribute("AnimIdle", "Idle1")
	model:SetAttribute("AnimWalk", "Walk1")
	model:SetAttribute("AnimRunAt", 99)
	model:SetAttribute("AnimWalkRef", 8)
	CollectionService:AddTag(model, "KeyframeAnimated")
end

---------------------------------------------------------------- rigs

local function weld(part: BasePart, to: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = part
	w.Parent = part
end

local function addPart(parent: Instance, to: BasePart, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	weld(p, to)
	return p
end

-- Block figure if R15 rigs can't be created.
local function fallbackRig(spec: Spec): Model
	local m = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CFrame = CF(0, 3, 0)
	root.Parent = m
	local function limb(name: string, size: Vector3, cf: CFrame, color: Color3)
		local p = addPart(m, root, size, cf, color, Enum.Material.SmoothPlastic)
		p.Name = name
	end
	limb("Torso", Vector3.new(2, 2, 1), CF(0, 3, 0), spec.shirt)
	limb("Head", Vector3.new(1.2, 1.2, 1.2), CF(0, 4.6, 0), spec.skin)
	limb("Left Arm", Vector3.new(1, 2, 1), CF(-1.5, 3, 0), spec.skin)
	limb("Right Arm", Vector3.new(1, 2, 1), CF(1.5, 3, 0), spec.skin)
	limb("Left Leg", Vector3.new(1, 2, 1), CF(-0.5, 1, 0), spec.pants)
	limb("Right Leg", Vector3.new(1, 2, 1), CF(0.5, 1, 0), spec.pants)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = m
	m.PrimaryPart = root
	return m
end

local function createRig(spec: Spec): Model
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
	-- R6 like everyone else, so the baked clips fit; R6 ignores the body
	-- scales, so the whole rig is scaled instead
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)
	local model = if ok and rig then rig else fallbackRig(spec)
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	if ok and rig and spec.height ~= 1 then
		pcall(function()
			model:ScaleTo(spec.height)
		end)
	end

	-- the friendly touches: a cap, reading glasses, an apron
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if head and head:IsA("BasePart") then
		local hs = head.Size
		if head:FindFirstChildOfClass("SpecialMesh") then
			-- R6 head: a 2x1x1 part showing a rounder mesh about 1.2 across
			local k = head.Size.Y * 1.2
			hs = Vector3.new(k, k, k)
		end
		local hcf = head.CFrame
		local cap = spec.cap
		if cap then
			addPart(model, head, Vector3.new(hs.X * 1.08, hs.Y * 0.32, hs.Z * 1.08), hcf * CF(0, hs.Y * 0.42, 0), cap, Enum.Material.Fabric)
			addPart(model, head, Vector3.new(hs.X * 0.9, 0.08, hs.Z * 0.5), hcf * CF(0, hs.Y * 0.3, -hs.Z * 0.62), cap, Enum.Material.Fabric)
		end
		if spec.glasses then
			for _, x in { -0.22, 0.22 } do
				addPart(model, head, Vector3.new(0.34, 0.24, 0.04), hcf * CF(x * hs.X, hs.Y * 0.08, -hs.Z / 2 - 0.03), rgb(25, 25, 25), Enum.Material.SmoothPlastic).Transparency = 0.3
			end
			addPart(model, head, Vector3.new(0.14, 0.04, 0.04), hcf * CF(0, hs.Y * 0.12, -hs.Z / 2 - 0.03), rgb(25, 25, 25), Enum.Material.SmoothPlastic)
		end
	end
	if spec.apron and torso and torso:IsA("BasePart") then
		local ts = torso.Size
		addPart(model, torso, Vector3.new(ts.X * 0.85, ts.Y * 1.6, 0.1), torso.CFrame * CF(0, -ts.Y * 0.3, -ts.Z / 2 - 0.06), rgb(220, 214, 200), Enum.Material.Fabric)
	end
	return model
end

-- Unmasked copies for the client cutscenes.
function Hosts.publishTemplates()
	if ReplicatedStorage:FindFirstChild("HostTemplates") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "HostTemplates"
	for name, spec in SPECS do
		local rig = createRig(spec)
		rig.Name = name
		for _, p in rig:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanCollide = false
			end
		end
		rig.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

---------------------------------------------------------------- live hosts

local function turnTowards(root: BasePart, target: Vector3)
	local flat = Vector3.new(target.X, root.Position.Y, target.Z)
	if (flat - root.Position).Magnitude > 0.5 then
		root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, flat), 0.35)
	end
end

-- The closest player within range, for the suspicious stare.
local function nearestPlayer(position: Vector3, range: number): Vector3?
	local best: Vector3? = nil
	local bestDistance = range
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local d = (root.Position - position).Magnitude
			if d < bestDistance then
				best = root.Position
				bestDistance = d
			end
		end
	end
	return best
end

-- 1: they stop to watch whoever is near; 2: from across the room, and longer.
function Hosts.setSuspicion(level: number)
	suspicion = level
end

local function step(host: Host)
	local now = os.clock()
	local root = host.root
	if host.busyUntil > now then
		host.humanoid:MoveTo(root.Position)
		local target = host.faceTarget
		if target then
			turnTowards(root, target)
		end
		return
	end
	-- suspicious: whoever comes close gets watched, standing dead still
	if suspicion > 0 then
		local watched = nearestPlayer(root.Position, if suspicion >= 2 then 22 else 12)
		if watched then
			host.humanoid:MoveTo(root.Position)
			turnTowards(root, watched)
			if host.waitUntil == 0 then
				host.waitUntil = now + (if suspicion >= 2 then 6 else 3)
			end
			if now < host.waitUntil then
				return
			end
		end
	end
	local goal = host.route[host.index]
	local offset = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
	if offset.Magnitude < 2.5 then
		if not host.pauses[host.index] then
			-- doorways and corners: walk straight on
			host.waitUntil = 0
			host.index = host.index % #host.route + 1
			return
		elseif host.waitUntil == 0 then
			host.waitUntil = now + math.random(30, 80) / 10
		elseif now >= host.waitUntil then
			host.waitUntil = 0
			host.index = host.index % #host.route + 1
		end
		host.humanoid:MoveTo(root.Position)
	else
		host.waitUntil = 0
		Doors.openNear(root.Position, 6)
		host.humanoid:MoveTo(goal)
	end
end

-- routes: house-local floor points (x, pause, z), walked in a loop; they
-- stop for a few seconds where pause > 0 and walk through the rest
function Hosts.spawn(origin: CFrame, parent: Instance, routes: { [string]: { Vector3 } }, onTalk: (player: Player, name: string) -> ())
	Hosts.remove()
	for name, points in routes do
		local spec = SPECS[name]
		local model = createRig(spec)
		model.Name = name
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.WalkSpeed = 6
		humanoid.MaxHealth = math.huge
		humanoid.Health = math.huge
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CollisionGroup = "NPC"
			end
		end
		local route: { Vector3 } = {}
		local pauses: { boolean } = {}
		for _, p in points do
			table.insert(route, (origin * CF(p.X, 0, p.Z)).Position)
			table.insert(pauses, p.Y > 0)
		end
		model:PivotTo(CF(route[1] + Vector3.new(0, 3.4 * spec.height, 0)))
		model.Parent = parent
		pcall(function()
			root:SetNetworkOwner(nil)
		end)

		tagForAnimation(model)

		local host: Host = {
			name = name,
			model = model,
			humanoid = humanoid,
			root = root,
			route = route,
			pauses = pauses,
			index = 1,
			waitUntil = 0,
			busyUntil = 0,
			faceTarget = nil,
		}
		hosts[name] = host
		local head = model:FindFirstChild("Head")
		Interact.add(if head and head:IsA("BasePart") then head else root, {
			action = "Talk",
			object = name,
			distance = 9,
			onUse = function(player)
				local character = player.Character
				local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
				host.busyUntil = os.clock() + 5
				host.faceTarget = if playerRoot and playerRoot:IsA("BasePart") then playerRoot.Position else nil
				onTalk(player, name)
			end,
		})
	end
	generation += 1
	local mine = generation
	task.spawn(function()
		while mine == generation do
			for _, host in hosts do
				if host.model.Parent then
					step(host)
				end
			end
			task.wait(0.25)
		end
	end)
end

function Hosts.position(name: string): Vector3?
	local host = hosts[name]
	return if host and host.model.Parent then host.root.Position else nil
end

function Hosts.remove()
	for _, host in hosts do
		host.model:Destroy()
	end
	table.clear(hosts)
	generation += 1
end

return Hosts

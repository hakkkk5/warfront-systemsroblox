--!strict
-- The scares the server sends now and then (RandomEvents.luau), played only
-- for you: a monster standing far off watching you that is gone when you
-- look straight at it, a shadow darting across the path, a monster lunging
-- into your face with the lights strobing, whispers, lights failing around
-- you, a scream out in the trees, knocking, thunder, footsteps behind you,
-- the music cutting out, breathing outside your hiding spot. Also the tells:
-- the flashlight flickers and your heart pounds when one of them is near.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Audio = require(script.Parent.Audio)
local Effects = require(script.Parent.Effects)
local Jumpscare = require(script.Parent.Jumpscare)
local MonsterForm = require(script.Parent.MonsterForm)
local Viewmodel = require(script.Parent.Viewmodel)
local HUD = require(script.Parent.Parent.UI.HUD)

local Scares = {}

local folder: Folder
local busy = false

local WHISPERS = {
	"...we can smell you...",
	"...dinner's almost ready...",
	"...behind you...",
	"...Michel... it's in here...",
	"...don't run. Running makes the meat tough...",
	"...there's always room at the table...",
	"...we found your friends...",
}

-- plain: no Blender body or meshes, so the shadow can paint the rig black
local function monster(kind: string?, plain: boolean?): Model?
	local templates = ReplicatedStorage:FindFirstChild("CannibalTemplates")
	if not templates then
		return nil
	end
	local options = templates:GetChildren()
	if #options == 0 then
		return nil
	end
	local pick = (kind and templates:FindFirstChild(kind)) or options[math.random(#options)]
	if not (pick and pick:IsA("Model")) then
		return nil
	end
	local m = pick:Clone()
	local root = m:FindFirstChild("HumanoidRootPart")
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == root
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	local humanoid = m:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	if plain then
		m:SetAttribute("Skin", nil)
		CollectionService:RemoveTag(m, "CannibalSkin")
		for _, d in m:GetDescendants() do
			if d:GetAttribute("Mesh") then
				d:SetAttribute("SkipMesh", true)
			end
		end
	end
	m.Parent = folder
	MonsterForm.apply(m, true, true, true)
	return m
end

local function groundBelow(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), params)
	return if hit then hit.Position else pos
end

-- Stands a model with its feet on `floor`, facing `toward`.
local function stand(m: Model, floor: Vector3, toward: Vector3)
	local flat = Vector3.new(toward.X, floor.Y, toward.Z)
	m:PivotTo(CFrame.lookAt(floor, if (flat - floor).Magnitude > 0.1 then flat else floor + Vector3.new(0, 0, -1)))
	local cf, size = m:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	m:PivotTo(m:GetPivot() + Vector3.new(0, floor.Y - bottom, 0))
end

local function vanish(m: Model)
	-- flicker between gone and as it was (parts under a Blender mesh stay hidden)
	local original: { [BasePart]: number } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			original[d] = d.LocalTransparencyModifier
		end
	end
	for i = 1, 4 do
		for d, value in original do
			d.LocalTransparencyModifier = if i % 2 == 1 then 1 else value
		end
		task.wait(0.06)
	end
	m:Destroy()
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

---------------------------------------------------------------- the scares

-- Off in the distance, watching you. Gone when you look right at it.
local function apparition()
	local camera = workspace.CurrentCamera
	local look = flat(camera.CFrame.LookVector)
	local side = flat(camera.CFrame.RightVector) * (if math.random() < 0.5 then -1 else 1)
	local spot = camera.CFrame.Position + look * math.random(36, 56) + side * math.random(6, 16)
	local m = monster()
	if not m then
		return
	end
	stand(m, groundBelow(spot), camera.CFrame.Position)
	m:SetAttribute("AnimForce", "none")
	Audio.play("Heartbeat", nil, 0.7, 0.8)
	local head = m:FindFirstChild("Head")
	local lookedAt = 0
	local started = os.clock()
	while m.Parent and os.clock() - started < 8 do
		local dt = task.wait(0.05)
		local cam = workspace.CurrentCamera.CFrame
		local target = if head and head:IsA("BasePart") then head.Position else m:GetPivot().Position
		local toward = target - cam.Position
		if toward.Magnitude < 16 then
			break
		end
		if cam.LookVector:Dot(toward.Unit) > 0.985 then
			lookedAt += dt
			if lookedAt > 0.45 then
				break
			end
		end
	end
	Audio.play("Whoosh", nil, 0.5, 0.6)
	vanish(m)
end

-- A black shape darting across the path.
local function shadow()
	local camera = workspace.CurrentCamera
	local look = flat(camera.CFrame.LookVector)
	local right = flat(camera.CFrame.RightVector)
	local center = camera.CFrame.Position + look * math.random(22, 34)
	local dir = if math.random() < 0.5 then 1 else -1
	local from = center - right * 22 * dir
	local to = center + right * 22 * dir
	local m = monster(nil, true)
	if not m then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = Color3.new(0, 0, 0)
			d.Material = Enum.Material.SmoothPlastic
		elseif d:IsA("Light") or d:IsA("Decal") then
			d:Destroy()
		end
	end
	m:SetAttribute("AnimForce", "run")
	m:SetAttribute("AnimRate", 1.6)
	CollectionService:AddTag(m, "KeyframeAnimated")
	Audio.play("Whoosh", center, 1, 0.7)
	local t = 0
	while t < 1.1 and m.Parent do
		t += task.wait()
		local p = from:Lerp(to, t / 1.1)
		stand(m, groundBelow(p), p + right * dir * 5)
	end
	m:Destroy()
end

-- It's in your face, the lights strobing (Jumpscare.luau).
local function jumpscare()
	Jumpscare.play(nil, { tail = true })
end

-- Breathing at the back of your neck, everything else gone quiet. Turn round
-- and it's in your face; keep still and it's gone when you finally look.
local function behind()
	local cam = workspace.CurrentCamera
	local start = cam.CFrame
	local m = monster()
	if not m then
		jumpscare()
		return
	end
	local spot = start.Position - flat(start.LookVector) * 3.4
	stand(m, groundBelow(spot), start.Position)
	m.Parent = folder
	Audio.duck(0.05, 9)
	local turned = false
	local began = os.clock()
	while not turned and os.clock() - began < 7 do
		Audio.play("Growl", spot + Vector3.new(0, 1.5, 0), 0.35, 0.42)
		for _ = 1, 22 do
			task.wait(0.1)
			if flat(cam.CFrame.LookVector):Dot(flat(start.LookVector)) < 0 then
				turned = true
				break
			end
		end
	end
	if turned then
		m:Destroy()
		Jumpscare.play(nil, { tail = true, build = false })
	else
		vanish(m)
		Audio.unduck()
	end
end

-- Every light near you stutters and dies for a moment.
local function lightsFail()
	local camPos = workspace.CurrentCamera.CFrame.Position
	local touched: { [Light]: boolean } = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("Light") and d.Enabled then
			local holder = d.Parent
			if holder and holder:IsA("BasePart") and (holder.Position - camPos).Magnitude < 45 then
				touched[d] = true
			end
		end
	end
	Audio.play("FlashlightClick", nil, 0.8, 0.6)
	for _ = 1, 10 do
		for light in touched do
			light.Enabled = math.random() < 0.35
		end
		task.wait(0.05 + math.random() * 0.12)
	end
	for light in touched do
		light.Enabled = false
	end
	task.wait(2.5)
	for light in touched do
		if light.Parent then
			light.Enabled = true
		end
	end
end

local function play(kind: string)
	if busy then
		return
	end
	busy = true
	local ok, err = pcall(function()
		if kind == "apparition" then
			apparition()
		elseif kind == "shadow" then
			shadow()
		elseif kind == "jumpscare" then
			jumpscare()
		elseif kind == "behind" then
			behind()
		elseif kind == "lights" then
			lightsFail()
		elseif kind == "whisper" then
			Audio.play("Wind", nil, 0.6, 0.6)
			HUD.subtitle("???", WHISPERS[math.random(#WHISPERS)], 3)
		elseif kind == "scream" then
			local cam = workspace.CurrentCamera.CFrame
			local a = math.random() * math.pi * 2
			Audio.play("Scream", cam.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * 80, 1, 0.6 + math.random() * 0.2)
		elseif kind == "knock" then
			local cam = workspace.CurrentCamera.CFrame
			for _ = 1, 3 do
				Audio.play("Impact", cam.Position - cam.LookVector * 10, 0.7, 0.9)
				task.wait(0.45)
			end
		elseif kind == "thunder" then
			Effects.lightning()
		elseif kind == "footsteps" then
			-- heavy steps coming up behind you; they stop dead if you turn round
			local cam = workspace.CurrentCamera
			local start = cam.CFrame
			for i = 0, math.random(4, 6) do
				local now = cam.CFrame
				if now.LookVector:Dot(-start.LookVector) > 0.3 then
					break
				end
				local back = Vector3.new(-start.LookVector.X, 0, -start.LookVector.Z).Unit
				Audio.play("Footstep", now.Position + back * (16 - i * 2.2) - Vector3.new(0, 4, 0), 0.9, 0.62 + math.random() * 0.05)
				task.wait(0.62 - i * 0.04)
			end
		elseif kind == "silence" then
			-- everything drops away... the director decides if anything follows
			Audio.duck(0.03, 10)
		elseif kind == "breath" then
			-- right next to your hiding spot
			local cam = workspace.CurrentCamera.CFrame
			for _ = 1, 2 do
				Audio.play("Growl", cam.Position + cam.RightVector * 2 + cam.LookVector * 1.5, 0.35, 0.5)
				task.wait(2.2)
			end
		end
	end)
	if not ok then
		warn("[Scares] " .. kind .. ": " .. tostring(err))
	end
	busy = false
end

-- For other scripts (the chase, cutscenes) to fire one directly.
Scares.play = play

function Scares.init()
	folder = Instance.new("Folder")
	folder.Name = "ScareFX"
	folder.Parent = workspace
	Net.event("Scare").OnClientEvent:Connect(function(kind)
		if typeof(kind) == "string" then
			task.spawn(play, kind)
		end
	end)

	-- Tells: when one of them is close (and not already on you) the flashlight
	-- gets nervous and your heart starts to pound, before you see anything.
	local heart = false
	RunService.Heartbeat:Connect(function()
		local cam = workspace.CurrentCamera
		local nearest = math.huge
		for _, rig in CollectionService:GetTagged("CannibalSkin") do
			if rig:IsA("Model") and rig.Parent then
				local pivot = rig:GetPivot().Position
				nearest = math.min(nearest, (pivot - cam.CFrame.Position).Magnitude)
			end
		end
		local chased = Players.LocalPlayer:GetAttribute("Chased") == true
		local playing = HUD.visible and Players.LocalPlayer:GetAttribute("InCutscene") ~= true
		local dread = if chased or not playing then 0 else math.clamp(1 - (nearest - 10) / 32, 0, 1)
		Viewmodel.dread = dread
		local want = dread > 0.35
		if want ~= heart then
			heart = want
			Audio.loop("Heartbeat", want, 0.25)
		end
		if heart then
			Audio.setLoopVolume("Heartbeat", 0.15 + dread * 0.55)
		end
	end)
end

return Scares

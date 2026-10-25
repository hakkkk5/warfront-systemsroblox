--!strict
-- The scares the server sends now and then (RandomEvents.luau), played only
-- for you: a monster standing far off watching you that is gone when you
-- look straight at it, a shadow darting across the path, a monster lunging
-- into your face with the lights strobing, whispers, lights failing around
-- you, a scream out in the trees, knocking, thunder.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Audio)
local CameraController = require(script.Parent.CameraController)
local Effects = require(script.Parent.Effects)
local MonsterForm = require(script.Parent.MonsterForm)
local HUD = require(script.Parent.Parent.UI.HUD)

local Scares = {}

local player = Players.LocalPlayer
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

local function monster(kind: string?): Model?
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
	for i = 1, 4 do
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if i % 2 == 1 then 1 else 0
			end
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
	local m = monster()
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

-- It's in your face, the lights strobing.
local function jumpscare()
	local camera = workspace.CurrentCamera
	local m = monster()
	if not m then
		return
	end
	local head = m:FindFirstChild("Head")
	local base = camera.CFrame
	stand(m, base.Position - Vector3.new(0, 6, 0) + flat(base.LookVector) * 9, base.Position)
	local headOffset = if head and head:IsA("BasePart") then head.Position - m:GetPivot().Position else Vector3.new(0, 5, 0)
	m:SetAttribute("AnimForce", "none")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Jumpscare"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local strobe = Instance.new("Frame")
	strobe.Size = UDim2.fromScale(1, 1)
	strobe.BorderSizePixel = 0
	strobe.BackgroundTransparency = 1
	strobe.Parent = gui

	Audio.play("Jumpscare", nil, 1.3, 1)
	Audio.play("Scream", nil, 1, 0.7)
	CameraController.shake(4, 1.6)
	Effects.flash(Color3.fromRGB(255, 20, 10), 0.7)
	local colors = { Color3.fromRGB(255, 20, 10), Color3.new(1, 1, 1), Color3.new(0, 0, 0) }
	local t = 0
	local frame = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		local cam = workspace.CurrentCamera.CFrame
		local d = Util.lerp(8, 1.3, math.min(t / 0.28, 1))
		-- the head lands just in front of your eyes, facing you
		local headPos = cam.Position + cam.LookVector * d - Vector3.new(0, 0.3, 0)
		local facing = CFrame.lookAt(Vector3.zero, flat(cam.Position - headPos))
		m:PivotTo(CFrame.new(headPos - headOffset) * facing.Rotation)
		frame += 1
		if frame % 2 == 0 then
			strobe.BackgroundColor3 = colors[(frame // 2) % #colors + 1]
			strobe.BackgroundTransparency = if (frame // 2) % 3 == 2 then 0 else 0.45
		end
	end)
	task.wait(0.75)
	conn:Disconnect()
	strobe.BackgroundColor3 = Color3.new(0, 0, 0)
	strobe.BackgroundTransparency = 0
	m:Destroy()
	task.wait(0.25)
	Util.tween(strobe, 0.5, { BackgroundTransparency = 1 })
	task.wait(0.55)
	gui:Destroy()
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
end

return Scares

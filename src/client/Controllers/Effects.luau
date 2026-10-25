--!strict
-- Local atmosphere: fear vignette + heartbeat, damage flashes, blur, rain,
-- lightning, flickering lights, hazard blinkers, TV static and the music
-- state machine.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Settings = require(script.Parent.Settings)
local Audio = require(script.Parent.Audio)
local CameraController = require(script.Parent.CameraController)
local Theme = require(script.Parent.Parent.UI.Theme)

local Effects = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local blur: BlurEffect
local fearGrade: ColorCorrectionEffect
local flashGrade: ColorCorrectionEffect
local overlay: ScreenGui
local fearVignette: Frame
local hurtVignette: Frame
local rainPart: Part
local rainEmitter: ParticleEmitter

Effects.blurOverride = nil :: number?
Effects.menuMode = true
Effects.brightness = 0

local fear = 0
local hurtFlash = 0

function Effects.setRain(on: boolean, heavy: boolean?)
	rainEmitter.Enabled = on
	rainEmitter.Rate = if heavy then 900 else 350
	Audio.loop("Rain", on, if heavy then 0.6 else 0.3)
end

function Effects.flash(color: Color3, strength: number)
	flashGrade.TintColor = color
	flashGrade.Brightness = strength * Settings.flashScale()
	Util.tween(flashGrade, 0.6, { Brightness = 0, TintColor = Color3.new(1, 1, 1) })
end

function Effects.lightning()
	local original = Lighting.Brightness
	Lighting.Brightness = 3
	Effects.flash(Color3.fromRGB(200, 215, 255), 0.35)
	task.delay(0.08, function()
		Lighting.Brightness = original
		task.wait(0.1)
		Lighting.Brightness = 2
		task.wait(0.06)
		Lighting.Brightness = original
	end)
	task.delay(math.random(15, 40) / 10, function()
		Audio.play("Thunder", nil, 0.8)
		CameraController.shake(0.4, 2)
	end)
end

local function musicFor(stage: string): string?
	if player:GetAttribute("Chased") then
		return "Chase"
	end
	if stage == "Investigate" or stage == "HouseEscape" or stage == "Captured" then
		return "House"
	elseif stage == "Forest" or stage == "Repair" then
		return "Forest"
	elseif stage == "Hunt" or stage == "Extraction" then
		return "Chase"
	elseif stage == "Power" or stage == "Radio" then
		return "Station"
	elseif stage == "Survive" then
		return "Tension"
	elseif stage == "Ending" then
		return "Ending"
	end
	return nil
end

local function setupTags()
	local function register(tag: string, fn: (BasePart) -> ())
		for _, inst in CollectionService:GetTagged(tag) do
			if inst:IsA("BasePart") then
				fn(inst)
			end
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			if inst:IsA("BasePart") then
				fn(inst)
			end
		end)
	end
	local flickers: { { light: Light, base: number, part: BasePart, phase: number } } = {}
	local candles: { { light: Light, base: number } } = {}
	local hazards: { BasePart } = {}
	local screens: { BasePart } = {}
	register("FlickerLight", function(part)
		local light = part:FindFirstChildWhichIsA("Light")
		if light then
			table.insert(flickers, { light = light, base = light.Brightness, part = part, phase = math.random() * 10 })
		end
	end)
	for _, tag in { "Candle", "FireLight" } do
		register(tag, function(part)
			local light = part:FindFirstChildWhichIsA("Light")
			if light then
				table.insert(candles, { light = light, base = light.Brightness })
			end
		end)
	end
	register("Hazard", function(part)
		table.insert(hazards, part)
	end)
	register("TVStatic", function(part)
		table.insert(screens, part)
	end)

	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for _, f in flickers do
			-- mostly steady with occasional stutters and dropouts
			local n = math.noise(t * 3 + f.phase, f.phase)
			local out = if n > 0.42 then 0.08 elseif n > 0.32 then 0.55 else 1
			f.light.Brightness = f.base * out
			f.part.Transparency = if out < 0.2 then 0.6 else 0
		end
		for _, c in candles do
			c.light.Brightness = c.base * (0.8 + math.noise(t * 6, c.base * 10) * 0.35)
		end
		local blink = math.floor(t / 0.55) % 2 == 0
		for _, h in hazards do
			h.Transparency = if blink then 0 else 0.85
			local light = h:FindFirstChildWhichIsA("Light")
			if light then
				light.Enabled = blink
			end
		end
		for _, s in screens do
			local g = math.random(120, 200)
			s.Color = Color3.fromRGB(g, g, g + 10)
		end
	end)
end

function Effects.init()
	blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = camera
	fearGrade = Instance.new("ColorCorrectionEffect")
	fearGrade.Name = "Fear"
	fearGrade.Parent = camera
	flashGrade = Instance.new("ColorCorrectionEffect")
	flashGrade.Name = "Flash"
	flashGrade.Parent = camera

	overlay = Theme.screen("Effects", 4)
	fearVignette = Theme.vignette(overlay, Color3.new(0, 0, 0), 0.32, 1)
	hurtVignette = Theme.vignette(overlay, Color3.fromRGB(110, 0, 0), 0.4, 2)
	for _, f in hurtVignette:GetChildren() do
		if f:IsA("Frame") then
			f.BackgroundTransparency = 1
		end
	end

	-- rain follows the camera
	rainPart = Instance.new("Part")
	rainPart.Name = "Rain"
	rainPart.Anchored = true
	rainPart.CanCollide = false
	rainPart.CanQuery = false
	rainPart.Transparency = 1
	rainPart.Size = Vector3.new(90, 1, 90)
	rainPart.Parent = workspace
	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rainEmitter.Rate = 350
	rainEmitter.Lifetime = NumberRange.new(0.9, 1.1)
	rainEmitter.Speed = NumberRange.new(80, 95)
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	rainEmitter.SpreadAngle = Vector2.new(4, 4)
	rainEmitter.Size = NumberSequence.new(0.08)
	rainEmitter.Squash = NumberSequence.new(-2.5)
	rainEmitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	rainEmitter.Color = ColorSequence.new(Color3.fromRGB(170, 185, 200))
	rainEmitter.Transparency = NumberSequence.new(0.55)
	rainEmitter.LightInfluence = 1
	rainEmitter.Enabled = false
	rainEmitter.Parent = rainPart

	Net.event("Hurt").OnClientEvent:Connect(function(amount: number)
		hurtFlash = 1
		CameraController.shake(math.clamp(amount / 30, 0.4, 1.6), 3)
		Effects.flash(Color3.fromRGB(255, 80, 70), 0.25)
		Audio.play("Impact", nil, 0.9)
	end)

	setupTags()

	local nextLightning = os.clock() + 40
	local stage = ""
	RunService.RenderStepped:Connect(function(dt: number)
		rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 40, 0))

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local health = if humanoid then humanoid.Health / humanoid.MaxHealth else 1
		local detection = (player:GetAttribute("Detection") :: number?) or 0
		local chased = player:GetAttribute("Chased") == true

		local target = math.max(detection * 0.8, if chased then 1 else 0)
		fear = Util.lerp(fear, target, math.min(1, dt * 2))
		local lowHealth = math.clamp((0.5 - health) / 0.5, 0, 1)

		for _, f in fearVignette:GetChildren() do
			if f:IsA("Frame") then
				f.BackgroundTransparency = Util.lerp(0.15, 0, fear) - (if Effects.menuMode then 0 else 0)
			end
		end
		hurtFlash = math.max(0, hurtFlash - dt * 1.4)
		local pulse = (math.sin(os.clock() * (4 + fear * 5)) + 1) / 2
		local red = math.max(hurtFlash, lowHealth * (0.4 + pulse * 0.3))
		for _, f in hurtVignette:GetChildren() do
			if f:IsA("Frame") then
				f.BackgroundTransparency = 1 - red
			end
		end

		fearGrade.Saturation = -fear * 0.35 - lowHealth * 0.4
		fearGrade.Contrast = fear * 0.15
		fearGrade.Brightness = Effects.brightness
		fearGrade.TintColor = Color3.new(1, 1 - lowHealth * 0.25, 1 - lowHealth * 0.25)

		local blurTarget = Effects.blurOverride or (lowHealth * 6)
		blur.Size = Util.lerp(blur.Size, blurTarget, math.min(1, dt * 5))

		-- heartbeat speeds up with fear
		if fear > 0.15 or lowHealth > 0.2 then
			Audio.loop("Heartbeat", true, math.max(fear, lowHealth) * 0.9)
		else
			Audio.loop("Heartbeat", false)
		end

		local currentStage = (workspace:GetAttribute("Stage") :: string?) or ""
		if not Effects.menuMode then
			local track = musicFor(currentStage)
			Audio.music(track)
		end
		if currentStage ~= stage then
			stage = currentStage
			if stage == "Intro" then
				Effects.setRain(true, true)
			elseif stage == "Forest" or stage == "Repair" or stage == "Hunt" then
				Effects.setRain(true, false)
			elseif stage == "Investigate" or stage == "HouseEscape" or stage == "Ending" then
				Effects.setRain(false)
			end
		end
		local outdoors = stage == "Forest" or stage == "Repair" or stage == "Hunt" or stage == "Power" or stage == "Survive"
		if outdoors and os.clock() > nextLightning then
			nextLightning = os.clock() + math.random(35, 80)
			Effects.lightning()
		end
	end)
end

return Effects

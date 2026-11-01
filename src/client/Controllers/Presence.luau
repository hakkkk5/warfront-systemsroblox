--!strict
-- One of the family is near, before it has ever seen you: the warning the
-- good horror games give (something is coming, and from where). As the
-- nearest of them closes in a low drone swells and the music gives way to
-- it; their heavy steps come from where they are; now and then a low growl
-- in the dark; the lights around them stutter and your flashlight gets
-- nervous. The moment one starts after you: a sting. Effects folds
-- Presence.level into the heartbeat and the vignette.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Util = require(game:GetService("ReplicatedStorage").Shared.Util)
local Audio = require(script.Parent.Audio)
local CameraController = require(script.Parent.CameraController)
local Viewmodel = require(script.Parent.Viewmodel)
local HUD = require(script.Parent.Parent.UI.HUD)

local Presence = {}

-- 0 nobody near .. 1 one of them right on top of you (a chase is its own
-- thing: chase music, the stinger, the red eye)
Presence.level = 0

local RANGE = 70 -- you start to feel one this far off
local NEAR = 10 -- and it's as bad as it gets this close
local STEP_RANGE = 75 -- their footsteps carry this far
local LIGHT_RADIUS = 16 -- lights this close to one of them stutter

local player = Players.LocalPlayer

type Rig = { model: Model, root: BasePart, state: string? }

-- (there can be more than one "Cannibals" folder about: look in every one)
local function folders(): { Instance }
	local list: { Instance } = {}
	for _, c in workspace:GetChildren() do
		if c.Name == "Cannibals" then
			table.insert(list, c)
		end
	end
	return list
end

local function rigs(): { Rig }
	local list: { Rig } = {}
	for _, m in (function(): { Instance }
		local all: { Instance } = {}
		for _, folder in folders() do
			for _, child in folder:GetChildren() do
				table.insert(all, child)
			end
		end
		return all
	end)() do
		if m:IsA("Model") and m:GetAttribute("Kind") then
			local state = m:GetAttribute("State") :: string?
			local root = m:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and state ~= "Sedated" and state ~= "Paused" then
				table.insert(list, { model = m, root = root, state = state })
			end
		end
	end
	return list
end

---------------------------------------------------------------- footsteps

local nextStep: { [Model]: number } = {}
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude

local WOOD = {
	[Enum.Material.Wood] = true,
	[Enum.Material.WoodPlanks] = true,
}

local function footstep(rig: Rig)
	local pos = rig.root.Position
	local hit = workspace:Raycast(pos, Vector3.new(0, -8, 0), floorParams)
	local feet = if hit then hit.Position else pos - Vector3.new(0, 3, 0)
	-- heavy: a person's step, pitched well down
	local sound = if hit and WOOD[hit.Material]
		then Audio.play("Footstep", feet, 0.85, 0.5 + math.random() * 0.06)
		else Audio.play("StepDirt", feet, 1, 0.58 + math.random() * 0.06)
	if sound then
		sound.RollOffMinDistance = 6
		sound.RollOffMaxDistance = STEP_RANGE
	end
end

---------------------------------------------------------------- lights

local lights: { Light } = {}
local seen: { [Light]: boolean } = {}
local disturbed: { [Light]: number } = {} -- its own brightness, while we flicker it

local OWN_FLICKER = { "FlickerLight", "Candle", "FireLight" } -- Effects animates these already

local function consider(inst: Instance)
	if not (inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight")) or seen[inst] then
		return
	end
	local part = inst.Parent
	if not (part and part:IsA("BasePart")) or part:IsDescendantOf(workspace.CurrentCamera) then
		return
	end
	for _, tag in OWN_FLICKER do
		if CollectionService:HasTag(part, tag) then
			return
		end
	end
	seen[inst] = true
	table.insert(lights, inst)
end

local function settle(light: Light)
	local base = disturbed[light]
	if base then
		light.Brightness = base
		disturbed[light] = nil
	end
end

local function stutterLights(list: { Rig }, camPos: Vector3, t: number)
	-- only the ones close enough to you to matter
	local near: { Vector3 } = {}
	for _, rig in list do
		if (rig.root.Position - camPos).Magnitude < 70 then
			table.insert(near, rig.root.Position)
		end
	end
	for i = #lights, 1, -1 do
		local light = lights[i]
		local part = light.Parent
		if not (part and part:IsA("BasePart")) then
			disturbed[light] = nil
			seen[light] = nil
			table.remove(lights, i)
			continue
		end
		local close = false
		if light.Enabled then
			for _, p in near do
				if (part.Position - p).Magnitude < LIGHT_RADIUS then
					close = true
					break
				end
			end
		end
		if close then
			if not disturbed[light] then
				disturbed[light] = light.Brightness
			end
			-- mostly on, dropping out in stutters
			local n = math.noise(t * 7, i * 0.37)
			light.Brightness = (disturbed[light] :: number) * (if n > 0.25 then 0.05 elseif n > 0.05 then 0.5 else 1)
		else
			settle(light)
		end
	end
end

---------------------------------------------------------------- the loop

function Presence.init()
	for _, d in workspace:GetDescendants() do
		consider(d)
	end
	workspace.DescendantAdded:Connect(consider)

	local nextGrowl = 0
	local lastSting = 0
	local wasChased = false
	local lightTick = 0

	RunService.Heartbeat:Connect(function(dt: number)
		local camPos = workspace.CurrentCamera.CFrame.Position
		local now = os.clock()
		local chased = player:GetAttribute("Chased") == true
		local playing = HUD.visible and player:GetAttribute("InCutscene") ~= true
		local list: { Rig } = if playing then rigs() else {}
		floorParams.FilterDescendantsInstances = folders()

		-- how close the nearest one is
		local nearest = math.huge
		local nearestRig: Rig? = nil
		for _, rig in list do
			local d = (rig.root.Position - camPos).Magnitude
			if d < nearest then
				nearest, nearestRig = d, rig
			end
		end
		local raw = if chased or not playing then 0 else math.clamp((RANGE - nearest) / (RANGE - NEAR), 0, 1)
		Presence.level = Util.lerp(Presence.level, raw, math.min(1, dt * (if raw > Presence.level then 1.5 else 0.8)))
		local level = Presence.level

		-- the drone under everything; the music steps back for it (and comes
		-- back for a chase, which has its own)
		Audio.loopLevel("Dread", if level > 0.02 then 0.08 + level ^ 1.3 * 0.62 else 0)
		Audio.setMusicLayer(if chased then 1 else 1 - level * 0.7)
		Viewmodel.dread = level

		-- their steps, from where they are
		for _, rig in list do
			local d = (rig.root.Position - camPos).Magnitude
			local v = rig.root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			if d < STEP_RANGE and speed > 2 then
				if now >= (nextStep[rig.model] or 0) then
					nextStep[rig.model] = now + math.clamp(4.4 / speed, 0.27, 0.7)
					footstep(rig)
				end
			end
		end

		-- a low growl now and then from one that's close but hasn't got you
		local closest = nearestRig
		if closest and not chased and nearest < 38 and now >= nextGrowl then
			nextGrowl = now + 9 + math.random() * 7
			local head = closest.model:FindFirstChild("Head")
			local at = if head and head:IsA("BasePart") then head.Position else closest.root.Position
			local growl = Audio.play("Growl", at, 0.4, 0.55 + math.random() * 0.15)
			if growl then
				growl.RollOffMinDistance = 5
				growl.RollOffMaxDistance = 60
			end
		end

		-- spotted: a sting and a jolt (not every time it loses and finds you)
		if chased and not wasChased and playing and now - lastSting > 8 then
			lastSting = now
			Audio.play("Stinger", nil, 0.75, 1)
			CameraController.punch(6)
			CameraController.shake(0.6, 3)
		end
		wasChased = chased

		lightTick += dt
		if lightTick >= 0.08 then
			lightTick = 0
			stutterLights(list, camPos, now)
		end
	end)
end

return Presence

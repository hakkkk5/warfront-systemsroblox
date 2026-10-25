--!strict
-- First-person hands: the flashlight (with a real shadow-casting spotlight
-- and draining battery) in the right hand and the equipped item in the left.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Audio)
local CameraController = require(script.Parent.CameraController)
local MeshLibrary = require(script.Parent.MeshLibrary)
local Movement = require(script.Parent.Movement)

local Viewmodel = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

Viewmodel.battery = 100
Viewmodel.on = false
Viewmodel.hidden = false

local SLEEVE = Color3.fromRGB(38, 44, 52)
local SKIN = Color3.fromRGB(214, 170, 140)

local root: Model
local rightGroup: Model
local leftGroup: Model
local spot: SpotLight
local fill: PointLight
local emitter: Part
local leftItem: Model? = nil
local leftItemId: string? = nil
local sway = CFrame.new()
local lowered = 1 -- 0 = raised, 1 = lowered out of view

local function part(parent: Instance, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function arm(parent: Model)
	local sleeve = part(parent, Vector3.new(0.5, 0.5, 1.9), SLEEVE, Enum.Material.Fabric)
	sleeve.Name = "Sleeve"
	local hand = part(parent, Vector3.new(0.42, 0.34, 0.56), SKIN, Enum.Material.SmoothPlastic)
	hand.Name = "Hand"
	local cuff = part(parent, Vector3.new(0.54, 0.54, 0.16), SLEEVE:Lerp(Color3.new(), 0.3), Enum.Material.Fabric)
	cuff.Name = "Cuff"
end

-- Item model scaled to fit the hand, centred on its bounding box.
local function holdable(id: string, length: number): Model?
	local def = Items.get(id)
	local folder = ReplicatedStorage:FindFirstChild("ItemModels")
	local template = if def and folder then folder:FindFirstChild(def.model) else nil
	if not template or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CastShadow = false
		end
	end
	model:PivotTo(CFrame.new())
	if model:GetAttribute("Mesh") then
		MeshLibrary.upgrade(model)
	end
	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		model:ScaleTo(model:GetScale() * (length / longest))
	end
	local cf = model:GetBoundingBox()
	model.WorldPivot = cf
	return model
end

local function buildFlashlight()
	local light = holdable("Flashlight", 1.15)
	if light then
		-- lens points along +X in the model; turn it to face camera-forward
		light:PivotTo(CFrame.new())
		light.Name = "Light"
		light.Parent = rightGroup
		light:SetAttribute("Offset", CFrame.Angles(0, math.rad(90), 0))
	end
end

local function setLeftItem(id: string?)
	if id == leftItemId then
		return
	end
	leftItemId = id
	if leftItem then
		leftItem:Destroy()
		leftItem = nil
	end
	if id then
		local model = holdable(id, if id == "Syringe" then 0.9 else 1.2)
		if model then
			model.Parent = leftGroup
			leftItem = model
			Audio.play(if id == "Knife" then "KnifeDraw" else "Whoosh")
		end
	end
end

function Viewmodel.toggle(force: boolean?)
	if player:GetAttribute("HasFlashlight") ~= true then
		return
	end
	local want = if force ~= nil then force else not Viewmodel.on
	if want and Viewmodel.battery <= 0 then
		want = false
	end
	Viewmodel.on = want
	Audio.play("FlashlightClick")
	Movement.setFlashlight(want)
end

function Viewmodel.init()
	root = Instance.new("Model")
	root.Name = "Viewmodel"
	rightGroup = Instance.new("Model")
	rightGroup.Name = "Right"
	rightGroup.Parent = root
	leftGroup = Instance.new("Model")
	leftGroup.Name = "Left"
	leftGroup.Parent = root
	arm(rightGroup)
	arm(leftGroup)

	emitter = part(root, Vector3.new(0.1, 0.1, 0.1), Color3.new(), Enum.Material.SmoothPlastic)
	emitter.Transparency = 1
	emitter.Name = "Emitter"
	spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 52
	spot.Range = 62
	spot.Brightness = 2.4
	spot.Color = Color3.fromRGB(255, 240, 214)
	spot.Shadows = true
	spot.Enabled = false
	spot.Parent = emitter
	fill = Instance.new("PointLight")
	fill.Range = 9
	fill.Brightness = 0.35
	fill.Color = Color3.fromRGB(255, 236, 210)
	fill.Shadows = false
	fill.Enabled = false
	fill.Parent = emitter
	root.Parent = camera

	task.spawn(function()
		ReplicatedStorage:WaitForChild("ItemModels", 60)
		buildFlashlight()
	end)

	ContextActionService:BindAction("Flashlight", function(_, state)
		if state == Enum.UserInputState.Begin then
			Viewmodel.toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonY) -- phones: UI TouchControls

	Net.event("Recharge").OnClientEvent:Connect(function(amount: number)
		Viewmodel.battery = math.min(100, Viewmodel.battery + amount)
	end)
	player:GetAttributeChangedSignal("HasFlashlight"):Connect(function()
		if player:GetAttribute("HasFlashlight") then
			Viewmodel.toggle(true)
		end
	end)

	local flicker = 1
	RunService:BindToRenderStep("Viewmodel", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local alive = humanoid ~= nil and humanoid.Health > 0
		local hasLight = player:GetAttribute("HasFlashlight") == true
		local equipped = player:GetAttribute("Equipped")
		setLeftItem(if typeof(equipped) == "string" then equipped else nil)

		local show = alive
			and not Viewmodel.hidden
			and CameraController.isEnabled()
			and camera.CameraType == Enum.CameraType.Custom
			and not player:GetAttribute("Hidden")
			and not player:GetAttribute("InCutscene")
		lowered = Util.lerp(lowered, if show then 0 else 1, math.min(1, dt * 7))

		-- battery
		if Viewmodel.on then
			Viewmodel.battery = math.max(0, Viewmodel.battery - Config.Player.FlashlightDrain * dt)
			if Viewmodel.battery <= 0 then
				Viewmodel.toggle(false)
			end
		end
		local low = Viewmodel.battery < 15
		if low and Viewmodel.on then
			if math.random() < dt * 6 then
				flicker = math.random() * 0.6
			else
				flicker = Util.lerp(flicker, 1, dt * 10)
			end
		else
			flicker = 1
		end
		local lightOn = Viewmodel.on and hasLight and alive and not player:GetAttribute("Hidden")
		spot.Enabled = lightOn
		fill.Enabled = lightOn
		spot.Brightness = 2.4 * flicker * (0.55 + 0.45 * math.min(Viewmodel.battery / 40, 1))

		-- sway from mouse movement
		local delta = UserInputService:GetMouseDelta()
		local target = CFrame.Angles(math.clamp(-delta.Y * 0.0025, -0.08, 0.08), math.clamp(-delta.X * 0.0025, -0.1, 0.1), 0)
		sway = sway:Lerp(target, math.min(1, dt * 9))
		local bob = math.sin(os.clock() * (if CameraController.sprinting then 12 else 7)) * (if Movement.isCrouching() then 0.01 else 0.025)

		local base = camera.CFrame * sway * CFrame.new(0, -lowered * 2.2 + bob, 0)
		local rightBase = base * CFrame.new(0.9, -0.95, -1.35) * CFrame.Angles(math.rad(4), math.rad(-6), 0)
		local leftBase = base * CFrame.new(-0.95, -1.05, -1.3) * CFrame.Angles(math.rad(6), math.rad(10), 0)

		local rightVisible = hasLight and lowered < 0.98
		local leftVisible = leftItem ~= nil and lowered < 0.98
		for _, group in { rightGroup, leftGroup } do
			local visible = if group == rightGroup then rightVisible else leftVisible
			local baseCF = if group == rightGroup then rightBase else leftBase
			for _, p in group:GetChildren() do
				if p:IsA("BasePart") then
					p.Transparency = if visible then 0 else 1
					if p.Name == "Sleeve" then
						p.CFrame = baseCF * CFrame.new(0, -0.05, 1.05)
					elseif p.Name == "Cuff" then
						p.CFrame = baseCF * CFrame.new(0, -0.05, 0.12)
					elseif p.Name == "Hand" then
						p.CFrame = baseCF * CFrame.new(0, -0.02, -0.1)
					end
				elseif p:IsA("Model") then
					local offset = (p:GetAttribute("Offset") :: CFrame?) or CFrame.Angles(0, math.rad(90), 0)
					p:PivotTo(baseCF * CFrame.new(0, 0.12, -0.35) * offset)
					-- with a Blender mesh applied, the procedural stand-in stays hidden
					local hasVisual = p:FindFirstChild("BlenderVisual") ~= nil
					for _, d in p:GetDescendants() do
						if d:IsA("BasePart") then
							local isVisual = d:FindFirstAncestor("BlenderVisual") ~= nil
							d.LocalTransparencyModifier = if (hasVisual and not isVisual) or not visible then 1 else 0
						end
					end
				end
			end
		end
		-- the light comes from the lens even while the hands are lowered
		emitter.CFrame = (camera.CFrame * sway) * CFrame.new(0.75, -0.55, -1.9)
	end)
end

return Viewmodel

--!strict
-- Procedural prop models built from parts. They are used directly for props
-- that have no mesh, and as fallbacks when a ForgeGUI mesh fails to load.
-- Every builder returns a Model whose pivot is the bottom centre at the
-- origin, with the front facing -Z.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)

local Props = {}

-- Props that have a Blender mesh (tools/blender/build_props.py). They are
-- tagged so clients can swap in the detailed mesh (client MeshLibrary).
local blenderMeshes: { [string]: boolean } = {}
for _, name in require(ReplicatedStorage.Shared.Meshes) :: { string } do
	blenderMeshes[name] = true
end

local rgb = Color3.fromRGB
local M = Enum.Material
local P = Build.part
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local function finish(model: Model, meshName: string?): Model
	model.WorldPivot = CFrame.new()
	local mesh = meshName or model.Name
	if blenderMeshes[mesh] then
		model:SetAttribute("Mesh", mesh)
		CollectionService:AddTag(model, "BlenderMesh")
	end
	return model
end
Props.finish = finish

local function noCollide(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
end

---------------------------------------------------------------- vegetation

function Props.PineTree(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "PineTree"
	local height = rng:NextNumber(34, 52)
	local trunkD = rng:NextNumber(1.5, 2.3)
	Build.post(m, height * 0.9, trunkD, CF(0, height * 0.45, 0), rgb(56, 41, 30), M.Wood).Name = "Trunk"
	local layers = rng:NextInteger(6, 8)
	local base = height * 0.22
	local green = rgb(rng:NextInteger(28, 38), rng:NextInteger(44, 54), rng:NextInteger(28, 34))
	for i = 0, layers - 1 do
		local t = i / layers
		local r = (1 - t) * rng:NextNumber(7.5, 9.5) + 1.2
		local y = base + t * (height - base) * 0.92
		local h = (height - base) / layers * 1.6
		local yaw = rng:NextNumber(0, math.pi)
		for q = 0, 3 do
			local rot = ANG(0, yaw + q * math.pi / 2, 0)
			Build.wedge(m, Vector3.new(r * 1.45, h, r), CF(0, y + h / 2, 0) * rot * CF(0, 0, -r / 2), green, M.LeafyGrass, {
				CanCollide = false,
			})
		end
	end
	return finish(m)
end

function Props.DeadTree(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "DeadTree"
	local bark = rgb(66, 60, 54)
	local height = rng:NextNumber(18, 30)
	local d = rng:NextNumber(1.6, 2.4)
	local y = 0
	for i = 1, 3 do
		local seg = height / 3
		local tilt = ANG(rad(rng:NextNumber(-6, 6)), 0, rad(rng:NextNumber(-6, 6)))
		Build.post(m, seg + 0.4, d * (1 - (i - 1) * 0.25), CF(0, y + seg / 2, 0) * tilt, bark, M.Wood)
		y += seg
	end
	for _ = 1, rng:NextInteger(5, 8) do
		local by = rng:NextNumber(height * 0.35, height * 0.95)
		local len = rng:NextNumber(4, 9)
		local yaw = rng:NextNumber(0, math.pi * 2)
		local pitch = rng:NextNumber(20, 55)
		local branch = CF(0, by, 0) * ANG(0, yaw, 0) * ANG(0, 0, rad(pitch)) * CF(len / 2, 0, 0)
		Build.cylinder(m, len, rng:NextNumber(0.35, 0.6), branch, bark, M.Wood, { CanCollide = false })
		local twig = branch * CF(len / 2, 0, 0) * ANG(0, rng:NextNumber(-0.8, 0.8), rad(rng:NextNumber(-30, 40))) * CF(len * 0.3, 0, 0)
		Build.cylinder(m, len * 0.6, 0.22, twig, bark, M.Wood, { CanCollide = false })
	end
	return finish(m, if rng:NextNumber() > 0.5 then "DeadTree" else "DeadTree2")
end

function Props.Bush(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "Bush"
	local green = rgb(rng:NextInteger(30, 42), rng:NextInteger(42, 52), rng:NextInteger(26, 32))
	for _ = 1, rng:NextInteger(3, 5) do
		local s = rng:NextNumber(2.2, 4.2)
		Build.ball(m, s, CF(rng:NextNumber(-1.6, 1.6), s * 0.32, rng:NextNumber(-1.6, 1.6)), green, M.LeafyGrass, {
			CanCollide = false,
			CastShadow = false,
		})
	end
	return finish(m)
end

function Props.Rock(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "Rock"
	local grey = rng:NextInteger(70, 92)
	for i = 1, rng:NextInteger(1, 3) do
		local s = Vector3.new(rng:NextNumber(2, 6), rng:NextNumber(1.5, 4), rng:NextNumber(2, 5)) * (if i == 1 then 1 else 0.6)
		local cf = CF(rng:NextNumber(-1.5, 1.5) * (i - 1), s.Y * 0.3, rng:NextNumber(-1.5, 1.5) * (i - 1))
			* ANG(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4))
		P(m, s, cf, rgb(grey, grey, grey - 4), if rng:NextNumber() > 0.5 then M.Slate else M.Rock)
	end
	return finish(m, if rng:NextNumber() > 0.5 then "Rock" else "Rock2")
end

function Props.Log(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "Log"
	local len = rng:NextNumber(8, 16)
	local d = rng:NextNumber(1.4, 2.4)
	Build.cylinder(m, len, d, CF(0, d * 0.42, 0) * ANG(0, rng:NextNumber(0, math.pi), 0), rgb(60, 46, 34), M.Wood)
	return finish(m)
end

function Props.Stump(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "Stump"
	local d = rng:NextNumber(1.8, 2.8)
	local h = rng:NextNumber(0.8, 2)
	Build.post(m, h, d, CF(0, h / 2, 0), rgb(58, 44, 32), M.Wood)
	Build.post(m, 0.06, d * 0.92, CF(0, h + 0.02, 0), rgb(120, 92, 62), M.Wood, { CanCollide = false })
	return finish(m)
end

function Props.Mushrooms(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "Mushrooms"
	for _ = 1, rng:NextInteger(3, 6) do
		local x, z = rng:NextNumber(-0.8, 0.8), rng:NextNumber(-0.8, 0.8)
		local h = rng:NextNumber(0.25, 0.6)
		Build.post(m, h, 0.12, CF(x, h / 2, z), rgb(210, 200, 180), M.SmoothPlastic)
		P(m, Vector3.new(0.45, 0.14, 0.45), CF(x, h, z), rgb(150, 110, 70), M.SmoothPlastic)
	end
	noCollide(m)
	return finish(m)
end

---------------------------------------------------------------- vehicles

local function wheel(m: Model, cf: CFrame, d: number)
	Build.cylinder(m, 1.1, d, cf, rgb(24, 24, 24), M.Rubber)
	Build.cylinder(m, 1.16, d * 0.55, cf, rgb(110, 105, 100), M.Metal)
end

function Props.PickupTruck(): Model
	local m = Instance.new("Model")
	m.Name = "PickupTruck"
	local paint = rgb(122, 40, 32)
	local rust = rgb(96, 58, 36)
	local chrome = rgb(170, 168, 160)
	-- chassis and body (front faces -Z)
	P(m, Vector3.new(6.6, 1.2, 17), CF(0, 2, 0), rgb(30, 28, 26), M.Metal)
	P(m, Vector3.new(7, 2.2, 6.2), CF(0, 3.5, -5.4), paint, M.CorrodedMetal).Name = "Hood"
	P(m, Vector3.new(7, 4.4, 4.2), CF(0, 4.6, -0.4), paint, M.CorrodedMetal).Name = "Cab"
	P(m, Vector3.new(6.4, 1.8, 3.8), CF(0, 5.6, -0.6), rgb(40, 52, 58), M.Glass, { Transparency = 0.35 }).Name = "Windows"
	P(m, Vector3.new(7, 0.3, 4.4), CF(0, 6.9, -0.4), paint, M.CorrodedMetal)
	-- bed
	P(m, Vector3.new(7, 0.6, 7.4), CF(0, 2.9, 6.2), rust, M.CorrodedMetal)
	P(m, Vector3.new(0.4, 2, 7.4), CF(-3.3, 3.9, 6.2), paint, M.CorrodedMetal)
	P(m, Vector3.new(0.4, 2, 7.4), CF(3.3, 3.9, 6.2), paint, M.CorrodedMetal)
	P(m, Vector3.new(7, 2, 0.4), CF(0, 3.9, 9.8), paint, M.CorrodedMetal)
	-- grille, bumpers, lights
	P(m, Vector3.new(6, 1.6, 0.3), CF(0, 3.4, -8.55), chrome, M.DiamondPlate)
	P(m, Vector3.new(7.4, 0.6, 0.6), CF(0, 2.2, -8.8), chrome, M.Metal)
	P(m, Vector3.new(7.4, 0.6, 0.6), CF(0, 2.2, 8.8), chrome, M.Metal)
	for _, x in { -2.6, 2.6 } do
		local lamp = Build.cylinder(m, 0.3, 1, CF(x, 3.6, -8.6) * ANG(0, rad(90), 0), rgb(230, 225, 200), M.Glass)
		lamp.Name = "Headlight"
		Build.cylinder(m, 0.3, 0.6, CF(x, 3.2, 9.95) * ANG(0, rad(90), 0), rgb(120, 10, 10), M.Glass).Name = "Taillight"
	end
	-- wheels
	for _, z in { -5.6, 5.8 } do
		for _, x in { -3.4, 3.4 } do
			wheel(m, CF(x, 1.6, z), 3.2)
		end
	end
	-- mirror + steering wheel visible through the glass
	Build.cylinder(m, 0.15, 1.4, CF(-1.6, 4.6, -1.6) * ANG(rad(60), rad(90), 0), rgb(20, 20, 20), M.SmoothPlastic)
	P(m, Vector3.new(0.6, 0.5, 0.2), CF(-3.8, 5.2, -2.2), chrome, M.Metal)
	return finish(m)
end

function Props.CrashedSedan(): Model
	local m = Instance.new("Model")
	m.Name = "CrashedSedan"
	local paint = rgb(32, 40, 66)
	P(m, Vector3.new(6.4, 1.6, 15), CF(0, 2, 0.6), paint, M.Metal)
	P(m, Vector3.new(6, 2.4, 6.2), CF(0, 4, 1.4), paint, M.Metal).Name = "Cabin"
	P(m, Vector3.new(5.6, 1.9, 5.8), CF(0, 4.1, 1.4), rgb(30, 36, 40), M.Glass, { Transparency = 0.5 })
	-- crumpled bonnet folded upward
	P(m, Vector3.new(6.2, 0.4, 4.6), CF(0, 3.6, -5) * ANG(rad(-24), rad(4), rad(-3)), paint, M.Metal).Name = "Hood"
	P(m, Vector3.new(5.6, 1.4, 1.8), CF(0.3, 2.2, -6.4) * ANG(0, rad(12), 0), rgb(40, 40, 42), M.CorrodedMetal)
	-- cracked windscreen
	P(m, Vector3.new(5.6, 2.2, 0.2), CF(0, 4.1, -1.8) * ANG(rad(-30), 0, 0), rgb(160, 175, 180), M.Glass, {
		Transparency = 0.3,
		Reflectance = 0.2,
	})
	-- dangling headlight
	Build.cylinder(m, 0.3, 0.8, CF(-2.6, 1.6, -7.2) * ANG(rad(30), rad(90), 0), rgb(230, 225, 200), M.Glass).Name = "Headlight"
	for _, z in { -4.8, 5.2 } do
		for _, x in { -3.2, 3.2 } do
			wheel(m, CF(x, 1.4, z) * ANG(0, 0, if z < 0 and x > 0 then rad(14) else 0), 2.8)
		end
	end
	return finish(m)
end

---------------------------------------------------------------- items

function Props.EngineBlock(): Model
	local m = Instance.new("Model")
	m.Name = "EngineBlock"
	local metal = rgb(70, 68, 64)
	P(m, Vector3.new(2.2, 1.6, 3), CF(0, 0.8, 0), metal, M.CorrodedMetal)
	for _, x in { -0.9, 0.9 } do
		P(m, Vector3.new(0.9, 0.7, 2.8), CF(x, 1.8, 0) * ANG(0, 0, rad(x * 25)), rgb(120, 30, 26), M.Metal)
	end
	P(m, Vector3.new(1, 0.5, 1.6), CF(0, 2.05, 0), rgb(40, 40, 40), M.Metal)
	Build.cylinder(m, 0.3, 1.2, CF(0, 1, -1.6) * ANG(0, rad(90), 0), rgb(30, 30, 30), M.Metal)
	Build.cylinder(m, 0.3, 0.7, CF(0.6, 1.5, -1.6) * ANG(0, rad(90), 0), rgb(30, 30, 30), M.Metal)
	return finish(m)
end

function Props.CarBattery(): Model
	local m = Instance.new("Model")
	m.Name = "CarBattery"
	P(m, Vector3.new(1.6, 1, 0.9), CF(0, 0.5, 0), rgb(25, 25, 25), M.Plastic)
	P(m, Vector3.new(1.62, 0.12, 0.92), CF(0, 0.95, 0), rgb(60, 60, 60), M.Plastic)
	Build.post(m, 0.2, 0.22, CF(-0.55, 1.1, 0), rgb(170, 30, 30), M.Metal)
	Build.post(m, 0.2, 0.22, CF(0.55, 1.1, 0), rgb(30, 30, 30), M.Metal)
	P(m, Vector3.new(0.9, 0.5, 0.02), CF(0, 0.5, -0.46), rgb(200, 170, 40), M.SmoothPlastic)
	return finish(m)
end

function Props.SparkPlugs(): Model
	local m = Instance.new("Model")
	m.Name = "SparkPlugs"
	P(m, Vector3.new(1.2, 0.35, 0.7), CF(0, 0.175, 0), rgb(150, 110, 70), M.Cardboard)
	for i = 0, 3 do
		local x = -0.42 + i * 0.28
		Build.post(m, 0.5, 0.12, CF(x, 0.55, 0), rgb(235, 235, 230), M.SmoothPlastic)
		Build.post(m, 0.15, 0.16, CF(x, 0.35, 0), rgb(160, 160, 160), M.Metal)
	end
	return finish(m)
end

function Props.TireWheel(): Model
	local m = Instance.new("Model")
	m.Name = "TireWheel"
	Build.cylinder(m, 1.1, 3, CF(0, 1.5, 0), rgb(22, 22, 22), M.Rubber)
	Build.cylinder(m, 1.16, 1.7, CF(0, 1.5, 0), rgb(110, 70, 50), M.CorrodedMetal)
	Build.cylinder(m, 1.2, 0.5, CF(0, 1.5, 0), rgb(60, 60, 60), M.Metal)
	return finish(m)
end

function Props.Syringe(): Model
	local m = Instance.new("Model")
	m.Name = "Syringe"
	Build.cylinder(m, 0.62, 0.16, CF(0, 0.09, 0), rgb(220, 240, 230), M.Glass, { Transparency = 0.45 })
	Build.cylinder(m, 0.5, 0.11, CF(0.02, 0.09, 0), rgb(90, 255, 120), M.Neon, { Transparency = 0.15 }).Name = "Liquid"
	Build.cylinder(m, 0.3, 0.05, CF(-0.45, 0.09, 0), rgb(240, 240, 240), M.SmoothPlastic)
	P(m, Vector3.new(0.04, 0.22, 0.22), CF(-0.6, 0.09, 0), rgb(240, 240, 240), M.SmoothPlastic)
	Build.cylinder(m, 0.32, 0.02, CF(0.47, 0.09, 0), rgb(200, 200, 205), M.Metal)
	noCollide(m)
	return finish(m)
end

function Props.CarKeys(): Model
	local m = Instance.new("Model")
	m.Name = "CarKeys"
	local brass = rgb(196, 160, 80)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		P(m, Vector3.new(0.09, 0.03, 0.03), CF(math.cos(a) * 0.14, 0.02, math.sin(a) * 0.14) * ANG(0, -a, 0), rgb(160, 160, 165), M.Metal)
	end
	P(m, Vector3.new(0.45, 0.03, 0.1), CF(0.36, 0.02, 0.05) * ANG(0, rad(-15), 0), brass, M.Metal)
	P(m, Vector3.new(0.4, 0.03, 0.1), CF(0.3, 0.02, -0.12) * ANG(0, rad(20), 0), rgb(150, 150, 150), M.Metal)
	Build.ball(m, 0.2, CF(-0.22, 0.08, 0), rgb(160, 130, 100), M.Fabric)
	noCollide(m)
	return finish(m)
end

function Props.HuntingKnife(): Model
	local m = Instance.new("Model")
	m.Name = "HuntingKnife"
	P(m, Vector3.new(0.8, 0.04, 0.16), CF(0.35, 0.04, 0), rgb(180, 180, 185), M.Metal).Name = "Blade"
	Build.wedge(m, Vector3.new(0.04, 0.16, 0.2), CF(0.85, 0.04, 0) * ANG(0, rad(90), rad(90)), rgb(180, 180, 185), M.Metal)
	P(m, Vector3.new(0.06, 0.08, 0.3), CF(-0.07, 0.04, 0), rgb(170, 130, 60), M.Metal)
	P(m, Vector3.new(0.5, 0.12, 0.14), CF(-0.35, 0.04, 0), rgb(70, 46, 30), M.Wood)
	noCollide(m)
	return finish(m)
end

function Props.Flashlight(): Model
	local m = Instance.new("Model")
	m.Name = "Flashlight"
	Build.cylinder(m, 1, 0.2, CF(0, 0.13, 0), rgb(26, 26, 28), M.Metal).Name = "Body"
	Build.cylinder(m, 0.25, 0.3, CF(0.6, 0.13, 0), rgb(40, 40, 42), M.Metal).Name = "Head"
	Build.cylinder(m, 0.03, 0.26, CF(0.735, 0.13, 0), rgb(255, 245, 220), M.Neon).Name = "Lens"
	P(m, Vector3.new(0.12, 0.04, 0.08), CF(0.2, 0.24, 0), rgb(80, 20, 20), M.Rubber)
	noCollide(m)
	return finish(m)
end

function Props.Battery(): Model
	local m = Instance.new("Model")
	m.Name = "Battery"
	for _, z in { -0.1, 0.1 } do
		Build.cylinder(m, 0.45, 0.2, CF(0, 0.1, z), rgb(30, 30, 30), M.SmoothPlastic)
		Build.cylinder(m, 0.12, 0.205, CF(0.17, 0.1, z), rgb(200, 150, 40), M.SmoothPlastic)
	end
	noCollide(m)
	return finish(m)
end

function Props.Bandage(): Model
	local m = Instance.new("Model")
	m.Name = "Bandage"
	Build.cylinder(m, 0.3, 0.36, CF(0, 0.18, 0) * ANG(0, 0, rad(90)), rgb(225, 220, 205), M.Fabric)
	P(m, Vector3.new(0.3, 0.02, 0.5), CF(0, 0.01, 0.35), rgb(225, 220, 205), M.Fabric)
	P(m, Vector3.new(0.12, 0.022, 0.15), CF(0.05, 0.012, 0.4), rgb(120, 20, 20), M.Fabric)
	noCollide(m)
	return finish(m)
end

function Props.HouseKey(): Model
	local m = Instance.new("Model")
	m.Name = "HouseKey"
	local iron = rgb(110, 86, 60)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		P(m, Vector3.new(0.08, 0.04, 0.04), CF(-0.25 + math.cos(a) * 0.1, 0.02, math.sin(a) * 0.1) * ANG(0, -a, 0), iron, M.CorrodedMetal)
	end
	P(m, Vector3.new(0.45, 0.04, 0.05), CF(0.06, 0.02, 0), iron, M.CorrodedMetal)
	P(m, Vector3.new(0.08, 0.04, 0.14), CF(0.24, 0.02, 0.07), iron, M.CorrodedMetal)
	noCollide(m)
	return finish(m)
end

function Props.Fuse(): Model
	local m = Instance.new("Model")
	m.Name = "Fuse"
	Build.cylinder(m, 0.5, 0.16, CF(0, 0.08, 0), rgb(235, 230, 220), M.SmoothPlastic)
	for _, x in { -0.27, 0.27 } do
		Build.cylinder(m, 0.08, 0.18, CF(x, 0.08, 0), rgb(190, 160, 90), M.Metal)
	end
	noCollide(m)
	return finish(m)
end

function Props.GasCan(): Model
	local m = Instance.new("Model")
	m.Name = "GasCan"
	local red = rgb(150, 30, 24)
	P(m, Vector3.new(0.7, 1.6, 1.2), CF(0, 0.8, 0), red, M.Metal)
	for _, z in { -0.35, 0, 0.35 } do
		P(m, Vector3.new(0.12, 0.3, 0.12), CF(0, 1.72, z), red, M.Metal)
	end
	P(m, Vector3.new(0.12, 0.1, 0.9), CF(0, 1.88, 0), red, M.Metal)
	Build.post(m, 0.3, 0.2, CF(0, 1.75, -0.5) * ANG(rad(30), 0, 0), rgb(40, 40, 40), M.Metal)
	return finish(m)
end

function Props.Note(): Model
	local m = Instance.new("Model")
	m.Name = "Note"
	local paper = P(m, Vector3.new(0.85, 0.02, 1.1), CF(0, 0.01, 0) * ANG(0, rad(8), 0), rgb(214, 204, 176), M.SmoothPlastic, {
		CanCollide = false,
	})
	paper.Name = "Paper"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(170, 220)
	gui.LightInfluence = 1
	gui.Parent = paper
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Text = "...they come at night...\n\n- - - - -\n- - - -\n- - - - - -\n- - -"
	text.TextColor3 = rgb(50, 40, 30)
	text.Font = Enum.Font.IndieFlower
	text.TextSize = 18
	text.TextWrapped = true
	text.Parent = gui
	return finish(m)
end

---------------------------------------------------------------- weapons / gear

function Props.Cleaver(): Model
	local m = Instance.new("Model")
	m.Name = "Cleaver"
	P(m, Vector3.new(0.06, 0.9, 1.1), CF(0, 1.25, 0.15), rgb(150, 148, 145), M.CorrodedMetal).Name = "Blade"
	P(m, Vector3.new(0.065, 0.25, 0.35), CF(0, 0.95, 0.4), rgb(90, 12, 10), M.Glass)
	Build.post(m, 0.8, 0.18, CF(0, 0.4, -0.25), rgb(64, 40, 26), M.Wood).Name = "Handle"
	noCollide(m)
	return finish(m)
end

function Props.Chainsaw(): Model
	local m = Instance.new("Model")
	m.Name = "Chainsaw"
	P(m, Vector3.new(0.8, 0.9, 1.4), CF(0, 0.45, 0), rgb(200, 90, 30), M.Plastic).Name = "Body"
	P(m, Vector3.new(0.16, 0.36, 3), CF(0, 0.45, -2.1), rgb(150, 150, 150), M.Metal).Name = "Bar"
	for i = 0, 11 do
		P(m, Vector3.new(0.2, 0.08, 0.12), CF(0, 0.65, -0.7 - i * 0.25), rgb(80, 80, 80), M.Metal)
		P(m, Vector3.new(0.2, 0.08, 0.12), CF(0, 0.25, -0.7 - i * 0.25), rgb(80, 80, 80), M.Metal)
	end
	P(m, Vector3.new(0.12, 0.5, 0.8), CF(0, 1.05, 0.1), rgb(30, 30, 30), M.Plastic)
	noCollide(m)
	return finish(m)
end

function Props.Lantern(): Model
	local m = Instance.new("Model")
	m.Name = "Lantern"
	local metal = rgb(40, 40, 36)
	Build.post(m, 0.15, 0.6, CF(0, 0.075, 0), metal, M.Metal)
	local glass = Build.post(m, 0.6, 0.45, CF(0, 0.45, 0), rgb(255, 190, 110), M.Neon, { Transparency = 0.3 })
	glass.Name = "Glass"
	Build.post(m, 0.15, 0.6, CF(0, 0.82, 0), metal, M.Metal)
	P(m, Vector3.new(0.05, 0.4, 0.05), CF(0, 1.05, 0), metal, M.Metal)
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 160, 80)
	light.Brightness = 1.6
	light.Range = 18
	light.Shadows = true
	light.Parent = glass
	Build.tag(glass, "Candle")
	noCollide(m)
	return finish(m)
end

---------------------------------------------------------------- furniture / house props

function Props.ButcherTable(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "ButcherTable"
	local wood = rgb(78, 52, 34)
	P(m, Vector3.new(8, 0.8, 3.6), CF(0, 3.1, 0), wood, M.Wood).Name = "Top"
	for _, x in { -3.6, 3.6 } do
		for _, z in { -1.5, 1.5 } do
			P(m, Vector3.new(0.6, 2.7, 0.6), CF(x, 1.35, z), wood, M.Wood)
		end
	end
	P(m, Vector3.new(7.6, 0.4, 3.2), CF(0, 0.6, 0), wood, M.WoodPlanks)
	Build.stain(m, CF(0.6, 3.52, 0.2), Vector2.new(2.4, 1.4), rng)
	Build.stain(m, CF(-2.2, 3.52, -0.6), Vector2.new(1.2, 0.9), rng)
	local cleaver = Props.Cleaver()
	cleaver:PivotTo(CF(2.8, 3.4, 0.8) * ANG(rad(15), rad(90), 0))
	cleaver.Parent = m
	-- saw and buckets
	P(m, Vector3.new(1.8, 0.04, 0.5), CF(-2.6, 3.52, 1.1) * ANG(0, rad(20), 0), rgb(150, 150, 150), M.Metal)
	Build.post(m, 1.2, 1.2, CF(-3, 0.6, 2.8), rgb(90, 90, 92), M.CorrodedMetal)
	return finish(m)
end

function Props.MeatHooks(): Model
	local m = Instance.new("Model")
	m.Name = "MeatHooks"
	P(m, Vector3.new(7, 0.8, 0.8), CF(0, 6.6, 0), rgb(60, 44, 32), M.Wood).Name = "Beam"
	for i = -1, 1 do
		local x = i * 2.4
		for c = 0, 4 do
			P(m, Vector3.new(0.1, 0.32, 0.18), CF(x, 6.05 - c * 0.3, 0) * ANG(0, if c % 2 == 0 then 0 else rad(90), 0), rgb(90, 86, 80), M.Metal)
		end
		P(m, Vector3.new(0.1, 0.9, 0.1), CF(x, 4.2, 0), rgb(110, 70, 50), M.CorrodedMetal)
		P(m, Vector3.new(0.1, 0.1, 0.5), CF(x, 3.78, 0.2), rgb(110, 70, 50), M.CorrodedMetal)
		P(m, Vector3.new(0.1, 0.3, 0.1), CF(x, 3.9, 0.42), rgb(110, 70, 50), M.CorrodedMetal)
	end
	noCollide(m)
	return finish(m)
end

function Props.BodyBag(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "BodyBag"
	local burlap = rgb(122, 98, 70)
	Build.cylinder(m, 4.6, 1.5, CF(0, 0.75, 0), burlap, M.Fabric)
	Build.ball(m, 1.5, CF(-2.3, 0.75, 0), burlap, M.Fabric)
	Build.ball(m, 1.3, CF(2.3, 0.7, 0), burlap, M.Fabric)
	for _, x in { -1.6, 0, 1.4 } do
		Build.cylinder(m, 0.18, 1.6, CF(x, 0.75, 0), rgb(160, 140, 100), M.Fabric)
	end
	Build.stain(m, CF(0.4, 1.51, 0) * ANG(0, 0, 0), Vector2.new(1.2, 0.5), rng)
	return finish(m)
end

function Props.Chair(withRopes: boolean): Model
	local m = Instance.new("Model")
	m.Name = "Chair"
	local wood = rgb(84, 60, 40)
	P(m, Vector3.new(2.2, 0.25, 2.2), CF(0, 1.9, 0), wood, M.Wood).Name = "Seat"
	for _, x in { -0.95, 0.95 } do
		for _, z in { -0.95, 0.95 } do
			P(m, Vector3.new(0.22, 1.9, 0.22), CF(x, 0.95, z), wood, M.Wood)
		end
		P(m, Vector3.new(0.22, 2.6, 0.22), CF(x, 3.3, 0.95), wood, M.Wood)
	end
	P(m, Vector3.new(2.1, 0.4, 0.18), CF(0, 4.3, 0.95), wood, M.Wood)
	P(m, Vector3.new(2.1, 0.3, 0.18), CF(0, 3.3, 0.95), wood, M.Wood)
	if withRopes then
		local rope = rgb(170, 150, 110)
		for _, y in { 2.6, 3.4 } do
			local r = P(m, Vector3.new(2.3, 0.18, 0.18), CF(0, y, 1.08), rope, M.Fabric)
			r.Name = "Rope"
		end
		for _, x in { -0.95, 0.95 } do
			local r = P(m, Vector3.new(0.3, 0.16, 0.3), CF(x, 0.5, -0.95), rope, M.Fabric)
			r.Name = "Rope"
		end
	end
	return finish(m, if withRopes then "ChairRopes" else "Chair")
end

function Props.Cage(): Model
	local m = Instance.new("Model")
	m.Name = "Cage"
	local iron = rgb(70, 60, 52)
	P(m, Vector3.new(4.4, 0.3, 4.4), CF(0, 0.15, 0), iron, M.CorrodedMetal)
	P(m, Vector3.new(4.4, 0.3, 4.4), CF(0, 5.3, 0), iron, M.CorrodedMetal)
	for i = 0, 7 do
		local t = -2 + i * (4 / 7)
		for _, side in { -2, 2 } do
			Build.post(m, 5, 0.14, CF(t, 2.7, side), iron, M.CorrodedMetal)
			Build.post(m, 5, 0.14, CF(side, 2.7, t), iron, M.CorrodedMetal)
		end
	end
	return finish(m)
end

function Props.Barrel(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "Barrel"
	local colors = { rgb(70, 50, 34), rgb(60, 70, 60), rgb(110, 60, 40) }
	local c = colors[rng:NextInteger(1, #colors)]
	Build.post(m, 3.4, 2.4, CF(0, 1.7, 0), c, M.CorrodedMetal)
	for _, y in { 0.5, 1.7, 2.9 } do
		Build.post(m, 0.18, 2.48, CF(0, y, 0), rgb(50, 46, 42), M.Metal)
	end
	return finish(m)
end

function Props.Crate(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "Crate"
	local s = rng:NextNumber(2.4, 3.4)
	P(m, Vector3.new(s, s, s), CF(0, s / 2, 0), rgb(110, 82, 52), M.WoodPlanks)
	for _, y in { 0.1, s - 0.1 } do
		P(m, Vector3.new(s + 0.08, 0.25, 0.25), CF(0, y, -s / 2), rgb(80, 58, 38), M.Wood)
		P(m, Vector3.new(s + 0.08, 0.25, 0.25), CF(0, y, s / 2), rgb(80, 58, 38), M.Wood)
	end
	return finish(m)
end

function Props.Generator(): Model
	local m = Instance.new("Model")
	m.Name = "Generator"
	local frame = rgb(40, 40, 40)
	for _, x in { -1.8, 1.8 } do
		for _, z in { -1.1, 1.1 } do
			Build.post(m, 2.8, 0.18, CF(x, 1.4, z), frame, M.Metal)
		end
	end
	P(m, Vector3.new(3.6, 0.2, 2.2), CF(0, 2.8, 0), frame, M.Metal)
	P(m, Vector3.new(3.2, 1.4, 1.8), CF(0, 0.9, 0), rgb(60, 62, 60), M.CorrodedMetal).Name = "Engine"
	P(m, Vector3.new(2.6, 0.9, 1.6), CF(0, 2.15, 0), rgb(200, 160, 40), M.CorrodedMetal).Name = "Tank"
	P(m, Vector3.new(0.1, 0.9, 1.2), CF(1.75, 1.2, 0), rgb(30, 30, 30), M.Metal).Name = "Panel"
	local lamp = P(m, Vector3.new(0.12, 0.2, 0.2), CF(1.82, 1.5, 0.35), rgb(80, 10, 10), M.Neon)
	lamp.Name = "Lamp"
	Build.cylinder(m, 1.2, 0.4, CF(-1.4, 1.3, -1.2), rgb(80, 70, 60), M.CorrodedMetal)
	return finish(m)
end

function Props.Radio(): Model
	local m = Instance.new("Model")
	m.Name = "Radio"
	local olive = rgb(70, 76, 50)
	P(m, Vector3.new(2, 1.2, 1.1), CF(0, 0.6, 0), olive, M.Metal).Name = "Case"
	P(m, Vector3.new(1.8, 0.9, 0.05), CF(0, 0.6, -0.56), rgb(30, 32, 30), M.SmoothPlastic)
	for i = 0, 3 do
		Build.cylinder(m, 0.1, 0.18, CF(-0.6 + i * 0.4, 0.4, -0.6) * ANG(0, rad(90), 0), rgb(200, 200, 190), M.Metal)
	end
	local dial = P(m, Vector3.new(0.9, 0.3, 0.03), CF(0, 0.85, -0.6), rgb(255, 180, 80), M.Neon, { Transparency = 0.4 })
	dial.Name = "Dial"
	P(m, Vector3.new(0.3, 0.3, 0.8), CF(1.2, 0.2, -0.2), rgb(20, 20, 20), M.Plastic).Name = "Handset"
	Build.post(m, 3, 0.05, CF(-0.8, 2.6, 0.3), rgb(40, 40, 40), M.Metal)
	return finish(m)
end

function Props.Helicopter(): Model
	local m = Instance.new("Model")
	m.Name = "Helicopter"
	local white = rgb(225, 225, 220)
	local red = rgb(180, 30, 30)
	P(m, Vector3.new(7, 6, 14), CF(0, 5, 0), white, M.Metal).Name = "Body"
	Build.ball(m, 7, CF(0, 5, -6.5), white, M.Metal)
	P(m, Vector3.new(7.05, 1.2, 14), CF(0, 4, 0), red, M.Metal)
	P(m, Vector3.new(6, 3, 0.2), CF(0, 6, -9.6) * ANG(rad(-35), 0, 0), rgb(40, 60, 70), M.Glass, { Transparency = 0.3 })
	P(m, Vector3.new(1.6, 1.6, 16), CF(0, 6.5, 14), white, M.Metal).Name = "Tail"
	P(m, Vector3.new(0.4, 4, 2.4), CF(0.8, 8, 21.5), red, M.Metal)
	for _, x in { -3.6, 3.6 } do
		P(m, Vector3.new(0.4, 0.4, 13), CF(x, 0.3, 0), rgb(50, 50, 50), M.Metal)
		P(m, Vector3.new(0.3, 2, 0.3), CF(x, 1.3, -4), rgb(50, 50, 50), M.Metal)
		P(m, Vector3.new(0.3, 2, 0.3), CF(x, 1.3, 4), rgb(50, 50, 50), M.Metal)
	end
	Build.post(m, 1.6, 0.8, CF(0, 8.8, 0), rgb(50, 50, 50), M.Metal)
	local rotor = Instance.new("Model")
	rotor.Name = "Rotor"
	for i = 0, 3 do
		P(rotor, Vector3.new(1.2, 0.2, 19), CF(0, 9.7, 0) * ANG(0, i * math.pi / 2, 0) * CF(0, 0, 9.5), rgb(30, 30, 30), M.Metal)
	end
	rotor:SetAttribute("KeepVisible", true)
	rotor.Parent = m
	local spot = P(m, Vector3.new(1, 1, 1), CF(0, 1.8, -8), rgb(255, 250, 230), M.Neon)
	spot.Name = "Searchlight"
	local light = Instance.new("SpotLight")
	light.Angle = 40
	light.Range = 60
	light.Brightness = 6
	light.Face = Enum.NormalId.Bottom
	light.Shadows = true
	light.Parent = spot
	noCollide(m)
	return finish(m)
end

---------------------------------------------------------------- camp / outdoor

function Props.Tent(): Model
	local m = Instance.new("Model")
	m.Name = "Tent"
	local canvas = rgb(70, 80, 56)
	-- wedge's tall face is its +Z side; turn it towards the ridge in the middle
	Build.wedge(m, Vector3.new(7, 5, 3.2), CF(-1.6, 2.5, 0) * ANG(0, rad(90), 0), canvas, M.Fabric)
	Build.wedge(m, Vector3.new(7, 5, 3.2), CF(1.6, 2.5, 0) * ANG(0, rad(-90), 0), canvas, M.Fabric)
	P(m, Vector3.new(6.6, 0.1, 7.2), CF(0, 0.05, 0), rgb(50, 54, 42), M.Fabric)
	return finish(m)
end

function Props.Campfire(): Model
	local m = Instance.new("Model")
	m.Name = "Campfire"
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		Build.ball(m, 0.9, CF(math.cos(a) * 1.8, 0.3, math.sin(a) * 1.8), rgb(80, 78, 74), M.Slate)
	end
	for i = 0, 3 do
		Build.cylinder(m, 2.6, 0.4, CF(0, 0.4, 0) * ANG(0, i * math.pi / 4, rad(12)), rgb(50, 36, 26), M.Wood)
	end
	local core = P(m, Vector3.new(1, 0.4, 1), CF(0, 0.5, 0), rgb(255, 120, 40), M.Neon, { Transparency = 0.2 })
	core.Name = "Embers"
	Build.fire(core, 4, true)
	return finish(m)
end

function Props.Gravestone(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "Gravestone"
	local g = rng:NextInteger(80, 105)
	local tilt = ANG(rad(rng:NextNumber(-8, 8)), 0, rad(rng:NextNumber(-8, 8)))
	local cross = rng:NextNumber() < 0.35
	if cross then
		P(m, Vector3.new(0.4, 4, 0.4), CF(0, 1.6, 0) * tilt, rgb(70, 54, 40), M.Wood)
		P(m, Vector3.new(2.2, 0.4, 0.4), CF(0, 2.6, 0) * tilt, rgb(70, 54, 40), M.Wood)
	else
		P(m, Vector3.new(2, 2.6, 0.5), CF(0, 1.1, 0) * tilt, rgb(g, g, g), M.Slate)
		Build.cylinder(m, 0.5, 2, CF(0, 2.4, 0) * tilt * ANG(0, rad(90), 0), rgb(g, g, g), M.Slate)
	end
	P(m, Vector3.new(2.4, 0.3, 5), CF(0, 0.15, 2.6), rgb(52, 42, 32), M.Mud, { CanCollide = false })
	return finish(m, if cross then "GraveCross" else "Gravestone")
end

function Props.FenceSegment(): Model
	local m = Instance.new("Model")
	m.Name = "Fence"
	local wood = rgb(78, 62, 46)
	for _, x in { -4, 4 } do
		P(m, Vector3.new(0.4, 4.4, 0.4), CF(x, 2.2, 0), wood, M.Wood)
	end
	P(m, Vector3.new(8.4, 0.35, 0.15), CF(0, 3.4, 0), wood, M.WoodPlanks)
	P(m, Vector3.new(8.4, 0.35, 0.15), CF(0, 1.8, 0) * ANG(0, 0, rad(4)), wood, M.WoodPlanks)
	return finish(m)
end

function Props.Sign(text: string): Model
	local m = Instance.new("Model")
	m.Name = "Sign"
	P(m, Vector3.new(0.4, 6, 0.4), CF(0, 3, 0), rgb(70, 54, 40), M.Wood)
	local board = P(m, Vector3.new(4.4, 1.4, 0.2), CF(0, 5.2, -0.3) * ANG(0, 0, rad(-3)), rgb(98, 76, 52), M.WoodPlanks)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(440, 140)
		gui.LightInfluence = 1
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = text
		label.TextColor3 = rgb(230, 220, 200)
		label.Font = Enum.Font.SpecialElite
		label.TextScaled = true
		label.Parent = gui
	end
	return finish(m)
end

function Props.PowerPole(): Model
	local m = Instance.new("Model")
	m.Name = "PowerPole"
	Build.post(m, 26, 1, CF(0, 13, 0), rgb(60, 46, 34), M.Wood)
	P(m, Vector3.new(7, 0.5, 0.5), CF(0, 24, 0), rgb(60, 46, 34), M.Wood)
	for _, x in { -3, 0, 3 } do
		Build.post(m, 0.5, 0.35, CF(x, 24.5, 0), rgb(80, 120, 130), M.Glass)
	end
	return finish(m)
end

return Props

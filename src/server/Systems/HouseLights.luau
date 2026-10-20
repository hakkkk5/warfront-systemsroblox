--!strict
-- Ceiling lights and a wall switch in every room of the farmhouse. While the
-- hosts play nice the power is on and each switch works. At the reveal they
-- cut the power. The breaker box in the kitchen brings it back, but it's
-- loud: the family comes to see who did it, and sooner or later someone
-- pulls it again.
--
-- House-local coordinates as in House.luau (floor top y = 0, upper floor 13).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Build = require(script.Parent.Parent.World.Build)
local Cannibals = require(script.Parent.Cannibals)
local Interact = require(script.Parent.Interact)

local HouseLights = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local CF = CFrame.new
local U = 13

type Room = {
	name: string,
	light: PointLight,
	fixture: BasePart,
	toggle: BasePart,
	toggleBase: CFrame,
	face: number,
	on: boolean,
	prompt: ProximityPrompt?,
}

-- light: ceiling point. switch: on the wall beside the door, face = the
-- direction (+1 / -1 along X) the plate faces into the room.
local LAYOUT = {
	{ name = "Living room", light = Vector3.new(-18, 11.6, -12), switch = Vector3.new(-5.55, 4.5, -8), face = -1 },
	{ name = "Kitchen", light = Vector3.new(-18, 11.6, 12), switch = Vector3.new(-5.55, 4.5, 8), face = -1 },
	{ name = "Dining room", light = Vector3.new(18, 11.6, -12), switch = Vector3.new(5.55, 4.5, -8), face = 1 },
	{ name = "Hallway", light = Vector3.new(0, 11.6, -12), switch = Vector3.new(-4.45, 4.5, -20), face = 1 },
	{ name = "Landing", light = Vector3.new(0, U + 10.6, -4), switch = Vector3.new(4.45, U + 4.5, 6), face = -1 },
	{ name = "Master bedroom", light = Vector3.new(-18, U + 10.6, -12), switch = Vector3.new(-5.55, U + 4.5, -2), face = -1 },
	{ name = "Kid's room", light = Vector3.new(18, U + 10.6, -12), switch = Vector3.new(5.55, U + 4.5, -2), face = 1 },
	{ name = "Bathroom", light = Vector3.new(-18, U + 10.6, 12), switch = Vector3.new(-5.55, U + 4.5, 8), face = -1 },
	{ name = "Trophy room", light = Vector3.new(18, U + 10.6, 12), switch = Vector3.new(5.55, U + 4.5, 8), face = 1 },
}

local rooms: { Room } = {}
local powered = false
local cutToken = 0
local soundRemote = Net.event("Sound")

local function refresh(room: Room)
	local lit = powered and room.on
	room.light.Enabled = lit
	room.fixture.Material = if lit then M.Neon else M.SmoothPlastic
	room.fixture.Color = if lit then rgb(255, 222, 172) else rgb(70, 64, 56)
	room.toggle.CFrame = room.toggleBase * CF(0, if room.on then 0.1 else -0.1, 0)
	local prompt = room.prompt
	if prompt then
		prompt.ActionText = if room.on then "Turn off" else "Turn on"
	end
end

function HouseLights.powered(): boolean
	return powered
end

function HouseLights.setPower(on: boolean)
	powered = on
	cutToken += 1
	for _, room in rooms do
		refresh(room)
	end
end

-- A short stutter of every lit room.
function HouseLights.flicker()
	task.spawn(function()
		for _ = 1, 6 do
			for _, room in rooms do
				room.light.Enabled = powered and room.on and math.random() < 0.3
			end
			task.wait(0.06 + math.random() * 0.12)
		end
		for _, room in rooms do
			refresh(room)
		end
	end)
end

function HouseLights.build(origin: CFrame, parent: Instance, canRestore: () -> boolean)
	local folder = Build.folder(parent, "HouseLights")
	local function L(v: Vector3): CFrame
		return origin * CF(v)
	end

	for _, spec in LAYOUT do
		local fixture = Build.part(folder, Vector3.new(1.4, 0.25, 1.4), L(spec.light), rgb(70, 64, 56), M.SmoothPlastic, {
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 196, 140)
		light.Range = 22
		light.Brightness = 0.8
		light.Shadows = true
		light.Enabled = false
		light.Parent = fixture

		local plate = Build.part(folder, Vector3.new(0.1, 0.75, 0.5), L(spec.switch), rgb(226, 220, 204), M.SmoothPlastic, {
			CanCollide = false,
			CastShadow = false,
		})
		local toggleBase = plate.CFrame * CF(spec.face * 0.07, 0, 0)
		local toggle = Build.part(folder, Vector3.new(0.08, 0.22, 0.12), toggleBase, rgb(240, 236, 224), M.SmoothPlastic, {
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		local room: Room = {
			name = spec.name,
			light = light,
			fixture = fixture,
			toggle = toggle,
			toggleBase = toggleBase,
			face = spec.face,
			on = true,
			prompt = nil,
		}
		room.prompt = Interact.add(plate, {
			action = "Turn off",
			object = "Light switch",
			distance = 6,
			hold = 0,
			canUse = function()
				if not powered then
					soundRemote:FireAllClients("FlashlightClick", plate.Position)
					return false, "Click. Nothing. They cut the power."
				end
				return true
			end,
			onUse = function()
				room.on = not room.on
				soundRemote:FireAllClients("FlashlightClick", plate.Position)
				refresh(room)
			end,
		})
		table.insert(rooms, room)
		refresh(room)
	end

	-- the breaker box in the kitchen, on the wall by the living-room opening
	local breaker = Build.part(folder, Vector3.new(1.6, 2.2, 0.3), L(Vector3.new(-28, 5, 0.65)), rgb(78, 80, 76), M.DiamondPlate)
	Build.part(folder, Vector3.new(0.5, 0.25, 0.12), breaker.CFrame * CF(0, 0.5, 0.2), rgb(170, 30, 26), M.SmoothPlastic, {
		CanCollide = false,
		CanQuery = false,
	})
	Interact.add(breaker, {
		action = "Restore power",
		object = "Breaker box",
		distance = 6,
		hold = 1.2,
		canUse = function()
			if powered then
				return false, "The power's on."
			end
			if not canRestore() then
				return false, "It won't budge."
			end
			return true
		end,
		onUse = function(player)
			HouseLights.setPower(true)
			soundRemote:FireAllClients("Impact", breaker.Position)
			Cannibals.noise(breaker.Position, 120)
			Interact.notify(player, "The lights are back... and they heard that.", "warn")
			-- sooner or later one of them pulls it again
			local mine = cutToken
			task.delay(math.random(60, 95), function()
				if mine == cutToken and powered then
					HouseLights.setPower(false)
					soundRemote:FireAllClients("Impact", breaker.Position)
					for _, other in Players:GetPlayers() do
						Interact.notify(other, "The lights die again. Someone's at the breaker...", "warn")
					end
				end
			end)
		end,
	})
end

return HouseLights

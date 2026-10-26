--!strict
-- Extra hiding spots in the farmhouse: a wardrobe, cabinets, a meat locker,
-- under the beds and the butcher table, behind the sofa, the bath behind
-- its curtain and the coats in the trophy room. While a player hides their
-- body is made invisible, so the low and open spots don't give them away.
--
-- House-local coordinates as in House.luau: origin = centre of the ground
-- floor (floor top at y = 0), front door facing -Z, upper floor at y = 13.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local HouseLayout = require(ReplicatedStorage.Shared.HouseLayout)
local Hiding = require(script.Parent.Parent.Systems.Hiding)

local HidingSpots = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local U = 13
local FACE_EAST = ANG(0, rad(-90), 0) -- look +X
local FACE_WEST = ANG(0, rad(90), 0) -- look -X
local FACE_NORTH = CFrame.identity -- look -Z

-- Hidden players' bodies are invisible to everyone (restored when they leave).
local function watchBodies()
	local saved: { [Player]: { [Instance]: number } } = {}
	local function sync(player: Player)
		local character = player.Character
		if player:GetAttribute("Hidden") == true then
			if saved[player] or not character then
				return
			end
			local list: { [Instance]: number } = {}
			for _, d in character:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					list[d] = (d :: any).Transparency;
					(d :: any).Transparency = 1
				end
			end
			saved[player] = list
		else
			local list = saved[player]
			saved[player] = nil
			if list then
				for inst, v in list do
					if inst.Parent then
						(inst :: any).Transparency = v
					end
				end
			end
		end
	end
	local function track(player: Player)
		player:GetAttributeChangedSignal("Hidden"):Connect(function()
			sync(player)
		end)
		player.CharacterAdded:Connect(function()
			saved[player] = nil
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		saved[player] = nil
	end)
end

function HidingSpots.build(house: any, parent: Instance)
	local O: CFrame = house.origin
	local folder = Build.folder(parent, "HidingSpots")
	-- the spots are on the house plan; each group moves into the bigger house
	-- with the piece of furniture it is around (HouseLayout)
	local shift = Vector3.zero
	local function around(x: number, y: number, z: number)
		local v = Vector3.new(x, y, z)
		shift = HouseLayout.place(v) - v
	end
	local function L(x: number, y: number, z: number): CFrame
		return O * CF(Vector3.new(x, y, z) + shift)
	end
	local function box(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, extra: { [string]: any }?): Part
		return Build.part(folder, size, cf, color, material, extra)
	end
	-- invisible part that carries the prompt
	local function promptPart(size: Vector3, cf: CFrame, name: string): Part
		return box(size, cf, rgb(0, 0, 0), M.SmoothPlastic, {
			Name = name,
			Transparency = 1,
			CanCollide = false,
		})
	end
	local function spot(prompt: BasePart, inside: CFrame, exit: CFrame, label: string)
		Hiding.add(prompt, inside, exit, label)
	end
	-- a tall cupboard against a side wall with two door panels facing `dir` (+1 east, -1 west)
	local function cupboard(x: number, y: number, z: number, depth: number, color: Color3, dir: number, label: string)
		around(x, y, z)
		local body = box(Vector3.new(3, 9, depth), L(x, y + 4.5, z), color, M.Wood, { Name = label, CanCollide = false })
		for _, dz in { -depth / 4, depth / 4 } do
			box(Vector3.new(0.2, 8.6, depth / 2 - 0.15), L(x + dir * 1.55, y + 4.5, z + dz), color:Lerp(rgb(0, 0, 0), 0.15), M.WoodPlanks, {
				CanCollide = false,
			})
		end
		box(Vector3.new(0.1, 0.5, 0.15), L(x + dir * 1.7, y + 4.4, z - 0.2), rgb(160, 140, 90), M.Metal, { CanCollide = false })
		local facing = if dir > 0 then FACE_EAST else FACE_WEST
		spot(body, L(x + 0.1 * dir, y + 3, z) * facing, L(x + dir * 4.3, y + 3, z) * facing, label)
	end

	-------------------------------------------------------------- ground floor
	-- living room: a second wardrobe on the west wall
	cupboard(-30.4, 0, -15.5, 5, rgb(70, 50, 36), 1, "Wardrobe")

	-- living room: crouched behind the sofa, peeking over the backrest at the fire
	around(-19.8, 0, -6)
	local sofa = promptPart(Vector3.new(2, 3, 8), L(-16.4, 1.5, -6), "BehindSofa")
	spot(sofa, L(-15.8, 2.3, -6) * FACE_WEST, L(-14.5, 3, -6) * FACE_WEST, "Behind the sofa")

	-- dining room: linen cabinet on the east wall
	cupboard(30.4, 0, -6, 5, rgb(110, 86, 62), -1, "Linen cabinet")

	-- kitchen: in the cupboard under the counter
	around(-21, 1.5, 22.3)
	local counter = promptPart(Vector3.new(3.6, 3, 2.4), L(-21, 1.5, 22.3), "UnderCounter")
	box(Vector3.new(3.4, 2.6, 0.12), L(-21, 1.5, 21.05), rgb(86, 70, 54), M.WoodPlanks, { CanCollide = false })
	spot(counter, L(-21, 0.2, 23.2) * FACE_NORTH, L(-21, 3, 18.6) * FACE_NORTH, "Under the counter")

	-- slaughter room: a meat locker in the corner, and under the butcher table
	around(30.4, 4.5, 21.5)
	local locker = box(Vector3.new(3, 9, 4), L(30.4, 4.5, 21.5), rgb(120, 124, 128), M.DiamondPlate, { Name = "MeatLocker", CanCollide = false })
	box(Vector3.new(0.2, 8.6, 3.6), L(28.85, 4.5, 21.5), rgb(100, 104, 108), M.Metal, { CanCollide = false })
	box(Vector3.new(0.15, 1.2, 0.2), L(28.7, 4.4, 20.2), rgb(40, 40, 40), M.Metal, { CanCollide = false })
	spot(locker, L(30.3, 3, 21.5) * FACE_WEST, L(26.6, 3, 22) * FACE_WEST, "Meat locker")
	around(17, 1.3, 9)
	local underTable = promptPart(Vector3.new(7, 2.6, 4), L(17, 1.3, 9), "UnderTable")
	spot(underTable, L(17, -1.4, 10.6) * FACE_NORTH, L(17, 3, 13.4) * FACE_NORTH, "Under the table")

	-------------------------------------------------------------- upper floor
	-- master bedroom: under the bed, looking out toward the door
	around(-24, U + 1.2, -18.5)
	local masterBed = promptPart(Vector3.new(7.4, 2.4, 9.4), L(-24, U + 1.2, -18.5), "UnderBed")
	spot(masterBed, L(-22.6, U - 1.55, -18.5) * FACE_EAST, L(-18.6, U + 3, -18.5) * FACE_EAST, "Under the bed")

	-- kid's room: under the little bed
	around(27.5, U + 1, -10)
	local kidBed = promptPart(Vector3.new(4.4, 2, 7.4), L(27.5, U + 1, -10), "UnderKidBed")
	spot(kidBed, L(27.4, U - 1.6, -10) * FACE_WEST, L(23.6, U + 3, -10) * FACE_WEST, "Under the bed")

	-- bathroom: in the tub behind a stained shower curtain
	around(-26, U + 1, 21.6)
	box(Vector3.new(8.2, 0.12, 0.12), L(-26, U + 8, 19.7), rgb(150, 150, 150), M.Metal, { CanCollide = false })
	local curtain = box(Vector3.new(8, 6.4, 0.08), L(-26, U + 4.75, 19.7), rgb(196, 186, 160), M.Fabric, {
		Name = "ShowerCurtain",
		Transparency = 0.25,
		CanCollide = false,
	})
	box(Vector3.new(1.6, 1.2, 0.02), L(-24.5, U + 3.2, 19.64), rgb(110, 20, 16), M.SmoothPlastic, { CanCollide = false, Transparency = 0.3 })
	spot(curtain, L(-26, U + 1.8, 21.8) * FACE_NORTH, L(-26, U + 3, 17.4) * FACE_NORTH, "Bathtub")

	-- trophy room: behind the coats on the rack
	around(9, U + 4.6, 12)
	local coats = promptPart(Vector3.new(1.6, 4, 7), L(8.2, U + 4.6, 12), "BehindCoats")
	spot(coats, L(7, U + 2.8, 12) * FACE_EAST, L(11.8, U + 3, 12) * FACE_EAST, "Behind the coats")

	watchBodies()
end

return HidingSpots

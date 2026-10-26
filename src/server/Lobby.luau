--!strict
-- The lobby: a roadside gas station at night, the last stop before Hollow
-- Road. Players gather in the beds of three pickup trucks; each truck is a
-- party of up to four (the queue: see "parties" below). The first one in is
-- the host and picks the difficulty. When the countdown runs out, everyone
-- is ready or the host starts early, the party is teleported into a fresh
-- reserved server of this place, carrying the difficulty in the teleport
-- data. A player can also drive out alone.
--
-- Lobby.run() is called by Main before the world is built. In a lobby
-- server it never returns. In a game server it publishes the difficulty and
-- returns at once. In Studio, where teleports don't work, the lobby is torn
-- down when a party leaves and run() returns so this server runs the game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Items = require(ReplicatedStorage.Shared.Items)
local Session = require(ReplicatedStorage.Shared.Session)
local StoreCatalog = require(ReplicatedStorage.Shared.StoreCatalog)
local Trophies = require(ReplicatedStorage.Shared.Trophies)
local Util = require(ReplicatedStorage.Shared.Util)
local Build = require(script.Parent.World.Build)
local LightingSetup = require(script.Parent.World.Lighting)
local Props = require(script.Parent.World.Props)
local AssetService = require(script.Parent.Systems.AssetService)
local Cannibals = require(script.Parent.Systems.Cannibals)
local R6Characters = require(script.Parent.Systems.R6Characters)
local Profiles = require(script.Parent.Systems.Profiles)
local Leaderboards = require(script.Parent.Systems.Leaderboards)
local Matchmaking = require(script.Parent.Systems.Matchmaking)
local Rejoin = require(script.Parent.Systems.Rejoin)

local Lobby = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local ORIGIN = CF(0, 600, 0) -- floats high above the map
local MAX_PARTY = 4
local WAIT = 40 -- a truck waits this long after its first rider climbs in
local JOIN_GRACE = 12 -- and never less than this after anyone new does
local READY_GO = 5 -- everyone aboard ready: off in this long
local QUICK_START = 3 -- the host's Start now
local KICK_BAN = 90 -- a kicked player can't climb back into that truck for this long
local TRUCKS = 3

type Party = {
	index: number,
	zone: BasePart,
	exit: CFrame, -- behind the tailgate, facing the truck
	members: { Player },
	ready: { [Player]: boolean },
	host: Player?,
	difficulty: string,
	countdown: number?,
	leaving: boolean,
	locked: boolean, -- friends of the host only
	banned: { [number]: number }, -- kicked: UserId -> os.clock() they may return
	label: TextLabel,
}

local parties: { Party } = {}
local connections: { RBXScriptConnection } = {}
local retries: { [Player]: number } = {} -- failed teleports, by player
local departing: { [Player]: string } = {} -- off without a truck (alone or matched): their difficulty
local spawnCF = ORIGIN
local studioStart: string? = nil
local stateRemote: RemoteEvent
local actionRemote: RemoteEvent
local noticeRemote: RemoteEvent

---------------------------------------------------------------- the set

local function L(x: number, y: number, z: number): CFrame
	return ORIGIN * CF(x, y, z)
end

local function sign(parent: Instance, text: string, size: Vector3, cf: CFrame, color: Color3, glow: boolean): Part
	local board = Build.part(parent, size, cf, rgb(24, 22, 20), M.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(size.X * 50, size.Y * 50)
	gui.LightInfluence = if glow then 0 else 1
	gui.Brightness = if glow then 2 else 1
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.SpecialElite
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = gui
	return board
end

-- things to poke at while the party gathers (handled on the client; the
-- bell on the billboard also on the server)
local function prompt(part: BasePart, actionText: string, objectText: string, action: string): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = actionText
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Custom
	p:SetAttribute("LobbyAction", action)
	p.Parent = part
	return p
end

-- A glowing tube (Neon parts stay out of the Blender bake).
local function neon(parent: Instance, size: Vector3, cf: CFrame, color: Color3, range: number?): Part
	local p = Build.part(parent, size, cf, color, M.Neon, { CanCollide = false, CastShadow = false })
	if range then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = 1.3
		light.Parent = p
	end
	return p
end

-- A lamp post with a glowing head.
local function lamp(parent: Instance, x: number, z: number)
	Build.post(parent, 12, 0.4, L(x, 6, z), rgb(60, 60, 58), M.Metal)
	local head = Build.part(parent, Vector3.new(1.6, 0.5, 1.6), L(x, 12.2, z), rgb(255, 220, 160), M.Neon, { CanCollide = false })
	local light = Instance.new("PointLight")
	light.Range = 34
	light.Brightness = 1.8
	light.Color = rgb(255, 214, 160)
	light.Shadows = true
	light.Parent = head
end

-- Leaderboard boards (filled by the server, Leaderboards.luau) and the bell
-- at the top of the billboard climb.
local boards: { [string]: TextLabel } = {}
local bellPrompt: ProximityPrompt? = nil

local function board(parent: Instance, title: string, cf: CFrame): TextLabel
	local part = Build.part(parent, Vector3.new(6, 8, 0.3), cf, rgb(22, 20, 18), M.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(300, 400)
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Parent = part
	local head = Instance.new("TextLabel")
	head.Size = UDim2.new(1, 0, 0, 64)
	head.BackgroundColor3 = rgb(120, 22, 18)
	head.Font = Enum.Font.SpecialElite
	head.TextScaled = true
	head.TextColor3 = rgb(240, 226, 196)
	head.Text = title
	head.Parent = gui
	local list = Instance.new("TextLabel")
	list.Position = UDim2.fromOffset(14, 74)
	list.Size = UDim2.new(1, -28, 1, -84)
	list.BackgroundTransparency = 1
	list.Font = Enum.Font.SpecialElite
	list.TextSize = 24
	list.TextXAlignment = Enum.TextXAlignment.Left
	list.TextYAlignment = Enum.TextYAlignment.Top
	list.TextColor3 = rgb(226, 214, 190)
	list.RichText = true
	list.Text = "…"
	list.Parent = gui
	return list
end

local function buildSet(parent: Instance): { Party }
	local rng = Util.rng(4242)
	-- everything that stands still; its plain parts are shown as the Blender
	-- remodel LobbyParts (Build.bake, at the end)
	local set = Build.model(parent, "Set")
	local function keepPlain(p: BasePart)
		p:SetAttribute("KeepVisible", true)
	end
	local steel = rgb(70, 72, 76)
	local cream = rgb(240, 226, 196)
	local pink = rgb(255, 70, 150)
	local cyan = rgb(80, 220, 255)
	local amber = rgb(255, 196, 90)

	------------------------------------------------------------ ground, lot, highway
	keepPlain(Build.part(set, Vector3.new(460, 4, 460), L(40, -2, 20), rgb(34, 40, 30), M.Grass))
	keepPlain(Build.part(set, Vector3.new(176, 0.3, 80), L(38, 0.15, 2), rgb(36, 36, 38), M.Asphalt))
	keepPlain(Build.part(set, Vector3.new(460, 0.25, 24), L(40, 0.13, -50), rgb(30, 30, 32), M.Asphalt))
	-- the gravel yard behind the buildings, where the billboard climb is
	keepPlain(Build.part(set, Vector3.new(120, 0.2, 52), L(30, 0.1, 68), rgb(74, 70, 64), M.Pebble))
	for x = -180, 260, 12 do
		Build.part(set, Vector3.new(6, 0.05, 0.4), L(x, 0.28, -50), rgb(190, 170, 90), M.SmoothPlastic, { CanCollide = false })
	end
	for i = 1, TRUCKS + 1 do
		Build.part(set, Vector3.new(0.4, 0.05, 16), L(18 + (i - 1) * 13, 0.32, -6), rgb(200, 200, 190), M.SmoothPlastic, { CanCollide = false })
	end
	for i = 0, 7 do
		Build.part(set, Vector3.new(0.4, 0.05, 12), L(64 + i * 8, 0.32, 0), rgb(200, 200, 190), M.SmoothPlastic, { CanCollide = false })
	end

	------------------------------------------------------------ the gas station
	-- The canopy, pumps, island and store are stand-ins for the Blender gas
	-- station (build_buildings.py GasStationExterior): clients hide them and
	-- show the model; they keep the collisions.
	local shell = Build.standIn(set, "GasStationExterior")
	for _, x in { -26, -2 } do
		for _, z in { -16, 0 } do
			Build.post(shell, 9.4, 0.9, L(x, 4.7, z), rgb(200, 196, 186), M.Metal)
		end
	end
	Build.part(shell, Vector3.new(34, 1.2, 24), L(-14, 9.9, -8), rgb(220, 216, 206), M.SmoothPlastic)
	Build.part(shell, Vector3.new(34.4, 0.6, 24.4), L(-14, 9.1, -8), rgb(170, 30, 26), M.SmoothPlastic)
	for i, x in { -24, -14, -4 } do
		local strip = neon(set, Vector3.new(6, 0.2, 0.6), L(x, 9.25, -8), rgb(225, 240, 255))
		local light = Instance.new("PointLight")
		light.Range = 26
		light.Brightness = 1.6
		light.Color = rgb(200, 225, 255)
		light.Shadows = true
		light.Parent = strip
		if i == 2 then
			Build.tag(strip, "FlickerLight")
		end
	end
	Build.part(shell, Vector3.new(26, 0.6, 5), L(-14, 0.3, -8), rgb(120, 116, 108), M.Concrete)
	for _, x in { -20, -8 } do
		Build.part(shell, Vector3.new(2.6, 5.2, 1.8), L(x, 3.2, -8), rgb(170, 30, 26), M.Metal)
		Build.part(shell, Vector3.new(2, 1.4, 0.1), L(x, 4.2, -8.95), rgb(20, 24, 22), M.Glass, { CanCollide = false })
	end
	sign(set, "PINECREST GAS", Vector3.new(16, 2.2, 0.4), L(-14, 11.6, -20.3), amber, true)
	-- the store: lit windows, an OPEN sign, a payphone
	Build.part(shell, Vector3.new(34, 12, 18), L(-14, 6, 26), rgb(120, 104, 86), M.WoodPlanks)
	Build.part(shell, Vector3.new(36, 1, 20), L(-14, 12.5, 26), rgb(60, 48, 40), M.Slate)
	Build.markStandIn(shell, ORIGIN)
	for _, x in { -24, -4 } do
		local window = Build.part(set, Vector3.new(8, 4.4, 0.3), L(x, 5, 16.9), rgb(255, 214, 150), M.Neon, { Transparency = 0.35 })
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Front
		light.Range = 18
		light.Brightness = 1.4
		light.Color = rgb(255, 200, 140)
		light.Parent = window
	end
	Build.part(set, Vector3.new(4, 8, 0.4), L(-14, 4, 16.9), rgb(50, 40, 32), M.Wood)
	sign(set, "OPEN 24H", Vector3.new(5, 1.4, 0.2), L(-24, 8.6, 16.7), rgb(255, 70, 60), true)
	sign(set, "LAST STOP BEFORE HOLLOW ROAD", Vector3.new(30, 2.4, 0.4), L(-14, 13.8, 16.6), cream, false)
	local payphone = Build.part(set, Vector3.new(1.6, 3, 1), L(4.5, 4, 17.6), rgb(60, 70, 64), M.Metal)
	Build.part(set, Vector3.new(0.4, 1.2, 0.4), L(4.1, 4.4, 16.95), rgb(20, 20, 20), M.SmoothPlastic, { CanCollide = false })
	prompt(payphone, "Answer", "Ringing payphone", "payphone")
	local vending = Build.part(set, Vector3.new(3.4, 7, 2.4), L(-33.6, 3.5, 14.8), rgb(150, 26, 24), M.Metal)
	local vendGlow = neon(set, Vector3.new(2.6, 4.2, 0.1), L(-33.6, 4.2, 13.55), rgb(255, 236, 200), 10)
	vendGlow.Transparency = 0.2
	Build.tag(vendGlow, "FlickerLight")
	prompt(vending, "Buy a soda", "Vending machine", "vending")
	for _, x in { -27, -1 } do
		local porch = Build.part(set, Vector3.new(1, 0.6, 0.6), L(x, 9.5, 16.4), rgb(255, 220, 170), M.Neon, { CanCollide = false })
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = 110
		light.Range = 30
		light.Brightness = 2
		light.Color = rgb(255, 205, 150)
		light.Parent = porch
		porch.CFrame = porch.CFrame * ANG(rad(-60), 0, 0)
	end

	-- the rules of the road, readable from the spawn
	for _, z in { 5, 11 } do
		Build.post(set, 7, 0.3, L(0, 3.5, z), rgb(70, 56, 44), M.Wood)
	end
	local howto = sign(set, table.concat({
		"HOW TO SURVIVE",
		"WASD move · Shift run · C crouch · F flashlight",
		"E use · Tab bag · H hint",
		"Stay quiet. Stay dark. Hide when they see you.",
	}, "\n"), Vector3.new(7.4, 4.4, 0.3), L(0, 5.6, 8) * ANG(0, rad(90), 0), cream, false)
	prompt(howto, "Read", "How to play", "howto")
	for _, z in { -1, 5 } do
		Build.post(set, 7, 0.3, L(-31, 3.5, z), rgb(70, 56, 44), M.Wood)
	end
	local missing = Build.part(set, Vector3.new(7, 4.2, 0.3), L(-31, 5.6, 2) * ANG(0, rad(-90), 0), rgb(150, 112, 70), M.Fabric)
	for i, who in { "DALE\nWHITCOMB\n2019", "THE\nHARLANS\n2021", "MARISOL\nVEGA\n2022", "DEP.\nBRANDT\n2023" } do
		local poster = sign(set, "MISSING\n" .. who, Vector3.new(1.3, 1.7, 0.05), missing.CFrame * CF(-2.4 + (i - 1) * 1.6, 0.6 - ((i - 1) % 2) * 1.2, -0.18), rgb(40, 30, 28), false)
		poster.Color = rgb(230, 224, 205)
		poster.CanCollide = false
	end
	sign(set, "MISSING", Vector3.new(5, 0.9, 0.1), missing.CFrame * CF(0, 1.75, -0.2), rgb(170, 30, 26), false).CanCollide = false
	prompt(missing, "Read", "Missing persons", "missing")

	------------------------------------------------------------ the diner
	-- A chrome railcar diner you can walk into: booths along the windows, a
	-- counter with stools, a jukebox, the kitchen through a pass window, and
	-- your trophy wall on the west wall. The parts in the stand-in are the
	-- collisions of the Blender model (tools/blender/build_lobby.py).
	local diner = Build.standIn(set, "TruckStopDiner")
	local chrome = rgb(196, 198, 202)
	local red = rgb(170, 30, 36)
	Build.part(diner, Vector3.new(40, 0.5, 22), L(34, 0.25, 29), rgb(230, 228, 220), M.SmoothPlastic)
	local booths = { 19.5, 26.5, 41.5, 48.5 }
	local openings: { Build.Opening } = { { at = 34, width = 4.4, bottom = 0, top = 8 } }
	for _, x in booths do
		table.insert(openings, { at = x, width = 6, bottom = 3.2, top = 8.6 })
	end
	Build.wall(diner, ORIGIN, Vector2.new(14, 18.3), Vector2.new(54, 18.3), 0.5, 11, 0.6, openings, chrome, M.Metal)
	Build.wall(diner, ORIGIN, Vector2.new(14, 39.7), Vector2.new(54, 39.7), 0.5, 11, 0.6, {}, chrome, M.Metal)
	Build.wall(diner, ORIGIN, Vector2.new(14.3, 18), Vector2.new(14.3, 40), 0.5, 11, 0.6, {}, chrome, M.Metal)
	Build.wall(diner, ORIGIN, Vector2.new(53.7, 18), Vector2.new(53.7, 40), 0.5, 11, 0.6, {}, chrome, M.Metal)
	-- the kitchen wall: the pass window over the counter and a door at the end
	Build.wall(diner, ORIGIN, Vector2.new(14.6, 35.4), Vector2.new(53.4, 35.4), 0.5, 11, 0.4, {
		{ at = 34, width = 12, bottom = 4.5, top = 7.5 },
		{ at = 50, width = 3.4, bottom = 0, top = 7.5 },
	}, rgb(220, 216, 206), M.SmoothPlastic)
	for _, x in booths do
		Build.part(diner, Vector3.new(6, 5.4, 0.2), L(x, 6.4, 18.3), rgb(60, 70, 76), M.Glass, { Transparency = 0.6 })
		-- a booth: table, two benches with high backs
		Build.part(diner, Vector3.new(3.6, 0.3, 2.4), L(x, 3, 21.4), red, M.SmoothPlastic)
		Build.post(diner, 2.6, 0.4, L(x, 1.6, 21.4), chrome, M.Metal)
		for _, z in { 19.6, 23.3 } do
			Build.part(diner, Vector3.new(5, 1.4, 1.6), L(x, 1.2, z), red, M.Fabric)
		end
		Build.part(diner, Vector3.new(5, 2.8, 0.5), L(x, 3.3, 24.35), red, M.Fabric)
	end
	Build.part(diner, Vector3.new(28, 3.4, 2), L(34, 2.2, 33), red, M.SmoothPlastic) -- the counter
	for x = 22, 46, 3 do
		Build.post(diner, 2.6, 1.2, L(x, 1.8, 30.6), chrome, M.Metal) -- stools
	end
	local jukebox = Build.part(diner, Vector3.new(1.8, 5.4, 2.6), L(52.4, 3.2, 28), rgb(120, 40, 30), M.Wood)
	Build.part(diner, Vector3.new(41, 1, 23), L(34, 12, 29), chrome, M.Metal) -- roof
	Build.markStandIn(diner, ORIGIN)
	prompt(jukebox, "Play a song", "Jukebox", "jukebox")
	-- neon: along the roof, under the windows, the sign on the roof
	neon(set, Vector3.new(40.4, 0.3, 0.3), L(34, 11.8, 17.85), cyan, 14)
	neon(set, Vector3.new(40.4, 0.3, 0.3), L(34, 3.3, 17.85), pink, 10)
	sign(set, "DINER", Vector3.new(14, 3.4, 0.5), L(34, 14.8, 18.6), pink, true)
	neon(set, Vector3.new(14.6, 0.25, 0.25), L(34, 16.65, 18.3), cyan)
	neon(set, Vector3.new(14.6, 0.25, 0.25), L(34, 12.95, 18.3), cyan)
	sign(set, "EAT", Vector3.new(3, 1.6, 0.3), L(34, 9.7, 17.95), amber, true)
	-- pendant lamps inside
	for x = 20, 48, 7 do
		for _, z in { 22, 30 } do
			local bulb = neon(set, Vector3.new(0.8, 0.5, 0.8), L(x, 9.6, z), rgb(255, 226, 180))
			local light = Instance.new("PointLight")
			light.Range = 12
			light.Brightness = 1.1
			light.Color = rgb(255, 220, 170)
			light.Parent = bulb
			Build.part(set, Vector3.new(0.08, 1.8, 0.08), L(x, 10.8, z), rgb(30, 30, 30), M.SmoothPlastic, { CanCollide = false })
		end
	end
	-- the trophy wall: one frame per achievement and polaroid (the client
	-- shows yours: LobbyTrophyWall)
	sign(set, "WALL OF FAME", Vector3.new(8, 1.2, 0.2), L(14.75, 10.3, 27) * ANG(0, rad(-90), 0), amber, true)
	local frames: { { kind: string, id: string } } = {}
	for _, a in Trophies.achievementList() do
		table.insert(frames, { kind = "Ach", id = a.id })
	end
	for _, p in Trophies.polaroidList() do
		table.insert(frames, { kind = "Pol", id = p.id })
	end
	for i, f in frames do
		local col, row = (i - 1) % 9, (i - 1) // 9
		local frame = Build.part(set, Vector3.new(1.6, 1.6, 0.15), L(14.75, 8.8 - row * 1.8, 19.6 + col * 1.85) * ANG(0, rad(-90), 0), rgb(40, 30, 24), M.Wood, {
			CanCollide = false,
			Name = "TrophyFrame",
		})
		frame:SetAttribute("TrophyKind", f.kind)
		frame:SetAttribute("TrophyId", f.id)
		Build.tag(frame, "TrophyFrame")
	end

	------------------------------------------------------------ the motel
	-- six rooms and an office under one long roof, a walkway out front
	local motel = Build.standIn(set, "TruckStopMotel")
	local MX0, MX1 = 64, 122
	local wallColor = rgb(170, 150, 120)
	Build.part(motel, Vector3.new(MX1 - MX0, 0.5, 20), L((MX0 + MX1) / 2, 0.25, 20), rgb(120, 116, 108), M.Concrete)
	local mOpen: { Build.Opening } = {}
	local doors: { number } = {}
	for i = 0, 5 do
		table.insert(doors, MX0 + 2.5 + i * 8)
		table.insert(mOpen, { at = MX0 + 2.5 + i * 8, width = 3.2, bottom = 0, top = 7 })
		table.insert(mOpen, { at = MX0 + 5.8 + i * 8, width = 3, bottom = 2.8, top = 6.2 })
	end
	table.insert(mOpen, { at = 115, width = 3.4, bottom = 0, top = 7.4 })
	table.insert(mOpen, { at = 119.2, width = 4, bottom = 2.6, top = 7 })
	Build.wall(motel, ORIGIN, Vector2.new(MX0, 14.3), Vector2.new(MX1, 14.3), 0.5, 9.5, 0.6, mOpen, wallColor, M.Plaster)
	Build.wall(motel, ORIGIN, Vector2.new(MX0, 29.7), Vector2.new(MX1, 29.7), 0.5, 9.5, 0.6, {}, wallColor, M.Plaster)
	Build.wall(motel, ORIGIN, Vector2.new(MX0 + 0.3, 14), Vector2.new(MX0 + 0.3, 30), 0.5, 9.5, 0.6, {}, wallColor, M.Plaster)
	Build.wall(motel, ORIGIN, Vector2.new(MX1 - 0.3, 14), Vector2.new(MX1 - 0.3, 30), 0.5, 9.5, 0.6, {}, wallColor, M.Plaster)
	local roomDoors: { BasePart } = {}
	for i, x in doors do
		table.insert(roomDoors, Build.part(motel, Vector3.new(3.2, 7, 0.3), L(x, 4, 14.3), rgb(40, 110, 110), M.Wood))
		Build.part(motel, Vector3.new(3, 3.4, 0.2), L(x + 3.3, 4.7, 14.3), rgb(60, 70, 76), M.Glass, { Transparency = 0.5 })
		sign(set, tostring(i), Vector3.new(1, 0.8, 0.1), L(x, 8.1, 13.95), rgb(230, 190, 90), false).CanCollide = false
		local bulb = neon(set, Vector3.new(0.5, 0.5, 0.3), L(x + 1.6, 8.3, 13.9), rgb(255, 214, 150), 8)
		if i == 4 then
			Build.tag(bulb, "FlickerLight")
		end
	end
	Build.part(motel, Vector3.new(3.4, 7.4, 0.3), L(115, 4.2, 14.3), rgb(40, 110, 110), M.Wood)
	Build.part(motel, Vector3.new(4, 4.4, 0.2), L(119.2, 5.3, 14.3), rgb(255, 220, 170), M.Glass, { Transparency = 0.4 })
	Build.part(motel, Vector3.new(MX1 - MX0 + 2, 0.8, 22), L((MX0 + MX1) / 2, 10.4, 19.5), rgb(80, 60, 50), M.Wood) -- roof
	for x = MX0 + 1, MX1 - 1, 8 do
		Build.post(motel, 9.6, 0.5, L(x, 5.3, 10.3), rgb(230, 226, 214), M.Wood)
	end
	Build.markStandIn(motel, ORIGIN)
	prompt(roomDoors[4], "Knock", "Room 4", "knock")
	sign(set, "MOTEL", Vector3.new(14, 3.6, 0.5), L(93, 13.2, 9.8), cyan, true)
	sign(set, "VACANCY", Vector3.new(8, 1.6, 0.4), L(108, 13, 9.8), pink, true)
	sign(set, "OFFICE", Vector3.new(5, 1.2, 0.2), L(117, 8.5, 13.95), amber, true).CanCollide = false
	local ice = Build.part(set, Vector3.new(3, 5, 2.4), L(61.5, 2.5, 13), rgb(200, 205, 210), M.Metal)
	sign(set, "ICE", Vector3.new(2.4, 1, 0.1), ice.CFrame * CF(0, 1.4, -1.25), cyan, true).CanCollide = false

	------------------------------------------------------------ the roadside sign
	local pylon = Build.standIn(set, "TruckStopPylon")
	local PX, PZ = 74, -30
	for _, dx in { -6, 6 } do
		Build.part(pylon, Vector3.new(1.2, 30, 1.2), L(PX + dx, 15, PZ), steel, M.Metal)
	end
	Build.part(pylon, Vector3.new(18, 9, 1.8), L(PX, 25.5, PZ), rgb(30, 30, 34), M.Metal)
	Build.part(pylon, Vector3.new(16, 3.4, 1.2), L(PX, 18.6, PZ), rgb(30, 30, 34), M.Metal)
	Build.markStandIn(pylon, ORIGIN)
	for _, face in { -1, 1 } do
		local turn = if face < 0 then CFrame.identity else ANG(0, math.pi, 0)
		sign(set, "HOLLOW ROAD\nTRUCK STOP", Vector3.new(16.4, 7.4, 0.3), L(PX, 25.5, PZ + face * 1.1) * turn, amber, true).CanCollide = false
		sign(set, "EAT · GAS · MOTEL", Vector3.new(15, 2.6, 0.3), L(PX, 18.6, PZ + face * 0.75) * turn, cream, true).CanCollide = false
		for _, y in { 21.05, 29.95 } do
			neon(set, Vector3.new(18.2, 0.25, 0.25), L(PX, y, PZ + face * 0.95), pink)
		end
	end

	------------------------------------------------------------ leaderboards
	-- three boards under a little roof, facing the spawn
	local KX, KZ = 9, -17
	for _, dz in { -10, 10 } do
		Build.post(set, 11, 0.5, L(KX, 5.5, KZ + dz), rgb(70, 56, 44), M.Wood)
	end
	Build.part(set, Vector3.new(2.6, 0.4, 22), L(KX, 11.2, KZ), rgb(60, 46, 36), M.WoodPlanks)
	for i, stat in { { "Escapes", "MOST ESCAPES" }, { "Teeth", "MOST TEETH" }, { "Trophies", "MOST TROPHIES" } } do
		boards[stat[1]] = board(set, stat[2], L(KX, 6, KZ + 6.6 - (i - 1) * 6.6) * ANG(0, rad(90), 0))
	end
	neon(set, Vector3.new(0.25, 0.25, 21), L(KX - 0.2, 10.8, KZ), amber, 12)

	------------------------------------------------------------ the billboard climb
	-- behind the buildings: tyres, drums, a flatbed with crates, stacked
	-- containers, a scaffold and a ladder up to the billboard's catwalk, and a
	-- bell at the end of it (a trophy the first time)
	sign(set, "CLIMB THE BILLBOARD  ↑", Vector3.new(9, 1.4, 0.2), L(8.5, 3.4, 42), cream, false).CanCollide = false
	Build.post(set, 3, 0.3, L(8.5, 1.5, 42.2), rgb(70, 56, 44), M.Wood)
	for _, t in { { -6, 48, 2 }, { -2, 51, 3 } } do
		for k = 0, t[3] - 1 do
			Build.post(set, 1.1, 3, L(t[1], 0.55 + k * 1.1, t[2]), rgb(24, 24, 24), M.Rubber)
		end
	end
	Build.post(set, 3.4, 2.4, L(2.5, 1.7, 54), rgb(110, 60, 40), M.CorrodedMetal)
	Build.post(set, 3.4, 2.4, L(6.5, 1.7, 56), rgb(60, 70, 60), M.CorrodedMetal)
	Build.part(set, Vector3.new(3, 0.8, 3), L(10.5, 0.4, 58.5), rgb(110, 84, 58), M.WoodPlanks)
	Build.post(set, 3.4, 2.4, L(10.5, 2.5, 58.5), rgb(70, 50, 34), M.CorrodedMetal)
	-- the flatbed
	Build.part(set, Vector3.new(30, 0.6, 8), L(28, 4.2, 60), rgb(90, 70, 52), M.WoodPlanks)
	for _, z in { 56.6, 63.4 } do
		Build.part(set, Vector3.new(30, 0.8, 0.6), L(28, 3.5, z), steel, M.Metal)
	end
	for _, x in { 37.5, 40.5 } do
		for _, z in { 56.4, 63.6 } do
			Build.cylinder(set, 1, 3, L(x, 1.5, z) * ANG(0, rad(90), 0), rgb(22, 22, 22), M.Rubber)
		end
	end
	for _, z in { 57.5, 62.5 } do
		Build.part(set, Vector3.new(0.5, 3.6, 0.5), L(15, 1.8, z), steel, M.Metal)
	end
	Build.part(set, Vector3.new(4, 3, 4), L(30, 6, 60), rgb(110, 82, 52), M.WoodPlanks)
	Build.part(set, Vector3.new(4, 6, 4), L(36, 7.5, 61), rgb(96, 72, 46), M.WoodPlanks)
	-- the containers: A on the ground, C beside it with B stacked on top
	local function container(cx: number, cy: number, cz: number, color: Color3)
		Build.part(set, Vector3.new(20, 8.5, 8), L(cx, cy, cz), color, M.CorrodedMetal)
		for k = 0, 15 do
			for _, s in { -1, 1 } do
				Build.part(set, Vector3.new(0.3, 8, 0.2), L(cx - 9 + k * 1.2, cy, cz + s * 4.05), color:Lerp(rgb(0, 0, 0), 0.2), M.CorrodedMetal, { CanCollide = false })
			end
		end
	end
	container(54, 4.25, 58, rgb(150, 60, 40))
	container(66, 4.25, 66, rgb(40, 90, 110))
	container(66, 12.75, 66, rgb(170, 130, 40))
	Build.part(set, Vector3.new(4, 3, 4), L(52, 10, 58), rgb(110, 82, 52), M.WoodPlanks)
	Build.part(set, Vector3.new(4, 6, 4), L(58, 11.5, 60), rgb(96, 72, 46), M.WoodPlanks)
	-- the billboard: legs, the face, a catwalk, a scaffold and a ladder
	local billboard = Build.standIn(set, "TruckStopBillboard")
	local BX, BZ = 60, 79
	for _, dx in { -14, 0, 14 } do
		Build.part(billboard, Vector3.new(1.2, 28, 1.2), L(BX + dx, 14, BZ + 0.8), steel, M.Metal)
	end
	Build.part(billboard, Vector3.new(40, 16, 1), L(BX, 36, BZ), rgb(30, 30, 30), M.WoodPlanks)
	Build.part(billboard, Vector3.new(40, 0.4, 2.6), L(BX, 27, BZ - 1.8), steel, M.DiamondPlate)
	Build.part(billboard, Vector3.new(40, 0.25, 0.25), L(BX, 30.2, BZ - 3), steel, M.Metal)
	Build.part(billboard, Vector3.new(8, 0.6, 4), L(60, 19.7, 74), steel, M.DiamondPlate)
	for _, dx in { -3.6, 3.6 } do
		for _, dz in { -1.6, 1.6 } do
			Build.part(billboard, Vector3.new(0.4, 19.4, 0.4), L(60 + dx, 9.7, 74 + dz), steel, M.Metal)
		end
	end
	local ladder = Instance.new("TrussPart")
	ladder.Anchored = true
	ladder.Size = Vector3.new(2, 7.4, 2)
	ladder.CFrame = L(60, 23.7, 75.4)
	ladder.Color = steel
	ladder.Material = M.Metal
	ladder.Parent = billboard
	Build.markStandIn(billboard, ORIGIN)
	sign(set, "HOLLOW MEATS\nFamily Butchers since 1971\n“Come for dinner”", Vector3.new(39, 15, 0.3), L(BX, 36, BZ - 0.65), rgb(200, 40, 30), false).CanCollide = false
	for _, dx in { -12, 0, 12 } do
		local flood = neon(set, Vector3.new(1.2, 0.5, 0.8), L(BX + dx, 28.6, BZ - 3.4), rgb(255, 236, 200))
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Top
		light.Angle = 70
		light.Range = 22
		light.Brightness = 2.4
		light.Color = rgb(255, 230, 190)
		light.Parent = flood
	end
	local bell = Build.ball(set, 1.4, L(BX + 18, 29, BZ - 1.8), rgb(196, 160, 70), M.Metal)
	Build.part(set, Vector3.new(0.3, 2.6, 0.3), L(BX + 18, 28.6, BZ - 1.8), steel, M.Metal, { CanCollide = false })
	bellPrompt = prompt(bell, "Ring the bell", "Billboard", "bell")

	------------------------------------------------------------ lamps and the woods
	-- a tall lamp by the trucks, half dead
	Build.post(set, 16, 0.5, L(14, 8, 10), rgb(60, 60, 58), M.Metal)
	local trucksLamp = Build.part(set, Vector3.new(2.4, 0.6, 1.2), L(15.2, 16.2, 10), rgb(255, 220, 160), M.Neon, { CanCollide = false })
	local lampLight = Instance.new("SpotLight")
	lampLight.Face = Enum.NormalId.Bottom
	lampLight.Angle = 100
	lampLight.Range = 40
	lampLight.Brightness = 2.2
	lampLight.Color = rgb(255, 210, 150)
	lampLight.Shadows = true
	lampLight.Parent = trucksLamp
	Build.tag(trucksLamp, "FlickerLight")
	for _, pos in { Vector2.new(-40, 6), Vector2.new(4, -26), Vector2.new(58, -14), Vector2.new(100, -8), Vector2.new(128, 8), Vector2.new(20, 50), Vector2.new(72, 52) } do
		lamp(set, pos.X, pos.Y)
	end
	-- pines all round (the road and the truck stop stay clear)
	for _ = 1, 150 do
		local x, z = rng:NextNumber(-185, 265), rng:NextNumber(-185, 225)
		local onSite = x > -72 and x < 146 and z > -76 and z < 100
		if not onSite and math.abs(z + 50) > 18 then
			local tree = Props.PineTree(rng)
			tree:PivotTo(L(x, 0, z) * ANG(0, rng:NextNumber(0, math.pi * 2), 0))
			tree:SetAttribute("KeepVisible", true) -- the woods stay as they are
			tree.Parent = set
		end
	end

	------------------------------------------------------------ the trucks
	-- party zones over their beds, a billboard above each
	local list: { Party } = {}
	for i = 1, TRUCKS do
		local truckCF = L(24.5 + (i - 1) * 13, 0, -6)
		local truck = Props.PickupTruck()
		truck:PivotTo(truckCF)
		truck.Parent = set
		-- headlights on, engine running: these are the rides out
		for _, x in { -2.6, 2.6 } do
			local beam = Build.part(parent, Vector3.new(0.6, 0.6, 0.2), truckCF * CF(x, 3.6, -8.9), rgb(255, 244, 220), M.Neon, { CanCollide = false })
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Front
			light.Angle = 45
			light.Range = 50
			light.Brightness = 3
			light.Color = rgb(255, 238, 210)
			light.Parent = beam
		end
		local zone = Build.part(parent, Vector3.new(8, 8, 9.4), truckCF * CF(0, 6.4, 6.2), rgb(255, 255, 255), M.SmoothPlastic, {
			Name = "PartyZone" .. i,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		local glow = Build.part(parent, Vector3.new(6.2, 0.05, 7), truckCF * CF(0, 3.25, 6.2), rgb(255, 170, 60), M.Neon, {
			Transparency = 0.75,
			CanCollide = false,
		})
		local underglow = Instance.new("PointLight")
		underglow.Range = 10
		underglow.Brightness = 0.8
		underglow.Color = rgb(255, 170, 60)
		underglow.Parent = glow
		local billboardGui = Instance.new("BillboardGui")
		billboardGui.Size = UDim2.fromOffset(240, 78)
		billboardGui.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
		billboardGui.AlwaysOnTop = false
		billboardGui.MaxDistance = 90
		billboardGui.LightInfluence = 0
		billboardGui.Parent = zone
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.SpecialElite
		label.TextScaled = true
		label.TextColor3 = cream
		label.TextStrokeTransparency = 0.4
		label.Text = ""
		label.Parent = billboardGui
		local party: Party = {
			index = i,
			zone = zone,
			exit = truckCF * CF(0, 3, 13),
			members = {},
			ready = {},
			host = nil,
			difficulty = "Normal",
			countdown = nil,
			leaving = false,
			locked = false,
			banned = {},
			label = label,
		}
		table.insert(list, party)
	end
	spawnCF = L(-14, 3.5, 6) * ANG(0, rad(-90), 0)

	-- every plain part above is shown as its Blender remodel (LobbyParts)
	Build.bake(set, "LobbyParts", ORIGIN)
	return list
end

-- The truck stop without the lobby running, for dumping its parts in Studio
-- (tools/blender/build_house_parts.py builds LobbyParts from them).
function Lobby.preview(parent: Instance): Model?
	local folder = Instance.new("Folder")
	folder.Name = "LobbyPreview"
	buildSet(folder)
	folder.Parent = parent
	return folder:FindFirstChild("Set") :: Model?
end

---------------------------------------------------------------- parties
-- The queue. Climbing into a truck bed joins its party; the first one in
-- is the host. A truck waits WAIT seconds after its first rider, and never
-- less than JOIN_GRACE after someone new climbs in, so nobody gets driven
-- off the moment they arrive. Once everyone aboard is ready it leaves in
-- READY_GO, and the host can start it at once. The host also picks the
-- difficulty, can make the truck friends-only, hand the truck over or kick
-- someone out (who then can't climb back in for KICK_BAN). Players who
-- don't want to walk can quick-join the best truck, board one from the
-- queue panel, or drive out alone.

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function inside(zone: BasePart, pos: Vector3): boolean
	local rel = zone.CFrame:PointToObjectSpace(pos)
	local half = zone.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local function partyOf(player: Player): Party?
	for _, party in parties do
		if table.find(party.members, player) then
			return party
		end
	end
	return nil
end

local function notice(players: { Player }, text: string, ...: any)
	for _, p in players do
		noticeRemote:FireClient(p, text, ...)
	end
end

local function allReady(party: Party): boolean
	if #party.members == 0 then
		return false
	end
	for _, m in party.members do
		if not party.ready[m] then
			return false
		end
	end
	return true
end

local function readyCount(party: Party): number
	local n = 0
	for _, m in party.members do
		if party.ready[m] then
			n += 1
		end
	end
	return n
end

local function seconds(party: Party): number?
	return if party.countdown then math.max(0, math.ceil(party.countdown)) else nil
end

-- Friends-only trucks ask Roblox whether you're the host's friend; the
-- answer is kept, and nil means still asking.
local friends: { [string]: boolean } = {}
local asking: { [string]: boolean } = {}
local function friendOf(player: Player, host: Player?): boolean?
	if not host or host == player then
		return true
	end
	local key = math.min(player.UserId, host.UserId) .. ":" .. math.max(player.UserId, host.UserId)
	local known = friends[key]
	if known ~= nil then
		return known
	end
	if not asking[key] then
		asking[key] = true
		task.spawn(function()
			local ok, result = pcall(function()
				return player:IsFriendsWithAsync(host.UserId)
			end)
			friends[key] = ok and result == true
			asking[key] = nil
		end)
	end
	return nil
end

-- Why this player can't ride in this truck right now (nil: they can).
local function refusal(party: Party, player: Player): string?
	if party.leaving then
		return "That truck is already leaving."
	end
	local until_ = party.banned[player.UserId]
	if until_ and until_ > os.clock() then
		return "You were kicked from that truck. Try another one."
	end
	if #party.members >= MAX_PARTY then
		return "That truck is full."
	end
	if party.locked and friendOf(player, party.host) == false then
		return "That truck is friends only."
	end
	return nil
end

-- Off the tailgate, facing the truck.
local function eject(party: Party, player: Player)
	local root = rootOf(player)
	if root then
		root.CFrame = party.exit * CF(math.random(-30, 30) / 10, 0, 0)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Into the bed of the truck (the next step() picks them up).
local function climbIn(party: Party, player: Player)
	local root = rootOf(player)
	if root then
		root.CFrame = party.zone.CFrame * CF(math.random(-15, 15) / 10, -0.6, math.random(-20, 20) / 10)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function summary(party: Party, viewer: Player): { [string]: any }
	local list = {}
	for _, m in party.members do
		table.insert(list, {
			id = m.UserId,
			name = m.DisplayName,
			host = m == party.host,
			ready = party.ready[m] == true,
			me = m == viewer,
		})
	end
	return {
		truck = party.index,
		members = list,
		max = MAX_PARTY,
		isHost = party.host == viewer,
		ready = party.ready[viewer] == true,
		readyCount = readyCount(party),
		difficulty = party.difficulty,
		countdown = seconds(party),
		leaving = party.leaving,
		locked = party.locked,
	}
end

-- Every truck at a glance, for the queue panel.
local function overview(): { { [string]: any } }
	local list = {}
	for _, party in parties do
		table.insert(list, {
			truck = party.index,
			count = #party.members,
			max = MAX_PARTY,
			difficulty = party.difficulty,
			countdown = seconds(party),
			leaving = party.leaving,
			locked = party.locked,
		})
	end
	return list
end

local function broadcast()
	for _, party in parties do
		local count = #party.members
		local left = seconds(party)
		local status = if party.leaving
			then "Leaving…"
			elseif count >= MAX_PARTY and left then string.format("Full  ·  Leaving in %ds", left)
			elseif left then string.format("Leaving in %ds", left)
			else "Step in to ride"
		local lines = {
			string.format("TRUCK %d  ·  %d/%d", party.index, count, MAX_PARTY),
			string.format("%s  ·  %s", party.difficulty, status),
		}
		if party.locked then
			table.insert(lines, "Friends only")
		elseif count > 0 and not party.leaving then
			table.insert(lines, string.format("%d/%d ready", readyCount(party), count))
		end
		party.label.Text = table.concat(lines, "\n")
	end
	local trucks = overview()
	for _, player in Players:GetPlayers() do
		local party = partyOf(player)
		local searchDifficulty, searchTime = Matchmaking.status(player)
		stateRemote:FireClient(player, {
			party = if party then summary(party, player) else nil,
			trucks = trucks,
			solo = departing[player],
			search = if searchDifficulty then { difficulty = searchDifficulty, elapsed = searchTime } else nil,
		})
	end
end

local function reset(party: Party)
	party.members = {}
	party.ready = {}
	party.host = nil
	party.difficulty = "Normal"
	party.countdown = nil
	party.leaving = false
	party.locked = false
	party.banned = {}
end

-- Everyone ready: go soon. Someone not ready any more: give them time.
local function retime(party: Party)
	if party.leaving or not party.countdown then
		return
	end
	if allReady(party) then
		party.countdown = math.min(party.countdown, READY_GO)
	else
		party.countdown = math.max(party.countdown, JOIN_GRACE)
	end
end

local function join(party: Party, player: Player)
	Matchmaking.cancel(player) -- found company here
	table.insert(party.members, player)
	party.ready[player] = false
	if not party.host then
		party.host = player
	end
	party.countdown = math.max(party.countdown or WAIT, JOIN_GRACE)
end

local function leave(party: Party, player: Player)
	local i = table.find(party.members, player)
	if i then
		table.remove(party.members, i)
	end
	party.ready[player] = nil
	if party.host == player then
		party.host = party.members[1]
		if party.host then
			notice(party.members, "%s is the host now.", party.host.DisplayName)
		end
	end
	if #party.members == 0 then
		reset(party)
	else
		retime(party)
	end
end

-- Sends players into one fresh reserved server of this place. It is
-- reserved first so that anyone whose teleport fails can be sent after the
-- others (TeleportInitFailed in run()), and noted (Rejoin) so anyone who
-- drops out of the run can get back in. Yields; false if it failed.
local function depart(members: { Player }, difficulty: string): boolean
	if RunService:IsStudio() then
		studioStart = difficulty
		return true
	end
	-- write their Teeth and perks first: the game server loads them on arrival
	for _, member in members do
		Profiles.save(member)
	end
	local ok, err = pcall(function()
		local code, server = TeleportService:ReserveServer(game.PlaceId)
		local ids = {}
		for _, member in members do
			table.insert(ids, member.UserId)
		end
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData({ difficulty = difficulty, party = ids })
		Rejoin.remember(members, { code = code, server = server })
		TeleportService:TeleportAsync(game.PlaceId, members, options)
	end)
	if not ok then
		warn("[Lobby] teleport failed: " .. tostring(err))
	end
	return ok
end

local function launch(party: Party)
	party.leaving = true
	local members = table.clone(party.members)
	broadcast()
	task.spawn(function()
		if not depart(members, party.difficulty) then
			notice(members, "The truck wouldn't start. Try again in a moment.")
			party.leaving = false
			party.countdown = JOIN_GRACE
			broadcast()
			return
		end
		if RunService:IsStudio() then
			return
		end
		-- anyone still here after the retries didn't make it; free the truck
		task.wait(45)
		if party.leaving then
			reset(party)
			broadcast()
		end
	end)
end

-- Drive out alone, at your own difficulty.
local function goSolo(player: Player, difficulty: string)
	if departing[player] or partyOf(player) then
		return
	end
	Matchmaking.cancel(player)
	departing[player] = difficulty
	notice({ player }, "Driving out alone…")
	broadcast()
	if not depart({ player }, difficulty) then
		notice({ player }, "The truck wouldn't start. Try again in a moment.")
		departing[player] = nil
		broadcast()
		return
	end
	task.wait(45)
	departing[player] = nil
end

-- The best truck for someone who just wants to play: the fullest one that
-- will take them (more company, sooner), then the one leaving soonest.
local function quickJoin(player: Player, preferred: string?)
	if partyOf(player) or departing[player] then
		return
	end
	local best: Party? = nil
	local bestScore = -math.huge
	for _, party in parties do
		if not party.locked and refusal(party, player) == nil then
			local score = #party.members * 100 - (party.countdown or WAIT)
			if preferred and party.difficulty == preferred and #party.members > 0 then
				score += 50
			end
			if score > bestScore then
				best, bestScore = party, score
			end
		end
	end
	if best then
		climbIn(best, player)
	else
		notice({ player }, "Every truck is full or leaving. Try again in a moment.")
	end
end

-- Matchmaking found this player company on other servers: off to the game
-- it reserved for them.
local function sendMatched(player: Player, ticket: Matchmaking.Ticket)
	if not player.Parent or partyOf(player) or departing[player] then
		return
	end
	departing[player] = ticket.difficulty
	notice({ player }, "Found players. Off you go…")
	broadcast()
	Profiles.save(player)
	local ok, err = pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = ticket.code
		options:SetTeleportData({ difficulty = ticket.difficulty, party = ticket.party })
		Rejoin.remember({ player }, { code = ticket.code, server = ticket.server })
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		warn("[Lobby] matched teleport failed: " .. tostring(err))
		notice({ player }, "Couldn't reach your party. Rejoin the game to try again.")
		departing[player] = nil
		broadcast()
	end
end

-- A player whose party is still playing (they dropped out of the run) goes
-- straight back to it.
local function rejoinParty(player: Player)
	local g = Rejoin.lookup(player.UserId)
	if not g or not player.Parent then
		return
	end
	notice({ player }, "Your party is still in the woods. Taking you back…")
	local ok, err = pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = g.code
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		warn("[Lobby] rejoin failed: " .. tostring(err))
		notice({ player }, "Couldn't reach your party. Rejoin the game to try again.")
	end
end

local function step(dt: number)
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local current = partyOf(player)
		if (current and current.leaving) or departing[player] then
			continue
		end
		local now: Party? = nil
		if root then
			for _, party in parties do
				if inside(party.zone, root.Position) then
					now = party
					break
				end
			end
		end
		if now ~= current then
			if current then
				leave(current, player)
			end
			if now then
				local why = refusal(now, player)
				if why then
					eject(now, player)
					notice({ player }, why)
				elseif now.locked and friendOf(player, now.host) == nil then
					-- still asking Roblox; try again next step
				else
					join(now, player)
				end
			end
		end
		-- fell off the edge of the world
		if root and root.Position.Y < ORIGIN.Y - 60 then
			root.CFrame = spawnCF
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
	for _, party in parties do
		if party.countdown and not party.leaving then
			party.countdown -= dt
			if party.countdown <= 0 then
				launch(party)
			end
		end
	end
end

local function memberById(party: Party, id: any): Player?
	for _, m in party.members do
		if m.UserId == id then
			return m
		end
	end
	return nil
end

local function onAction(player: Player, action: any, value: any)
	-- anyone, in a truck or not
	if action == "quickjoin" then
		quickJoin(player, if Difficulty.valid(value) then value else nil)
		return
	elseif action == "board" then
		local party = if typeof(value) == "number" then parties[value] else nil
		if party and partyOf(player) == nil and not departing[player] then
			if party.locked then
				-- worth the wait: we only let friends of the host on
				local ok = friendOf(player, party.host)
				while ok == nil do
					task.wait(0.2)
					ok = friendOf(player, party.host)
				end
			end
			local why = refusal(party, player)
			if why then
				notice({ player }, why)
			else
				climbIn(party, player)
			end
		end
		return
	elseif action == "solo" then
		if Difficulty.valid(value) then
			goSolo(player, value)
		end
		return
	elseif action == "search" then
		if Difficulty.valid(value) and not partyOf(player) and not departing[player] then
			if Matchmaking.search(player, value) then
				notice({ player }, "Looking for players on other servers…")
			else
				notice({ player }, "Finding players works on live servers only.")
			end
			broadcast()
		end
		return
	elseif action == "cancelsearch" then
		Matchmaking.cancel(player)
		broadcast()
		return
	end

	local party = partyOf(player)
	if not party or party.leaving then
		return
	end
	-- members
	if action == "ready" then
		party.ready[player] = not party.ready[player]
		retime(party)
		broadcast()
		return
	elseif action == "leave" then
		leave(party, player)
		eject(party, player)
		broadcast()
		return
	end
	-- the host
	if party.host ~= player then
		return
	end
	if action == "difficulty" and Difficulty.valid(value) then
		party.difficulty = value
		notice(party.members, string.format("Difficulty: %s", value))
	elseif action == "start" then
		party.countdown = math.min(party.countdown or QUICK_START, QUICK_START)
	elseif action == "lock" then
		party.locked = not party.locked
		notice(party.members, if party.locked then "The truck is friends only now." else "Anyone can ride now.")
	elseif action == "kick" then
		local target = memberById(party, value)
		if target and target ~= player then
			party.banned[target.UserId] = os.clock() + KICK_BAN
			leave(party, target)
			eject(party, target)
			notice({ target }, "The host kicked you from the truck.")
		end
	elseif action == "promote" then
		local target = memberById(party, value)
		if target and target ~= player then
			party.host = target
			notice(party.members, "%s is the host now.", target.DisplayName)
		end
	end
	broadcast()
end

---------------------------------------------------------------- players

local function spawnPlayer(player: Player)
	if not player.Parent then
		return
	end
	-- your own avatar on an R6 body
	local character = R6Characters.load(player)
	local root = character and character:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") then
		root.CFrame = spawnCF * CF(math.random(-6, 6), 0, math.random(-6, 6))
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(connections, humanoid.Died:Connect(function()
			task.delay(3, function()
				if studioStart == nil then
					spawnPlayer(player)
				end
			end)
		end))
	end
end

local function makeRemotes(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "LobbyRemotes"
	local function remote(name: string): RemoteEvent
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
		return r
	end
	stateRemote = remote("State")
	actionRemote = remote("Action")
	noticeRemote = remote("Notice")
	folder.Parent = ReplicatedStorage
	return folder
end

---------------------------------------------------------------- game servers

-- Reserved game servers take the difficulty from the first arrival's
-- teleport data, and the party (Rejoin) from everyone's.
local function readTeleportData()
	local function fromPlayer(player: Player)
		local ok, joinData = pcall(function()
			return player:GetJoinData()
		end)
		local data = if ok and typeof(joinData) == "table" then (joinData :: any).TeleportData else nil
		if typeof(data) ~= "table" then
			return
		end
		if typeof(data.party) == "table" then
			Rejoin.expect(data.party)
		end
		if not Difficulty.valid(workspace:GetAttribute("Difficulty")) and Difficulty.valid(data.difficulty) then
			workspace:SetAttribute("Difficulty", data.difficulty)
		end
	end
	Players.PlayerAdded:Connect(fromPlayer)
	for _, player in Players:GetPlayers() do
		fromPlayer(player)
	end
end

---------------------------------------------------------------- entry

function Lobby.run()
	if not Session.isLobby() then
		workspace:SetAttribute("Mode", "Game")
		readTeleportData()
		Rejoin.watchGame()
		Difficulty.watch(Cannibals.Kinds)
		return
	end
	workspace:SetAttribute("Mode", "Lobby")
	LightingSetup.apply()
	-- a little kinder than the woods, so people can find the trucks
	-- (Studio re-applies the game's lighting when it turns into the game)
	local Lighting = game:GetService("Lighting")
	Lighting.Brightness = 0.9
	Lighting.ExposureCompensation = 0.25
	Lighting.OutdoorAmbient = rgb(40, 44, 56)
	-- previews for the store's perk cards (client LobbyMenu)
	local previews: { string } = {}
	for _, perk in StoreCatalog.list() do
		local def = Items.get(perk.item)
		if def then
			table.insert(previews, def.model)
		end
	end
	AssetService.publishItemModels(previews)
	local remotes = makeRemotes()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	parties = buildSet(folder)
	folder.Parent = workspace

	-- the bell on top of the billboard: a trophy the first time
	if bellPrompt then
		table.insert(connections, bellPrompt.Triggered:Connect(function(player: Player)
			local a = Trophies.Achievements.Billboard
			if a and Profiles.unlock(player, a.id) then
				Profiles.award(player, a.teeth, a.name)
				notice({ player }, string.format("Trophy: %s  (+%d Teeth)", a.name, a.teeth))
			end
		end))
	end
	-- the leaderboards, every minute
	task.spawn(function()
		while studioStart == nil do
			for stat, label in boards do
				local top = Leaderboards.top(stat, 10)
				if top == nil then
					label.Text = "<i>The records live online.\nThey show on published servers.</i>"
				elseif #top == 0 then
					label.Text = "<i>Nobody yet. Be the first.</i>"
				else
					local lines = {}
					for i, e in top do
						table.insert(lines, string.format("%d. %s  <font color=\"#f0c450\">%d</font>", i, e.name, e.value))
					end
					label.Text = table.concat(lines, "\n")
				end
			end
			task.wait(60)
		end
	end)

	table.insert(connections, actionRemote.OnServerEvent:Connect(onAction))
	Matchmaking.start(sendMatched)
	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		task.spawn(rejoinParty, player)
		spawnPlayer(player)
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		retries[player] = nil
		departing[player] = nil
		local party = partyOf(player)
		if party then
			leave(party, player)
		end
	end))
	-- a teleport that fails for one of the party is tried again into the same
	-- reserved server (the options carry its code), so nobody plays apart
	table.insert(connections, TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string, placeId: number, options: TeleportOptions?)
		warn("[Lobby] teleport of " .. player.Name .. " failed: " .. tostring(message))
		local tries = (retries[player] or 0) + 1
		retries[player] = tries
		if options and options.ReservedServerAccessCode ~= "" and tries <= 4 then
			noticeRemote:FireClient(player, "Lost the truck. Catching up with your party…")
			task.wait(if result == Enum.TeleportResult.Flooded then 10 else 2 * tries)
			if player.Parent then
				pcall(function()
					TeleportService:TeleportAsync(placeId, { player }, options)
				end)
			end
			return
		end
		retries[player] = nil
		departing[player] = nil
		noticeRemote:FireClient(player, "Couldn't reach your party. Rejoin the game to try again.")
		local party = partyOf(player)
		if party then
			leave(party, player)
			if party.leaving and #party.members == 0 then
				reset(party)
			end
		end
	end))
	for _, player in Players:GetPlayers() do
		task.spawn(rejoinParty, player)
		task.spawn(spawnPlayer, player)
	end

	local lastBroadcast = 0
	while studioStart == nil do
		local dt = task.wait(0.2)
		step(dt)
		if os.clock() - lastBroadcast > 0.5 then
			lastBroadcast = os.clock()
			broadcast()
		end
	end

	-- Studio: this server becomes the game for everyone in it
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			player.Character = nil
			character:Destroy()
		end
	end
	folder:Destroy()
	remotes:Destroy()
	workspace:SetAttribute("Difficulty", studioStart)
	workspace:SetAttribute("Mode", "Game")
	Difficulty.watch(Cannibals.Kinds)
end

return Lobby

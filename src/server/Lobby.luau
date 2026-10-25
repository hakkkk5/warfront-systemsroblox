--!strict
-- The lobby: a roadside gas station at night, the last stop before Hollow
-- Road. Players gather in the beds of three pickup trucks; each truck is a
-- party of up to four. The first one in is the host and picks the
-- difficulty. When the countdown runs out (or the host starts early) the
-- party is teleported into a fresh reserved server of this place, carrying
-- the difficulty in the teleport data.
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
local Session = require(ReplicatedStorage.Shared.Session)
local Util = require(ReplicatedStorage.Shared.Util)
local Build = require(script.Parent.World.Build)
local LightingSetup = require(script.Parent.World.Lighting)
local Props = require(script.Parent.World.Props)
local Cannibals = require(script.Parent.Systems.Cannibals)
local R6Characters = require(script.Parent.Systems.R6Characters)

local Lobby = {}

local rgb = Color3.fromRGB
local M = Enum.Material
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

local ORIGIN = CF(0, 600, 0) -- floats high above the map
local MAX_PARTY = 4
local COUNTDOWN = 25
local QUICK_START = 3
local TRUCKS = 3

type Party = {
	index: number,
	zone: BasePart,
	members: { Player },
	host: Player?,
	difficulty: string,
	countdown: number?,
	leaving: boolean,
	label: TextLabel,
}

local parties: { Party } = {}
local connections: { RBXScriptConnection } = {}
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

local function buildSet(parent: Instance): { Party }
	local rng = Util.rng(4242)

	-- ground, parking lot and the highway
	Build.part(parent, Vector3.new(280, 4, 280), L(0, -2, 0), rgb(34, 40, 30), M.Grass)
	Build.part(parent, Vector3.new(96, 0.3, 74), L(0, 0.15, 0), rgb(36, 36, 38), M.Asphalt)
	Build.part(parent, Vector3.new(280, 0.25, 24), L(0, 0.13, -50), rgb(30, 30, 32), M.Asphalt)
	for x = -132, 132, 12 do
		Build.part(parent, Vector3.new(6, 0.05, 0.4), L(x, 0.28, -50), rgb(190, 170, 90), M.SmoothPlastic, { CanCollide = false })
	end
	for i = 1, TRUCKS + 1 do
		Build.part(parent, Vector3.new(0.4, 0.05, 16), L(18 + (i - 1) * 13, 0.32, -6), rgb(200, 200, 190), M.SmoothPlastic, { CanCollide = false })
	end

	-- the pump island under a canopy of buzzing strip lights
	for _, x in { -26, -2 } do
		for _, z in { -16, 0 } do
			Build.post(parent, 9.4, 0.9, L(x, 4.7, z), rgb(200, 196, 186), M.Metal)
		end
	end
	Build.part(parent, Vector3.new(34, 1.2, 24), L(-14, 9.9, -8), rgb(220, 216, 206), M.SmoothPlastic)
	Build.part(parent, Vector3.new(34.4, 0.6, 24.4), L(-14, 9.1, -8), rgb(170, 30, 26), M.SmoothPlastic)
	for i, x in { -24, -14, -4 } do
		local strip = Build.part(parent, Vector3.new(6, 0.2, 0.6), L(x, 9.25, -8), rgb(225, 240, 255), M.Neon, { CanCollide = false })
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
	Build.part(parent, Vector3.new(26, 0.6, 5), L(-14, 0.3, -8), rgb(120, 116, 108), M.Concrete)
	for _, x in { -20, -8 } do
		Build.part(parent, Vector3.new(2.6, 5.2, 1.8), L(x, 3.2, -8), rgb(170, 30, 26), M.Metal)
		Build.part(parent, Vector3.new(2, 1.4, 0.1), L(x, 4.2, -8.95), rgb(20, 24, 22), M.Glass, { CanCollide = false })
	end
	sign(parent, "PINECREST GAS", Vector3.new(16, 2.2, 0.4), L(-14, 11.6, -20.3), rgb(255, 210, 120), true)

	-- the store: lit windows, an OPEN sign, a payphone
	Build.part(parent, Vector3.new(34, 12, 18), L(-14, 6, 26), rgb(120, 104, 86), M.WoodPlanks)
	-- flat roof: stand-in for the Blender store front (build_buildings.py:
	-- parapet, awning, window frames, rooftop units, canopy trim)
	local shell = Build.standIn(parent, "GasStationExterior")
	Build.part(shell, Vector3.new(36, 1, 20), L(-14, 12.5, 26), rgb(60, 48, 40), M.Slate)
	Build.markStandIn(shell, ORIGIN)
	for _, x in { -24, -4 } do
		local window = Build.part(parent, Vector3.new(8, 4.4, 0.3), L(x, 5, 16.9), rgb(255, 214, 150), M.Neon, { Transparency = 0.35 })
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Front
		light.Range = 18
		light.Brightness = 1.4
		light.Color = rgb(255, 200, 140)
		light.Parent = window
	end
	Build.part(parent, Vector3.new(4, 8, 0.4), L(-14, 4, 16.9), rgb(50, 40, 32), M.Wood)
	sign(parent, "OPEN 24H", Vector3.new(5, 1.4, 0.2), L(-24, 8.6, 16.7), rgb(255, 70, 60), true)
	sign(parent, "LAST STOP BEFORE HOLLOW ROAD", Vector3.new(30, 2.4, 0.4), L(-14, 13.8, 16.6), rgb(226, 214, 190), false)
	-- things to poke at while the party gathers (handled on the client)
	local function prompt(part: BasePart, actionText: string, objectText: string, action: string)
		local p = Instance.new("ProximityPrompt")
		p.ActionText = actionText
		p.ObjectText = objectText
		p.HoldDuration = 0
		p.MaxActivationDistance = 10
		p.RequiresLineOfSight = false
		p.Style = Enum.ProximityPromptStyle.Custom
		p:SetAttribute("LobbyAction", action)
		p.Parent = part
	end
	local payphone = Build.part(parent, Vector3.new(1.6, 3, 1), L(4.5, 4, 17.6), rgb(60, 70, 64), M.Metal)
	Build.part(parent, Vector3.new(0.4, 1.2, 0.4), L(4.1, 4.4, 16.95), rgb(20, 20, 20), M.SmoothPlastic, { CanCollide = false })
	prompt(payphone, "Answer", "Ringing payphone", "payphone")

	local vending = Build.part(parent, Vector3.new(3.4, 7, 2.4), L(-33.6, 3.5, 14.8), rgb(150, 26, 24), M.Metal)
	local vendGlow = Build.part(parent, Vector3.new(2.6, 4.2, 0.1), L(-33.6, 4.2, 13.55), rgb(255, 236, 200), M.Neon, {
		CanCollide = false,
		Transparency = 0.2,
	})
	Build.tag(vendGlow, "FlickerLight")
	local vendLight = Instance.new("PointLight")
	vendLight.Range = 10
	vendLight.Brightness = 1
	vendLight.Color = rgb(255, 220, 180)
	vendLight.Parent = vendGlow
	prompt(vending, "Buy a soda", "Vending machine", "vending")

	-- the rules of the road, readable from the spawn
	for _, z in { 5, 11 } do
		Build.post(parent, 7, 0.3, L(0, 3.5, z), rgb(70, 56, 44), M.Wood)
	end
	local howto = sign(parent, table.concat({
		"HOW TO SURVIVE",
		"WASD move · Shift run · C crouch · F flashlight",
		"E use · Tab bag · H hint",
		"Stay quiet. Stay dark. Hide when they see you.",
	}, "\n"), Vector3.new(7.4, 4.4, 0.3), L(0, 5.6, 8) * ANG(0, rad(90), 0), rgb(226, 214, 190), false)
	prompt(howto, "Read", "How to play", "howto")

	for _, z in { -1, 5 } do
		Build.post(parent, 7, 0.3, L(-31, 3.5, z), rgb(70, 56, 44), M.Wood)
	end
	local board = Build.part(parent, Vector3.new(7, 4.2, 0.3), L(-31, 5.6, 2) * ANG(0, rad(-90), 0), rgb(150, 112, 70), M.Fabric)
	for i, who in { "DALE\nWHITCOMB\n2019", "THE\nHARLANS\n2021", "MARISOL\nVEGA\n2022", "DEP.\nBRANDT\n2023" } do
		local poster = Build.part(parent, Vector3.new(1.3, 1.7, 0.05), board.CFrame * CF(-2.4 + (i - 1) * 1.6, 0.6 - ((i - 1) % 2) * 1.2, -0.18), rgb(230, 224, 205), M.SmoothPlastic, {
			CanCollide = false,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(130, 170)
		gui.Parent = poster
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.SpecialElite
		label.TextScaled = true
		label.TextColor3 = rgb(40, 30, 28)
		label.Text = "MISSING\n" .. who
		label.Parent = gui
	end
	sign(parent, "MISSING", Vector3.new(5, 0.9, 0.1), board.CFrame * CF(0, 1.75, -0.2), rgb(170, 30, 26), false).CanCollide = false
	prompt(board, "Read", "Missing persons", "missing")

	-- tall lamp by the trucks, half dead
	Build.post(parent, 16, 0.5, L(14, 8, 10), rgb(60, 60, 58), M.Metal)
	local lamp = Build.part(parent, Vector3.new(2.4, 0.6, 1.2), L(15.2, 16.2, 10), rgb(255, 220, 160), M.Neon, { CanCollide = false })
	local lampLight = Instance.new("SpotLight")
	lampLight.Face = Enum.NormalId.Bottom
	lampLight.Angle = 100
	lampLight.Range = 40
	lampLight.Brightness = 2.2
	lampLight.Color = rgb(255, 210, 150)
	lampLight.Shadows = true
	lampLight.Parent = lamp
	Build.tag(lamp, "FlickerLight")

	-- porch lights on the store, lamps along the lot
	for _, x in { -27, -1 } do
		local porch = Build.part(parent, Vector3.new(1, 0.6, 0.6), L(x, 9.5, 16.4), rgb(255, 220, 170), M.Neon, { CanCollide = false })
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = 110
		light.Range = 30
		light.Brightness = 2
		light.Color = rgb(255, 205, 150)
		light.Parent = porch
		porch.CFrame = porch.CFrame * ANG(rad(-60), 0, 0)
	end
	for _, pos in { Vector3.new(-40, 0, 6), Vector3.new(4, 0, -26), Vector3.new(50, 0, 14) } do
		Build.post(parent, 12, 0.4, L(pos.X, 6, pos.Z), rgb(60, 60, 58), M.Metal)
		local head = Build.part(parent, Vector3.new(1.6, 0.5, 1.6), L(pos.X, 12.2, pos.Z), rgb(255, 220, 160), M.Neon, { CanCollide = false })
		local light = Instance.new("PointLight")
		light.Range = 34
		light.Brightness = 1.8
		light.Color = rgb(255, 214, 160)
		light.Shadows = true
		light.Parent = head
	end

	-- a ring of pines (the road stays clear)
	for _ = 1, 70 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(66, 128)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if math.abs(z + 50) > 18 then
			local tree = Props.PineTree(rng)
			tree:PivotTo(L(x, 0, z) * ANG(0, rng:NextNumber(0, math.pi * 2), 0))
			tree.Parent = parent
		end
	end

	-- the trucks: party zones over their beds, a billboard above each
	local list: { Party } = {}
	for i = 1, TRUCKS do
		local truckCF = L(24.5 + (i - 1) * 13, 0, -6)
		local truck = Props.PickupTruck()
		truck:PivotTo(truckCF)
		truck.Parent = parent
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
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(240, 78)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 90
		billboard.LightInfluence = 0
		billboard.Parent = zone
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.SpecialElite
		label.TextScaled = true
		label.TextColor3 = rgb(226, 214, 190)
		label.TextStrokeTransparency = 0.4
		label.Text = ""
		label.Parent = billboard
		local party: Party = {
			index = i,
			zone = zone,
			members = {},
			host = nil,
			difficulty = "Normal",
			countdown = nil,
			leaving = false,
			label = label,
		}
		table.insert(list, party)
	end
	spawnCF = L(-14, 3.5, 6) * ANG(0, rad(-90), 0)
	return list
end

---------------------------------------------------------------- parties

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

local function notice(players: { Player }, text: string)
	for _, p in players do
		noticeRemote:FireClient(p, text)
	end
end

local function summary(party: Party, viewer: Player): { [string]: any }
	local names = {}
	for _, m in party.members do
		table.insert(names, { name = m.DisplayName, host = m == party.host })
	end
	return {
		truck = party.index,
		members = names,
		max = MAX_PARTY,
		isHost = party.host == viewer,
		difficulty = party.difficulty,
		countdown = if party.countdown then math.max(0, math.ceil(party.countdown)) else nil,
		leaving = party.leaving,
	}
end

local function broadcast()
	for _, party in parties do
		local count = #party.members
		local status = if party.leaving
			then "Leaving…"
			elseif party.countdown then string.format("Leaving in %ds", math.max(0, math.ceil(party.countdown)))
			else "Step in to ride"
		party.label.Text = string.format("TRUCK %d  ·  %d/%d\n%s  ·  %s", party.index, count, MAX_PARTY, party.difficulty, status)
	end
	for _, player in Players:GetPlayers() do
		local party = partyOf(player)
		stateRemote:FireClient(player, if party then summary(party, player) else nil)
	end
end

local function reset(party: Party)
	party.members = {}
	party.host = nil
	party.difficulty = "Normal"
	party.countdown = nil
	party.leaving = false
end

local function join(party: Party, player: Player)
	table.insert(party.members, player)
	if not party.host then
		party.host = player
	end
	if not party.countdown then
		party.countdown = COUNTDOWN
	end
end

local function leave(party: Party, player: Player)
	local i = table.find(party.members, player)
	if i then
		table.remove(party.members, i)
	end
	if party.host == player then
		party.host = party.members[1]
	end
	if #party.members == 0 then
		reset(party)
	end
end

-- Teleport the party into a fresh reserved server of this place.
local function launch(party: Party)
	party.leaving = true
	local members = table.clone(party.members)
	broadcast()
	if RunService:IsStudio() then
		studioStart = party.difficulty
		return
	end
	task.spawn(function()
		local options = Instance.new("TeleportOptions")
		options.ShouldReserveServer = true
		options:SetTeleportData({ difficulty = party.difficulty })
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, members, options)
		end)
		if not ok then
			warn("[Lobby] teleport failed: " .. tostring(err))
			notice(members, "The truck wouldn't start. Try again in a moment.")
			party.leaving = false
			party.countdown = COUNTDOWN
			broadcast()
			return
		end
		-- anyone still here after a while didn't make it; free the truck
		task.wait(20)
		if party.leaving then
			reset(party)
			broadcast()
		end
	end)
end

local function step(dt: number)
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local current = partyOf(player)
		if current and current.leaving then
			continue
		end
		local now: Party? = nil
		if root then
			for _, party in parties do
				if not party.leaving and inside(party.zone, root.Position) then
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
				if #now.members < MAX_PARTY then
					join(now, player)
				else
					notice({ player }, "That truck is full.")
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

local function onAction(player: Player, action: any, value: any)
	local party = partyOf(player)
	if not party or party.leaving or party.host ~= player then
		return
	end
	if action == "difficulty" and Difficulty.valid(value) then
		party.difficulty = value
		notice(party.members, string.format("Difficulty: %s", value))
	elseif action == "start" then
		party.countdown = math.min(party.countdown or QUICK_START, QUICK_START)
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
-- teleport data.
local function readDifficulty()
	local function fromPlayer(player: Player)
		if Difficulty.valid(workspace:GetAttribute("Difficulty")) then
			return
		end
		local ok, joinData = pcall(function()
			return player:GetJoinData()
		end)
		local data = if ok and typeof(joinData) == "table" then (joinData :: any).TeleportData else nil
		if typeof(data) == "table" and Difficulty.valid(data.difficulty) then
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
		readDifficulty()
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
	local remotes = makeRemotes()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	parties = buildSet(folder)
	folder.Parent = workspace

	table.insert(connections, actionRemote.OnServerEvent:Connect(onAction))
	table.insert(connections, Players.PlayerAdded:Connect(spawnPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		local party = partyOf(player)
		if party then
			leave(party, player)
		end
	end))
	table.insert(connections, TeleportService.TeleportInitFailed:Connect(function(player: Player, _result, message: string)
		warn("[Lobby] teleport of " .. player.Name .. " failed: " .. tostring(message))
		noticeRemote:FireClient(player, "Couldn't reach the woods. Step back in to try again.")
		local party = partyOf(player)
		if party then
			leave(party, player)
			if party.leaving and #party.members == 0 then
				reset(party)
			end
		end
	end))
	for _, player in Players:GetPlayers() do
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

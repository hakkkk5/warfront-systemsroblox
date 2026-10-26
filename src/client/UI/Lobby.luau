--!strict
-- Lobby screen: how to form a party, the party panel (members, difficulty,
-- countdown, start), notices and the menu (LobbyMenu: store, records,
-- settings, invites). Lobby.run() is called by Main before the title menu:
-- in a game server it only applies the difficulty and returns; in a lobby
-- server it runs the lobby and returns only if this server turns into the
-- game (Studio).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Session = require(ReplicatedStorage.Shared.Session)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local HUD = require(script.Parent.HUD)
local LobbyMenu = require(script.Parent.LobbyMenu)
local LobbyTrophyWall = require(script.Parent.LobbyTrophyWall)
local Theme = require(script.Parent.Theme)
local Tutorial = require(script.Parent.Tutorial)

local Lobby = {}

local C = Theme.Colors
local player = Players.LocalPlayer

local DIFFICULTY_COLORS: { [string]: Color3 } = {
	Normal = C.Bone,
	Hard = C.Warn,
	Nightmare = C.BloodBright,
}

type Member = { id: number, name: string, host: boolean, ready: boolean, me: boolean }

type PartyState = {
	truck: number,
	members: { Member },
	max: number,
	isHost: boolean,
	ready: boolean,
	readyCount: number,
	difficulty: string,
	countdown: number?,
	leaving: boolean,
	locked: boolean,
}

type TruckState = {
	truck: number,
	count: number,
	max: number,
	difficulty: string,
	countdown: number?,
	leaving: boolean,
	locked: boolean,
}

type State = {
	party: PartyState?,
	trucks: { TruckState },
	solo: boolean,
	search: { difficulty: string, elapsed: number }?, -- finding players on other servers
}

type Screen = {
	render: (state: State) -> (),
	toggleReady: () -> (),
}

local function truckStatus(t: TruckState): string
	if t.leaving then
		return Lang.t("Leaving…")
	elseif t.count >= t.max then
		return Lang.t("Full")
	elseif t.locked then
		return Lang.t("Friends only")
	elseif t.countdown then
		return Lang.f("Leaving in %ds", t.countdown)
	end
	return Lang.t("Empty: step in to ride")
end

local function build(gui: Frame, action: RemoteEvent): Screen
	-- title and how-to (top left)
	local header = Theme.frame(gui, {
		Position = UDim2.fromOffset(28, 26),
		Size = UDim2.fromOffset(560, 120),
		BackgroundTransparency = 1,
	})
	local title = Theme.label(header, Config.GameName, {
		Size = UDim2.new(1, 0, 0, 52),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.Title,
		TextSize = 48,
		TextColor3 = C.BloodBright,
		TextStrokeTransparency = 0.4,
	})
	Util.create("UITextSizeConstraint", { MaxTextSize = 48, Parent = title })
	title.TextScaled = true
	Theme.label(header, "LOBBY  ·  step into a truck bed to form a party (max 4)", {
		Position = UDim2.fromOffset(2, 54),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 17,
		TextColor3 = C.BoneDim,
	})

	-- notices (top centre, under the menu's nav bar)
	local noticeLabel = Theme.label(gui, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.new(0.6, 0, 0, 30),
		TextSize = 20,
		TextColor3 = C.Bone,
		TextStrokeTransparency = 0.4,
		TextTransparency = 1,
	})

	local function panelFrame(height: number, width: number): Frame
		local f = Theme.frame(gui, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -24),
			Size = UDim2.new(0.92, 0, 0, height),
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.12,
			Visible = false,
		})
		Util.create("UISizeConstraint", { MaxSize = Vector2.new(width, height), Parent = f })
		Theme.corner(f, 6)
		Theme.stroke(f, C.Blood, 1).Transparency = 0.4
		Theme.padding(f, 12)
		return f
	end

	local function row(parent: Instance, y: number, height: number): Frame
		local r = Theme.frame(parent, {
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
		})
		Util.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = r,
		})
		return r
	end

	-- a button in a row of them whose text shrinks to fit (French runs long)
	local function fitted(parent: Instance, text: string, width: number, order: number): TextButton
		local b = Theme.button(parent, text, { Size = UDim2.new(width, -6, 1, 0), TextScaled = true, LayoutOrder = order })
		Util.create("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 9, Parent = b })
		Util.create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = b })
		return b
	end

	------------------------------------------------------------ the queue
	-- not in a truck: every truck at a glance (click one to climb in), quick
	-- join, or drive out alone, at the difficulty picked here
	local queue = panelFrame(178, 640)
	Theme.label(queue, "RIDES OUT TONIGHT", {
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.UIBold,
		TextSize = 16,
		TextColor3 = C.Bone,
	})
	local cardRow = row(queue, 28, 80)
	local cards: { { button: TextButton, title: TextLabel, line: TextLabel, status: TextLabel } } = {}
	for i = 1, 3 do
		local b = Theme.button(cardRow, "", { Size = UDim2.new(1 / 3, -6, 1, 0), LayoutOrder = i })
		local function line(y: number, size: number, bold: boolean): TextLabel
			return Theme.label(b, "", {
				Position = UDim2.fromOffset(10, y),
				Size = UDim2.new(1, -20, 0, size + 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = size,
				Font = if bold then Theme.Fonts.UIBold else Theme.Fonts.UI,
				TextColor3 = if bold then C.Bone else C.BoneDim,
			})
		end
		local card = { button = b, title = line(6, 17, true), line = line(30, 14, false), status = line(52, 14, false) }
		b.Activated:Connect(function()
			action:FireServer("board", i)
		end)
		cards[i] = card
	end
	local soloDifficulty = "Normal"
	local searching = false
	local bottom = row(queue, 116, 38)
	local quick = fitted(bottom, "Quick join", 0.25, 1)
	local find = fitted(bottom, "Find players", 0.25, 2)
	local solo = fitted(bottom, "Play solo", 0.25, 3)
	local pick = fitted(bottom, "", 0.25, 4)
	find.Activated:Connect(function()
		action:FireServer(if searching then "cancelsearch" else "search", soloDifficulty)
	end)
	local function showPick()
		pick.Text = "< " .. Lang.t(soloDifficulty) .. " >"
		pick.TextColor3 = DIFFICULTY_COLORS[soloDifficulty] or C.Bone
	end
	showPick()
	pick.Activated:Connect(function()
		local i = table.find(Difficulty.NAMES, soloDifficulty) or 0
		soloDifficulty = Difficulty.NAMES[i % #Difficulty.NAMES + 1]
		showPick()
	end)
	quick.Activated:Connect(function()
		action:FireServer("quickjoin", soloDifficulty)
	end)
	solo.Activated:Connect(function()
		action:FireServer("solo", soloDifficulty)
	end)

	------------------------------------------------------------ the party
	local panel = panelFrame(326, 450)
	local heading = Theme.label(panel, "", {
		Size = UDim2.new(1, -120, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.UIBold,
		TextSize = 20,
		TextColor3 = C.Bone,
	})
	local lockBadge = Theme.label(panel, "FRIENDS ONLY", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		Size = UDim2.fromOffset(120, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.Fonts.UIBold,
		TextSize = 14,
		TextColor3 = C.Warn,
	})
	-- one row per seat: ready light, name, and for the host Host / Kick
	local seats: { { frame: Frame, dot: TextLabel, name: TextLabel, promote: TextButton, kick: TextButton } } = {}
	local seatIds: { number } = {}
	for i = 1, 4 do
		local f = Theme.frame(panel, {
			Position = UDim2.fromOffset(0, 32 + (i - 1) * 28),
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.4,
		})
		Theme.corner(f, 4)
		local dot = Theme.label(f, "●", {
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.fromOffset(18, 26),
			TextSize = 16,
		})
		local name = Theme.label(f, "", {
			Position = UDim2.fromOffset(28, 0),
			Size = UDim2.new(1, -160, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 16,
		})
		local promote = Theme.button(f, "Host", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -66, 0.5, 0),
			Size = UDim2.fromOffset(58, 22),
			TextSize = 13,
		})
		local kick = Theme.button(f, "Kick", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -2, 0.5, 0),
			Size = UDim2.fromOffset(58, 22),
			TextSize = 13,
			TextColor3 = C.BloodBright,
		})
		promote.Activated:Connect(function()
			action:FireServer("promote", seatIds[i])
		end)
		kick.Activated:Connect(function()
			action:FireServer("kick", seatIds[i])
		end)
		seats[i] = { frame = f, dot = dot, name = name, promote = promote, kick = kick }
	end
	local diffRow = row(panel, 148, 34)
	local buttons: { [string]: TextButton } = {}
	for i, name in Difficulty.NAMES do
		local b = Theme.button(diffRow, name, { Size = UDim2.new(1 / 3, -6, 1, 0), TextSize = 17, LayoutOrder = i })
		b.Activated:Connect(function()
			action:FireServer("difficulty", name)
		end)
		buttons[name] = b
	end
	local info = Theme.label(panel, "", {
		Position = UDim2.fromOffset(0, 186),
		Size = UDim2.new(1, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 14,
		TextColor3 = C.BoneDim,
	})
	local status = Theme.label(panel, "", {
		Position = UDim2.fromOffset(0, 224),
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.UIBold,
		TextSize = 19,
		TextColor3 = C.Bone,
	})
	local actions = row(panel, 258, 38)
	local readyButton = fitted(actions, "", 0.25, 1)
	local start = fitted(actions, "Start now", 0.25, 2)
	local lock = fitted(actions, "", 0.25, 3)
	local leaveButton = fitted(actions, "Leave", 0.25, 4)
	readyButton.Activated:Connect(function()
		action:FireServer("ready")
	end)
	start.Activated:Connect(function()
		action:FireServer("start")
	end)
	lock.Activated:Connect(function()
		action:FireServer("lock")
	end)
	leaveButton.Activated:Connect(function()
		action:FireServer("leave")
	end)

	local noticeToken = 0
	Lobby.notice = function(text: string)
		noticeToken += 1
		local token = noticeToken
		noticeLabel.Text = Lang.t(text)
		Util.tween(noticeLabel, 0.25, { TextTransparency = 0 })
		task.delay(3, function()
			if token == noticeToken then
				Util.tween(noticeLabel, 0.6, { TextTransparency = 1 })
			end
		end)
	end

	local function renderQueue(state: State)
		for i, card in cards do
			local t = state.trucks[i]
			card.button.Visible = t ~= nil
			if t then
				card.title.Text = Lang.f("TRUCK %d  ·  %d/%d", t.truck, t.count, t.max)
				card.line.Text = Lang.t(t.difficulty)
				card.line.TextColor3 = DIFFICULTY_COLORS[t.difficulty] or C.BoneDim
				card.status.Text = truckStatus(t)
				local open = not t.leaving and t.count < t.max
				card.button.AutoButtonColor = open
				card.button.BackgroundColor3 = if open then C.PanelLight else C.Panel
			end
		end
		quick.Active = not state.solo
		solo.Text = Lang.t(if state.solo then "Driving out…" else "Play solo")
		local search = state.search
		searching = search ~= nil
		if search then
			local t = search.elapsed
			find.Text = Lang.f("Searching %d:%02d · cancel", t // 60, t % 60)
			find.BackgroundColor3 = C.Blood
		else
			find.Text = Lang.t("Find players")
			find.BackgroundColor3 = C.PanelLight
		end
	end

	local wasIn = false
	local inParty = false
	local function render(state: State)
		local party = state.party
		inParty = party ~= nil
		queue.Visible = party == nil
		panel.Visible = party ~= nil
		if not party then
			wasIn = false
			renderQueue(state)
			return
		end
		if not wasIn then
			wasIn = true
			Audio.play("Whoosh", nil, 0.4)
		end
		heading.Text = Lang.f("TRUCK %d  ·  %d/%d", party.truck, #party.members, party.max)
		lockBadge.Visible = party.locked
		table.clear(seatIds)
		for i, seat in seats do
			local m = party.members[i]
			seat.frame.Visible = m ~= nil
			if m then
				seatIds[i] = m.id
				seat.dot.TextColor3 = if m.ready then C.Sickly else C.BoneDim
				seat.name.Text = m.name .. (if m.host then Lang.t(" (host)") else "") .. (if m.me then Lang.t(" (you)") else "")
				seat.name.TextColor3 = if m.ready then C.Bone else C.BoneDim
				seat.promote.Visible = party.isHost and not m.me
				seat.kick.Visible = party.isHost and not m.me
			end
		end
		for name, b in buttons do
			local selected = name == party.difficulty
			b.BackgroundColor3 = if selected then C.Blood else C.PanelLight
			b.TextColor3 = if selected then Color3.new(1, 1, 1) else (DIFFICULTY_COLORS[name] or C.Bone)
			b.Active = party.isHost
			b.AutoButtonColor = false
		end
		info.Text = Lang.t(Difficulty.INFO[party.difficulty] or "")
			.. (if party.isHost then "" else Lang.t("  The host picks the difficulty."))
		local readyText = Lang.f("%d/%d ready", party.readyCount, #party.members)
		status.Text = if party.leaving
			then Lang.t("Leaving…")
			elseif party.countdown then Lang.f("Leaving in %ds", party.countdown) .. "  ·  " .. readyText
			else readyText
		readyButton.Text = Lang.t(if party.ready then "Not ready" else "Ready (R)")
		readyButton.BackgroundColor3 = if party.ready then C.PanelLight else C.Blood
		start.Visible = party.isHost and not party.leaving
		lock.Visible = party.isHost and not party.leaving
		lock.Text = Lang.t(if party.locked then "Open to all" else "Friends only")
		readyButton.Visible = not party.leaving
		leaveButton.Visible = not party.leaving
	end

	return {
		render = render,
		toggleReady = function()
			if inParty then
				action:FireServer("ready")
			end
		end,
	}
end

function Lobby.notice(_text: string) end

---------------------------------------------------------------- lobby props

local HOW_TO = table.concat({
	"<b>In the lobby</b>",
	"Step into the bed of a truck to form a party (up to 4). The first one in is the host and picks the difficulty.",
	"Press Ready (R) when you're set: once everyone aboard is ready, the truck leaves. The host can also start at once, make the truck friends only, or kick someone.",
	"No party? Quick join puts you in the best truck here, Find players matches you with players on other servers, and Play solo drives you out alone.",
	"",
	"<b>Controls</b>",
	"<b>WASD</b> move   <b>Mouse</b> look   <b>Shift</b> run   <b>C</b> crouch",
	"<b>E</b> interact / hold to use   <b>F</b> flashlight   <b>Tab</b> inventory   <b>H</b> hint",
	"",
	"<b>Staying alive</b>",
	"- They see your flashlight and hear you run. Crouch to sneak.",
	"- Break line of sight, then hide in wardrobes, closets and lockers. If they see you hide, they drag you out.",
	"- A sedative syringe drops one of them for a while, but only from behind.",
	"- Notes tell you where to go. Batteries recharge the light, bandages heal.",
}, "\n")

local MISSING = table.concat({
	"<b>MISSING - last seen on Hollow Road</b>",
	"",
	"- Dale Whitcomb, 34. Deer hunter. Truck found with the engine running. June 2019.",
	"- The Harlan family (4). Station wagon found empty at the old logging road. August 2021.",
	"- Marisol Vega, 22. Hitchhiking to Pinecrest. October 2022.",
	"- Deputy T. Brandt, Pinecrest Sheriff's Dept. Went to check on a noise complaint. 2023.",
	"",
	"Someone has written across the bottom in red marker: <font color=\"#d6221a\">THEY ARE ALWAYS HUNGRY</font>",
}, "\n")

local CALLS: { { { string } } } = {
	{
		{ "Caller", "…is this the Hollow place? My brother drove out here in June. He never…" },
		{ "Caller", "If you see a white truck, don't stop. Don't let them help you." },
	},
	{ { "Caller", "(slow breathing)" }, { "Caller", "…we can smell the city on you…" } },
	{
		{ "Operator", "Pinecrest County. The number you have dialed is… out of service." },
		{ "Operator", "…out of service… out of… service…" },
	},
	{ { "Caller", "Turn back. The road doesn't go where the map says it goes." } },
}

local VENDING = {
	"It ate my dollar.",
	"Grape soda. Best before 1998.",
	"Something's stuck behind the glass. Is that… a tooth?",
	"A can rolls out. It's warm.",
}

-- Centred reading panel; a Modal close button frees the mouse in first person.
local function readPanel(gui: Frame, heading: string, body: string)
	local old = gui:FindFirstChild("ReadPanel")
	if old then
		old:Destroy()
	end
	local panel = Theme.frame(gui, {
		Name = "ReadPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.8, 0),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
		ZIndex = 30,
	})
	Util.create("UISizeConstraint", { MaxSize = Vector2.new(640, 460), Parent = panel })
	Theme.corner(panel, 6)
	Theme.stroke(panel, C.Blood, 1).Transparency = 0.3
	Theme.padding(panel, 18)
	Theme.label(panel, heading, {
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.Fonts.Title,
		TextSize = 34,
		TextColor3 = C.BloodBright,
		ZIndex = 31,
	})
	Theme.label(panel, body, {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -104),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 16,
		ZIndex = 31,
	})
	local close = Theme.button(panel, "Close", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(140, 40),
		TextSize = 18,
		ZIndex = 31,
	})
	close.Modal = true
	close.Activated:Connect(function()
		panel:Destroy()
	end)
end

local calling = false
local function answerPayphone()
	if calling then
		return
	end
	calling = true
	Audio.play("Radio", nil, 0.5)
	task.spawn(function()
		local call = CALLS[math.random(1, #CALLS)]
		for _, line in call do
			HUD.subtitle(line[1], line[2], 3.4)
			task.wait(3.6)
		end
		HUD.subtitle("You", "…hello? Hello?", 2)
		task.wait(2)
		calling = false
	end)
end

local function vend(machine: Instance?)
	Audio.play("Impact", nil, 0.5, 1.6)
	HUD.subtitle("You", VENDING[math.random(1, #VENDING)], 3)
	if machine and machine:IsA("BasePart") then
		local can = Instance.new("Part")
		can.Shape = Enum.PartType.Cylinder
		can.Size = Vector3.new(0.8, 0.45, 0.45)
		can.Color = Color3.fromRGB(110, 40, 150)
		can.Material = Enum.Material.Metal
		can.CFrame = machine.CFrame * CFrame.new(0.6, -2.6, -1.6)
		can.CanCollide = true
		can.Parent = workspace
		can.AssemblyLinearVelocity = machine.CFrame.LookVector * 4
		task.delay(20, function()
			can:Destroy()
		end)
	end
end

-- the diner jukebox, a knock on room 4, the bell on the billboard (its
-- trophy is the server's)
local JUKEBOX = {
	"♪ A scratchy country record about a farmhouse on Hollow Road where supper never ends. ♪",
	"♪ A crooner, slowed right down, singing about coming home for dinner. ♪",
	"♪ Static, then a hymn, then someone humming along who isn't on the record. ♪",
}
local KNOCKS = {
	"(from inside) …we're full. Go away.",
	"(something scratches at the door, then nothing)",
	"(a woman, very close to the door) Is that you, sweetheart? Supper's nearly ready.",
}

local function playJukebox()
	Audio.play("Radio", nil, 0.4, 0.8)
	HUD.subtitle(Lang.t("Jukebox"), Lang.t(JUKEBOX[math.random(1, #JUKEBOX)]), 5)
end

local function knock()
	Audio.play("Impact", nil, 0.35, 1.3)
	task.delay(1.4, function()
		HUD.subtitle("???", Lang.t(KNOCKS[math.random(1, #KNOCKS)]), 4)
	end)
end

local function ringBell()
	Audio.play("Impact", nil, 0.9, 0.55)
	HUD.subtitle(Lang.t("You"), Lang.t("*CLANG* The whole truck stop heard that."), 3)
end

function Lobby.run()
	Difficulty.watch()
	if Session.mode() ~= "Lobby" then
		Tutorial.start()
		return
	end
	local remotes = ReplicatedStorage:WaitForChild("LobbyRemotes", 30)
	if not remotes then
		return
	end
	local stateRemote = remotes:WaitForChild("State") :: RemoteEvent
	local actionRemote = remotes:WaitForChild("Action") :: RemoteEvent
	local noticeRemote = remotes:WaitForChild("Notice") :: RemoteEvent

	HUD.setVisible(false)
	Effects.setRain(true, false)
	Audio.music("Menu", 0.4)
	-- third person with a free mouse in the lobby (right-drag to look), so the
	-- party panel and the props can be clicked; the game is first person again
	player.CameraMaxZoomDistance = 18
	player.CameraMinZoomDistance = 6
	player.CameraMode = Enum.CameraMode.Classic
	local gui = Theme.screen("Lobby", 20)
	-- clear of the Roblox top bar and notches, laid out for 1300 x 620 (the
	-- nav bar and the title side by side) and
	-- scaled down to fit phones
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local canvas = Theme.canvas(gui, Vector2.new(1300, 620))
	local screen = build(canvas, actionRemote)
	local menu = LobbyMenu.build(canvas)
	local stopWall = LobbyTrophyWall.init()
	local inParty = false
	-- look at the trucks whenever we spawn
	local function faceTrucks()
		task.wait(0.3)
		local lobby = workspace:FindFirstChild("Lobby")
		local zone = lobby and lobby:FindFirstChild("PartyZone2")
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if zone and zone:IsA("BasePart") and head and head:IsA("BasePart") then
			local camera = workspace.CurrentCamera
			local target = Vector3.new(zone.Position.X, head.Position.Y, zone.Position.Z)
			camera.CFrame = CFrame.lookAt(camera.CFrame.Position, target)
		end
	end
	if player.Character then
		task.spawn(faceTrucks)
	end
	local connections = {
		player.CharacterAdded:Connect(faceTrucks),
		ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
			local action = prompt:GetAttribute("LobbyAction")
			if action == "howto" then
				readPanel(canvas, "How to play", HOW_TO)
			elseif action == "missing" then
				readPanel(canvas, "Missing persons", MISSING)
			elseif action == "payphone" then
				answerPayphone()
			elseif action == "vending" then
				vend(prompt.Parent)
			elseif action == "jukebox" then
				playJukebox()
			elseif action == "knock" then
				knock()
			elseif action == "bell" then
				ringBell()
			end
		end),
		stateRemote.OnClientEvent:Connect(function(state: any)
			if typeof(state) ~= "table" or typeof(state.trucks) ~= "table" then
				return
			end
			local party = if typeof(state.party) == "table" then state.party else nil
			-- stepping into a truck closes the menu so the party panel shows
			if party and not inParty then
				menu.close()
			end
			inParty = party ~= nil
			local search = state.search
			screen.render({
				party = party,
				trucks = state.trucks,
				solo = state.solo == true,
				search = if typeof(search) == "table" and typeof(search.elapsed) == "number" then search else nil,
			})
		end),
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and input.KeyCode == Enum.KeyCode.R then
				screen.toggleReady()
			end
		end),
		-- a pattern and what goes in it ("%s is the host now.", name) or a text
		noticeRemote.OnClientEvent:Connect(function(text: any, ...: any)
			if typeof(text) == "string" then
				Lobby.notice(if select("#", ...) > 0 then Lang.f(text, ...) else text)
			end
		end),
	}

	-- only in Studio does a lobby server turn into the game
	while workspace:GetAttribute("Mode") ~= "Game" do
		task.wait(0.25)
	end
	for _, c in connections do
		c:Disconnect()
	end
	menu.destroy()
	stopWall()
	gui:Destroy()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	Effects.setRain(false)
	Audio.music(nil)
	Tutorial.start()
end

return Lobby

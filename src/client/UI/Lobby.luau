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

local Config = require(ReplicatedStorage.Shared.Config)
local Difficulty = require(ReplicatedStorage.Shared.Difficulty)
local Session = require(ReplicatedStorage.Shared.Session)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Effects = require(script.Parent.Parent.Controllers.Effects)
local HUD = require(script.Parent.HUD)
local LobbyMenu = require(script.Parent.LobbyMenu)
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

type PartyState = {
	truck: number,
	members: { { name: string, host: boolean } },
	max: number,
	isHost: boolean,
	difficulty: string,
	countdown: number?,
	leaving: boolean,
}

local function build(gui: Frame, action: RemoteEvent): (state: PartyState?) -> ()
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

	-- party panel (bottom centre)
	local panel = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0.92, 0, 0, 268),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.12,
		Visible = false,
	})
	Util.create("UISizeConstraint", { MaxSize = Vector2.new(440, 268), Parent = panel })
	Theme.corner(panel, 6)
	Theme.stroke(panel, C.Blood, 1).Transparency = 0.4
	Theme.padding(panel, 14)
	local heading = Theme.label(panel, "", {
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.UIBold,
		TextSize = 20,
		TextColor3 = C.Bone,
	})
	local members = Theme.label(panel, "", {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 16,
		TextColor3 = C.BoneDim,
	})
	local row = Theme.frame(panel, {
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
	})
	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		Parent = row,
	})
	local buttons: { [string]: TextButton } = {}
	for _, name in Difficulty.NAMES do
		local b = Theme.button(row, name, { Size = UDim2.new(1 / 3, -6, 1, 0), TextSize = 18 })
		b.Activated:Connect(function()
			action:FireServer("difficulty", name)
		end)
		buttons[name] = b
	end
	local info = Theme.label(panel, "", {
		Position = UDim2.fromOffset(0, 126),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 15,
		TextColor3 = C.BoneDim,
	})
	local countdown = Theme.label(panel, "", {
		Position = UDim2.fromOffset(0, 172),
		Size = UDim2.new(0.55, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.UIBold,
		TextSize = 20,
		TextColor3 = C.Bone,
	})
	local start = Theme.button(panel, "Start now", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 168),
		Size = UDim2.fromOffset(150, 38),
		TextSize = 18,
	})
	start.Activated:Connect(function()
		action:FireServer("start")
	end)
	Theme.label(panel, "Step out of the truck to leave the party.", {
		Position = UDim2.fromOffset(0, 212),
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		TextColor3 = C.BoneDim,
		Font = Theme.Fonts.UI,
	})

	local noticeToken = 0
	Lobby.notice = function(text: string)
		noticeToken += 1
		local token = noticeToken
		noticeLabel.Text = text
		Util.tween(noticeLabel, 0.25, { TextTransparency = 0 })
		task.delay(3, function()
			if token == noticeToken then
				Util.tween(noticeLabel, 0.6, { TextTransparency = 1 })
			end
		end)
	end

	local wasIn = false
	return function(state: PartyState?)
		panel.Visible = state ~= nil
		if not state then
			wasIn = false
			return
		end
		if not wasIn then
			wasIn = true
			Audio.play("Whoosh", nil, 0.4)
		end
		heading.Text = string.format("TRUCK %d  ·  %d/%d", state.truck, #state.members, state.max)
		local names = {}
		for _, m in state.members do
			table.insert(names, if m.host then m.name .. " (host)" else m.name)
		end
		members.Text = table.concat(names, "   ")
		for name, b in buttons do
			local selected = name == state.difficulty
			b.BackgroundColor3 = if selected then C.Blood else C.PanelLight
			b.TextColor3 = if selected then Color3.new(1, 1, 1) else (DIFFICULTY_COLORS[name] or C.Bone)
			b.Active = state.isHost
			b.AutoButtonColor = false
		end
		info.Text = (Difficulty.INFO[state.difficulty] or "")
			.. (if state.isHost then "" else "  The host picks the difficulty.")
		countdown.Text = if state.leaving
			then "Leaving…"
			elseif state.countdown then string.format("Leaving in %ds", state.countdown)
			else ""
		start.Visible = state.isHost and not state.leaving
	end
end

function Lobby.notice(_text: string) end

---------------------------------------------------------------- lobby props

local HOW_TO = table.concat({
	"<b>In the lobby</b>",
	"Step into the bed of a truck to form a party (up to 4). The first one in is the host and picks the difficulty.",
	"When the countdown ends (or the host presses Start now) the truck drives your party into the woods.",
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
	-- clear of the Roblox top bar and notches, laid out for 1000 x 620 and
	-- scaled down to fit phones
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local canvas = Theme.canvas(gui, Vector2.new(1000, 620))
	local render = build(canvas, actionRemote)
	local menu = LobbyMenu.build(canvas)
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
			end
		end),
		stateRemote.OnClientEvent:Connect(function(state: any)
			local party = if typeof(state) == "table" then state else nil
			-- stepping into a truck closes the menu so the party panel shows
			if party and not inParty then
				menu.close()
			end
			inParty = party ~= nil
			render(party)
		end),
		noticeRemote.OnClientEvent:Connect(function(text: any)
			if typeof(text) == "string" then
				Lobby.notice(text)
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
	gui:Destroy()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	Effects.setRain(false)
	Audio.music(nil)
	Tutorial.start()
end

return Lobby

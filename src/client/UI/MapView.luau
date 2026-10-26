--!strict
-- The map: Hollow Road on an old county map (M, or MAP on a phone). Every
-- place you can go (shared Config.Sites, the last act's only once you get
-- there), you as an arrow pointing where you look, your party, and red marks
-- on what to do next, the same targets as a hint but with no wait (none on
-- Nightmare, where you find your own way). For new players finding their
-- feet; nothing else stops while it's open.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Theme = require(script.Parent.Theme)

local MapView = {}

local C = Theme.Colors
local me = Players.LocalPlayer

-- what each site is called on the map; the last act's appear only then
local NAMES: { [string]: string } = {
	House = "The farmhouse",
	Crash = "Your car",
	Truck = "The old truck",
	Barn = "Old barn",
	Camp = "Hunter's camp",
	Trailer = "Doctor's trailer",
	Cemetery = "Cemetery",
	Wreck = "Wreck",
	Station = "Ranger station",
	Tower = "Lookout tower",
	Shed = "Tool shed",
	Helipad = "Helipad",
	HeliCrash = "Helicopter crash",
	Plant = "Hollow Meats",
	Church = "Pinecrest",
}
local LATE: { [string]: boolean } = { HeliCrash = true, Plant = true, Church = true }
local LATE_STAGES: { [string]: boolean } = {
	Downed = true,
	Wreck = true,
	Plant = true,
	Church = true,
	LastStand = true,
	Getaway = true,
	Ending = true,
}

-- the county, in world X / Z
local MIN = Vector2.new(-700, -650)
local MAX = Vector2.new(720, 620)
local SIZE = 520

local gui: ScreenGui? = nil
local paper: Frame
local you: TextLabel
local siteDots: { [string]: Frame } = {}
local others: { [Player]: TextLabel } = {}
local targets: { Frame } = {}
local open = false
local lastAsk = 0

local function toMap(x: number, z: number): UDim2
	local u = (x - MIN.X) / (MAX.X - MIN.X)
	local v = (z - MIN.Y) / (MAX.Y - MIN.Y)
	return UDim2.fromScale(math.clamp(u, 0, 1), math.clamp(v, 0, 1))
end

local function dot(parent: Instance, color: Color3, size: number): Frame
	local f = Theme.frame(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		ZIndex = 52,
	})
	Theme.corner(f, math.ceil(size / 2))
	return f
end

local function build()
	local g = Theme.screen("Map", 45)
	g.Enabled = false
	gui = g
	local shade = Theme.frame(g, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, ZIndex = 50 })
	shade.Active = true
	local holder = Theme.frame(g, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(SIZE + 40, SIZE + 90),
		BackgroundColor3 = Color3.fromRGB(70, 58, 42),
		ZIndex = 50,
	})
	Theme.corner(holder, 6)
	Util.create("UIAspectRatioConstraint", { AspectRatio = (SIZE + 40) / (SIZE + 90), Parent = holder })
	Util.create("UISizeConstraint", { MaxSize = Vector2.new(SIZE + 40, SIZE + 90), Parent = holder })
	Theme.label(holder, "HOLLOW ROAD  ·  PINECREST COUNTY", {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Fonts.Title,
		TextSize = 26,
		TextColor3 = Color3.fromRGB(230, 214, 180),
		ZIndex = 51,
	})
	paper = Theme.frame(holder, {
		Position = UDim2.new(0, 20, 0, 40),
		Size = UDim2.new(1, -40, 1, -80),
		BackgroundColor3 = Color3.fromRGB(196, 178, 140),
		ZIndex = 51,
		ClipsDescendants = true,
	})
	Theme.corner(paper, 3)
	-- the lake, as a blot of blue
	local lake = Config.Lake
	local blot = dot(paper, Color3.fromRGB(96, 116, 120), 1)
	blot.Position = toMap(lake.pos.X, lake.pos.Y)
	blot.Size = UDim2.fromScale(lake.radius * 2 / (MAX.X - MIN.X), lake.radius * 2 / (MAX.Y - MIN.Y))
	blot.BackgroundTransparency = 0.3
	blot.ZIndex = 51
	for name, site in Config.Sites do
		local label = NAMES[name]
		if label then
			local d = dot(paper, Color3.fromRGB(80, 62, 44), 9)
			d.Position = toMap(site.pos.X, site.pos.Y)
			Theme.label(d, label, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 1, 1),
				Size = UDim2.fromOffset(140, 16),
				TextSize = 13,
				Font = Theme.Fonts.UIBold,
				TextColor3 = Color3.fromRGB(56, 40, 28),
				ZIndex = 53,
			})
			siteDots[name] = d
		end
	end
	you = Theme.label(paper, "▲", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(22, 22),
		TextSize = 22,
		Font = Theme.Fonts.UIBold,
		TextColor3 = C.Blood,
		ZIndex = 56,
	})
	local legend = Theme.label(holder, "▲ You    ● Your party    ✕ Where to go    (M to close)", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -10),
		Size = UDim2.new(1, -40, 0, 24),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(230, 214, 180),
		ZIndex = 51,
	})
	legend.TextScaled = true
end

local function showTargets(list: { Vector3 })
	for _, t in targets do
		t:Destroy()
	end
	table.clear(targets)
	for _, pos in list do
		local x = Theme.label(paper, "✕", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = toMap(pos.X, pos.Z),
			Size = UDim2.fromOffset(22, 22),
			TextSize = 22,
			Font = Theme.Fonts.UIBold,
			TextColor3 = C.BloodBright,
			ZIndex = 55,
		}) :: any
		table.insert(targets, x)
	end
end

local function refresh()
	local late = LATE_STAGES[workspace:GetAttribute("Stage") or ""] == true
	for name, d in siteDots do
		d.Visible = not LATE[name] or late
	end
	local character = me.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		you.Position = toMap(root.Position.X, root.Position.Z)
		-- the arrow points where the camera looks (north is up: -Z)
		local look = workspace.CurrentCamera.CFrame.LookVector
		you.Rotation = math.deg(math.atan2(look.X, -look.Z))
	end
	for _, other in Players:GetPlayers() do
		if other ~= me then
			local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			local mark = others[other]
			if not mark then
				mark = Theme.label(paper, "●", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(16, 16),
					TextSize = 16,
					TextColor3 = Color3.fromRGB(40, 70, 120),
					ZIndex = 54,
				})
				others[other] = mark
			end
			local m = mark :: TextLabel
			m.Visible = r ~= nil and r:IsA("BasePart")
			if r and r:IsA("BasePart") then
				m.Position = toMap(r.Position.X, r.Position.Z)
			end
		end
	end
	-- what to do next, from the server (every couple of seconds)
	if os.clock() - lastAsk > 2 then
		lastAsk = os.clock()
		Net.event("RequestMap"):FireServer()
	end
end

function MapView.toggle(on: boolean?)
	local g = gui
	if not g then
		return -- the lobby: no map
	end
	open = if on == nil then not open else on
	g.Enabled = open
	Audio.play("PageTurn", nil, 0.5)
	if open then
		lastAsk = 0
		refresh()
	end
end

function MapView.init()
	build()
	Net.event("MapTargets").OnClientEvent:Connect(function(list: any)
		if typeof(list) == "table" then
			showTargets(list)
		end
	end)
	ContextActionService:BindAction("Map", function(_, state)
		if state == Enum.UserInputState.Begin then
			MapView.toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonSelect)
	RunService.RenderStepped:Connect(function()
		if open then
			refresh()
		end
	end)
	Players.PlayerRemoving:Connect(function(other)
		local mark = others[other]
		if mark then
			mark:Destroy()
			others[other] = nil
		end
	end)end

return MapView

--!strict
-- Keeping track of the rest of your party in the woods. A faint name and
-- distance over each teammate, shown only when they're far off or out of
-- sight (close by you can see them, and the dark should stay dark), and a
-- warning when one of them is caught. Settings > Party markers turns the
-- names off; the warnings stay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Lang = require(ReplicatedStorage.Shared.Lang)
local Settings = require(script.Parent.Parent.Controllers.Settings)
local HUD = require(script.Parent.HUD)
local Theme = require(script.Parent.Theme)

local PartyMarkers = {}

local C = Theme.Colors
local NEAR = 18 -- closer than this and in sight: no marker
local FAR = 400

type Marker = { gui: BillboardGui, name: TextLabel, dist: TextLabel, caught: boolean }

local markers: { [Player]: Marker } = {}
local me = Players.LocalPlayer

local function make(player: Player): Marker
	local gui = Instance.new("BillboardGui")
	gui.Name = "PartyMarker"
	gui.Size = UDim2.fromOffset(140, 40)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = FAR
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local function label(y: number, size: number, bold: boolean): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, size + 4)
		l.Font = if bold then Theme.Fonts.UIBold else Theme.Fonts.UI
		l.TextSize = size
		l.TextColor3 = C.Bone
		l.TextTransparency = 0.3
		l.TextStrokeTransparency = 0.6
		l.Parent = gui
		return l
	end
	local name = label(0, 15, true)
	name.Text = player.DisplayName
	-- a player's name: not for translating, nor for Roblox to capture
	name.AutoLocalize = false
	name:SetAttribute("NoTranslate", true)
	local dist = label(18, 13, false)
	gui.Parent = me:WaitForChild("PlayerGui")
	return { gui = gui, name = name, dist = dist, caught = false }
end

local function watch(player: Player)
	if player == me then
		return
	end
	local marker = make(player)
	markers[player] = marker
	local function onCharacter(character: Model)
		marker.caught = false
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				marker.caught = true
				HUD.toast(Lang.f("%s was caught.", player.DisplayName), "warn")
			end)
		end
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

local function step()
	local camera = workspace.CurrentCamera
	local myChar = me.Character
	local show = Settings.get("partyMarkers") >= 0.5
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for player, marker in markers do
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		if not (show and head and head:IsA("BasePart")) then
			marker.gui.Enabled = false
			continue
		end
		marker.gui.Adornee = head
		local from = camera.CFrame.Position
		local offset = head.Position - from
		local distance = offset.Magnitude
		local inSight = false
		if distance < NEAR then
			local ignore: { Instance } = { head.Parent :: Instance }
			if myChar then
				table.insert(ignore, myChar)
			end
			params.FilterDescendantsInstances = ignore
			inSight = workspace:Raycast(from, offset, params) == nil
		end
		marker.gui.Enabled = not inSight or marker.caught
		marker.dist.Text = if marker.caught then Lang.t("Caught") else string.format("%dm", math.round(distance * 0.28))
		marker.name.TextColor3 = if marker.caught then C.BloodBright else C.Bone
	end
end

-- Lives left this run, top left (nothing on Easy, where there's no limit).
local function livesCounter()
	local gui = Theme.screen("Lives", 4)
	local label = Theme.label(gui, "", {
		Position = UDim2.fromOffset(18, 18),
		Size = UDim2.fromOffset(220, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.UIBold,
		TextSize = 18,
		TextColor3 = C.BloodBright,
		TextStrokeTransparency = 0.5,
	})
	local function refresh()
		local lives = me:GetAttribute("Lives")
		local shown = typeof(lives) == "number" and lives >= 0 and me:GetAttribute("InCutscene") ~= true
		label.Visible = shown
		if shown then
			label.Text = Lang.f("Lives: %d", lives :: number)
		end
	end
	me:GetAttributeChangedSignal("Lives"):Connect(refresh)
	me:GetAttributeChangedSignal("InCutscene"):Connect(refresh)
	refresh()
end

-- Game servers only (Main calls it once the lobby is behind us).
function PartyMarkers.init()
	livesCounter()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local marker = markers[player]
		if marker then
			marker.gui:Destroy()
			markers[player] = nil
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return PartyMarkers

--!strict
-- The diner's Wall of Fame in the lobby. The server (Lobby.luau) puts up one
-- frame per achievement and polaroid, tagged TrophyFrame; this shows on
-- each whether you have it, from your profile's attributes (Ach_<id>,
-- Pol_<id>): a gold plaque or a photo once earned, a dark empty frame
-- until then.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trophies = require(ReplicatedStorage.Shared.Trophies)
local Lang = require(ReplicatedStorage.Shared.Lang)

local LobbyTrophyWall = {}

local player = Players.LocalPlayer
local rgb = Color3.fromRGB

local function dress(frame: Instance, conns: { any })
	local kind, id = frame:GetAttribute("TrophyKind"), frame:GetAttribute("TrophyId")
	if not frame:IsA("BasePart") or typeof(kind) ~= "string" or typeof(id) ~= "string" then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(160, 160)
	gui.LightInfluence = 0.4
	gui.Brightness = 1.3
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(10, 10)
	label.Size = UDim2.new(1, -20, 1, -20)
	label.Font = Enum.Font.SpecialElite
	label.TextScaled = true
	label.TextWrapped = true
	label.BorderSizePixel = 0
	label.Parent = gui
	gui.Parent = frame

	local key = kind .. "_" .. id
	local function refresh()
		local got = player:GetAttribute(key) == true
		if kind == "Ach" then
			local a = Trophies.Achievements[id]
			local name = if a then Lang.t(a.name) else id
			label.Text = if got then "★\n" .. name elseif a and a.secret then "?" else name
			label.BackgroundColor3 = if got then rgb(196, 150, 60) else rgb(30, 26, 22)
			label.TextColor3 = if got then rgb(40, 26, 12) else rgb(110, 100, 86)
		else
			local p = Trophies.Polaroids[id]
			label.Text = if got and p then Lang.t(p.title) else "?"
			label.BackgroundColor3 = if got then rgb(236, 230, 214) else rgb(30, 26, 22)
			label.TextColor3 = if got then rgb(50, 40, 34) else rgb(110, 100, 86)
		end
	end
	refresh()
	table.insert(conns, player:GetAttributeChangedSignal(key):Connect(refresh))
	table.insert(conns, Lang.Changed:Connect(refresh))
end

-- Dresses every frame there is and any that arrive; returns a cleanup.
function LobbyTrophyWall.init(): () -> ()
	local conns: { any } = {}
	for _, frame in CollectionService:GetTagged("TrophyFrame") do
		dress(frame, conns)
	end
	table.insert(conns, CollectionService:GetInstanceAddedSignal("TrophyFrame"):Connect(function(frame)
		dress(frame, conns)
	end))
	return function()
		for _, c in conns do
			c:Disconnect()
		end
	end
end

return LobbyTrophyWall

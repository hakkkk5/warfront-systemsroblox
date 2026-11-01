--!strict
-- Where to go next, always: the server puts each player's nearest objective
-- on them (GuideTarget, the same places a hint shows; none on Nightmare).
-- On screen it's a small diamond over the spot with the distance; off
-- screen or behind you, an arrow on the edge of the screen pointing the way.
-- Settings > Guide arrow turns it off.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Settings = require(script.Parent.Parent.Controllers.Settings)
local HUD = require(script.Parent.HUD)
local Theme = require(script.Parent.Theme)

local GuideArrow = {}

local C = Theme.Colors
local player = Players.LocalPlayer
local AMBER = Color3.fromRGB(255, 196, 92)
local MARGIN = 56 -- the edge arrow keeps this far in from the screen edge
local ARRIVED = 7 -- studs: close enough, the arrow goes

local function distanceLabel(parent: Instance): TextLabel
	return Theme.label(parent, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(70, 16),
		Font = Theme.Fonts.UIBold,
		TextSize = 13,
		TextColor3 = C.Bone,
		TextStrokeTransparency = 0.35,
	})
end

function GuideArrow.init()
	local gui = Theme.screen("Guide", 6)

	-- on screen: a diamond over the spot
	local pin = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = AMBER,
		BackgroundTransparency = 0.15,
		Rotation = 45,
		Visible = false,
	})
	Theme.stroke(pin, Color3.new(0, 0, 0), 1.5).Transparency = 0.3
	local pinHolder = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local pinDist = distanceLabel(pinHolder)

	-- off screen: an arrow on the edge, pointing the way
	local edge = Theme.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(40, 40),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local arrow = Theme.label(edge, "▲", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Fonts.UIBold,
		TextSize = 30,
		TextColor3 = AMBER,
		TextStrokeTransparency = 0.25,
	})
	local edgeDist = distanceLabel(edge)

	local edgePos = Vector2.zero
	RunService.RenderStepped:Connect(function(dt: number)
		local target = player:GetAttribute("GuideTarget")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local show = typeof(target) == "Vector3"
			and root ~= nil
			and root:IsA("BasePart")
			and HUD.visible
			and player:GetAttribute("InCutscene") ~= true
			and Settings.get("guideArrow") >= 0.5
		if not show then
			pin.Visible, pinHolder.Visible, edge.Visible = false, false, false
			return
		end
		local spot = (target :: Vector3) + Vector3.new(0, 2, 0)
		local distance = ((root :: BasePart).Position - (target :: Vector3)).Magnitude
		if distance < ARRIVED then
			pin.Visible, pinHolder.Visible, edge.Visible = false, false, false
			return
		end
		local text = string.format("%dm", math.floor(distance * 0.28))
		local camera = workspace.CurrentCamera
		local size = camera.ViewportSize
		local point, inFront = camera:WorldToViewportPoint(spot)
		local onScreen = inFront and point.X > MARGIN and point.X < size.X - MARGIN and point.Y > MARGIN and point.Y < size.Y - MARGIN
		-- breathes a little so the eye finds it
		local alpha = 0.1 + (math.sin(os.clock() * 3) + 1) * 0.08

		if onScreen then
			pin.Position = UDim2.fromOffset(point.X, point.Y)
			pinHolder.Position = pin.Position
			pin.BackgroundTransparency = alpha
			pinDist.Text = text
			pin.Visible, pinHolder.Visible, edge.Visible = true, true, false
			return
		end

		-- which way, from where the camera looks (behind you included)
		local rel = camera.CFrame:PointToObjectSpace(spot)
		local dir = Vector2.new(rel.X, -rel.Y)
		if dir.Magnitude < 1e-3 then
			dir = Vector2.new(0, 1)
		end
		dir = dir.Unit
		local half = size / 2
		local reach = math.min((half.X - MARGIN) / math.max(math.abs(dir.X), 1e-3), (half.Y - MARGIN) / math.max(math.abs(dir.Y), 1e-3))
		local want = half + dir * reach
		edgePos = if edge.Visible then edgePos:Lerp(want, math.min(1, dt * 12)) else want
		edge.Position = UDim2.fromOffset(edgePos.X, edgePos.Y)
		arrow.Rotation = math.deg(math.atan2(dir.Y, dir.X)) + 90
		arrow.TextTransparency = alpha
		edgeDist.Text = text
		pin.Visible, pinHolder.Visible, edge.Visible = false, false, true
	end)
end

return GuideArrow

--!strict
-- The view from inside a wardrobe / locker: dark slats, slow breathing,
-- limited look-around. Press E / Space to step out.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local CameraController = require(script.Parent.CameraController)
local Theme = require(script.Parent.Parent.UI.Theme)

local HidingView = {}

local camera = workspace.CurrentCamera
local player = Players.LocalPlayer
local gui: ScreenGui
local hiding = false
local baseCF = CFrame.new()
local yaw, pitch = 0, 0

local function leave()
	if hiding then
		Net.event("LeaveHiding"):FireServer()
	end
end

local slats: Frame
local leaves: Frame

local function setHiding(on: boolean, inside: CFrame?, kind: string?)
	hiding = on
	gui.Enabled = on
	slats.Visible = kind ~= "bush"
	leaves.Visible = kind == "bush"
	if on and inside then
		-- just past the door panels so the room is visible between the slats
		baseCF = inside * CFrame.new(0, 2, -1.8)
		yaw, pitch = 0, 0
		CameraController.setEnabled(false)
		camera.CameraType = Enum.CameraType.Scriptable
		ContextActionService:BindActionAtPriority("LeaveHiding", function(_, state)
			if state == Enum.UserInputState.Begin then
				leave()
			end
			return Enum.ContextActionResult.Sink
		end, true, 2500, Enum.KeyCode.E, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
		ContextActionService:SetTitle("LeaveHiding", "Leave")
	else
		ContextActionService:UnbindAction("LeaveHiding")
		if not player:GetAttribute("InCutscene") then
			CameraController.setEnabled(true)
		end
	end
end

function HidingView.init()
	gui = Theme.screen("Hiding", 7)
	gui.Enabled = false
	-- slats you peek through (wardrobes, closets, lockers)
	slats = Theme.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	-- leaves crowding the edges, a gap in the middle (bushes)
	leaves = Theme.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	local rng = Random.new(7)
	for _ = 1, 26 do
		local edge = rng:NextInteger(1, 4)
		local along = rng:NextNumber()
		local x = if edge == 1 then -0.05 elseif edge == 2 then 1.05 else along
		local y = if edge == 3 then -0.05 elseif edge == 4 then 1.05 else along
		local size = rng:NextNumber(0.28, 0.5)
		local leaf = Theme.frame(leaves, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(size, size * 1.4),
			BackgroundColor3 = Color3.fromRGB(rng:NextInteger(12, 22), rng:NextInteger(24, 36), rng:NextInteger(12, 20)),
			BackgroundTransparency = rng:NextNumber(0, 0.15),
			Rotation = rng:NextNumber(0, 360),
		})
		Theme.corner(leaf, 400)
	end
	for i = 0, 7 do
		local slat = Theme.frame(slats, {
			Position = UDim2.fromScale(0, i / 8),
			Size = UDim2.new(1, 0, 1 / 8, -14),
			BackgroundColor3 = Color3.fromRGB(14, 10, 8),
			BackgroundTransparency = 0.04,
		})
		Util.create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(30, 22, 16), Color3.fromRGB(6, 4, 3)),
			Parent = slat,
		})
	end
	Theme.vignette(gui, Color3.new(0, 0, 0), 0.45, 5)
	Theme.label(gui, "Hiding...  [E] step out   Hold your breath.", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(500, 24),
		TextSize = 17,
		TextColor3 = Theme.Colors.BoneDim,
		ZIndex = 10,
	})

	Net.event("Hiding").OnClientEvent:Connect(setHiding)

	RunService.RenderStepped:Connect(function()
		if not hiding then
			return
		end
		local delta = UserInputService:GetMouseDelta()
		yaw = math.clamp(yaw - delta.X * 0.003, -0.5, 0.5)
		pitch = math.clamp(pitch - delta.Y * 0.003, -0.25, 0.25)
		local breathe = math.sin(os.clock() * 1.1) * 0.03
		camera.CFrame = baseCF * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch + breathe * 0.2, 0, 0) * CFrame.new(0, breathe, 0)
		camera.FieldOfView = 60
	end)
end

return HidingView

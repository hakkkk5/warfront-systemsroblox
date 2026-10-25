--!strict
-- Shared look for every screen: colours, fonts and small UI builders.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Shared.Util)

local Theme = {}

Theme.Colors = {
	Ink = Color3.fromRGB(8, 7, 7),
	Panel = Color3.fromRGB(16, 13, 12),
	PanelLight = Color3.fromRGB(30, 25, 22),
	Bone = Color3.fromRGB(226, 214, 190),
	BoneDim = Color3.fromRGB(150, 140, 124),
	Blood = Color3.fromRGB(150, 16, 14),
	BloodBright = Color3.fromRGB(214, 34, 26),
	Rust = Color3.fromRGB(176, 96, 52),
	Sickly = Color3.fromRGB(150, 220, 120),
	Warn = Color3.fromRGB(230, 170, 60),
}

Theme.Fonts = {
	Title = Enum.Font.Creepster,
	Type = Enum.Font.SpecialElite,
	Hand = Enum.Font.IndieFlower,
	UI = Enum.Font.GothamMedium,
	UIBold = Enum.Font.GothamBlack,
}

local playerGui: PlayerGui? = nil

function Theme.playerGui(): PlayerGui
	if not playerGui then
		playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	end
	return playerGui :: PlayerGui
end

function Theme.screen(name: string, order: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = order
	gui.Parent = Theme.playerGui()
	return gui
end

function Theme.frame(parent: Instance, props: { [string]: any }?): Frame
	local f = Util.create("Frame", {
		BackgroundColor3 = Theme.Colors.Panel,
		BorderSizePixel = 0,
	})
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	f.Parent = parent
	return f
end

function Theme.label(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local l = Util.create("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Theme.Colors.Bone,
		Font = Theme.Fonts.Type,
		TextSize = 18,
		TextWrapped = true,
		RichText = true,
	})
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	l.Parent = parent
	return l
end

function Theme.button(parent: Instance, text: string, props: { [string]: any }?): TextButton
	local b = Util.create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.PanelLight,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Theme.Colors.Bone,
		Font = Theme.Fonts.Type,
		TextSize = 22,
	})
	if props then
		for k, v in props do
			(b :: any)[k] = v
		end
	end
	Theme.corner(b, 4)
	local stroke = Theme.stroke(b, Theme.Colors.Blood, 1)
	stroke.Transparency = 0.5
	b.MouseEnter:Connect(function()
		Util.tween(b, 0.15, { BackgroundColor3 = Theme.Colors.Blood, TextColor3 = Color3.new(1, 1, 1) })
	end)
	b.MouseLeave:Connect(function()
		Util.tween(b, 0.2, { BackgroundColor3 = Theme.Colors.PanelLight, TextColor3 = Theme.Colors.Bone })
	end)
	b.Parent = parent
	return b
end

function Theme.corner(parent: Instance, radius: number): UICorner
	return Util.create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

function Theme.stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	return Util.create("UIStroke", {
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Theme.padding(parent: Instance, px: number)
	Util.create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

-- Fits UI laid out for `design` (pixels) on small screens such as phones: a
-- UIScale that shrinks `object` until `design` fits its ScreenGui (it never
-- grows it). With `canvas`, the object is a full-screen frame that is also
-- resized by 1 / scale, so its children lay out on a virtual screen at least
-- `design` big that still covers the real one. Parent the object first.
function Theme.autoScale(object: GuiObject, design: Vector2, canvas: boolean?): UIScale
	local scale = Util.create("UIScale", { Parent = object })
	local screen = object:FindFirstAncestorWhichIsA("LayerCollector") :: ScreenGui
	local camera = workspace.CurrentCamera
	local function update()
		-- a disabled ScreenGui keeps a stale size, so use the viewport then
		local size = if screen.Enabled then screen.AbsoluteSize else camera.ViewportSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local s = math.clamp(math.min(size.X / design.X, size.Y / design.Y), 0.5, 1)
		scale.Scale = s
		if canvas then
			object.Size = UDim2.fromScale(1 / s, 1 / s)
		end
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	screen:GetPropertyChangedSignal("Enabled"):Connect(update)
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
	return scale
end

-- A full-screen, see-through frame scaled with Theme.autoScale(canvas).
function Theme.canvas(parent: Instance, design: Vector2): Frame
	local canvas = Theme.frame(parent, {
		Name = "Canvas",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	Theme.autoScale(canvas, design, true)
	return canvas
end

-- Soft vignette made from four edge gradients (no image assets needed).
function Theme.vignette(parent: Instance, color: Color3, depth: number, zindex: number): Frame
	local holder = Theme.frame(parent, {
		Name = "Vignette",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zindex,
	})
	type Edge = { size: UDim2, pos: UDim2, rot: number }
	local edges: { Edge } = {
		{ size = UDim2.fromScale(1, depth), pos = UDim2.fromScale(0, 0), rot = 90 },
		{ size = UDim2.fromScale(1, depth), pos = UDim2.fromScale(0, 1 - depth), rot = -90 },
		{ size = UDim2.fromScale(depth * 0.6, 1), pos = UDim2.fromScale(0, 0), rot = 0 },
		{ size = UDim2.fromScale(depth * 0.6, 1), pos = UDim2.fromScale(1 - depth * 0.6, 0), rot = 180 },
	}
	for _, e in edges do
		local f = Theme.frame(holder, {
			Size = e.size,
			Position = e.pos,
			BackgroundColor3 = color,
			BackgroundTransparency = 0,
			ZIndex = zindex,
		})
		Util.create("UIGradient", {
			Rotation = e.rot,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.55, 0.65),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = f,
		})
	end
	return holder
end

-- Rotating 3D preview of an item model inside a ViewportFrame.
function Theme.viewport(parent: Instance, model: Model?, props: { [string]: any }?): ViewportFrame
	local vp = Util.create("ViewportFrame", {
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(120, 110, 100),
		LightColor = Color3.fromRGB(255, 230, 200),
		LightDirection = Vector3.new(-1, -1.4, -0.6),
	})
	if props then
		for k, v in props do
			(vp :: any)[k] = v
		end
	end
	vp.Parent = parent
	if model then
		local clone = model:Clone()
		clone:PivotTo(CFrame.new())
		clone.Parent = vp
		local cf, size = clone:GetBoundingBox()
		local radius = size.Magnitude / 2
		local camera = Instance.new("Camera")
		camera.FieldOfView = 30
		local distance = radius / math.tan(math.rad(15)) * 1.05
		camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0.6, 0.45, 0.75).Unit * distance, cf.Position)
		camera.Parent = vp
		vp.CurrentCamera = camera
		vp:SetAttribute("Center", cf.Position)
		vp:SetAttribute("Distance", distance)
	end
	return vp
end

return Theme

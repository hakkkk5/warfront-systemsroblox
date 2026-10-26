--!strict
-- Shows the game's text in the player's language (shared Lang) wherever it
-- appears: every TextLabel and TextButton on the screens (PlayerGui) and on
-- signs in the world (SurfaceGui / BillboardGui in the workspace). The
-- English a label was given is kept in its LangSource attribute, so
-- changing the language later swaps every label again. Only texts a table
-- knows are touched; text put together from pieces (subtitles, toasts,
-- objectives) is translated where it is put together (HUD).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lang = require(ReplicatedStorage.Shared.Lang)

local Localizer = {}

local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local setting: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function update(obj: TextLabel | TextButton)
	if setting[obj] then
		return
	end
	local source = obj:GetAttribute("LangSource")
	local text = obj.Text
	if typeof(source) ~= "string" or (text ~= source and text ~= Lang.t(source)) then
		-- the game gave it a new text: only keep track if we can translate it
		if not Lang.has(text) then
			if source ~= nil then
				obj:SetAttribute("LangSource", nil)
			end
			return
		end
		source = text
		obj:SetAttribute("LangSource", text)
	end
	local want = Lang.t(source :: string)
	if obj.Text ~= want then
		setting[obj] = true
		(obj :: any).Text = want
		setting[obj] = nil
	end
end

local function hook(obj: Instance)
	if hooked[obj] or not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then
		return
	end
	-- world text only on signs (SurfaceGui / BillboardGui)
	if obj:IsDescendantOf(workspace) and not obj:FindFirstAncestorWhichIsA("LayerCollector") then
		return
	end
	hooked[obj] = true
	local label = obj :: TextLabel
	label:GetPropertyChangedSignal("Text"):Connect(function()
		update(label)
	end)
	update(label)
end

function Localizer.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, root in { playerGui, workspace } do
		for _, d in root:GetDescendants() do
			hook(d)
		end
		root.DescendantAdded:Connect(hook)
	end
	Lang.Changed:Connect(function()
		for obj in hooked do
			if obj.Parent then
				update(obj :: any)
			end
		end
	end)
end

return Localizer

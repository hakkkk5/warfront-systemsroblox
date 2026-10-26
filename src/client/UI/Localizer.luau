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
local Net = require(ReplicatedStorage.Shared.Net)

local Localizer = {}

local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local setting: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function update(obj: TextLabel | TextButton)
	-- names and the like: never translated, never captured by Roblox
	local target: any = obj
	if setting[obj] then
		return
	elseif obj:GetAttribute("NoTranslate") == true then
		target.AutoLocalize = false
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
			-- text we put together ourselves (already in our language) or
			-- English: Roblox may translate only the English
			target.AutoLocalize = Lang.code() == "en" or not Lang.hasTable()
			return
		end
		source = text
		obj:SetAttribute("LangSource", text)
	end
	local want = Lang.t(source :: string)
	-- Roblox's automatic translation covers every language without a table
	-- here; where this table translates a label, Roblox must leave it be
	-- (and not capture the French as new English source text)
	target.AutoLocalize = want == source
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

	-- Machine translation (server Systems/Translate): what the current
	-- language is missing goes to the server in batches; what comes back
	-- goes into Lang, which refreshes every label.
	local outbox: { [string]: { string } } = {}
	Lang.Requested:Connect(function(code: string, key: string)
		local list = outbox[code]
		if not list then
			list = {}
			outbox[code] = list
		end
		table.insert(list, key)
	end)
	Net.event("Translations").OnClientEvent:Connect(function(code: any, map: any)
		if typeof(code) == "string" and typeof(map) == "table" then
			Lang.addTranslations(code, map)
		end
	end)
	-- a language seen for the first time: everything the server already has
	-- for it, and (without a table of our own) every line the game knows,
	-- translated in the background
	local warmed: { [string]: boolean } = {}
	local function warm()
		local code = Lang.code()
		if code == "en" or warmed[code] then
			return
		end
		warmed[code] = true
		Net.event("TranslateRequest"):FireServer(code, nil, false)
		if not Lang.hasTable() then
			local keys = {}
			for _, line in Lang.knownLines() do
				table.insert(keys, (Lang.key(line)))
			end
			for i = 1, #keys, 50 do
				Net.event("TranslateRequest"):FireServer(code, table.move(keys, i, math.min(i + 49, #keys), 1, {}), true)
			end
		end
	end
	Lang.Changed:Connect(warm)
	warm()
	task.spawn(function()
		while true do
			task.wait(0.4)
			for code, keys in outbox do
				for i = 1, #keys, 50 do
					Net.event("TranslateRequest"):FireServer(code, table.move(keys, i, math.min(i + 49, #keys), 1, {}), false)
				end
			end
			table.clear(outbox)
		end
	end)
end

return Localizer

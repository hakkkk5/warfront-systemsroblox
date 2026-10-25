--!strict
-- The lobby menu, laid out like a web page: a nav bar along the top (Play,
-- Store, Records, Settings, Invite) with the Teeth counter, and a page for
-- each tab over the lobby. Play is the lobby itself: walk into a truck.
-- Store sells starting perks for Teeth (checked by server Store), Records
-- shows the saved profile and how Teeth are earned, Settings is the shared
-- SettingsPage.
--
-- Built by Lobby.run on lobby servers. The profile is read from the player's
-- attributes (server Profiles).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Net = require(ReplicatedStorage.Shared.Net)
local StoreCatalog = require(ReplicatedStorage.Shared.StoreCatalog)
local Util = require(ReplicatedStorage.Shared.Util)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Inventory = require(script.Parent.Inventory)
local SettingsPage = require(script.Parent.SettingsPage)
local Theme = require(script.Parent.Theme)

local LobbyMenu = {}

export type Menu = {
	close: () -> (),
	destroy: () -> (),
}

local C = Theme.Colors
local player = Players.LocalPlayer
local CURRENCY = StoreCatalog.Currency
local TABS = { "Play", "Store", "Records", "Settings" }
local STORE_FOOTNOTE = "One of each stocked perk goes in your bag when a night starts."
local REQUEST_GAP = 0.5 -- the server ignores purchases closer together than this
local REQUEST_TIMEOUT = 5

local function stat(name: string): number
	local v = player:GetAttribute(name)
	return if typeof(v) == "number" then v else 0
end

local function profileReady(): boolean
	return player:GetAttribute("ProfileReady") == true
end

-- A little tooth drawn from frames (no image asset needed).
local function tooth(parent: Instance, size: number, props: { [string]: any }?): Frame
	local icon = Theme.frame(parent, {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	})
	if props then
		for k, v in props do
			(icon :: any)[k] = v
		end
	end
	local crown = Theme.frame(icon, {
		Position = UDim2.fromScale(0.06, 0),
		Size = UDim2.fromScale(0.88, 0.62),
		BackgroundColor3 = C.Bone,
	})
	Theme.corner(crown, math.ceil(size * 0.26))
	for _, x in { 0.12, 0.54 } do
		local root = Theme.frame(icon, {
			Position = UDim2.fromScale(x, 0.4),
			Size = UDim2.fromScale(0.34, 0.6),
			BackgroundColor3 = C.Bone,
		})
		Theme.corner(root, math.ceil(size * 0.16))
	end
	return icon
end

-- Nav bar link: plain text with a red underline when it's the open tab.
local function navLink(parent: Instance, text: string, order: number): (TextButton, Frame)
	local b = Util.create("TextButton", {
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = string.upper(text),
		Font = Theme.Fonts.UIBold,
		TextSize = 15,
		TextColor3 = C.BoneDim,
		LayoutOrder = order,
		Parent = parent,
	}) :: TextButton
	Util.create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = b })
	local underline = Theme.frame(b, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = C.BloodBright,
		Visible = false,
	})
	Theme.corner(underline, 2)
	b.MouseEnter:Connect(function()
		if not underline.Visible then
			b.TextColor3 = C.Bone
		end
	end)
	b.MouseLeave:Connect(function()
		if not underline.Visible then
			b.TextColor3 = C.BoneDim
		end
	end)
	return b, underline
end

-- A page over the lobby: title, subtitle, close button and a body to fill.
local function pageShell(parent: Instance, title: string, subtitle: string, onClose: () -> ()): (Frame, Frame)
	local page = Theme.frame(parent, {
		Name = title .. "Page",
		-- under the lobby title (top left) and the nav bar
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 152),
		Size = UDim2.new(0.94, 0, 1, -176),
		BackgroundColor3 = C.Panel,
		Visible = false,
		ZIndex = 5,
	})
	Util.create("UISizeConstraint", { MaxSize = Vector2.new(900, 520), Parent = page })
	Theme.corner(page, 8)
	Theme.stroke(page, C.Blood, 1.5).Transparency = 0.3
	Theme.padding(page, 22)
	Theme.label(page, title, {
		Size = UDim2.new(1, -56, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.Title,
		TextSize = 42,
		TextColor3 = C.BloodBright,
	})
	Theme.label(page, subtitle, {
		Position = UDim2.fromOffset(2, 46),
		Size = UDim2.new(1, -56, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		TextColor3 = C.BoneDim,
	})
	local close = Theme.button(page, "X", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(44, 44),
		TextSize = 20,
	})
	close.Activated:Connect(onClose)
	local body = Theme.frame(page, {
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.new(1, 0, 1, -84),
		BackgroundTransparency = 1,
	})
	return page, body
end

---------------------------------------------------------------- store

type Card = {
	perk: StoreCatalog.Perk,
	buy: TextButton,
	pips: { Frame },
	enabled: boolean,
}

local function storePage(body: Frame, conns: { RBXScriptConnection }): () -> ()
	ReplicatedStorage:WaitForChild("ItemModels", 5) -- previews, published by the server lobby
	local cards = Theme.frame(body, {
		Size = UDim2.new(1, 0, 1, -40),
		BackgroundTransparency = 1,
	})
	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = cards,
	})
	local message = Theme.label(body, STORE_FOOTNOTE, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		TextColor3 = C.BoneDim,
	})

	local list: { Card } = {}
	local pending: Card? = nil
	local lastRequest = -math.huge
	local messageToken = 0

	local function refresh()
		local ready = profileReady()
		local teeth = stat("Teeth")
		for _, card in list do
			local perk = card.perk
			local owned = stat("Perk" .. perk.id)
			for n, pip in card.pips do
				pip.BackgroundColor3 = if n <= owned then C.BloodBright else C.Ink
			end
			if card == pending then
				continue
			end
			local full = owned >= perk.max
			local afford = teeth >= perk.price
			card.enabled = ready and afford and not full
			card.buy.Text = if not ready
				then "Loading…"
				elseif full then "Fully stocked"
				elseif afford then string.format("Buy  ·  %d %s", perk.price, CURRENCY)
				else string.format("%d %s  ·  need %d more", perk.price, CURRENCY, perk.price - teeth)
			card.buy.TextColor3 = if card.enabled then Color3.new(1, 1, 1) else C.BoneDim
			card.buy.BackgroundColor3 = if card.enabled then C.Blood else C.PanelLight
			card.buy.BackgroundTransparency = if card.enabled then 0.1 else 0.5
		end
	end

	local function say(text: string, color: Color3)
		messageToken += 1
		local token = messageToken
		message.Text = text
		message.TextColor3 = color
		task.delay(4, function()
			if token == messageToken then
				message.Text = STORE_FOOTNOTE
				message.TextColor3 = C.BoneDim
			end
		end)
	end

	local perks = StoreCatalog.list()
	for i, perk in perks do
		local card = Theme.frame(cards, {
			Size = UDim2.new(1 / #perks, -14 * (#perks - 1) / #perks, 1, 0),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.25,
			LayoutOrder = i,
		})
		Theme.corner(card, 6)
		Theme.stroke(card, C.Blood, 1).Transparency = 0.6
		Theme.padding(card, 12)

		local model = Inventory.itemModel(perk.item)
		local preview = Theme.viewport(card, model, { Size = UDim2.new(1, 0, 0.36, 0) })
		preview:SetAttribute("Spin", true)
		if not model then
			tooth(preview, 56, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		end
		Theme.label(card, perk.name, {
			Position = UDim2.new(0, 0, 0.36, 8),
			Size = UDim2.new(1, 0, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Fonts.UIBold,
			TextSize = 18,
		})
		Theme.label(card, perk.description, {
			Position = UDim2.new(0, 0, 0.36, 36),
			Size = UDim2.new(1, 0, 0.64, -36 - 80),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextSize = 14,
			TextColor3 = C.BoneDim,
		})

		-- stock: one pip per perk you can keep in reserve
		local stock = Theme.frame(card, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -52),
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
		})
		Util.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = stock,
		})
		Theme.label(stock, "STOCKED", {
			Size = UDim2.fromOffset(0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			Font = Theme.Fonts.UIBold,
			TextSize = 12,
			TextColor3 = C.BoneDim,
			LayoutOrder = 0,
		})
		local pips: { Frame } = {}
		for n = 1, perk.max do
			local pip = Theme.frame(stock, {
				Size = UDim2.fromOffset(12, 12),
				BackgroundColor3 = C.Ink,
				LayoutOrder = n,
			})
			Theme.corner(pip, 3)
			Theme.stroke(pip, C.Blood, 1).Transparency = 0.3
			table.insert(pips, pip)
		end

		local buy = Util.create("TextButton", {
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 44),
			Font = Theme.Fonts.UIBold,
			TextSize = 16,
			Text = "",
			BorderSizePixel = 0,
			Parent = card,
		}) :: TextButton
		Theme.corner(buy, 4)
		Theme.stroke(buy, C.Blood, 1).Transparency = 0.4

		local entry: Card = { perk = perk, buy = buy, pips = pips, enabled = false }
		table.insert(list, entry)
		buy.MouseEnter:Connect(function()
			if entry.enabled and pending == nil then
				buy.BackgroundColor3 = C.BloodBright
			end
		end)
		buy.MouseLeave:Connect(refresh)
		buy.Activated:Connect(function()
			local now = os.clock()
			if not entry.enabled or pending or now - lastRequest < REQUEST_GAP then
				return
			end
			lastRequest = now
			pending = entry
			buy.Text = "…"
			Net.event("StoreBuy"):FireServer(perk.id)
			-- in case the reply never comes
			task.delay(REQUEST_TIMEOUT, function()
				if pending == entry then
					pending = nil
					refresh()
				end
			end)
		end)
	end

	table.insert(
		conns,
		Net.event("StoreResult").OnClientEvent:Connect(function(ok: any, text: any)
			pending = nil
			if typeof(text) == "string" and text ~= "" then
				say(text, if ok then C.Sickly else C.BloodBright)
			end
			Audio.play(if ok then "Pickup" else "DoorLocked", nil, 0.5)
			refresh()
		end)
	)
	for _, name in { "Teeth", "ProfileReady" } do
		table.insert(conns, player:GetAttributeChangedSignal(name):Connect(refresh))
	end
	for _, perk in perks do
		table.insert(conns, player:GetAttributeChangedSignal("Perk" .. perk.id):Connect(refresh))
	end
	refresh()
	return refresh
end

---------------------------------------------------------------- records

local function recordsPage(body: Frame): () -> ()
	local tiles = Theme.frame(body, {
		Size = UDim2.new(1, 0, 0, 104),
		BackgroundTransparency = 1,
	})
	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tiles,
	})
	local function tile(label: string, order: number): TextLabel
		local t = Theme.frame(tiles, {
			Size = UDim2.new(0.25, -9, 1, 0),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.25,
			LayoutOrder = order,
		})
		Theme.corner(t, 6)
		local value = Theme.label(t, "0", {
			Position = UDim2.fromOffset(0, 12),
			Size = UDim2.new(1, 0, 0, 52),
			Font = Theme.Fonts.UIBold,
			TextSize = 40,
		})
		Theme.label(t, label, {
			Position = UDim2.new(0, 0, 1, -34),
			Size = UDim2.new(1, 0, 0, 22),
			Font = Theme.Fonts.UIBold,
			TextSize = 13,
			TextColor3 = C.BoneDim,
		})
		return value
	end
	local teeth = tile(string.upper(CURRENCY), 1)
	local escapes = tile("ESCAPES", 2)
	local deaths = tile("DEATHS", 3)
	local rate = tile("SURVIVAL RATE", 4)

	Theme.label(body, "How to earn " .. CURRENCY, {
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.UIBold,
		TextSize = 18,
	})
	local R = StoreCatalog.Rewards
	local B = StoreCatalog.DifficultyBonus
	local dim = "#968c7c"
	local earn: { { string } } = {
		{
			string.format("Escape the woods  <font color=\"%s\">×%g on Hard, ×%g on Nightmare</font>", dim, B.Hard, B.Nightmare),
			"+" .. R.escape,
		},
		{ string.format("Read a note  <font color=\"%s\">first time each night</font>", dim), "+" .. R.note },
		{ "Put one of the family to sleep", "+" .. R.sedate },
		{ string.format("Finish a household chore  <font color=\"%s\">everyone in the house</font>", dim), "+" .. R.chore },
	}
	local rows = Theme.frame(body, {
		Position = UDim2.fromOffset(0, 152),
		Size = UDim2.new(1, 0, 1, -152 - 30),
		BackgroundTransparency = 1,
	})
	Util.create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = rows })
	for i, e in earn do
		local row = Theme.frame(rows, {
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = if i % 2 == 1 then 0.6 else 1,
			LayoutOrder = i,
		})
		Theme.corner(row, 4)
		Theme.label(row, e[1], {
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -110, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 16,
		})
		Theme.label(row, e[2], {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -38, 0, 0),
			Size = UDim2.fromOffset(70, 32),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Theme.Fonts.UIBold,
			TextSize = 17,
			TextColor3 = C.Sickly,
		})
		tooth(row, 16, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0) })
	end
	local note = Theme.label(body, "", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
	})

	return function()
		local ready = profileReady()
		local e, d = stat("Escapes"), stat("Deaths")
		teeth.Text = if ready then tostring(stat("Teeth")) else "…"
		escapes.Text = if ready then tostring(e) else "…"
		deaths.Text = if ready then tostring(d) else "…"
		rate.Text = if ready and e + d > 0 then string.format("%d%%", math.round(e / (e + d) * 100)) else "-"
		local offline = player:GetAttribute("ProfileOffline") == true
		note.Text = if offline
			then "Progress can't be saved on this server right now. It lasts until you leave."
			else "Saved to your profile."
		note.TextColor3 = if offline then C.Warn else C.BoneDim
	end
end

---------------------------------------------------------------- settings

local function settingsPage(body: Frame)
	local list = Theme.frame(body, {
		Size = UDim2.new(1, 0, 1, -30),
		BackgroundTransparency = 1,
	})
	Util.create("UISizeConstraint", { MaxSize = Vector2.new(560, math.huge), Parent = list })
	SettingsPage.fill(list)
	Theme.label(body, "Saved with your profile, so they follow you into the woods.", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
		TextColor3 = C.BoneDim,
	})
end

---------------------------------------------------------------- menu

local function invite()
	local ok, canInvite = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and canInvite then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end
end

-- Builds the nav bar and pages on `canvas` (the lobby's scaled full-screen
-- frame).
function LobbyMenu.build(canvas: Frame): Menu
	local conns: { RBXScriptConnection } = {}

	local nav = Theme.frame(canvas, {
		Name = "Nav",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 20),
		Size = UDim2.fromOffset(0, 52),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.12,
		ZIndex = 6,
	})
	Theme.corner(nav, 26)
	Theme.stroke(nav, C.Blood, 1).Transparency = 0.45
	Util.create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 6), Parent = nav })
	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = nav,
	})

	local pages: { [string]: Frame } = {}
	local refreshers: { [string]: () -> () } = {}
	local links: { [string]: { button: TextButton, underline: Frame } } = {}
	local current = "Play"

	local function setTab(name: string)
		if name ~= current then
			Audio.play("PageTurn", nil, 0.35)
		end
		current = name
		for tab, link in links do
			local open = tab == name
			link.underline.Visible = open
			link.button.TextColor3 = if open then C.Bone else C.BoneDim
		end
		for tab, page in pages do
			page.Visible = tab == name
		end
		local refresh = refreshers[name]
		if refresh then
			refresh()
		end
	end
	local function close()
		setTab("Play")
	end

	for i, name in TABS do
		local button, underline = navLink(nav, name, i)
		links[name] = { button = button, underline = underline }
		button.Activated:Connect(function()
			setTab(if current == name then "Play" else name)
		end)
	end
	local inviteLink = navLink(nav, "Invite", #TABS + 1)
	inviteLink.Activated:Connect(invite)

	-- Teeth counter (opens the store)
	local pill = Util.create("TextButton", {
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.PanelLight,
		BorderSizePixel = 0,
		LayoutOrder = #TABS + 2,
		Parent = nav,
	}) :: TextButton
	Theme.corner(pill, 20)
	Theme.stroke(pill, C.BloodBright, 1).Transparency = 0.3
	Util.create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 16), Parent = pill })
	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = pill,
	})
	local pillScale = Util.create("UIScale", { Parent = pill }) :: UIScale
	tooth(pill, 20, { LayoutOrder = 1 })
	local count = Theme.label(pill, "…", {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		Font = Theme.Fonts.UIBold,
		TextSize = 20,
		LayoutOrder = 2,
	})
	pill.Activated:Connect(function()
		setTab("Store")
	end)

	-- the counter rolls to the new amount and flashes green (earned) or red
	local shown = Instance.new("NumberValue")
	shown.Value = stat("Teeth")
	table.insert(
		conns,
		shown.Changed:Connect(function(v: number)
			count.Text = tostring(math.round(v))
		end)
	)
	local function onTeeth()
		if not profileReady() then
			count.Text = "…"
			return
		end
		local target = stat("Teeth")
		if target == shown.Value then
			count.Text = tostring(target)
			return
		end
		count.TextColor3 = if target > shown.Value then C.Sickly else C.BloodBright
		Util.tween(count, 0.9, { TextColor3 = C.Bone })
		Util.tween(shown, 0.6, { Value = target }, Enum.EasingStyle.Quad)
		pillScale.Scale = 1.14
		Util.tween(pillScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	table.insert(conns, player:GetAttributeChangedSignal("Teeth"):Connect(onTeeth))
	table.insert(conns, player:GetAttributeChangedSignal("ProfileReady"):Connect(onTeeth))
	onTeeth()

	-- pages
	local storeFrame, storeBody =
		pageShell(canvas, "Store", "Spend " .. CURRENCY .. " on supplies for your next night in the woods.", close)
	pages.Store = storeFrame
	refreshers.Store = storePage(storeBody, conns)

	local recordsFrame, recordsBody = pageShell(canvas, "Records", "What the woods remember about you.", close)
	pages.Records = recordsFrame
	local refreshRecords = recordsPage(recordsBody)
	refreshers.Records = refreshRecords
	for _, name in { "Teeth", "Escapes", "Deaths", "ProfileReady", "ProfileOffline" } do
		table.insert(conns, player:GetAttributeChangedSignal(name):Connect(refreshRecords))
	end

	local settingsFrame, settingsBody = pageShell(canvas, "Settings", "Look, sound and comfort.", close)
	pages.Settings = settingsFrame
	settingsPage(settingsBody)

	-- spin the store previews while the store is open
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function()
			if current ~= "Store" then
				return
			end
			local a = os.clock() * 0.8
			for _, d in storeFrame:GetDescendants() do
				if d:IsA("ViewportFrame") and d:GetAttribute("Spin") and d.CurrentCamera then
					local center = d:GetAttribute("Center") :: Vector3
					local distance = d:GetAttribute("Distance") :: number
					d.CurrentCamera.CFrame = CFrame.lookAt(center + Vector3.new(math.cos(a) * 0.9, 0.5, math.sin(a) * 0.9).Unit * distance, center)
				end
			end
		end)
	)

	setTab("Play")

	return {
		close = close,
		destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			shown:Destroy()
		end,
	}
end

return LobbyMenu

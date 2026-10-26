--!strict
-- Saved player data: Teeth (the store currency), stocked perks, records
-- (escapes, deaths) and settings (shared PlayerSettings). Kept in a DataStore
-- so it follows a player from the lobby into the reserved game server and back.
--
-- Loaded when a player joins and mirrored onto player attributes for the
-- client (Teeth, Escapes, Deaths, Perk<Id>, Setting<key>, ProfileReady). Saved on leave,
-- on shutdown, a few seconds after a change, and right before a teleport
-- (Profiles.save) so the next server reads fresh data. When DataStores are
-- unavailable (Studio without "Enable Studio Access to API Services") the
-- profile lives for the session only.
--
-- Initialised before Lobby.run(), which never returns on lobby servers.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local PlayerSettings = require(ReplicatedStorage.Shared.PlayerSettings)
local StoreCatalog = require(ReplicatedStorage.Shared.StoreCatalog)
local Trophies = require(ReplicatedStorage.Shared.Trophies)

local Profiles = {}

export type Data = {
	teeth: number,
	perks: { [string]: number },
	escapes: number,
	deaths: number,
	settings: { [string]: number },
	achievements: { [string]: boolean },
	polaroids: { [string]: boolean },
}

local STORE_NAME = "CannibalFamilyProfiles_v1"
local SAVE_DELAY = 6

local store: DataStore? = nil
local warned = false
local profiles: { [Player]: Data } = {}
local dirty: { [Player]: boolean } = {}
local offline: { [Player]: boolean } = {}
local runAwards: { [Player]: { [string]: boolean } } = {}

local function blank(): Data
	return { teeth = 0, perks = {}, escapes = 0, deaths = 0, settings = {}, achievements = {}, polaroids = {} }
end

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function warnOnce(err: any)
	if not warned then
		warned = true
		warn("[Profiles] DataStores unavailable, progress is kept for this session only: " .. tostring(err))
	end
end

local function sanitize(raw: any): Data
	local data = blank()
	if typeof(raw) ~= "table" then
		return data
	end
	data.teeth = math.max(0, math.floor(tonumber(raw.teeth) or 0))
	data.escapes = math.max(0, math.floor(tonumber(raw.escapes) or 0))
	data.deaths = math.max(0, math.floor(tonumber(raw.deaths) or 0))
	if typeof(raw.perks) == "table" then
		for id, perk in StoreCatalog.Perks do
			data.perks[id] = math.clamp(math.floor(tonumber(raw.perks[id]) or 0), 0, perk.max)
		end
	end
	data.settings = PlayerSettings.sanitize(raw.settings)
	for _, field in { "achievements", "polaroids" } do
		local known: { [string]: any } = if field == "achievements" then Trophies.Achievements else Trophies.Polaroids
		local saved = raw[field]
		if typeof(saved) == "table" then
			for id in known do
				if saved[id] == true then
					(data :: any)[field][id] = true
				end
			end
		end
	end
	return data
end

-- Mirror the profile onto attributes the client reads.
local function publish(player: Player)
	local data = profiles[player]
	if not data then
		return
	end
	player:SetAttribute("Teeth", data.teeth)
	player:SetAttribute("Escapes", data.escapes)
	player:SetAttribute("Deaths", data.deaths)
	for id in StoreCatalog.Perks do
		player:SetAttribute("Perk" .. id, data.perks[id] or 0)
	end
	for id in data.achievements do
		player:SetAttribute("Ach_" .. id, true)
	end
	local photos = 0
	for id in data.polaroids do
		player:SetAttribute("Pol_" .. id, true)
		photos += 1
	end
	player:SetAttribute("Polaroids", photos)
	for key, value in data.settings do
		player:SetAttribute("Setting" .. key, value)
	end
end

local function load(player: Player)
	local data: Data = blank()
	local loaded = false
	local s = store
	if s then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return s:GetAsync(key(player))
			end)
			if ok then
				data = sanitize(result)
				loaded = true
				break
			elseif attempt == 3 then
				warnOnce(result)
			else
				task.wait(attempt)
			end
		end
	end
	if not player.Parent then
		return
	end
	-- a profile that didn't load is never saved, so a DataStore hiccup can't
	-- overwrite the real one with a blank
	if not loaded then
		offline[player] = true
		player:SetAttribute("ProfileOffline", true)
	end
	profiles[player] = data
	publish(player)
	player:SetAttribute("ProfileReady", true)
end

-- Writes the profile now (yields). Call before teleporting a player.
function Profiles.save(player: Player)
	local data = profiles[player]
	local s = store
	dirty[player] = nil
	if not data or not s or offline[player] then
		return
	end
	local ok, err = pcall(function()
		s:UpdateAsync(key(player), function()
			return {
				teeth = data.teeth,
				perks = table.clone(data.perks),
				escapes = data.escapes,
				deaths = data.deaths,
				settings = table.clone(data.settings),
				achievements = table.clone(data.achievements),
				polaroids = table.clone(data.polaroids),
			}
		end)
	end)
	if not ok then
		warnOnce(err)
	end
end

local function changed(player: Player)
	publish(player)
	if dirty[player] then
		return
	end
	dirty[player] = true
	task.delay(SAVE_DELAY, function()
		if dirty[player] and player.Parent then
			Profiles.save(player)
		end
	end)
end

function Profiles.get(player: Player): Data?
	return profiles[player]
end

-- Adds Teeth (and tells the player why).
function Profiles.award(player: Player, amount: number, reason: string?)
	local data = profiles[player]
	if not data or amount <= 0 then
		return
	end
	data.teeth += math.floor(amount)
	changed(player)
	if reason then
		Net.event("Notify"):FireClient(player, string.format("+%d %s  %s", math.floor(amount), StoreCatalog.Currency, reason), "item")
	end
end

-- Awards once per key per run (the same note read twice pays once).
function Profiles.awardOnce(player: Player, awardKey: string, amount: number, reason: string?)
	local seen = runAwards[player]
	if not seen then
		seen = {}
		runAwards[player] = seen
	end
	if seen[awardKey] then
		return
	end
	seen[awardKey] = true
	Profiles.award(player, amount, reason)
end

-- Spends Teeth; false when there aren't enough.
function Profiles.spend(player: Player, amount: number): boolean
	local data = profiles[player]
	if not data or data.teeth < amount then
		return false
	end
	data.teeth -= amount
	changed(player)
	return true
end

function Profiles.addPerk(player: Player, id: string, count: number)
	local data = profiles[player]
	local perk = StoreCatalog.Perks[id]
	if not data or not perk then
		return
	end
	data.perks[id] = math.clamp((data.perks[id] or 0) + count, 0, perk.max)
	changed(player)
end

-- Marks an achievement earned; true the first time.
function Profiles.unlock(player: Player, id: string): boolean
	local data = profiles[player]
	if not data or not Trophies.Achievements[id] or data.achievements[id] then
		return false
	end
	data.achievements[id] = true
	changed(player)
	return true
end

-- Adds a polaroid to the album; true the first time.
function Profiles.collectPolaroid(player: Player, id: string): boolean
	local data = profiles[player]
	if not data or not Trophies.Polaroids[id] or data.polaroids[id] then
		return false
	end
	data.polaroids[id] = true
	changed(player)
	return true
end

function Profiles.polaroidCount(player: Player): number
	local data = profiles[player]
	local n = 0
	if data then
		for _ in data.polaroids do
			n += 1
		end
	end
	return n
end

function Profiles.record(player: Player, stat: "escapes" | "deaths")
	local data = profiles[player]
	if not data then
		return
	end
	data[stat] += 1
	changed(player)
end

-- The client's settings (it debounces them); checked like everything else.
local function saveSettings(player: Player, raw: any)
	local data = profiles[player]
	if data and typeof(raw) == "table" then
		data.settings = PlayerSettings.sanitize(raw)
		changed(player)
	end
end

function Profiles.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warnOnce(result)
	end
	local function onPlayer(player: Player)
		task.spawn(load, player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Net.event("SaveSettings").OnServerEvent:Connect(saveSettings)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	-- only unsaved changes are written on the way out: after a teleport the
	-- next server owns the profile, and a late write here would undo its saves
	Players.PlayerRemoving:Connect(function(player)
		if dirty[player] then
			Profiles.save(player)
		end
		profiles[player] = nil
		dirty[player] = nil
		offline[player] = nil
		runAwards[player] = nil
	end)
	game:BindToClose(function()
		local pending = 0
		for player in dirty do
			pending += 1
			task.spawn(function()
				Profiles.save(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 20 do
			task.wait(0.2)
		end
	end)
end

return Profiles

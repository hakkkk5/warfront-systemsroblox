--!strict
-- Automatic translation into the language each player's Roblox is set to
-- (shared Lang picks it). French has a table written by hand; every line it
-- lacks, and every line in every other language, is translated here with
-- Roblox's Translate Text API (Open Cloud, through Roblox's official "Open
-- Cloud" package in ServerScriptService: OpenCloud.V2:TranslateText). See
-- https://create.roblox.com/docs/production/localization/auto-translate-dynamic-content
--
-- Each translation is asked for once, ever: it's kept in this server's
-- memory and in a DataStore with one entry per language, so the next server
-- loads a whole language in one read. Lines a player is looking at go
-- first; the background warm-up (every line the game knows) fills in behind,
-- at a pace inside the API's limit (150 Open Cloud calls a minute per
-- server).
--
-- The API only answers live servers (it authenticates as the game server),
-- so in Studio everything stays in English.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Lang = require(ReplicatedStorage.Shared.Lang)
local Net = require(ReplicatedStorage.Shared.Net)

local Translate = {}

local STORE = "Translations_v1"
local SPACING = 0.5 -- seconds between API calls (~120 a minute)
local FLUSH_EVERY = 30 -- seconds between DataStore writes
local MAX_KEY = 400
local PER_PLAYER = 400 -- lines a player may ask for a minute (the warm-up included)

type Language = {
	code: string, -- Lang.List code
	api: string, -- Translate Text API code
	map: { [string]: string }, -- key -> translation
	dirty: { [string]: string }, -- not saved yet
	loaded: boolean,
	loading: boolean,
}

local languages: { [string]: Language } = {}
local waiting: { [string]: { [string]: { [Player]: boolean } } } = {} -- key -> code -> players
local urgent: { string } = {}
local background: { string } = {}
local queued: { [string]: boolean } = {}
local budget: { [Player]: { count: number, since: number } } = {}
local store: DataStore? = nil
local openCloud: any = nil
local pausedUntil = 0
local warned = false
local remote = Net.event("Translations")

local function language(code: string): Language?
	local api = Lang.API[code]
	if not api or code == "en" then
		return nil
	end
	local l = languages[code]
	if not l then
		l = { code = code, api = api, map = {}, dirty = {}, loaded = false, loading = false }
		languages[code] = l
	end
	return l
end

-- Everything saved for a language so far, once per server.
local function load(l: Language)
	if l.loaded or l.loading then
		while l.loading do
			task.wait(0.1)
		end
		return
	end
	l.loading = true
	local s = store
	if s then
		local ok, saved = pcall(function()
			return s:GetAsync("lang_" .. l.api)
		end)
		if ok and typeof(saved) == "table" then
			for key, text in saved :: any do
				if typeof(key) == "string" and typeof(text) == "string" then
					l.map[key] = text
				end
			end
		end
	end
	l.loaded = true
	l.loading = false
end

local function allowed(player: Player, count: number): boolean
	local now = os.clock()
	local b = budget[player]
	if not b or now - b.since > 60 then
		local fresh = { count = 0, since = now }
		budget[player] = fresh
		b = fresh
	end
	local mine = b :: { count: number, since: number }
	mine.count += count
	return mine.count <= PER_PLAYER
end

local function deliver(l: Language, key: string, text: string)
	l.map[key] = text
	local who = waiting[key] and waiting[key][l.code]
	if who then
		for player in who do
			if player.Parent then
				remote:FireClient(player, l.code, { [key] = text })
			end
		end
		waiting[key][l.code] = nil
	end
end

-- One line into every language someone's waiting for it in.
local function translate(key: string)
	local wanted = waiting[key]
	queued[key] = nil
	if not wanted then
		return
	end
	local targets: { string } = {}
	local byApi: { [string]: Language } = {}
	for code in wanted do
		local l = language(code)
		if l then
			local known = l.map[key]
			if known then
				deliver(l, key, known)
			else
				table.insert(targets, l.api)
				byApi[l.api] = l
			end
		end
	end
	if #targets == 0 or not openCloud or os.clock() < pausedUntil then
		return
	end
	local ok, result = pcall(function()
		return openCloud:TranslateText({
			path = openCloud:UniversePath(tostring(game.GameId)),
			text = key,
			source_language_code = "en-us",
			target_language_codes = targets,
		})
	end)
	local response = ok and result and result.Error == nil and result.Response
	if not response then
		if not warned then
			warned = true
			local why = if not ok then tostring(result) elseif result and result.Error then tostring(result.Error.message) else "no answer"
			warn("[Translate] the Translate Text API isn't answering here (it only works on live servers): " .. why)
		end
		pausedUntil = os.clock() + 60
		return
	end
	for code, text in response.translations or {} do
		if typeof(code) == "string" and typeof(text) == "string" then
			-- the answer's codes may come back in another case or form
			local l = byApi[string.lower(code)] or byApi[code]
			if not l then
				for api, candidate in byApi do
					if string.sub(api, 1, 2) == string.sub(string.lower(code), 1, 2) then
						l = candidate
						break
					end
				end
			end
			if l then
				l.dirty[key] = text
				deliver(l, key, text)
			end
		end
	end
end

local function flush()
	local s = store
	if not s then
		return
	end
	for _, l in languages do
		if next(l.dirty) then
			local batch = l.dirty
			l.dirty = {}
			pcall(function()
				s:UpdateAsync("lang_" .. l.api, function(old: any)
					local merged = if typeof(old) == "table" then old else {}
					for key, text in batch do
						merged[key] = text
					end
					return merged
				end)
			end)
		end
	end
end

local function onRequest(player: Player, code: any, keys: any, later: any)
	if typeof(code) ~= "string" then
		return
	end
	local l = language(code)
	if not l then
		return
	end
	load(l)
	-- no keys: everything this server has for the language
	if keys == nil then
		if next(l.map) then
			remote:FireClient(player, code, l.map)
		end
		return
	end
	if typeof(keys) ~= "table" or not allowed(player, #keys) then
		return
	end
	local found: { [string]: string } = {}
	local count = 0
	for _, key in keys do
		count += 1
		if count > 60 then
			break
		end
		if typeof(key) == "string" and #key > 0 and #key <= MAX_KEY then
			local known = l.map[key]
			if known then
				found[key] = known
			else
				local w = waiting[key]
				if not w then
					w = {}
					waiting[key] = w
				end
				local who = w[code]
				if not who then
					who = {}
					w[code] = who
				end
				who[player] = true
				if not queued[key] then
					queued[key] = true
					table.insert(if later == true then background else urgent, key)
				end
			end
		end
	end
	if next(found) then
		remote:FireClient(player, code, found)
	end
end

function Translate.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE)
	end)
	if ok then
		store = result
	end
	local package = ServerScriptService:FindFirstChild("OpenCloud")
	local v2 = package and package:FindFirstChild("V2")
	if v2 and v2:IsA("ModuleScript") then
		local loaded, module = pcall(require, v2)
		if loaded then
			openCloud = module
		end
	end
	if not openCloud then
		warn("[Translate] the Open Cloud package isn't in ServerScriptService: only French is translated")
	end
	Net.event("TranslateRequest").OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player)
		budget[player] = nil
	end)
	task.spawn(function()
		while true do
			local key = table.remove(urgent, 1) or table.remove(background, 1)
			if key then
				translate(key)
				task.wait(SPACING)
			else
				task.wait(0.3)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(FLUSH_EVERY)
			flush()
		end
	end)
	game:BindToClose(flush)
end

return Translate

--!strict
-- Translations. The game is written in English; Lang.t(text) gives the text
-- in the player's language: from that language's table when it has one (the
-- ModuleScripts under this one, named by language code and keyed by the
-- English text: French), and otherwise machine-translated by the server
-- (Systems/Translate, Roblox's Translate Text API) and kept. Until a
-- translation arrives the English shows, so a missing line never breaks
-- anything. The language is a setting (PlayerSettings "language": 0 = the
-- player's Roblox language), saved with the profile; on the client
-- UI/Localizer then swaps the text of screens and world signs in place.

local LocalizationService = game:GetService("LocalizationService")
local RunService = game:GetService("RunService")

local Signal = require(script.Parent.Signal)

local Lang = {}

export type Language = { code: string, name: string }

-- the Settings choice, in order (1..n; 0 is automatic): English, French
-- (with a table here) and every language Roblox's Translate Text API knows
-- (translated at runtime, server Systems/Translate)
Lang.List = {
	{ code = "en", name = "English" },
	{ code = "fr", name = "Français" },
	{ code = "es", name = "Español" },
	{ code = "pt", name = "Português" },
	{ code = "de", name = "Deutsch" },
	{ code = "it", name = "Italiano" },
	{ code = "pl", name = "Polski" },
	{ code = "ru", name = "Русский" },
	{ code = "tr", name = "Türkçe" },
	{ code = "id", name = "Bahasa Indonesia" },
	{ code = "vi", name = "Tiếng Việt" },
	{ code = "th", name = "ไทย" },
	{ code = "ja", name = "日本語" },
	{ code = "ko", name = "한국어" },
	{ code = "zh-cn", name = "简体中文" },
	{ code = "zh-tw", name = "繁體中文" },
} :: { Language }

-- each language's code for the Translate Text API (IETF BCP-47)
Lang.API = {
	en = "en-us",
	fr = "fr-fr",
	es = "es-es",
	pt = "pt-br",
	de = "de-de",
	it = "it-it",
	pl = "pl-pl",
	ru = "ru-ru",
	tr = "tr-tr",
	id = "id-id",
	vi = "vi-vn",
	th = "th-th",
	ja = "ja-jp",
	ko = "ko-kr",
	["zh-cn"] = "zh-cn",
	["zh-tw"] = "zh-tw",
} :: { [string]: string }

Lang.Changed = Signal.new()
-- (code, key): a line the current language has no translation for yet; the
-- client's Localizer asks the server (key: Lang.key)
Lang.Requested = Signal.new()

local current = "en"
local tables: { [string]: { [string]: string } | false } = {}

local function tableFor(code: string): { [string]: string }?
	if code == "en" then
		return nil
	end
	local cached = tables[code]
	if cached == false then
		return nil
	elseif cached then
		return cached :: any
	end
	local module = script:FindFirstChild(code)
	local loaded: { [string]: string }? = nil
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and typeof(result) == "table" then
			loaded = result :: any
		end
	end
	tables[code] = loaded or false
	return loaded
end

-- The language the player set for Roblox (es-es, pt-br, fr-fr...), if the
-- game has it; else English. Nobody is asked: this is what Auto means.
function Lang.guess(): string
	local ok, locale = pcall(function()
		local id = LocalizationService.RobloxLocaleId
		if id == "" then
			id = (game:GetService("Players").LocalPlayer :: Player).LocaleId
		end
		return id
	end)
	local lower = if ok and typeof(locale) == "string" then string.lower(locale) else "en"
	local code = string.sub(lower, 1, 2)
	if code == "zh" then
		-- Taiwan, Hong Kong, traditional script: traditional characters
		local traditional = string.find(lower, "tw", 1, true) or string.find(lower, "hk", 1, true) or string.find(lower, "hant", 1, true)
		code = if traditional then "zh-tw" else "zh-cn"
	end
	for _, l in Lang.List do
		if l.code == code then
			return code
		end
	end
	return "en"
end

-- The language for a Settings value (0 = automatic).
function Lang.fromSetting(value: number): string
	local l = Lang.List[math.round(value)]
	return if l then l.code else Lang.guess()
end

function Lang.code(): string
	return current
end

function Lang.set(code: string)
	if code ~= current then
		current = code
		Lang.Changed:Fire(code)
	end
end

-- A text with numbers in it ("Hint ready in 5s") is looked up as its
-- pattern ("Hint ready in %ds") and the numbers put back in order.
local function withNumbers(t: { [string]: string }, text: string): string?
	if not string.find(text, "%d") then
		return nil
	end
	local numbers: { string } = {}
	local pattern = string.gsub(text, "%d+", function(n)
		table.insert(numbers, n)
		return "%d"
	end)
	local translated = t[pattern]
	if not translated then
		return nil
	end
	local i = 0
	return (string.gsub(translated, "%%d", function()
		i += 1
		return numbers[i] or ""
	end))
end

-- Capitals, accented letters included (string.upper leaves UTF-8 alone).
local ACCENTS: { [string]: string } = {
	["à"] = "À", ["â"] = "Â", ["ç"] = "Ç", ["é"] = "É", ["è"] = "È", ["ê"] = "Ê", ["ë"] = "Ë",
	["î"] = "Î", ["ï"] = "Ï", ["ô"] = "Ô", ["ù"] = "Ù", ["û"] = "Û", ["ü"] = "Ü", ["ñ"] = "Ñ",
	["á"] = "Á", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ã"] = "Ã", ["õ"] = "Õ", ["ö"] = "Ö",
}
local function upper(s: string): string
	return (string.gsub(string.upper(s), "[\192-\223][\128-\191]", function(c)
		return ACCENTS[c] or c
	end))
end

-- Labels shown in capitals ("PLAY") are looked up by their capitals too.
local capitals: { [{ [string]: string }]: { [string]: string } } = {}
local function capitalised(t: { [string]: string }, text: string): string?
	if string.find(text, "%l") then
		return nil
	end
	local index = capitals[t]
	if not index then
		local built: { [string]: string } = {}
		for k, v in t do
			built[upper(k)] = upper(v)
		end
		capitals[t] = built
		index = built
	end
	return (index :: { [string]: string })[text]
end

local function lookup(t: { [string]: string }, text: string): string?
	return t[text] or withNumbers(t, text) or capitalised(t, text)
end

-- Text put together from pieces: lines ("HOW TO SURVIVE\nWASD move..."),
-- "Picked up: Bandage" (a known prefix and the rest), "Spark Plugs, Spare
-- Wheel" (a list).
local function pieces(t: { [string]: string }, text: string): string?
	if string.find(text, "\n", 1, true) then
		local out, any = {}, false
		for _, line in string.split(text, "\n") do
			local known = lookup(t, line) or pieces(t, line)
			any = any or known ~= nil
			table.insert(out, known or line)
		end
		return if any then table.concat(out, "\n") else nil
	end
	local cut = string.find(text, ": ", 1, true)
	if cut then
		local head = string.sub(text, 1, cut + 1)
		local known = lookup(t, head)
		if known then
			local rest = string.sub(text, cut + 2)
			return known .. (lookup(t, rest) or pieces(t, rest) or rest)
		end
	end
	-- "Hard  ·  Leaving in 12s" (signs and panels), "Spark Plugs, Spare Wheel"
	for _, sep in { "  ·  ", ", " } do
		if string.find(text, sep, 1, true) then
			local out, any = {}, false
			for _, item in string.split(text, sep) do
				local known = lookup(t, item)
				any = any or known ~= nil
				table.insert(out, known or item)
			end
			if any then
				return table.concat(out, sep)
			end
		end
	end
	return nil
end

-- Machine translations from the server (Systems/Translate), by language and
-- key. A key is the English with its numbers and format slots taken out
-- ("Leaving in 12s" -> "Leaving in {A}s"), so one translation serves every
-- value and the translator never touches them.
local runtime: { [string]: { [string]: string } } = {}
local asked: { [string]: boolean } = {}

function Lang.key(text: string): (string, { string })
	local fills: { string } = {}
	local key = string.gsub(text, "%%[%-%d%.]*[dsgf]", function(slot)
		table.insert(fills, slot)
		return "\1"
	end)
	key = string.gsub(key, "%d+", function(n)
		table.insert(fills, n)
		return "\1"
	end)
	-- the marks in order: {A}, {B}...
	local i = 0
	key = string.gsub(key, "\1", function()
		i += 1
		return "{" .. string.char(64 + math.min(i, 26)) .. "}"
	end)
	return key, fills
end

local function fromRuntime(text: string): string?
	local key, fills = Lang.key(text)
	local found = runtime[current] and runtime[current][key]
	if found then
		return (string.gsub(found, "{(%u)}", function(c)
			return fills[string.byte(c) - 64] or ""
		end))
	end
	-- worth asking: some words, not too long
	local mark = current .. "\0" .. key
	if not asked[mark] and #key <= 400 and string.find(key, "%a%a") then
		asked[mark] = true
		Lang.Requested:Fire(current, key)
	end
	return nil
end

-- Translations arriving from the server (code: a Lang.List code).
local refreshing = false
function Lang.addTranslations(code: string, map: { [string]: string })
	local into = runtime[code]
	if not into then
		into = {}
		runtime[code] = into
	end
	for key, text in map do
		into[key] = text
	end
	-- one refresh for a burst of arrivals
	if code == current and not refreshing then
		refreshing = true
		task.delay(0.15, function()
			refreshing = false
			Lang.Changed:Fire(current)
		end)
	end
end

-- The text in the current language (or as it is): this game's own table
-- first (French), then the machine translations.
function Lang.t(text: string): string
	if current == "en" or text == "" then
		return text
	end
	local t = tableFor(current)
	if t then
		local found = lookup(t, text) or pieces(t, text)
		if found then
			return found
		end
	end
	return fromRuntime(text) or text
end

-- Whether the game has its own table for the current language (French).
function Lang.hasTable(): boolean
	return tableFor(current) ~= nil
end

-- Whether the current language has this text (asking the server if not).
function Lang.has(text: string): boolean
	if current == "en" or text == "" then
		return false
	end
	local t = tableFor(current)
	if t and (lookup(t, text) ~= nil or pieces(t, text) ~= nil) then
		return true
	end
	return fromRuntime(text) ~= nil
end

-- Every English line the game's own table knows (to warm up a language).
function Lang.knownLines(): { string }
	local fr = tableFor("fr")
	local list = {}
	if fr then
		for english in fr do
			table.insert(list, english)
		end
	end
	return list
end

-- A pattern with %s / %d in it, translated and then filled in.
function Lang.f(pattern: string, ...: any): string
	return string.format(Lang.t(pattern), ...)
end

if RunService:IsClient() then
	current = Lang.guess()
end

-- On Auto, follow the player changing their Roblox language mid-session.
local auto = true
function Lang.setAuto(on: boolean)
	auto = on
end
if RunService:IsClient() then
	pcall(function()
		LocalizationService:GetPropertyChangedSignal("RobloxLocaleId"):Connect(function()
			if auto then
				Lang.set(Lang.guess())
			end
		end)
	end)
end

return Lang

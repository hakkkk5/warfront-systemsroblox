--!strict
-- Translations. The game is written in English; Lang.t(text) gives the text
-- in the player's language when that language's table has it (the
-- ModuleScripts under this one, named by language code and keyed by the
-- English text) and the English otherwise, so a missing line never breaks
-- anything. The language is a setting (PlayerSettings "language": 0 = the
-- player's Roblox language), saved with the profile; on the client
-- UI/Localizer then swaps the text of screens and world signs in place.

local LocalizationService = game:GetService("LocalizationService")
local RunService = game:GetService("RunService")

local Signal = require(script.Parent.Signal)

local Lang = {}

export type Language = { code: string, name: string }

-- the Settings choice, in order (1..n; 0 is automatic)
Lang.List = {
	{ code = "en", name = "English" },
	{ code = "fr", name = "Français" },
} :: { Language }

Lang.Changed = Signal.new()

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
	local code = if ok and typeof(locale) == "string" then string.lower(string.sub(locale, 1, 2)) else "en"
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

-- The text in the current language (or as it is).
function Lang.t(text: string): string
	local t = tableFor(current)
	if not t or text == "" then
		return text
	end
	return lookup(t, text) or pieces(t, text) or text
end

-- Whether the game has its own table for the current language (French). For
-- every other language the text stays English and Roblox's automatic
-- translation (Creator Dashboard > Localization) translates it on screen.
function Lang.hasTable(): boolean
	return tableFor(current) ~= nil
end

-- Whether the current language has this text.
function Lang.has(text: string): boolean
	local t = tableFor(current)
	return t ~= nil and text ~= "" and (lookup(t, text) ~= nil or pieces(t, text) ~= nil)
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

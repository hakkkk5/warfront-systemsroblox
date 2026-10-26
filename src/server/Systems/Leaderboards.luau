--!strict
-- The lobby's leaderboards: most escapes, most Teeth and most trophies,
-- kept in OrderedDataStores. Profiles posts a player's numbers whenever it
-- saves them (lobby and game servers alike); the lobby reads the top ten
-- now and then. Where DataStores can't be reached (Studio without API
-- access) nothing is posted and the boards say so.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Leaderboards = {}

Leaderboards.Stats = { "Escapes", "Teeth", "Trophies" }

export type Entry = { name: string, value: number }

local stores: { [string]: OrderedDataStore } = {}
local names: { [number]: string } = {}

local function store(stat: string): OrderedDataStore?
	local s = stores[stat]
	if s then
		return s
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore("Leaderboard_" .. stat)
	end)
	if ok and result then
		stores[stat] = result
		return result
	end
	return nil
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and typeof(name) == "string" then name else "#" .. userId
	names[userId] = result
	return result
end

-- A player's current numbers, by stat.
function Leaderboards.post(userId: number, values: { [string]: number })
	for _, stat in Leaderboards.Stats do
		local value = values[stat]
		local s = store(stat)
		if s and value and value > 0 then
			pcall(function()
				s:SetAsync(tostring(userId), math.floor(value))
			end)
		end
	end
end

-- The top `count` for a stat, best first; nil if the store can't be read.
function Leaderboards.top(stat: string, count: number): { Entry }?
	local s = store(stat)
	if not s then
		return nil
	end
	local ok, page = pcall(function()
		return s:GetSortedAsync(false, count):GetCurrentPage()
	end)
	if not ok or typeof(page) ~= "table" then
		return nil
	end
	local list: { Entry } = {}
	for _, row in page :: { any } do
		local userId = tonumber(row.key)
		if userId then
			table.insert(list, { name = nameOf(userId), value = row.value })
		end
	end
	return list
end

return Leaderboards

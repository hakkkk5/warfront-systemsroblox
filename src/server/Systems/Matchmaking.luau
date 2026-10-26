--!strict
-- Finding players on other lobby servers. Someone who wants company but
-- finds the trucks here empty joins the search for a difficulty; the search
-- is one queue per difficulty shared by every lobby server (MemoryStore
-- sorted maps, oldest first). Each lobby server takes turns being the
-- matchmaker (a short lease): it puts the longest-waiting players together,
-- up to four at a time once there are at least two, reserves their game
-- server and leaves each of them a ticket. Every lobby server looks for
-- tickets for its own searchers and sends them on (Lobby's onMatched).
--
-- Off in Studio, where nothing can teleport.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Difficulty = require(game:GetService("ReplicatedStorage").Shared.Difficulty)

local Matchmaking = {}

export type Ticket = { code: string, server: string, difficulty: string, party: { number } }

local MAX_PARTY = 4
local ENTRY_TTL = 90 -- a searcher's entry lapses unless their server refreshes it
local REFRESH = 30
local TICKET_TTL = 60
local LEASE = 8 -- seconds a server is the matchmaker for a difficulty
local POLL = 3

type Search = { difficulty: string, since: number, refreshed: number }

local searching: { [Player]: Search } = {}
local queues: { [string]: MemoryStoreSortedMap } = {}
local tickets: MemoryStoreHashMap? = nil
local leases: MemoryStoreHashMap? = nil
local enabled = false

local function queueFor(difficulty: string): MemoryStoreSortedMap?
	local q = queues[difficulty]
	if q then
		return q
	end
	local ok, result = pcall(function()
		return MemoryStoreService:GetSortedMap("MatchQueue_" .. difficulty)
	end)
	if ok then
		queues[difficulty] = result
		return result
	end
	return nil
end

local function enter(player: Player, s: Search)
	local q = queueFor(s.difficulty)
	if q then
		pcall(function()
			q:SetAsync(tostring(player.UserId), { at = s.since }, ENTRY_TTL, s.since)
		end)
	end
	s.refreshed = os.clock()
end

local function remove(userId: number, difficulty: string)
	local q = queueFor(difficulty)
	if q then
		pcall(function()
			q:RemoveAsync(tostring(userId))
		end)
	end
end

-- Whether finding players works here (live lobby servers).
function Matchmaking.available(): boolean
	return enabled
end

function Matchmaking.search(player: Player, difficulty: string): boolean
	if not enabled or not Difficulty.valid(difficulty) then
		return false
	end
	local old = searching[player]
	if old and old.difficulty == difficulty then
		return true
	end
	if old then
		task.spawn(remove, player.UserId, old.difficulty)
	end
	local s: Search = { difficulty = difficulty, since = os.time(), refreshed = 0 }
	searching[player] = s
	task.spawn(enter, player, s)
	return true
end

function Matchmaking.cancel(player: Player)
	local s = searching[player]
	if s then
		searching[player] = nil
		task.spawn(remove, player.UserId, s.difficulty)
	end
end

-- What a player is searching for, and for how long (nil: not searching).
function Matchmaking.status(player: Player): (string?, number?)
	local s = searching[player]
	if not s then
		return nil, nil
	end
	return s.difficulty, os.time() - s.since
end

-- The matchmaker's turn for one difficulty, if no other server has it.
local function lease(difficulty: string): boolean
	local map = leases
	if not map then
		return false
	end
	local won = false
	pcall(function()
		map:UpdateAsync(difficulty, function(old: any)
			local now = os.time()
			won = not (typeof(old) == "table" and old.job ~= game.JobId and (old.expires or 0) > now)
			if not won then
				return nil
			end
			return { job = game.JobId, expires = now + LEASE }
		end, LEASE * 2)
	end)
	return won
end

-- Put the longest-waiting searchers together and hand out their tickets.
local function matchmake(difficulty: string)
	local q = queueFor(difficulty)
	local t = tickets
	if not q or not t or not lease(difficulty) then
		return
	end
	local ok, items = pcall(function()
		return q:GetRangeAsync(Enum.SortDirection.Ascending, 24)
	end)
	if not ok or typeof(items) ~= "table" then
		return
	end
	local ids: { number } = {}
	for _, item in items :: { any } do
		local id = tonumber(item.key)
		if id then
			table.insert(ids, id)
		end
	end
	while #ids >= 2 do
		local group: { number } = {}
		for _ = 1, math.min(MAX_PARTY, #ids) do
			table.insert(group, table.remove(ids, 1) :: number)
		end
		local reserved, code, server = pcall(function()
			return TeleportService:ReserveServer(game.PlaceId)
		end)
		if not reserved then
			warn("[Matchmaking] couldn't reserve a server: " .. tostring(code))
			return
		end
		local ticket: Ticket = { code = code, server = server, difficulty = difficulty, party = group }
		for _, id in group do
			pcall(function()
				t:SetAsync(tostring(id), ticket, TICKET_TTL)
				q:RemoveAsync(tostring(id))
			end)
		end
	end
end

-- Tickets for this server's searchers.
local function collect(onMatched: (player: Player, ticket: Ticket) -> ())
	local t = tickets
	if not t then
		return
	end
	-- a copy: the requests below yield, and people start and stop searching meanwhile
	for player, s in table.clone(searching) do
		local ok, value = pcall(function()
			return t:GetAsync(tostring(player.UserId))
		end)
		if ok and typeof(value) == "table" and typeof(value.code) == "string" and searching[player] == s then
			searching[player] = nil
			pcall(function()
				t:RemoveAsync(tostring(player.UserId))
			end)
			local ticket: Ticket = {
				code = value.code,
				server = value.server,
				difficulty = if Difficulty.valid(value.difficulty) then value.difficulty else s.difficulty,
				party = if typeof(value.party) == "table" then value.party else { player.UserId },
			}
			task.spawn(onMatched, player, ticket)
		elseif os.clock() - s.refreshed > REFRESH then
			task.spawn(enter, player, s)
		end
	end
end

-- Lobby servers only. onMatched sends a player to their ticket's server.
function Matchmaking.start(onMatched: (player: Player, ticket: Ticket) -> ())
	if RunService:IsStudio() then
		return
	end
	local ok = pcall(function()
		tickets = MemoryStoreService:GetHashMap("MatchTickets")
		leases = MemoryStoreService:GetHashMap("MatchLeases")
	end)
	if not ok then
		return
	end
	enabled = true
	Players.PlayerRemoving:Connect(Matchmaking.cancel)
	task.spawn(function()
		while true do
			task.wait(POLL)
			collect(onMatched)
			-- only difficulties someone here is searching for: a server with
			-- nobody searching has no reason to spend requests on the queues
			local wanted: { [string]: boolean } = {}
			for _, s in searching do
				wanted[s.difficulty] = true
			end
			for difficulty in wanted do
				matchmake(difficulty)
			end
		end
	end)
end

return Matchmaking

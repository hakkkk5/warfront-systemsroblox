--!strict
-- Keeping a truck's party together. A reserved game server lets nobody in
-- without its code, so a player who drops out of a run (a crash, a lost
-- connection, closing the app) would be shut out of their friends' game for
-- good. The lobby notes, for everyone in the truck, which game they went to;
-- whoever turns up on a lobby server while that game is still going is sent
-- straight back into it. The game server lets go of a player who leaves on
-- purpose (Play again) and of the whole party when the run ends or the
-- server closes.
--
-- Kept in a MemoryStore hash map whose entries expire on their own. Off in
-- Studio, where nothing can teleport.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Rejoin = {}

export type Game = { code: string, server: string }

local LIFETIME = 3 * 60 * 60 -- longer than any run

local map: MemoryStoreHashMap? = nil
-- game servers: everyone the lobby sent here
local roster: { [number]: boolean } = {}

local function store(): MemoryStoreHashMap?
	if map or RunService:IsStudio() then
		return map
	end
	local ok, result = pcall(function()
		return MemoryStoreService:GetHashMap("PartyGames")
	end)
	if ok then
		map = result
	end
	return map
end

-- Lobby: these players are off to this game.
function Rejoin.remember(players: { Player }, g: Game)
	local s = store()
	if not s then
		return
	end
	for _, player in players do
		task.spawn(pcall, function()
			s:SetAsync(tostring(player.UserId), { code = g.code, server = g.server }, LIFETIME)
		end)
	end
end

-- Lobby: the game this player's party is still playing, if any.
function Rejoin.lookup(userId: number): Game?
	local s = store()
	if not s then
		return nil
	end
	local ok, value = pcall(function()
		return s:GetAsync(tostring(userId))
	end)
	if ok and typeof(value) == "table" and typeof(value.code) == "string" and typeof(value.server) == "string" then
		return { code = value.code, server = value.server }
	end
	return nil
end

-- Game server: stop sending this player back here (only if it's still this
-- server they'd be sent to: they may have started another game since).
function Rejoin.forget(userId: number)
	local s = store()
	if not s then
		return
	end
	pcall(function()
		local value = s:GetAsync(tostring(userId))
		if typeof(value) == "table" and value.server == game.PrivateServerId then
			s:RemoveAsync(tostring(userId))
		end
	end)
end

-- Game server: the party the lobby sent here (from the teleport data).
function Rejoin.expect(userIds: { any })
	for _, id in userIds do
		if typeof(id) == "number" then
			roster[id] = true
		end
	end
end

-- Game server: let the whole party go when the run is over or the server
-- shuts down.
function Rejoin.watchGame()
	if not store() then
		return
	end
	local function releaseAll()
		for _, player in Players:GetPlayers() do
			roster[player.UserId] = true
		end
		for id in roster do
			Rejoin.forget(id)
		end
	end
	workspace:GetAttributeChangedSignal("Stage"):Connect(function()
		if workspace:GetAttribute("Stage") == "Ending" then
			task.spawn(releaseAll)
		end
	end)
	game:BindToClose(releaseAll)
end

return Rejoin

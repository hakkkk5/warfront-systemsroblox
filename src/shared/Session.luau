--!strict
-- Which kind of server this is. Public and VIP servers run the lobby; the
-- reserved servers a lobby party is teleported into run the game.
--
-- In Studio the lobby runs first (teleports don't work there, so when a party
-- leaves, the same server turns into the game). Set the workspace attribute
-- SkipLobby = true in Studio to go straight to the game.
--
-- The server publishes the result as workspace.Mode ("Lobby" | "Game").

local RunService = game:GetService("RunService")

local Session = {}

-- Server-side decision for this server.
function Session.isLobby(): boolean
	local mode = workspace:GetAttribute("Mode")
	if mode == "Game" then
		return false
	elseif mode == "Lobby" then
		return true
	end
	if workspace:GetAttribute("SkipLobby") == true then
		return false
	end
	if RunService:IsStudio() then
		return true
	end
	return game.PrivateServerId == "" or game.PrivateServerOwnerId ~= 0
end

-- The mode the server published (clients wait for it).
function Session.mode(): string
	local mode = workspace:GetAttribute("Mode")
	local started = os.clock()
	while typeof(mode) ~= "string" and os.clock() - started < 15 do
		task.wait(0.1)
		mode = workspace:GetAttribute("Mode")
	end
	if typeof(mode) == "string" then
		return mode
	end
	return if Session.isLobby() then "Lobby" else "Game"
end

return Session

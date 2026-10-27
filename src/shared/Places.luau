--!strict
-- The experience's two places. The lobby is the start place everyone joins;
-- the game (the woods) is the other place in the experience, and only the
-- lobby's trucks send parties into it, each into a server reserved for them.
-- Both places carry the same scripts: which one a server is in decides what
-- it runs (Session).
--
-- Until the game place exists the game runs in reserved servers of the lobby
-- place itself, as it always did.

local AssetService = game:GetService("AssetService")

local Places = {}

Places.LOBBY = 128295243061633

-- Whether this server is in the game place (not the lobby's, nor an
-- unpublished Studio file).
function Places.inGamePlace(): boolean
	return game.PlaceId ~= 0 and game.PlaceId ~= Places.LOBBY
end

local gamePlace: number? = nil

-- The place a party is sent into (server; yields the first time): the other
-- place in the experience, or the lobby place while there's only the one.
function Places.game(): number
	local known = gamePlace
	if known then
		return known
	end
	local ok, found = pcall(function(): number?
		local pages = AssetService:GetGamePlacesAsync()
		while true do
			for _, place in pages:GetCurrentPage() do
				if place.PlaceId ~= Places.LOBBY then
					return place.PlaceId
				end
			end
			if pages.IsFinished then
				return nil
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		warn("[Places] couldn't list the experience's places: " .. tostring(found))
		return game.PlaceId -- try again next time
	end
	gamePlace = found or game.PlaceId
	return gamePlace :: number
end

return Places

--!strict
-- The lobby store (shared StoreCatalog): buying perks with Teeth, and handing
-- the stocked perks out at the start of a run. Purchases are checked here,
-- never trusted from the client; one request per player at a time.
--
-- Initialised before Lobby.run() so purchases work on lobby servers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local StoreCatalog = require(ReplicatedStorage.Shared.StoreCatalog)
local Inventory = require(script.Parent.Inventory)
local Profiles = require(script.Parent.Profiles)

local Store = {}

local COOLDOWN = 0.4

local lastBuy: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function reply(player: Player, ok: boolean, message: string)
	Net.event("StoreResult"):FireClient(player, ok, message)
end

local function buy(player: Player, id: any)
	local now = os.clock()
	if now - (lastBuy[player] or 0) < COOLDOWN then
		return
	end
	lastBuy[player] = now
	local perk = if typeof(id) == "string" then StoreCatalog.Perks[id] else nil
	local data = Profiles.get(player)
	if not perk or not data then
		reply(player, false, "That isn't for sale.")
		return
	end
	if (data.perks[perk.id] or 0) >= perk.max then
		reply(player, false, string.format("You can't carry more than %d.", perk.max))
		return
	end
	if not Profiles.spend(player, perk.price) then
		reply(player, false, string.format("Not enough %s.", StoreCatalog.Currency))
		return
	end
	Profiles.addPerk(player, perk.id, 1)
	reply(player, true, perk.name .. " packed for your next night.")
end

-- At the start of a run: each stocked perk goes in the bag, one of each.
function Store.grantPerks(player: Player)
	local data = Profiles.get(player)
	if not data then
		return
	end
	local given: { string } = {}
	for _, perk in StoreCatalog.list() do
		if (data.perks[perk.id] or 0) > 0 then
			Profiles.addPerk(player, perk.id, -1)
			Inventory.add(player, perk.item, 1, true)
			table.insert(given, perk.name)
		end
	end
	if #given > 0 then
		Net.event("Notify"):FireClient(player, "Packed: " .. table.concat(given, ", "), "item")
	end
end

function Store.init()
	Net.event("StoreBuy").OnServerEvent:Connect(buy)
end

return Store

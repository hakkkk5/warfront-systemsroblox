--!strict
-- Per-player inventory, kept on the server and mirrored to the client UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Interact = require(script.Parent.Interact)

local Inventory = {}

type Bag = { items: { [string]: number }, equipped: string? }

local bags: { [Player]: Bag } = {}
local inventoryRemote = Net.event("Inventory")
local soundRemote = Net.event("Sound")

-- (player, itemId, newCount)
Inventory.Changed = Signal.new() :: Signal.Signal<Player, string, number>
-- (player, items they carried, last position) when someone leaves the server
Inventory.Lost = Signal.new() :: Signal.Signal<Player, { [string]: number }, Vector3?>

local function bag(player: Player): Bag
	local b = bags[player]
	if not b then
		b = { items = {}, equipped = nil }
		bags[player] = b
	end
	return b
end

function Inventory.sync(player: Player)
	local b = bag(player)
	local list = {}
	for _, id in Items.Order do
		local count = b.items[id]
		if count and count > 0 then
			table.insert(list, { id = id, count = count })
		end
	end
	inventoryRemote:FireClient(player, { items = list, equipped = b.equipped })

	local heavy = false
	for id, count in b.items do
		local def = Items.get(id)
		if def and def.heavy and count > 0 then
			heavy = true
		end
	end
	player:SetAttribute("Heavy", heavy)
	player:SetAttribute("Equipped", b.equipped)
	player:SetAttribute("HasFlashlight", (b.items.Flashlight or 0) > 0)
end

function Inventory.count(player: Player, id: string): number
	return bag(player).items[id] or 0
end

function Inventory.has(player: Player, id: string): boolean
	return Inventory.count(player, id) > 0
end

function Inventory.add(player: Player, id: string, amount: number?, silent: boolean?)
	local def = Items.get(id)
	if not def then
		warn("[Inventory] unknown item " .. id)
		return
	end
	local b = bag(player)
	local n = amount or 1
	if def.stackable then
		b.items[id] = (b.items[id] or 0) + n
	else
		b.items[id] = 1
	end
	if not silent then
		Interact.notify(player, "Picked up: " .. def.name, "item")
		soundRemote:FireClient(player, "Pickup")
	end
	Inventory.sync(player)
	Inventory.Changed:Fire(player, id, b.items[id])
end

function Inventory.remove(player: Player, id: string, amount: number?): boolean
	local b = bag(player)
	local have = b.items[id] or 0
	local n = amount or 1
	if have < n then
		return false
	end
	b.items[id] = have - n
	if b.items[id] <= 0 then
		b.items[id] = nil
		if b.equipped == id then
			b.equipped = nil
		end
	end
	Inventory.sync(player)
	Inventory.Changed:Fire(player, id, b.items[id] or 0)
	return true
end

-- First player holding the item, if any.
function Inventory.holder(id: string): Player?
	for _, player in Players:GetPlayers() do
		if Inventory.has(player, id) then
			return player
		end
	end
	return nil
end

function Inventory.equipped(player: Player): string?
	return bag(player).equipped
end

local function useItem(player: Player, id: string)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if id == "Battery" then
		if Inventory.remove(player, "Battery") then
			Net.event("Recharge"):FireClient(player, 50)
			Interact.notify(player, "Flashlight recharged", "item")
		end
	elseif id == "Bandage" then
		if humanoid.Health >= humanoid.MaxHealth then
			Interact.notify(player, "You are not hurt.", "warn")
			return
		end
		if Inventory.remove(player, "Bandage") then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 40)
			Interact.notify(player, "Bandaged your wounds (+40)", "item")
		end
	elseif id == "FirstAidKit" then
		if humanoid.Health >= humanoid.MaxHealth then
			Interact.notify(player, "You are not hurt.", "warn")
			return
		end
		if Inventory.remove(player, "FirstAidKit") then
			humanoid.Health = humanoid.MaxHealth
			Interact.notify(player, "Patched up properly (full health)", "item")
		end
	end
end

function Inventory.init()
	Players.PlayerRemoving:Connect(function(player)
		-- tell the story what walked out of the server with them, so quest
		-- items can be put back into the world instead of being lost
		local b = bags[player]
		if b then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local where = if root and root:IsA("BasePart") then root.Position else nil
			local carried: { [string]: number } = table.clone(b.items)
			bags[player] = nil
			Inventory.Lost:Fire(player, carried, where)
		end
	end)

	Net.event("InventoryAction").OnServerEvent:Connect(function(player, action, id)
		if typeof(action) ~= "string" or typeof(id) ~= "string" then
			return
		end
		local def = Items.get(id)
		if not def or not Inventory.has(player, id) then
			return
		end
		local b = bag(player)
		if action == "equip" and def.equippable then
			b.equipped = if b.equipped == id then nil else id
			Inventory.sync(player)
		elseif action == "use" and def.usable then
			useItem(player, id)
		end
	end)
end

return Inventory

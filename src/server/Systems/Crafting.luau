--!strict
-- Workbenches (shared Crafting has the recipes). Using one opens the
-- crafting screen on that client; crafting is checked here: you have to be
-- standing at a bench with everything the recipe needs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CraftingData = require(ReplicatedStorage.Shared.Crafting)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Build = require(script.Parent.Parent.World.Build)
local Interact = require(script.Parent.Interact)
local Inventory = require(script.Parent.Inventory)

local Crafting = {}

-- (player, recipe id) after something is made
Crafting.Crafted = Signal.new() :: Signal.Signal<Player, string>

local benches: { BasePart } = {}
local busy: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any

function Crafting.addBench(part: BasePart, label: string?)
	table.insert(benches, part)
	Interact.add(part, {
		action = "Use workbench",
		object = label or "Workbench",
		distance = 8,
		onUse = function(player)
			Net.event("Crafting"):FireClient(player)
		end,
	})
end

-- A bench at a spot with no part of its own (the top of the bench).
function Crafting.addBenchAt(cf: CFrame, parent: Instance, label: string?)
	local anchor = Build.part(parent, Vector3.new(4, 1, 2), cf * CFrame.new(0, 0.6, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		Name = "WorkbenchPrompt",
		Transparency = 1,
		CanCollide = false,
	})
	Crafting.addBench(anchor, label)
end

local function nearBench(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	for _, bench in benches do
		if bench.Parent and (bench.Position - root.Position).Magnitude <= CraftingData.BENCH_RANGE then
			return bench
		end
	end
	return nil
end

local function craft(player: Player, recipeId: any)
	if busy[player] or typeof(recipeId) ~= "string" then
		return
	end
	local recipe = CraftingData.ById[recipeId]
	local bench = nearBench(player)
	if not recipe or not bench then
		return
	end
	for _, need in recipe.needs do
		if Inventory.count(player, need.item) < need.count then
			local def = Items.get(need.item)
			Interact.notify(player, "Missing: " .. (if def then def.name else need.item), "warn")
			return
		end
	end
	busy[player] = true
	for _, need in recipe.needs do
		Inventory.remove(player, need.item, need.count)
	end
	Inventory.add(player, recipe.result, recipe.count)
	Net.event("Sound"):FireAllClients("Repair", bench.Position)
	Crafting.Crafted:Fire(player, recipe.id)
	busy[player] = nil
end

function Crafting.init()
	Net.event("Craft").OnServerEvent:Connect(craft)
end

return Crafting

--!strict
-- World item pickups and readable notes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Lore = require(ReplicatedStorage.Shared.Lore)
local Net = require(ReplicatedStorage.Shared.Net)
local StoreCatalog = require(ReplicatedStorage.Shared.StoreCatalog)
local AssetService = require(script.Parent.AssetService)
local Interact = require(script.Parent.Interact)
local Inventory = require(script.Parent.Inventory)
local Profiles = require(script.Parent.Profiles)
local Signal = require(ReplicatedStorage.Shared.Signal)

local Pickups = {}

-- (player, note id) whenever someone reads a note
Pickups.NoteRead = Signal.new() :: Signal.Signal<Player, string>
-- how many notes are out in the world this night
Pickups.notesPlaced = 0

export type Options = {
	amount: number?,
	onPicked: ((player: Player) -> ())?,
	glint: boolean?,
	yaw: number?,
}

local noteRemote = Net.event("Note")
local soundRemote = Net.event("Sound")

local function anchorAll(model: Model)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
		end
	end
end

-- Faint sparkle so small items can be spotted in the dark.
local function addGlint(part: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Rate = 1.2
	sparkle.Lifetime = NumberRange.new(0.6, 1)
	sparkle.Speed = NumberRange.new(0)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 236, 190))
	sparkle.Transparency = NumberSequence.new(0.2)
	sparkle.Parent = attachment
end

-- The sparkle that marks something you can pick up.
function Pickups.glint(part: BasePart)
	addGlint(part)
end

local function primary(model: Model): BasePart
	local best: BasePart? = nil
	local bestVolume = -1
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > bestVolume then
				bestVolume = v
				best = p
			end
		end
	end
	assert(best, "model has no parts")
	return best
end

function Pickups.spawn(itemId: string, cf: CFrame, parent: Instance, opts: Options?): Model
	local o: Options = opts or {}
	local def = Items.get(itemId)
	assert(def, "unknown item " .. itemId)
	local model = AssetService.create(def.model)
	model.Name = "Pickup_" .. itemId
	model:PivotTo(cf * CFrame.Angles(0, o.yaw or 0, 0))
	anchorAll(model)
	model.Parent = parent

	local main = primary(model)
	if o.glint ~= false then
		addGlint(main)
	end
	Interact.add(main, {
		action = "Pick up",
		object = def.name,
		distance = 7,
		hold = if def.heavy then 0.8 else 0,
		once = true,
		onUse = function(player)
			Inventory.add(player, itemId, o.amount)
			model:Destroy()
			if o.onPicked then
				o.onPicked(player)
			end
		end,
	})
	return model
end

function Pickups.note(noteId: string, cf: CFrame, parent: Instance): Model
	local note = Lore[noteId]
	assert(note, "unknown note " .. noteId)
	local model = AssetService.create("Note")
	Pickups.notesPlaced += 1
	model.Name = "Note_" .. noteId
	model:PivotTo(cf)
	anchorAll(model)
	model.Parent = parent
	local main = primary(model)
	addGlint(main)
	Interact.add(main, {
		action = "Read",
		object = note.title,
		distance = 7,
		onUse = function(player)
			soundRemote:FireClient(player, "PageTurn")
			noteRemote:FireClient(player, noteId)
			Profiles.awardOnce(player, "note:" .. noteId, StoreCatalog.Rewards.note, "Read: " .. note.title)
			Pickups.NoteRead:Fire(player, noteId)
		end,
	})
	return model
end

return Pickups

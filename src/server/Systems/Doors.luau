--!strict
-- Hinged doors. Players open them with a prompt; cannibals open them
-- automatically when they walk up to one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Interact = require(script.Parent.Interact)
local Inventory = require(script.Parent.Inventory)
local Net = require(ReplicatedStorage.Shared.Net)
local Items = require(ReplicatedStorage.Shared.Items)

local Doors = {}

export type Door = {
	name: string,
	hinge: CFrame,
	width: number,
	parts: { { part: BasePart, offset: CFrame } },
	angle: NumberValue,
	isOpen: boolean,
	locked: boolean,
	blockedText: string?, -- boarded up etc.: no key opens it (Doors.setBlocked)
	swing: number,
	prompt: ProximityPrompt?,
	center: Vector3,
	onOpened: ((player: Player?) -> ())?,
}

export type Options = {
	name: string?,
	color: Color3?,
	material: Enum.Material?,
	locked: boolean?,
	keyItem: string?, -- item that unlocks it (consumed)
	lockedText: string?,
	swing: number?, -- 1 or -1
	barred: boolean?, -- can never be opened
	onOpened: ((player: Player?) -> ())?,
}

local doors: { Door } = {}
local soundRemote = Net.event("Sound")

local function apply(door: Door)
	local cf = door.hinge * CFrame.Angles(0, door.angle.Value, 0)
	for _, entry in door.parts do
		entry.part.CFrame = cf * entry.offset
	end
end

function Doors.setOpen(door: Door, open: boolean, player: Player?)
	if door.isOpen == open then
		return
	end
	door.isOpen = open
	local target = if open then math.rad(100) * door.swing else 0
	local tween = game:GetService("TweenService"):Create(
		door.angle,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = target }
	)
	tween:Play()
	if door.prompt then
		door.prompt.ActionText = if open then "Close" else "Open"
	end
	soundRemote:FireAllClients("DoorOpen", door.center)
	if open and door.onOpened then
		door.onOpened(player)
	end
end

-- Something other than a lock keeps it shut (boards); nil clears it.
function Doors.setBlocked(door: Door, text: string?)
	door.blockedText = text
end

function Doors.unlock(door: Door)
	door.locked = false
end

function Doors.create(parent: Instance, hinge: CFrame, width: number, height: number, opts: Options?): Door
	local o: Options = opts or {}
	local model = Instance.new("Model")
	model.Name = o.name or "Door"
	model.Parent = parent

	local color = o.color or Color3.fromRGB(74, 52, 36)
	local material = o.material or Enum.Material.WoodPlanks
	local parts = {}

	local function add(size: Vector3, offset: CFrame, c: Color3, m: Enum.Material, name: string?)
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.Color = c
		p.Material = m
		p.CollisionGroup = "Door"
		p.Name = name or "DoorPart"
		p.CFrame = hinge * offset
		p.Parent = model
		table.insert(parts, { part = p :: BasePart, offset = offset })
		return p
	end

	local panel = add(Vector3.new(width - 0.1, height - 0.1, 0.32), CFrame.new(width / 2, height / 2, 0), color, material, "Panel")
	-- frame-and-panel detailing
	add(Vector3.new(width * 0.7, height * 0.32, 0.36), CFrame.new(width / 2, height * 0.72, 0), color:Lerp(Color3.new(0, 0, 0), 0.25), material)
	add(Vector3.new(width * 0.7, height * 0.32, 0.36), CFrame.new(width / 2, height * 0.3, 0), color:Lerp(Color3.new(0, 0, 0), 0.25), material)
	add(Vector3.new(0.22, 0.22, 0.6), CFrame.new(width - 0.55, height * 0.47, 0), Color3.fromRGB(150, 130, 90), Enum.Material.Metal, "Knob")

	local modifier = Instance.new("PathfindingModifier")
	modifier.PassThrough = true
	modifier.Parent = panel

	local angle = Instance.new("NumberValue")
	angle.Name = "Angle"
	angle.Parent = model

	local door: Door = {
		name = model.Name,
		hinge = hinge,
		width = width,
		parts = parts,
		angle = angle,
		isOpen = false,
		locked = o.locked == true or o.barred == true,
		swing = o.swing or 1,
		prompt = nil,
		center = (hinge * CFrame.new(width / 2, height / 2, 0)).Position,
		onOpened = o.onOpened,
	}
	angle.Changed:Connect(function()
		apply(door)
	end)

	door.prompt = Interact.add(panel, {
		action = "Open",
		object = if o.barred then "Boarded Door" else "Door",
		distance = 7,
		hold = 0,
		canUse = function(player)
			if door.blockedText then
				soundRemote:FireClient(player, "DoorLocked")
				return false, door.blockedText
			end
			if o.barred then
				return false, "It's nailed shut from the outside."
			end
			if door.locked then
				if o.keyItem and Inventory.has(player, o.keyItem) then
					return true
				end
				soundRemote:FireClient(player, "DoorLocked")
				return false, o.lockedText or "It's locked."
			end
			return true
		end,
		onUse = function(player)
			if door.locked and o.keyItem then
				Inventory.remove(player, o.keyItem)
				door.locked = false
				soundRemote:FireAllClients("Unlock", door.center)
				local def = Items.get(o.keyItem)
				Interact.notify(player, "Used " .. (if def then def.name else o.keyItem), "item")
			end
			Doors.setOpen(door, not door.isOpen, player)
		end,
	})

	table.insert(doors, door)
	return door
end

-- Cannibals call this as they move so doors swing open in front of them.
function Doors.openNear(position: Vector3, radius: number)
	for _, door in doors do
		if not door.isOpen and not door.locked and (door.center - position).Magnitude < radius then
			Doors.setOpen(door, true, nil)
		end
	end
end

return Doors

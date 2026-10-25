--!strict
-- Dresses the cannibals in their Blender bodies (tools/blender/build_monsters.py):
-- one mesh per R6 body part, a near-human set and a stretched monster set
-- per kind.
--
-- The server tags each rig "CannibalSkin" with Skin = kind and SkinScale = its
-- height (Cannibals.dress). This module makes the rig's body parts MeshLibrary
-- stand-ins, so the meshes are welded on and the plain R6 parts hidden
-- locally; the rig, its Motor6Ds, the keyframe animation and the AI are
-- untouched. The server-built mask and apron ("Costume") are hidden under
-- the new head and torso. MonsterForm calls setForm to swap in the monster
-- parts and put the weapon away ("Held"). Without the imported meshes
-- nothing changes and the rig keeps its old look.

local CollectionService = game:GetService("CollectionService")

local MeshLibrary = require(script.Parent.MeshLibrary)

local CannibalSkins = {}

local SLOTS: { [string]: string } = {
	Head = "Head",
	Torso = "Torso",
	["Left Arm"] = "Arm",
	["Right Arm"] = "Arm",
	["Left Leg"] = "Leg",
	["Right Leg"] = "Leg",
}

local dressed: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local heldHidden: { [Model]: { [BasePart]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function partsOf(root: Instance): { BasePart }
	local list: { BasePart } = {}
	if root:IsA("BasePart") then
		table.insert(list, root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- The mask, eye holes and apron the server built; the glowing eyes stay.
local function hideCostume(model: Model)
	for _, d in model:GetDescendants() do
		if d:GetAttribute("Costume") then
			if d:GetAttribute("Mesh") then
				-- e.g. the sack mask, which has a Blender mesh of its own
				d:SetAttribute("SkipMesh", true)
				MeshLibrary.remove(d)
			end
			for _, p in partsOf(d) do
				if p.Name ~= "Eye" then
					p.LocalTransparencyModifier = 1
				end
			end
		end
	end
end

-- The weapon and lantern, hidden while the claws are out (and their own
-- Blender visuals with them), restored as they were.
local function setHeld(model: Model, hidden: boolean)
	if hidden then
		local saved = heldHidden[model] or {}
		heldHidden[model] = saved
		for _, d in model:GetDescendants() do
			if d:GetAttribute("Held") then
				for _, p in partsOf(d) do
					if saved[p] == nil then
						saved[p] = p.LocalTransparencyModifier
					end
					p.LocalTransparencyModifier = 1
				end
			end
		end
	else
		local saved = heldHidden[model]
		heldHidden[model] = nil
		if saved then
			for p, value in saved do
				if p.Parent then
					p.LocalTransparencyModifier = value
				end
			end
		end
	end
end

-- Dresses a rig in its near-human body. Safe to call more than once; returns
-- whether the rig wears a Blender body.
function CannibalSkins.apply(model: Model): boolean
	if dressed[model] then
		return true
	end
	local kind = model:GetAttribute("Skin")
	if typeof(kind) ~= "string" or not MeshLibrary.template(kind .. "Head") then
		return false
	end
	dressed[model] = true
	local scale = model:GetAttribute("SkinScale")
	for name, slot in SLOTS do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part:SetAttribute("MeshScale", if typeof(scale) == "number" then scale else 1)
			-- keep a form already chosen (MonsterForm may have run first)
			if part:GetAttribute("Mesh") == nil then
				part:SetAttribute("Mesh", kind .. slot)
			end
			CollectionService:AddTag(part, "BlenderMesh")
		end
	end
	hideCostume(model)
	return true
end

-- Swaps between the near-human and the monster body. Returns false when the
-- rig has no Blender body (MonsterForm then keeps its procedural look).
function CannibalSkins.setForm(model: Model, monster: boolean): boolean
	if not CannibalSkins.apply(model) then
		return false
	end
	local kind = model:GetAttribute("Skin") :: string
	if monster and not MeshLibrary.template(kind .. "MonsterHead") then
		return false
	end
	for name, slot in SLOTS do
		local part = model:FindFirstChild(name)
		if part then
			part:SetAttribute("Mesh", kind .. (if monster then "Monster" else "") .. slot)
		end
	end
	-- the monster face has eyes of its own, and claws instead of the weapon
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Eye" then
			d.LocalTransparencyModifier = if monster then 1 else 0
		end
	end
	setHeld(model, monster)
	if monster then
		-- items whose own visual is still on its way (a fresh clone)
		task.defer(function()
			if heldHidden[model] then
				setHeld(model, true)
			end
		end)
	end
	return true
end

function CannibalSkins.isDressed(model: Model): boolean
	return dressed[model] == true
end

function CannibalSkins.init()
	local function onTagged(inst: Instance)
		if inst:IsA("Model") and inst:IsDescendantOf(workspace) then
			task.defer(CannibalSkins.apply, inst)
		end
	end
	CollectionService:GetInstanceAddedSignal("CannibalSkin"):Connect(onTagged)
	for _, inst in CollectionService:GetTagged("CannibalSkin") do
		onTagged(inst)
	end
end

return CannibalSkins

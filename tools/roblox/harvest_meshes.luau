--!nocheck
-- Files the Blender meshes imported with Studio's "Import 3D" under
-- ReplicatedStorage.MeshAssets.<MeshName>, where the client MeshLibrary
-- clones them from. Run in Studio (Edit mode) from the command bar or the
-- Studio MCP, after importing assets/blender/CannibalFamilyMeshes.glb
-- (tools/blender/export_combined.py). Safe to run again after a newer import:
-- parts with the same name are replaced.
--
-- Every imported part is named "<MeshName>_<material>". The 1-stud cube
-- "MeshOrigin" marks the origin the meshes were modelled around, so whatever
-- move or unit scale the importer applied is undone here. Save the place
-- afterwards: MeshAssets lives in the place file, not in the Rojo project.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function findImport(): (Instance?, BasePart?)
	for _, d in game:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "MeshOrigin" and not d:IsDescendantOf(ReplicatedStorage) then
			local root = d.Parent
			while root and root.Parent and root.Parent ~= workspace and root.Parent ~= game do
				root = root.Parent
			end
			return root, d
		end
	end
	return nil, nil
end

local root, marker = findImport()
if not root or not marker then
	local message = "No import found: Import 3D a CannibalFamilyMeshes .glb first."
	print(message)
	return message
end

local scale = 1 / marker.Size.X
-- Studio's importer turns glTF scenes (it put the first import 180 degrees
-- round Y); the second cube, 10 studs along +X, says by how much
local axis = root:FindFirstChild("MeshAxisX", true)
local turn = CFrame.Angles(0, math.pi, 0)
if axis and axis:IsA("BasePart") then
	local v = axis.Position - marker.Position
	turn = CFrame.Angles(0, -math.atan2(-v.Z, v.X), 0)
	axis:Destroy()
end
local origin = CFrame.new(marker.Position) * turn:Inverse()
local store = ReplicatedStorage:FindFirstChild("MeshAssets")
if not store then
	store = Instance.new("Folder")
	store.Name = "MeshAssets"
	store.Parent = ReplicatedStorage
end

local filed, meshes = 0, {}
for _, part in root:GetDescendants() do
	if part:IsA("MeshPart") and part ~= marker then
		local meshName = string.match(part.Name, "^([^_]+)_")
		if meshName then
			local rel = origin:Inverse() * part.CFrame
			local group = store:FindFirstChild(meshName)
			if group and not meshes[meshName] then
				-- a re-import replaces the whole mesh, not just same-named parts
				group:Destroy()
				group = nil
			end
			if not group then
				group = Instance.new("Model")
				group.Name = meshName
				group.Parent = store
				meshes[meshName] = true
			end
			local old = group:FindFirstChild(part.Name)
			if old then
				old:Destroy()
			end
			part.Size *= scale
			part.CFrame = CFrame.new(rel.Position * scale) * rel.Rotation
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			-- (CollisionFidelity is left alone: changing it on a big batch makes
			-- Studio rebuild every hull at once and can hang it)
			part.Parent = group
			group.WorldPivot = CFrame.new()
			filed += 1
		end
	end
end
root:Destroy()

local names = {}
for name in meshes do
	table.insert(names, name)
end
table.sort(names)
local message = string.format("Filed %d mesh parts (import scale %.3f) into ReplicatedStorage.MeshAssets. New meshes: %s. Now save the place.", filed, scale, table.concat(names, ", "))
print(message)
return message

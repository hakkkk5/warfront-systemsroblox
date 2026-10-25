--!strict
-- Everyone plays as an R6 character (the baked animations are R6) that looks
-- like their own Roblox avatar: clothes, accessories, colours and face.
--
-- The place's avatar setting can't be changed from a script, and dressing a
-- blank body after LoadCharacter kept failing on the first spawn, so each
-- body is built straight from the player's own avatar description and handed
-- to them as their character (R6Characters.load replaces LoadCharacter).
-- An R6 StarterCharacter stays in StarterPlayer as the fallback.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local R6Characters = {}

local descriptions: { [Player]: HumanoidDescription } = {}

local SKIN = Color3.fromRGB(234, 184, 146)

-- A plain description with a normal skin tone (a blank one is black).
local function plainDescription(): HumanoidDescription
	local base = Instance.new("HumanoidDescription")
	base.HeadColor = SKIN
	base.LeftArmColor = SKIN
	base.RightArmColor = SKIN
	base.TorsoColor = Color3.fromRGB(70, 84, 110)
	base.LeftLegColor = Color3.fromRGB(46, 50, 62)
	base.RightLegColor = Color3.fromRGB(46, 50, 62)
	return base
end

local function descriptionFor(player: Player): HumanoidDescription
	local cached = descriptions[player]
	if cached then
		return cached
	end
	if player.UserId > 0 then
		for _ = 1, 3 do
			local ok, desc = pcall(function()
				return Players:GetHumanoidDescriptionFromUserId(player.UserId)
			end)
			if ok and desc then
				-- R6 ignores body scales; keep the default proportions
				desc.HeightScale = 1
				desc.WidthScale = 1
				desc.DepthScale = 1
				desc.HeadScale = 1
				descriptions[player] = desc
				return desc
			end
			task.wait(0.5)
		end
		warn("[R6Characters] couldn't load " .. player.Name .. "'s avatar; using a plain body")
	end
	return plainDescription()
end

-- Builds the player's R6 body from their avatar and makes it their
-- character (fires CharacterAdded like LoadCharacter does). Yields.
function R6Characters.load(player: Player): Model?
	if not player.Parent then
		return nil
	end
	local desc = descriptionFor(player)
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)
	if not (ok and rig) then
		warn("[R6Characters] couldn't build " .. player.Name .. "'s body: " .. tostring(rig))
		local loaded = pcall(function()
			player:LoadCharacterAsync()
		end)
		if not loaded then
			(player :: any):LoadCharacter()
		end
		return player.Character
	end
	rig.Name = player.Name
	local root = rig:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		rig.PrimaryPart = root
	end
	local old = player.Character
	player.Character = rig
	rig.Parent = workspace
	if old and old ~= rig then
		old:Destroy()
	end
	if root and root:IsA("BasePart") then
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end
	return rig
end

function R6Characters.init()
	if not StarterPlayer:FindFirstChild("StarterCharacter") then
		local ok, rig = pcall(function()
			return Players:CreateHumanoidModelFromDescription(plainDescription(), Enum.HumanoidRigType.R6)
		end)
		if ok and rig then
			rig.Name = "StarterCharacter"
			for _, d in rig:GetDescendants() do
				if d:IsA("LuaSourceContainer") then
					d:Destroy()
				end
			end
			local root = rig:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				rig.PrimaryPart = root
			end
			rig.Parent = StarterPlayer
		else
			warn("[R6Characters] could not build the R6 StarterCharacter: " .. tostring(rig))
		end
	end
	-- fetch everyone's avatar early so the first spawn doesn't wait on it
	local function prefetch(player: Player)
		task.spawn(descriptionFor, player)
	end
	Players.PlayerAdded:Connect(prefetch)
	for _, player in Players:GetPlayers() do
		prefetch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		descriptions[player] = nil
	end)
end

return R6Characters

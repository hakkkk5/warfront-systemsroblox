--!strict
-- Everyone plays as an R6 character (the baked animations are R6). The
-- place's avatar setting can't be changed from a script, so an R6
-- StarterCharacter is put in StarterPlayer and each player's own avatar
-- (colours, clothes, accessories) is applied to it when they spawn.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local R6Characters = {}

local descriptions: { [Player]: HumanoidDescription } = {}

local function descriptionFor(player: Player): HumanoidDescription?
	local cached = descriptions[player]
	if cached then
		return cached
	end
	if player.UserId <= 0 then
		return nil -- Studio test players have no avatar
	end
	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if ok and desc then
		descriptions[player] = desc
		return desc
	end
	return nil
end

local function dress(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	local desc = descriptionFor(player)
	if desc then
		local copy = desc:Clone()
		-- R6 ignores body scales; keep the default proportions either way
		copy.HeightScale = 1
		copy.WidthScale = 1
		copy.DepthScale = 1
		copy.HeadScale = 1
		pcall(function()
			humanoid:ApplyDescriptionAsync(copy)
		end)
	end
end

function R6Characters.init()
	if not StarterPlayer:FindFirstChild("StarterCharacter") then
		local ok, rig = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
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
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(dress, player, character)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		descriptions[player] = nil
	end)
end

return R6Characters

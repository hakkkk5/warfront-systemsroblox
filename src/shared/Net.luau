--!strict
-- RemoteEvent registry. The server creates every remote up front; clients wait
-- for them by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local EVENTS = {
	-- server -> client
	"Story", -- objective / chapter state
	"Cutscene", -- play a named cutscene
	"Inventory", -- inventory snapshot
	"Notify", -- toast message
	"Subtitle", -- spoken line
	"Note", -- open a readable note
	"Hurt", -- took damage (for screen fx)
	"Caught", -- killed by a cannibal (jumpscare)
	"Hint", -- objective marker positions
	"Timer", -- survive countdown
	"Recharge", -- flashlight battery refill
	"Hiding", -- entered / left a hiding spot
	"Sound", -- play a 2D sound locally
	"Ending", -- show credits
	"Struggle", -- syringe fight-back: keys to press
	"Scare", -- apparitions, jumpscares, random events
	"ChaseFX", -- spikes and falling trees during the chase
	"StoreResult", -- lobby store: purchase outcome
	"Crafting", -- open the workbench screen
	-- client -> server
	"RequestPlay",
	"CutsceneDone",
	"InventoryAction",
	"Movement", -- sprint / crouch / flashlight state
	"RequestHint",
	"LeaveHiding",
	"PlayAgain",
	"GameOver", -- the whole party is out of lives
	"RequestMap", -- the map wants what to do next
	"MapTargets",
	"StruggleResult",
	"StoreBuy", -- lobby store: buy a perk
	"SaveSettings", -- settings kept with the profile
	"Throw", -- throw the held item (aim)
	"Craft", -- make a recipe at a workbench
}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.event(name: string): RemoteEvent
	local remote = folder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	if RunService:IsServer() then
		error("Unknown remote event: " .. name)
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

return Net

--!strict
-- Cinematic cutscenes. The server fires "Cutscene" with a name and data
-- (see server Story.luau); each scene is a module in this folder:
--
--   return function(data: any, kit: Kit)   -- yields until the scene ends
--
-- The dispatcher locks the player, runs the scene, cleans up everything the
-- scene created through the kit, and always reports "CutsceneDone" so the
-- server's story never stalls - even if a scene errors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Kit = require(script.Kit)

local Cutscenes = {}

Cutscenes.playing = false

type Scene = (data: any, kit: typeof(Kit)) -> ()

local SCENE_NAMES = { "Crash", "WakeUp", "TheyKnow", "TruckFound", "Drive", "DoorLock", "DoorBreak", "Radio", "Ending", "Downed", "Mine", "Dawn" }
local scenes: { [string]: Scene } = {}

local token = 0

local function play(name: string, data: any)
	token += 1
	local mine = token
	local scene = scenes[name]
	Cutscenes.playing = true
	Kit.begin()
	if scene then
		xpcall(scene, function(err)
			warn("[Cutscene] " .. name .. " failed: " .. tostring(err) .. "\n" .. debug.traceback())
		end, data, Kit)
	else
		Kit.fade(1, 0.6)
		task.wait(0.8)
	end
	if mine == token then
		Kit.finish()
		Cutscenes.playing = false
	end
	Net.event("CutsceneDone"):FireServer(name)
end

function Cutscenes.init()
	Kit.init()
	for _, name in SCENE_NAMES do
		local moduleScript = script:FindFirstChild(name)
		if moduleScript and moduleScript:IsA("ModuleScript") then
			local ok, scene = pcall(require, moduleScript)
			if ok and typeof(scene) == "function" then
				scenes[name] = scene :: any
			else
				warn("[Cutscene] could not load " .. name .. ": " .. tostring(scene))
			end
		end
	end
	Net.event("Cutscene").OnClientEvent:Connect(function(name: string, data: any)
		task.spawn(play, name, data)
	end)
	-- the admin skipped this part: cut the scene short
	Net.event("CutsceneSkip").OnClientEvent:Connect(function()
		local stage = script:FindFirstChild("Stage")
		if stage and stage:IsA("ModuleScript") then
			(require(stage) :: any).skip()
		end
	end)
end

return Cutscenes

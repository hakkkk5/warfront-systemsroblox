--!strict
-- ProximityPrompt wrapper. Prompts use the Custom style; the client draws
-- them (see client/UI/Prompts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local Interact = {}

export type Options = {
	action: string,
	object: string?,
	hold: number?,
	distance: number?,
	lineOfSight: boolean?,
	key: Enum.KeyCode?,
	-- return false plus a message to refuse the interaction
	canUse: ((player: Player) -> (boolean, string?))?,
	onUse: (player: Player, prompt: ProximityPrompt) -> (),
	once: boolean?,
}

local notify = Net.event("Notify")
local busy: { [Player]: boolean } = {}

function Interact.notify(player: Player, text: string, kind: string?)
	notify:FireClient(player, text, kind or "info")
end

function Interact.notifyAll(text: string, kind: string?)
	notify:FireAllClients(text, kind or "info")
end

local function playerCanAct(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	if player:GetAttribute("InCutscene") or player:GetAttribute("Hidden") then
		return false
	end
	return true
end
Interact.playerCanAct = playerCanAct

function Interact.add(parent: Instance, opts: Options): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = opts.action
	prompt.ObjectText = opts.object or ""
	prompt.HoldDuration = opts.hold or 0
	prompt.MaxActivationDistance = opts.distance or 8
	prompt.RequiresLineOfSight = if opts.lineOfSight == nil then false else opts.lineOfSight
	prompt.KeyboardKeyCode = opts.key or Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton

	prompt.Triggered:Connect(function(player)
		if busy[player] or not playerCanAct(player) then
			return
		end
		busy[player] = true
		xpcall(function()
			if opts.canUse then
				local allowed, message = opts.canUse(player)
				if not allowed then
					if message then
						Interact.notify(player, message, "warn")
					end
					return
				end
			end
			opts.onUse(player, prompt)
			if opts.once and prompt.Parent then
				prompt:Destroy()
			end
		end, function(err)
			warn("[Interact] " .. tostring(err) .. "\n" .. debug.traceback())
		end)
		busy[player] = nil
	end)

	prompt.Parent = parent
	return prompt
end

return Interact

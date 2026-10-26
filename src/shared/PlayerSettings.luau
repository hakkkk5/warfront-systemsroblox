--!strict
-- The player settings shown in the title menu and the lobby (client UI
-- SettingsPage): their ranges and how each one reads. Saved with the profile
-- (server Profiles) so they follow a player from the lobby into the game.

export type Spec = {
	key: string,
	label: string,
	default: number,
	min: number,
	max: number,
	step: number,
	format: (value: number) -> string,
}

local Lang = require(script.Parent.Lang)

local PlayerSettings = {}

PlayerSettings.List = {
	{
		key = "sensitivity",
		label = "Mouse sensitivity",
		default = 0.6,
		min = 0.1,
		max = 2,
		step = 0.1,
		format = function(v)
			return string.format("%.1f", v)
		end,
	},
	{
		key = "brightness",
		label = "Brightness",
		default = 0,
		min = -0.2,
		max = 0.3,
		step = 0.05,
		format = function(v)
			return string.format("%+d", math.round(v * 20))
		end,
	},
	{
		key = "fov",
		label = "Field of view",
		default = 72,
		min = 60,
		max = 96,
		step = 4,
		format = function(v)
			return tostring(math.round(v))
		end,
	},
	{
		key = "volume",
		label = "Volume",
		default = 1,
		min = 0,
		max = 1,
		step = 0.1,
		format = function(v)
			return string.format("%d%%", math.round(v * 100))
		end,
	},
	{
		-- 1 = on. For photosensitive players: see client Controllers/Settings
		key = "reduceFlashing",
		label = "Reduce flashing",
		default = 0,
		min = 0,
		max = 1,
		step = 1,
		format = function(v)
			return if v >= 0.5 then "On" else "Off"
		end,
	},
	{
		-- 0 = the player's Roblox language (shared Lang)
		key = "language",
		label = "Language",
		default = 0,
		min = 0,
		max = #Lang.List,
		step = 1,
		format = function(v)
			local l = Lang.List[math.round(v)]
			return if l then l.name else "Auto"
		end,
	},
} :: { Spec }

PlayerSettings.ByKey = {} :: { [string]: Spec }
for _, spec in PlayerSettings.List do
	PlayerSettings.ByKey[spec.key] = spec
end

-- Clamps to the range and snaps to the step (so 0.1 steps don't drift).
function PlayerSettings.clamp(spec: Spec, value: number): number
	local snapped = spec.min + math.round((value - spec.min) / spec.step) * spec.step
	return math.clamp(snapped, spec.min, spec.max)
end

-- Known keys with valid numbers only; anything else is dropped.
function PlayerSettings.sanitize(raw: any): { [string]: number }
	local clean: { [string]: number } = {}
	if typeof(raw) ~= "table" then
		return clean
	end
	for key, spec in PlayerSettings.ByKey do
		local value = tonumber(raw[key])
		if value and value == value then
			clean[key] = PlayerSettings.clamp(spec, value)
		end
	end
	return clean
end

return PlayerSettings

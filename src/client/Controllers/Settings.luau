--!strict
-- Player settings read by the effects. Reduce flashing (Menu > Settings) is
-- for photosensitive players: jumpscares drop their strobe and colour flips
-- for one soft pulse, and every full-screen flash is toned down. It starts on
-- when the device asks for reduced motion.

local GuiService = game:GetService("GuiService")

local Settings = {}

local ok, reduced = pcall(function()
	return (GuiService :: any).ReducedMotionEnabled
end)
Settings.reduceFlashing = ok and reduced == true

-- Multiplier for full-screen flash strength.
function Settings.flashScale(): number
	return if Settings.reduceFlashing then 0.35 else 1
end

return Settings

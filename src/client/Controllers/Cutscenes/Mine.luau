--!strict
-- Mine (~13 s): through the old mine in the dark, from the plant to the
-- crypt under Pinecrest's church. Mostly sound: footsteps on the sleepers,
-- dripping, something breathing in a side tunnel.

local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local Stage = require(script.Parent.Stage)

local at = Stage.at

return Stage.scene("Mine", function()
	Stage.fadeWait(1, 0.6)
	Stage.letterbox(true, 0.3)
	Stage.resetClock()
	Stage.loop("Wind", true, 0.25)
	Stage.cleanup(function()
		Stage.loop("Wind", false)
	end)
	at(0.8)
	HUD.subtitle("You", "Stay close. Don't lose the light.", 3)
	for i = 0, 5 do
		Stage.later(1.6 + i * 0.6, function()
			Stage.sfx("Footstep", nil, nil, 0.5, 0.8 + (i % 2) * 0.05)
		end)
	end
	at(4.4)
	HUD.subtitle("You", "Rails. They hauled the coal out this way... and other things.", 3.6)
	at(8.2)
	Stage.sfx("Growl", nil, nil, 0.35, 0.5)
	HUD.subtitle("???", "...supper's on the table...", 2.6)
	at(10.6)
	HUD.subtitle("You", "Light up ahead - stairs. GO!", 2.4)
	for i = 0, 5 do
		Stage.later(10.6 + i * 0.32, function()
			Stage.sfx("Footstep", nil, nil, 0.7, 0.9)
		end)
	end
	at(13)
end)

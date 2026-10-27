--!strict
-- How easy a player is to see, shared by the family's eyes (server
-- Cannibals) and the HUD's "HIDDEN" readout so the two always agree. Crouched
-- low and keeping still with the light off you're a shape in the dark they
-- have to walk right up to; running with the torch on you're seen across the
-- clearing.

local Stealth = {}

-- At or below this the HUD says you're hidden: they'd have to be close and
-- looking straight at you.
Stealth.HIDDEN = 0.35

-- crouching / sprinting / light: the player's attributes; speed: how fast
-- they're moving along the ground.
function Stealth.visibility(crouching: boolean, speed: number, sprinting: boolean, light: boolean): number
	local v = 1
	if crouching then
		v *= 0.5
	end
	if speed < 1 then
		v *= 0.6 -- keeping still
	elseif sprinting then
		v *= 1.25
	end
	if light then
		v *= 1.5
	end
	return v
end

-- The same, read off a player (either side).
function Stealth.of(player: Player, root: BasePart): number
	local velocity = root.AssemblyLinearVelocity
	return Stealth.visibility(
		player:GetAttribute("Crouching") == true,
		Vector3.new(velocity.X, 0, velocity.Z).Magnitude,
		player:GetAttribute("Sprinting") == true,
		player:GetAttribute("Flashlight") == true
	)
end

return Stealth

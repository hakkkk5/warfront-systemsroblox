--!strict
-- Grappling (AnimData/Author): one of the family locked in the syringe fight
-- with you, arms out at your throat, shoving and wrenching, leaning its
-- weight in, the head thrashing.

local Author = require(script.Parent.Author)

local A = CFrame.Angles
local TAU = math.pi * 2

return Author.clip(0.9, function(p: number): Author.Pose
	local s = math.sin(p * TAU)
	local s2 = math.sin(p * TAU * 2)
	local c = math.cos(p * TAU)
	return {
		torso = CFrame.new(0.08 * s, -0.14, -0.15) * A(-0.3 + 0.07 * s2, 0.14 * s, 0.06 * c),
		head = A(0.14 + 0.1 * s2, -0.28 * s, 0.1 * c),
		-- both hands at your throat, one pushing while the other wrenches
		rightArm = A(1.6 + 0.24 * s, 0, -0.2 + 0.1 * c),
		leftArm = A(1.6 - 0.24 * s, 0, 0.2 - 0.1 * c),
		-- braced, one foot forward
		rightLeg = A(0.3 + 0.08 * s, 0, 0.06),
		leftLeg = A(-0.2 - 0.08 * s, 0, -0.06),
	}
end, true)

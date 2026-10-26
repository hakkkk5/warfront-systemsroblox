--!strict
-- Sneaking (AnimData/Author): low and leaning in, short careful steps with
-- the legs kept under the body, the light held out ahead and steady, the
-- other arm out for balance.

local Author = require(script.Parent.Author)

local A = CFrame.Angles
local TAU = math.pi * 2
local LEAN = 0.38

return Author.clip(1.2, function(p: number): Author.Pose
	local s = math.sin(p * TAU)
	local bob = math.cos(p * TAU * 2)
	return {
		torso = CFrame.new(0, -0.42 + 0.04 * bob, 0.12) * A(-LEAN, 0.05 * s, 0),
		head = A(LEAN - 0.08, -0.05 * s, 0),
		rightLeg = A(0.68 + 0.3 * s + LEAN, 0, 0.05),
		leftLeg = A(0.68 - 0.3 * s + LEAN, 0, -0.05),
		rightArm = A(0.75 + LEAN + 0.05 * s, 0, 0.1),
		leftArm = A(0.3 + LEAN - 0.22 * s, 0, -0.16),
	}
end)

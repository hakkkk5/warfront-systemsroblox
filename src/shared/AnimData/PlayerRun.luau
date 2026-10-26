--!strict
-- The players' run (AnimData/Author): running for your life, leaning into
-- it, legs reaching far, arms pumping hard against them, the body bouncing
-- off each stride and the head held up to see where it's going.

local Author = require(script.Parent.Author)

local A = CFrame.Angles
local TAU = math.pi * 2
local LEAN = 0.24

return Author.clip(1, function(p: number): Author.Pose
	local s = math.sin(p * TAU)
	local bob = math.cos(p * TAU * 2)
	return {
		torso = CFrame.new(0, -0.1 + 0.13 * bob, 0) * A(-LEAN, 0.13 * s, 0),
		head = A(LEAN - 0.06, -0.11 * s, 0),
		rightLeg = A(0.95 * s + LEAN * 0.6, 0, 0),
		leftLeg = A(-0.95 * s + LEAN * 0.6, 0, 0),
		rightArm = A(-0.95 * s + 0.25, 0, 0.12),
		leftArm = A(0.95 * s + 0.25, 0, -0.12),
	}
end)

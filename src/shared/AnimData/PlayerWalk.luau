--!strict
-- The players' walk (AnimData/Author): a careful, slightly hunched walk,
-- legs swinging about 30 degrees, arms against them, the body rising as
-- the legs pass and settling as each foot lands. One cycle = two steps.

local Author = require(script.Parent.Author)

local A = CFrame.Angles
local TAU = math.pi * 2
local LEAN = 0.06

return Author.clip(1, function(p: number): Author.Pose
	local s = math.sin(p * TAU)
	local bob = math.cos(p * TAU * 2)
	return {
		torso = CFrame.new(0, -0.05 + 0.05 * bob, 0) * A(-LEAN, 0.06 * s, 0),
		head = A(LEAN - 0.02, -0.05 * s, 0),
		rightLeg = A(0.5 * s + LEAN, 0, 0),
		leftLeg = A(-0.5 * s + LEAN, 0, 0),
		rightArm = A(-0.4 * s + LEAN, 0, 0.05),
		leftArm = A(0.4 * s + LEAN, 0, -0.05),
	}
end)

--!strict
-- Crouched and still (AnimData/Author): low, one knee forward and one leg
-- back, leaning in, the light held out in front, breathing slow, the head
-- turning now and then to listen.

local Author = require(script.Parent.Author)

local A = CFrame.Angles
local TAU = math.pi * 2
local LEAN = 0.35

return Author.clip(4, function(p: number): Author.Pose
	local breathe = math.sin(p * TAU * 2)
	local look = math.sin(p * TAU) * 0.25
	return {
		torso = CFrame.new(0, -0.85 + 0.03 * breathe, 0.15) * A(-LEAN - 0.02 * breathe, 0, 0),
		head = A(LEAN - 0.06, look, 0),
		rightLeg = A(0.96 + LEAN, 0, 0.06),
		leftLeg = A(-0.96 + LEAN, 0, -0.04),
		rightArm = A(0.6 + LEAN + 0.02 * breathe, 0, 0.1),
		leftArm = A(0.25 + LEAN, 0, -0.14),
	}
end)

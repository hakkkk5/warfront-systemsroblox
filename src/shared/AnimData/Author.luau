--!strict
-- Clips written as code, the way the cutscenes pose their actors, instead
-- of baked from animation rigs. A pose function gets the phase of the cycle
-- (0..1) and says, in the torso's own terms:
--
--   torso    the torso's offset and lean from standing (y < 0 lowers it,
--            Angles(-a, 0, 0) leans it forward)
--   head     the head's turn on the neck
--   arms / legs   each limb's swing about its shoulder or hip:
--            Angles(a, 0, 0) with a > 0 swings it forward, Angles(0, 0, r)
--            with r > 0 lifts the right limb out (left: r < 0)
--
-- Author.clip samples it into the frames KeyframeAnimator plays (each joint's
-- Motor6D.Transform, as position and axis * angle), the same as the baked
-- clips. Limbs hang off the torso, so a lean also tips them: to keep a leg
-- where it was in the world, add the lean to its swing.

local Author = {}

export type Pose = {
	torso: CFrame?,
	head: CFrame?,
	leftArm: CFrame?,
	rightArm: CFrame?,
	leftLeg: CFrame?,
	rightLeg: CFrame?,
}

-- the rotation part of each standard R6 joint's C0
local RIGHT = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) -- Right Shoulder, Right Hip
local LEFT = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) -- Left Shoulder, Left Hip
local UPRIGHT = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) -- Neck, RootJoint

local FPS = 30

-- A rotation (and offset) in the parent part's space, as the joint's Transform.
local function toJoint(c0: CFrame, m: CFrame?): CFrame
	return if m then c0:Inverse() * m * c0 else CFrame.identity
end

local function push(out: { number }, cf: CFrame)
	local axis, angle = cf:ToAxisAngle()
	local r = axis * angle
	local p = cf.Position
	for _, v in { p.X, p.Y, p.Z, r.X, r.Y, r.Z } do
		table.insert(out, math.round(v * 10000) / 10000)
	end
end

function Author.clip(length: number, pose: (phase: number) -> Pose, loop: boolean?): { [string]: any }
	local n = math.max(2, math.round(length * FPS))
	local frames = {}
	-- one frame past the end, equal to the first, so the loop joins smoothly
	for i = 0, n do
		local p = pose((i % n) / n)
		local row: { number } = {}
		push(row, toJoint(UPRIGHT, p.torso))
		push(row, toJoint(UPRIGHT, p.head))
		push(row, toJoint(LEFT, p.leftArm))
		push(row, toJoint(RIGHT, p.rightArm))
		push(row, toJoint(LEFT, p.leftLeg))
		push(row, toJoint(RIGHT, p.rightLeg))
		table.insert(frames, row)
	end
	return {
		length = n / FPS,
		fps = FPS,
		loop = loop ~= false,
		joints = { "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" },
		frames = frames,
	}
end

return Author

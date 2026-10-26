--!strict
-- The family doesn't move quite like people. On your screen only (the
-- server's rigs are left alone), their heads snap to wrong angles and hang
-- there, their arms swing a beat late as if they belonged to someone else,
-- and now and then one of them skips: the body jumps a step to the side for
-- a frame and back. It gets worse the closer they are, and worse again when
-- they're after you (State = Chase). Only the family out in the world
-- (workspace.Cannibals), never cutscene actors.
--
-- The animator owns Motor6D.Transform (KeyframeAnimator), so this works on
-- the joints' C0 on top of whatever they're playing.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Uncanny = {}

type Rig = {
	joints: { [Motor6D]: CFrame }, -- the C0s they came with
	neck: Motor6D?,
	root: Motor6D?,
	left: Motor6D?,
	right: Motor6D?,
	tilt: CFrame,
	nextTwitch: number,
	skip: CFrame,
	skipUntil: number,
	nextSkip: number,
	phase: number,
}

local rigs: { [Model]: Rig } = {}

local function joint(parent: Instance?, name: string): Motor6D?
	local j = parent and parent:FindFirstChild(name)
	return if j and j:IsA("Motor6D") then j else nil
end

local function track(model: Instance)
	if not model:IsA("Model") or rigs[model] then
		return
	end
	local torso = model:FindFirstChild("Torso")
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	local now = os.clock()
	local r: Rig = {
		joints = {},
		neck = joint(torso, "Neck"),
		root = joint(rootPart, "RootJoint"),
		left = joint(torso, "Left Shoulder"),
		right = joint(torso, "Right Shoulder"),
		tilt = CFrame.identity,
		nextTwitch = now + math.random() * 3,
		skip = CFrame.identity,
		skipUntil = 0,
		nextSkip = now + 5 + math.random() * 8,
		phase = math.random() * 100,
	}
	for _, j in { r.neck, r.root, r.left, r.right } do
		if j then
			r.joints[j] = j.C0
		end
	end
	rigs[model] = r
end

local function step()
	local now = os.clock()
	local camPos = workspace.CurrentCamera.CFrame.Position
	for model, r in rigs do
		if not model.Parent then
			rigs[model] = nil
			continue
		end
		if not model:FindFirstAncestor("Cannibals") then
			continue
		end
		local rootPart = model:FindFirstChild("HumanoidRootPart")
		local dist = if rootPart and rootPart:IsA("BasePart") then (rootPart.Position - camPos).Magnitude else math.huge
		if dist > 140 then
			continue
		end
		local hunting = model:GetAttribute("State") == "Chase"
		local near = math.clamp(1 - (dist - 8) / 60, 0, 1)
		local strength = 0.35 + near * 0.65 + (if hunting then 0.4 else 0)

		-- the head: snaps to a wrong angle, holds it, snaps back
		if now > r.nextTwitch then
			if r.tilt == CFrame.identity then
				local side = if math.random() < 0.5 then -1 else 1
				r.tilt = CFrame.Angles((math.random() - 0.5) * 0.6 * strength, (math.random() - 0.5) * 0.9 * strength, side * (0.5 + math.random() * 0.5) * strength)
				r.nextTwitch = now + 0.25 + math.random() * (if hunting then 0.4 else 1.2)
			else
				r.tilt = CFrame.identity
				r.nextTwitch = now + (if hunting then 0.3 else 1.2) + math.random() * (if hunting then 1 else 3)
			end
		end
		-- hunting, the head never quite stops shaking
		local shiver = if hunting
			then CFrame.Angles(math.noise(now * 22, r.phase) * 0.12, math.noise(now * 22, r.phase + 3) * 0.12, math.noise(now * 22, r.phase + 7) * 0.18)
			else CFrame.identity
		-- the skip: a frame gone, a step out of place, back again
		if now > r.nextSkip and near > 0.2 then
			r.skipUntil = now + 0.12
			r.skip = CFrame.new((math.random() - 0.5) * 2.4, (math.random() - 0.5) * 2.4, 0)
			r.nextSkip = now + (if hunting then 2.5 else 6) + math.random() * 8
		end
		local skipping = now < r.skipUntil

		if r.neck then
			r.neck.C0 = r.joints[r.neck] * r.tilt * shiver
		end
		if r.root then
			r.root.C0 = r.joints[r.root] * (if skipping then r.skip else CFrame.identity)
		end
		-- the arms hang and swing late, like they belong to someone else
		local sway = math.sin(now * 1.7 + r.phase) * 0.25 * strength
		if r.left then
			r.left.C0 = r.joints[r.left] * CFrame.Angles(sway, 0, 0)
		end
		if r.right then
			r.right.C0 = r.joints[r.right] * CFrame.Angles(-sway * 0.8, 0, 0)
		end
	end
end

function Uncanny.init()
	for _, model in CollectionService:GetTagged("CannibalSkin") do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal("CannibalSkin"):Connect(track)
	RunService.RenderStepped:Connect(step)
end

return Uncanny

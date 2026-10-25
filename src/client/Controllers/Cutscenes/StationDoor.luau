--!strict
-- A local stand-in for the ranger station's door that the station scenes
-- (DoorLock, DoorBreak) can swing, shake and smash. The real door is hidden
-- while a scene runs and comes back when it ends.

local Stage = require(script.Parent.Stage)

local StationDoor = {}

local CF = CFrame.new
local rgb = Color3.fromRGB
local WIDTH, HEIGHT = 4.8, 9

export type Door = {
	center: Vector3,
	inward: Vector3,
	set: (open: number) -> (),
	swing: (open: number, duration: number) -> (),
	thump: (strength: number) -> (),
	smash: () -> (),
	restore: () -> (),
}

-- hinge: the door's hinge CFrame (Doors.create); stationCenter: inside.
function StationDoor.new(hinge: CFrame, stationCenter: Vector3): Door
	local server = workspace:FindFirstChild("StationDoor", true)
	if server then
		Stage.hide(server)
	end
	local slab = Stage.part(Vector3.new(WIDTH - 0.1, HEIGHT - 0.1, 0.32), hinge * CF(WIDTH / 2, HEIGHT / 2, 0), rgb(60, 80, 60), Enum.Material.WoodPlanks)
	local bar = Stage.part(Vector3.new(WIDTH * 0.7, 0.4, 0.4), slab.CFrame * CF(0, -0.6, 0), rgb(50, 64, 50), Enum.Material.WoodPlanks)
	local knob = Stage.part(Vector3.new(0.22, 0.22, 0.6), slab.CFrame * CF(WIDTH / 2 - 0.55, -0.2, 0), rgb(150, 130, 90), Enum.Material.Metal)
	local centerPos = slab.Position
	local inward = Vector3.new(stationCenter.X - centerPos.X, 0, stationCenter.Z - centerPos.Z)
	inward = if inward.Magnitude > 1e-3 then inward.Unit else hinge.LookVector
	-- which way round the hinge opens into the station
	local sign = if hinge:VectorToObjectSpace(inward).Z < 0 then 1 else -1
	local angle = 0

	local function place()
		local frame = hinge * CFrame.Angles(0, sign * angle, 0) * CF(WIDTH / 2, HEIGHT / 2, 0)
		slab.CFrame = frame
		bar.CFrame = frame * CF(0, -0.6, 0)
		knob.CFrame = frame * CF(WIDTH / 2 - 0.55, -0.2, 0)
	end

	local door: Door
	door = {
		center = centerPos,
		inward = inward,
		set = function(open: number)
			angle = open
			place()
		end,
		swing = function(open: number, duration: number)
			local from = angle
			Stage.go(function()
				Stage.animate(duration, function(a)
					angle = from + (open - from) * a * a
					place()
				end)
			end)
		end,
		thump = function(strength: number)
			Stage.go(function()
				angle = 0.03 + strength * 0.025
				place()
				Stage.sleep(0.07)
				angle = 0
				place()
			end)
		end,
		smash = function()
			for _, p in { slab, bar, knob } do
				p.Anchored = false
				p.CanCollide = true
				p.AssemblyLinearVelocity = inward * 60 + Vector3.new(0, 14, 0)
				p.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-8, 8), math.random(-6, 6))
			end
		end,
		restore = function()
			slab:Destroy()
			bar:Destroy()
			knob:Destroy()
		end,
	}
	place()
	return door
end

return StationDoor

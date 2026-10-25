--!strict
-- TruckFound (~10 s): you walk up to the broken-down pickup while the camera
-- orbits it, past the bonnet, ending on you at the driver's door.
-- data: { truck: CFrame }

local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local Stage = require(script.Parent.Stage)
local Cast = require(script.Parent.Cast)

local CF = CFrame.new

return Stage.scene("TruckFound", function(data: any)
	local truckCF = Stage.cf(data.truck, workspace.CurrentCamera.CFrame)
	local function T(x: number, y: number, z: number): Vector3
		return truckCF * Vector3.new(x, y, z)
	end
	Stage.fadeWait(1, 0.45)
	Stage.letterbox(true, 0)
	-- a cold moonlight key so the truck reads in the dark
	local key = Stage.part(Vector3.one, truckCF * CF(-6, 16, -9), Color3.new(0, 0, 0), nil, { Transparency = 1 })
	local moon = Instance.new("PointLight")
	moon.Range = 36
	moon.Brightness = 1.3
	moon.Color = Color3.fromRGB(150, 170, 210)
	moon.Shadows = true
	moon.Parent = key
	-- you come out of the trees and walk up to the driver's door
	local door = Stage.ground(T(-4.8, 0, -0.8))
	local from = Stage.ground(T(-13, 0, 9))
	local me = Cast.me(CFrame.lookAt(from, Vector3.new(door.X, from.Y, door.Z)))
	Stage.go(function()
		Stage.sleep(0.6)
		Cast.walk(me, { Stage.ground(T(-9, 0, 4)), door }, 5.5, { ground = true })
		Cast.face(me, T(-3.4, 4, -0.8), 0.6)
		Cast.pose(me, "leftShoulder", Cast.arm(me, false, 1.2, 0.1), 0.6) -- hand on the door
	end)
	-- orbit from the front-left, low past the bonnet, ending on the driver's door
	Stage.shot(9.3, {
		T(-15, 7.5, -12),
		T(-5, 5.6, -17.5),
		T(5, 4.2, -13.5),
		T(3, 6.9, -9.2),
		T(-11, 6.2, -3),
		T(-9.2, 4.9, 1.8),
	}, {
		T(0, 3, 0),
		T(0, 3.4, -4.5),
		T(0, 3.6, -5.6),
		T(0, 3.3, -5.8),
		T(-3.6, 4.3, -1.6),
		T(-3.8, 4.4, -0.6),
	}, { fov = 60, fovTo = 52, wait = false })
	Stage.fadeTo(0, 0.8)
	Stage.later(1.2, function()
		HUD.subtitle("You", "A truck… out here? Maybe it still runs.", 3.6)
	end)
	Stage.sleep(8.5)
	Stage.fadeTo(1, 0.8)
	Stage.sleep(0.85)
end)

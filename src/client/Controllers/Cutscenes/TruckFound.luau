--!strict
-- TruckFound (~10 s): an orbit around the broken-down pickup, past the
-- bonnet, ending on the driver's door.
-- data: { truck: CFrame }

local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local Stage = require(script.Parent.Stage)

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

--!strict
-- Radio (~19 s): close-up of the field radio, static, the mayday call.
-- data: { radio: CFrame }

local CameraController = require(script.Parent.Parent.CameraController)
local Effects = require(script.Parent.Parent.Effects)
local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local Stage = require(script.Parent.Stage)

local rgb = Color3.fromRGB
local at = Stage.at

return Stage.scene("Radio", function(data: any)
	local radioCF = Stage.cf(data.radio, workspace.CurrentCamera.CFrame)
	-- the set sits turned around on the desk: its face points along +Z here
	local front = radioCF * CFrame.Angles(0, math.pi, 0)
	local function R(x: number, y: number, z: number): Vector3
		return front * Vector3.new(x, y, z)
	end
	local rainOn, rainHeavy = Stage.rainState()
	Stage.fadeWait(1, 0.4)
	Stage.letterbox(true, 0)
	Effects.setRain(false) -- indoors
	Stage.cleanup(function()
		Effects.setRain(rainOn, rainHeavy)
	end)

	-- dial glow that stutters with the static
	local dial = Stage.part(Vector3.new(0.95, 0.32, 0.03), front * CFrame.new(0, 0.05, -0.64), rgb(255, 170, 70), Enum.Material.Neon, {
		Transparency = 0.3,
	})
	local glow = Instance.new("PointLight")
	glow.Color = rgb(255, 160, 80)
	glow.Range = 7
	glow.Brightness = 1.3
	glow.Parent = dial
	local staticOn = false
	Stage.go(function()
		while true do
			dial.Transparency = if staticOn then math.random() * 0.6 else 0.3
			glow.Brightness = if staticOn then 0.4 + math.random() * 1.8 else 1.3
			Stage.sleep(0.04)
		end
	end)
	local function burst(duration: number)
		staticOn = true
		Stage.staticNoise(duration)
		Stage.sfx("Radio", nil, nil, 0.5)
		Stage.later(duration, function()
			staticOn = false
		end)
	end

	Stage.shot(18.4, { R(1.7, 1.2, -3.8), R(0.5, 0.5, -2.7), R(-0.4, 0.35, -2.2) }, { R(0, -0.1, 0), R(0, -0.15, 0), R(0.1, -0.1, 0) }, {
		fov = 60,
		fovTo = 48,
		ease = Stage.smooth,
		wait = false,
	})
	Stage.sway(0.45)
	Stage.resetClock()
	Stage.fadeTo(0, 0.6)
	Stage.loop("Radio", true, 0.35)
	at(0.8)
	HUD.subtitle("You", "Mayday, mayday! Is anyone there?", 3.2)
	at(4.2)
	burst(0.9)
	CameraController.shake(0.15, 4)
	at(4.6)
	HUD.subtitle("Dispatch", "…Pinecrest dispatch… copy… what's your location?", 4)
	at(6.4)
	burst(0.4)
	at(8.8)
	HUD.subtitle("You", "The ranger station off Hollow Road! They're… they're eating people!", 4)
	Stage.sway(0.8)
	at(12.9)
	burst(0.8)
	at(13.2)
	HUD.subtitle("Dispatch", "…rescue chopper inbound, two minutes. Hold on. Barricade yourself in.", 4.4)
	at(15.2)
	burst(0.3)
	at(17.5)
	Stage.fadeTo(1, 0.9)
	Stage.sleep(0.95)
end)

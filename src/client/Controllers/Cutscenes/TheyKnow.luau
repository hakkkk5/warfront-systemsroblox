--!strict
-- TheyKnow (~16 s): the end of Chapter 1. From the hall you watch Jason and
-- Michel whisper by the front door. They know what you found. They turn,
-- the eyes close for a heartbeat, and the friendly couple are gone: two
-- masked butchers stand in their place.
-- data: { camera, jason, michel: CFrame }

local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local CameraController = require(script.Parent.Parent.CameraController)
local Effects = require(script.Parent.Parent.Effects)
local Stage = require(script.Parent.Stage)
local Cast = require(script.Parent.Cast)

local rgb = Color3.fromRGB
local CF = CFrame.new
local UP = Vector3.yAxis
local at = Stage.at
local sleep = Stage.sleep

return Stage.scene("TheyKnow", function(data: any)
	local camera = workspace.CurrentCamera
	local cam = Stage.cf(data.camera, camera.CFrame)
	local jasonCF = Stage.cf(data.jason, cam * CF(-2.7, -4.6, -12.5))
	local michelCF = Stage.cf(data.michel, cam * CF(0.1, -4.6, -11.5))
	local jasonPos, michelPos = jasonCF.Position, michelCF.Position

	Effects.setRain(false)
	Stage.letterbox(true, 0)
	Stage.setBlack(1)
	Stage.eyes(1, 0)
	Stage.blur(0)

	-- one dim bulb over the door
	local bulb = Stage.part(Vector3.new(0.4, 0.4, 0.4), CF((jasonPos + michelPos) / 2 + UP * 9), rgb(255, 210, 150), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 190, 130)
	light.Range = 16
	light.Brightness = 1.1
	light.Shadows = true
	light.Parent = bulb

	-- facing each other, heads down, whispering
	local jason = Cast.actor("Jason", CFrame.lookAt(jasonPos, Vector3.new(michelPos.X, jasonPos.Y, michelPos.Z)), "HostTemplates")
	local michel = Cast.actor("Michel", CFrame.lookAt(michelPos, Vector3.new(jasonPos.X, michelPos.Y, jasonPos.Z)), "HostTemplates")
	Cast.play(jason, "idle")
	Cast.play(michel, "idle")
	Cast.pose(jason, "neck", Cast.neck(jason, -0.25, 0, 0), 0)
	Cast.pose(michel, "neck", Cast.neck(michel, -0.3, 0, 0), 0)

	Stage.cut(cam, 55)
	Stage.move(cam * CF(0, -0.2, -2.6), 11, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	Stage.sway(0.3)
	Stage.resetClock()
	Stage.fadeTo(0, 0.6)
	at(1)
	HUD.subtitle("Michel", "They found it, Jason.", 2.6)
	at(3.8)
	HUD.subtitle("Jason", "…All of it?", 1.8)
	at(5.8)
	HUD.subtitle("Michel", "The drawer. The hatch. Everything.", 2.6)
	at(8.4)
	-- they turn to look straight down the hall
	local camPos = cam.Position
	Stage.go(function()
		Cast.face(jason, camPos, 1.4)
	end)
	Stage.go(function()
		sleep(0.3)
		Cast.face(michel, camPos, 1.4)
	end)
	Cast.pose(jason, "neck", Cast.neck(jason, 0, 0, 0), 1.2)
	Cast.pose(michel, "neck", Cast.neck(michel, 0, 0, 0), 1.2)
	at(10)
	Stage.zoom(38, 1.4)
	HUD.subtitle("Jason", "Find them.", 2.2)
	at(11.6)

	-- blink, and the masks are on
	Stage.eyes(0, 0.12)
	sleep(0.3)
	local butcherCF = jason.root.CFrame - UP * jason.lift
	local brotherCF = michel.root.CFrame - UP * michel.lift
	jason.model:Destroy()
	michel.model:Destroy()
	local butcher = Cast.actor("Butcher", butcherCF)
	local brother = Cast.actor("Brother", brotherCF)
	Cast.play(butcher, "idle")
	Cast.play(brother, "idle")
	Cast.pose(butcher, "rightShoulder", Cast.arm(butcher, true, 1.9, 0.2), 0)
	light.Color = rgb(255, 120, 90)
	Stage.zoom(46, 0)
	Stage.eyes(1, 0.08)
	Stage.sfx("Jumpscare", "Growl", butcherCF.Position, 0.9, 1)
	Stage.sfx("Growl", nil, butcherCF.Position, 1, 0.85)
	CameraController.shake(1.4, 3)
	Stage.go(function()
		Cast.laugh(brother, 1.6)
	end)
	Stage.go(function()
		for _ = 1, 10 do
			light.Brightness = if math.random() < 0.4 then 0.1 else 1.4
			sleep(0.07 + math.random() * 0.1)
		end
		light.Brightness = 1.1
	end)
	sleep(0.6)
	-- the Butcher starts down the hall
	Stage.go(function()
		local toward = Vector3.new(camPos.X, butcherCF.Y, camPos.Z)
		local step = butcherCF.Position + (toward - butcherCF.Position).Unit * 3
		Cast.walk(butcher, { step }, 6)
	end)
	sleep(1.5)
	Stage.setBlack(1)
	Stage.sfx("Impact", nil, nil, 0.8, 0.6)
	sleep(0.6)
	Stage.stopCamera()
	butcher.model:Destroy()
	brother.model:Destroy()
end)

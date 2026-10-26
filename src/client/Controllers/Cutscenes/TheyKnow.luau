--!strict
-- TheyKnow (~17 s): the end of Chapter 1. From the hall you watch Jason and
-- Michel whisper by the front door, over your shoulder. They know what you
-- found. They turn, the bulb dies for a heartbeat, and the friendly couple
-- are gone: two masked butchers stand in their place, and Papa steps out of
-- the dining room between you and them with the chainsaw running. You run.
-- data: { camera, jason, michel, house: CFrame }

local Util = require(game:GetService("ReplicatedStorage").Shared.Util)
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

	-- you, at the end of the hall, watching them over your shoulder
	local forward = Util.flat(cam.LookVector)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.new(0, 0, -1)
	local standAt = cam.Position + forward * 2.2 + cam.RightVector * 0.9 - UP * 4.6
	local me = Cast.me(CFrame.lookAt(standAt, standAt + forward))
	Cast.play(me, "idle")
	Cast.pose(me, "waist", Cast.waist(me, 0.15, -0.2), 0) -- leaning round the corner

	Stage.cut(cam * CF(1.3, 0.4, 2.4), 55)
	Stage.move(cam * CF(1.1, 0.2, 0.9), 11, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
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

	-- the bulb dies for a heartbeat, and the masks are on
	Stage.sfx("FlashlightClick", nil, bulb.Position, 1, 0.8)
	light.Enabled = false
	bulb.Material = Enum.Material.SmoothPlastic
	Stage.fadeTo(0.85, 0.08)
	sleep(0.35)
	light.Enabled = true
	bulb.Material = Enum.Material.Neon
	Stage.fadeTo(0, 0.06)
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
	Cast.pose(me, "waist", Cast.waist(me, -0.15, 0), 0.15) -- you flinch back
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
	-- and Papa steps out of the dining room doorway, between you and them,
	-- the chainsaw already running
	local house = Stage.cf(data.house, cam)
	local dining = house * CF(7, 0, -11.5)
	local papa = Cast.actor("Papa", CFrame.lookAt(dining.Position, (house * CF(0, 0, -11.5)).Position))
	Cast.play(papa, "idle")
	Cast.pose(papa, "rightShoulder", Cast.arm(papa, true, 1.4, 0.3), 0)
	Stage.sfx("Chainsaw", nil, dining.Position, 1, 1)
	CameraController.shake(0.8, 2.5)
	Stage.go(function()
		Cast.walk(papa, { (house * CF(2.5, 0, -10)).Position }, 7)
		Cast.face(papa, camPos, 0.4)
		Cast.laugh(papa, 1.2)
	end)
	Stage.zoom(42, 0.5)
	sleep(0.9)
	-- the Butcher starts down the hall; you turn and run past the camera
	Stage.go(function()
		local toward = Vector3.new(camPos.X, butcherCF.Y, camPos.Z)
		local step = butcherCF.Position + (toward - butcherCF.Position).Unit * 3
		Cast.walk(butcher, { step }, 6)
	end)
	Stage.go(function()
		Cast.pose(me, "waist", CFrame.identity, 0.2)
		local base = me.root.Position - UP * me.lift
		Cast.face(me, base - forward * 10, 0.3)
		Cast.walk(me, { base - forward * 6 + cam.RightVector * 1.8 }, 16, { anim = 1.1 })
	end)
	Stage.zoom(60, 1)
	sleep(1.5)
	Stage.setBlack(1)
	Stage.sfx("Impact", nil, nil, 0.8, 0.6)
	sleep(0.6)
	Stage.stopCamera()
	butcher.model:Destroy()
	brother.model:Destroy()
	papa.model:Destroy()
	me.model:Destroy()
end)

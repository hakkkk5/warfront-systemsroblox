--!strict
-- DoorBreak (~11 s): the siege begins. Inside the station you hear it come
-- back up the steps. The door takes one hit, two, three, then bursts off
-- its hinges and the monster stands in the doorway, screaming.
-- data: { door: CFrame (the door's hinge), center: Vector3 (station centre) }

local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local CameraController = require(script.Parent.Parent.CameraController)
local Effects = require(script.Parent.Parent.Effects)
local MonsterForm = require(script.Parent.Parent.MonsterForm)
local Stage = require(script.Parent.Stage)
local Cast = require(script.Parent.Cast)
local StationDoor = require(script.Parent.StationDoor)

local UP = Vector3.yAxis
local at = Stage.at
local sleep = Stage.sleep

return Stage.scene("DoorBreak", function(data: any)
	local hinge = Stage.cf(data.door, workspace.CurrentCamera.CFrame)
	local center = if typeof(data.center) == "Vector3" then data.center else hinge.Position
	local door = StationDoor.new(hinge, center)
	local doorCenter = door.center
	local inward = door.inward
	local side = inward:Cross(UP).Unit
	local floor = Vector3.new(doorCenter.X, hinge.Y, doorCenter.Z)

	Stage.letterbox(true, 0)
	Stage.setBlack(1)
	door.set(0)
	-- you, backing away from the door
	local standAt = floor + inward * 8 + side * 2.5
	local me = Cast.me(CFrame.lookAt(standAt, Vector3.new(doorCenter.X, standAt.Y, doorCenter.Z)))
	Cast.play(me, "idle")
	local monster = Cast.actor("Butcher", CFrame.lookAt(floor - inward * 3, floor + inward))
	MonsterForm.apply(monster.model, true, true, true)

	Stage.cut(CFrame.lookAt(floor + inward * 14 + UP * 4 - side * 3, doorCenter), 55)
	Stage.move(CFrame.lookAt(floor + inward * 11 + UP * 3.5 - side * 2, doorCenter), 7)
	Stage.resetClock()
	Stage.fadeTo(0, 0.5)
	at(0.4)
	HUD.subtitle("???", "Little guest, little guest... let me come in.", 2.6)
	Stage.sfx("Growl", nil, doorCenter - inward * 2, 0.4, 0.5)
	at(2.6)
	HUD.subtitle("You", "...no. No no no.", 1.6)
	for i = 1, 3 do
		at(1.8 + i * 1.3)
		door.thump(i + 1)
		Stage.sfx("Impact", nil, doorCenter, 1, 0.5)
		CameraController.shake(1.2 + i * 0.7, 4)
		if i == 2 then
			Stage.go(function()
				Cast.walk(me, { standAt + inward * 3 }, 3, { anim = 0.4 })
				Cast.face(me, doorCenter, 0.3)
			end)
		end
	end
	at(6.2)
	-- it comes through
	door.smash()
	Stage.sfx("Explosion", nil, doorCenter, 1, 0.8)
	Stage.sfx("Scream", nil, doorCenter, 1, 0.7)
	Effects.flash(Color3.fromRGB(255, 30, 20), 0.6)
	CameraController.shake(4, 2)
	Stage.zoom(40, 0.4)
	Stage.go(function()
		Cast.walk(monster, { floor + inward * 1.5 }, 10, { anim = 1.2 })
		Cast.pose(monster, "rightShoulder", Cast.arm(monster, true, 2.6, 0.3), 0.3)
		Cast.pose(monster, "leftShoulder", Cast.arm(monster, false, 2.6, 0.3), 0.3)
	end)
	at(7)
	HUD.subtitle("You", "RUN- hide- just MOVE!", 2)
	at(9.6)
	Stage.fadeTo(1, 0.4)
	sleep(0.5)
	Stage.stopCamera()
	door.restore()
	monster.model:Destroy()
	me.model:Destroy()
end)

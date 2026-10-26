--!strict
-- DoorLock (~14 s): the end of the chase. You sprint up the station steps
-- with the monster right behind you, get inside, slam the door and throw
-- the bolt. It hits the door, again, again... then it goes quiet.
-- data: { door: CFrame (the door's hinge), center: Vector3 (station centre) }

local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local CameraController = require(script.Parent.Parent.CameraController)
local MonsterForm = require(script.Parent.Parent.MonsterForm)
local Stage = require(script.Parent.Stage)
local Cast = require(script.Parent.Cast)
local StationDoor = require(script.Parent.StationDoor)

local UP = Vector3.yAxis
local at = Stage.at
local sleep = Stage.sleep

return Stage.scene("DoorLock", function(data: any)
	local hinge = Stage.cf(data.door, workspace.CurrentCamera.CFrame)
	local center = if typeof(data.center) == "Vector3" then data.center else hinge.Position
	local door = StationDoor.new(hinge, center)
	local doorCenter = door.center
	local inward = door.inward
	local floorY = Stage.groundY(doorCenter.X - inward.X * 10, doorCenter.Z - inward.Z * 10, hinge.Y)

	Stage.letterbox(true, 0)
	Stage.setBlack(1)
	door.set(1.6)

	-- outside: you running for the door, the monster on your heels
	local outsideFar = Vector3.new(doorCenter.X, floorY, doorCenter.Z) - inward * 22
	local me = Cast.me(CFrame.lookAt(outsideFar, outsideFar + inward))
	local monster = Cast.actor("Butcher", CFrame.lookAt(outsideFar - inward * 9, outsideFar))
	MonsterForm.apply(monster.model, true, true, true)
	local inside = Vector3.new(doorCenter.X, hinge.Y, doorCenter.Z) + inward * 3
	Stage.go(function()
		Cast.walk(me, { Vector3.new(doorCenter.X, hinge.Y, doorCenter.Z) - inward * 2, inside }, 26, { anim = 1.4 })
		Cast.face(me, doorCenter, 0.25)
	end)
	Stage.go(function()
		Cast.walk(monster, { Vector3.new(doorCenter.X, floorY, doorCenter.Z) - inward * 4 }, 23, { anim = 1.5 })
	end)

	local side = inward:Cross(UP).Unit
	Stage.cut(CFrame.lookAt(outsideFar + side * 9 + UP * 3 - inward * 4, doorCenter), 62)
	Stage.track(function()
		local p = me.root.Position
		return CFrame.lookAt(p + side * 8 + UP * 2.5 - inward * 6, p + inward * 4)
	end)
	Stage.resetClock()
	Stage.fadeTo(0, 0.3)
	CameraController.shake(0.8, 4)
	at(0.4)
	HUD.subtitle("You", "*gasping* Come on, come on...!", 2)
	at(1.3)

	-- inside, facing the door: you burst in and slam it
	Stage.stopCamera()
	Stage.cut(CFrame.lookAt(doorCenter + inward * 12 + UP * 1 + side * 4, doorCenter - side * 1.5), 60)
	at(1.6)
	door.swing(0, 0.22)
	Stage.sfx("Impact", nil, doorCenter, 1, 0.8)
	CameraController.shake(1.6, 5)
	at(2.1)
	-- the bolt
	Cast.pose(me, "rightShoulder", Cast.arm(me, true, 1.4, 0), 0.25)
	Stage.sfx("Unlock", nil, doorCenter, 1, 0.7)
	HUD.subtitle("You", "Lock- lock it, LOCK IT!", 1.8)
	at(2.8)
	Cast.pose(me, "rightShoulder", CFrame.identity, 0.4)
	Stage.go(function()
		Cast.walk(me, { inside + inward * 3 - side * 3.5 }, 3, { anim = 0.4 })
		Cast.face(me, doorCenter, 0.3)
	end)
	Stage.zoom(48, 6)

	-- it hits the door
	for i = 1, 3 do
		at(3.4 + i * 1.6)
		door.thump(i)
		Stage.sfx("Impact", nil, doorCenter, 1, 0.55 + i * 0.05)
		Stage.sfx("Growl", nil, doorCenter - inward * 2, 0.9, 0.7)
		CameraController.shake(1 + i * 0.6, 4)
	end
	at(8.6)
	HUD.subtitle("You", "...please hold... please hold...", 2.6)
	at(11.2)
	-- silence; its steps fade off the porch
	monster.model:Destroy()
	HUD.subtitle("You", "...it stopped. It's waiting.", 2.4)
	-- ...then the handle turns, slowly, and a whisper through the wood
	at(13.4)
	Stage.sfx("DoorLocked", nil, doorCenter, 0.7, 0.7)
	door.thump(1)
	Stage.zoom(40, 1.4)
	at(14.2)
	HUD.subtitle("???", "(whispering) ...open the door. We just want to talk.", 3)
	at(16.6)
	Stage.fadeTo(1, 0.6)
	sleep(0.7)
	Stage.stopCamera()
	door.restore()
	me.model:Destroy()
end)

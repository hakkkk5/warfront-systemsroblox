--!strict
-- WakeUp (~37 s), shot from across the room: you come to on the farmhouse
-- sofa by the fire. Michel and Jason are kind, a little too kind: the phone
-- is down, they'll drive you to town in the morning, make yourself at
-- home... and stay out of the basement. You sit up; they leave you to rest,
-- and the camera settles back into your eyes for the game.
-- data: { eye, jason, michel, exit, doorway: CFrame }

local Players = game:GetService("Players")

local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local Effects = require(script.Parent.Parent.Effects)
local Stage = require(script.Parent.Stage)
local Cast = require(script.Parent.Cast)

local rgb = Color3.fromRGB
local CF = CFrame.new
local UP = Vector3.yAxis
local at = Stage.at
local sleep = Stage.sleep

return Stage.scene("WakeUp", function(data: any)
	local camera = workspace.CurrentCamera
	local eye = Stage.cf(data.eye, camera.CFrame)
	local doorway = Stage.cf(data.doorway, eye * CF(-8, -3.9, 14))
	local exit = Stage.cf(data.exit, doorway * CF(3, 0, 0))
	local alone = #Players:GetPlayers() <= 1

	-- house frame from the doorway (L(-6.5, 0, -11.5)) and the hall (L(-3.5, 0, -11.5))
	local hx = exit.Position - doorway.Position
	local houseCF = if hx.Magnitude > 0.5
		then CFrame.fromMatrix(doorway.Position, hx.Unit, UP) * CF(6.5, 0, 11.5)
		else CF(doorway.Position) * CF(6.5, 0, 11.5)
	local function L(x: number, y: number, z: number): Vector3
		return (houseCF * CF(x, y, z)).Position
	end
	local function H(x: number, z: number): Vector3
		return L(x, 0, z)
	end
	local X, Z = houseCF.XVector, houseCF.ZVector

	Effects.setRain(false) -- indoors
	Stage.letterbox(true, 0)
	Stage.setBlack(1)
	Stage.eyes(1, 0)
	Stage.blur(8)

	-- warm firelight
	local glow = Stage.part(Vector3.one, houseCF * CF(-26, 3.5, -6), rgb(0, 0, 0), nil, { Transparency = 1 })
	local fire = Instance.new("PointLight")
	fire.Color = rgb(255, 160, 90)
	fire.Range = 22
	fire.Brightness = 1.1
	fire.Shadows = true
	fire.Parent = glow
	Stage.go(function()
		while true do
			fire.Brightness = 1 + math.noise(os.clock() * 4) * 0.35
			sleep(0)
		end
	end)

	-- you, lying along the sofa, head on the armrest
	local me = Cast.me(CFrame.identity)
	Cast.still(me)
	Cast.pose(me, "neck", Cast.neck(me, 0.25, -0.3, 0), 0)
	Cast.pose(me, "rightShoulder", Cast.arm(me, true, 0.3, 0.3), 0)
	Cast.pose(me, "leftShoulder", Cast.arm(me, false, -0.2, 0.1), 0)
	local lying = CFrame.fromMatrix(L(-20.3, 2.65, -6.6), -X, -Z)
	local seatPos = L(-20.2, 2.1, -6) + UP * Cast.seatLift(me)
	local seated = CFrame.lookAt(seatPos, seatPos - X)
	me.root.CFrame = lying

	local jason = Cast.actor("Jason", Stage.cf(data.jason, CFrame.lookAt(H(-25.5, -9.6), H(-20.6, -6))), "HostTemplates")
	local michel = Cast.actor("Michel", Stage.cf(data.michel, CFrame.lookAt(H(-24.4, -2.6), H(-20.6, -6))), "HostTemplates")
	Cast.play(jason, "idle")
	Cast.play(michel, "idle")
	Cast.pose(jason, "neck", Cast.neck(jason, -0.18, 0, 0), 0)

	local function myHead(): Vector3
		return Cast.head(me)
	end
	local function michelHead(): Vector3
		return Cast.head(michel)
	end
	local function jasonHead(): Vector3
		return Cast.head(jason)
	end

	-- the camera: a position that glides between set-ups and a focus that
	-- follows whoever is talking
	local camPos = L(-15, 7.5, -1)
	local camGoal = camPos
	local glide = 0.6
	local focusFn: () -> Vector3 = function()
		return L(-21.5, 2.4, -6.3)
	end
	local focus = focusFn()
	local rate = 1.5
	local function shot(pos: Vector3, fn: () -> Vector3, cut: boolean?, glideRate: number?)
		camGoal = pos
		focusFn = fn
		glide = glideRate or 0.6
		if cut then
			camPos = pos
			focus = fn()
		end
	end
	Stage.track(function(dt)
		camPos = camPos:Lerp(camGoal, 1 - math.exp(-glide * dt))
		focus = focus:Lerp(focusFn(), 1 - math.exp(-rate * dt))
		return CFrame.lookAt(camPos, focus)
	end)
	Stage.zoom(55, 0)
	Stage.sway(0.25)

	Stage.resetClock()
	shot(L(-15.8, 6.8, -2.2), function()
		return L(-21.5, 2.4, -6.3)
	end, false, 0.15)
	Stage.fadeTo(0, 1.6)
	Stage.blurTo(1.5, 4)
	at(2.6)
	-- Michel leans over the sofa
	Cast.pose(michel, "waist", Cast.waist(michel, 0.32), 1.4)
	Cast.pose(michel, "neck", Cast.neck(michel, -0.3, 0, 0), 1.4)
	at(3.8)
	HUD.subtitle("Michel", "There you are. You gave us quite a scare.", 3.4)
	at(5.4)
	Cast.pose(me, "neck", Cast.neck(me, 0.2, 0.35, 0), 1.2) -- you stir, turning to the voice
	at(7.4)
	HUD.subtitle("You", "Wh… where am I…?", 2.4)
	at(9.4)
	-- over you, toward Jason
	shot(L(-19.4, 4.4, -4.4), jasonHead, true)
	Stage.zoom(48, 0)
	Cast.pose(jason, "neck", Cast.neck(jason, -0.12, 0, 0), 0.6)
	at(9.6)
	HUD.subtitle("Jason", "Our place. Your car wrapped itself around a pine on Hollow Road.", 3.6)
	at(13.2)
	-- you sit up, face on, between the two of them
	shot(L(-27.6, 4.3, -6.3), myHead, true)
	Stage.zoom(50, 0)
	Stage.go(function()
		Stage.animate(2.2, function(a)
			me.root.CFrame = lying:Lerp(seated, Stage.smooth(a))
		end)
	end)
	Cast.sit(me, 0.35, 2.2)
	Cast.pose(me, "neck", CFrame.identity, 2.2)
	Cast.pose(michel, "waist", CFrame.identity, 1.6)
	Cast.pose(michel, "neck", Cast.neck(michel, -0.12, 0, 0), 1.6)
	at(14)
	if alone then
		HUD.subtitle("Michel", "Your friends…? Sweetheart, you were the only one in that car.", 4)
	else
		HUD.subtitle("Michel", "Your friends are fine. A few bruises, that's all.", 3.6)
	end
	at(16.2)
	-- over Michel's shoulder
	shot(L(-26.6, 5.6, -1.2), myHead, true)
	at(18)
	if alone then
		HUD.subtitle("You", "No… no, they were right there next to me…", 2.8)
		Cast.pose(me, "neck", Cast.neck(me, -0.25, 0.2, 0), 0.8)
	else
		HUD.subtitle("You", "Thank you… both of you.", 2.4)
	end
	at(20.4)
	shot(L(-19.8, 4.5, -3.2), jasonHead, true)
	HUD.subtitle("Jason", "Phone line's down with the storm. We'll drive you into town come morning.", 3.8)
	at(24.2)
	shot(L(-21.4, 4.6, -4.4), michelHead, true)
	HUD.subtitle("Michel", "Make yourself at home. There's stew on the stove.", 3)
	at(27.2)
	-- the smile slips
	Stage.zoom(36, 2.2)
	Cast.pose(michel, "neck", Cast.neck(michel, -0.2, 0, 0.06), 1)
	Stage.sfx("Thunder", nil, nil, 0.35, 0.8)
	HUD.subtitle("Michel", "Just… stay out of the basement. It floods.", 3.6)
	at(31)
	Stage.zoom(52, 0)
	shot(L(-17.6, 5.2, -7.6), jasonHead, true)
	Cast.pose(jason, "neck", CFrame.identity, 0.5)
	HUD.subtitle("Jason", if alone then "Come on, Michel. Let our guest rest." else "Come on, Michel. Let our guests rest.", 2.8)
	at(31.8)
	-- they leave through the hall doorway
	Stage.go(function()
		Cast.walk(jason, { doorway.Position, exit.Position, H(0, -3) }, 4.6)
	end)
	Stage.go(function()
		sleep(0.7)
		Cast.pose(michel, "neck", CFrame.identity, 0.5)
		Cast.walk(michel, { H(-24.5, -10.8), doorway.Position, exit.Position, H(0, -3) }, 4.4)
	end)
	at(32.6)
	focusFn = michelHead
	at(35)
	-- back into your own eyes for the game
	local eyePos = myHead() + seated.LookVector * 0.3
	shot(eyePos, function()
		return eyePos + seated.LookVector * 10
	end, false, 2.2)
	Stage.zoom(70, 1.6)
	at(36.4)
	Stage.fadeTo(1, 0.8)
	sleep(0.9)
	Stage.stopCamera()
	jason.model:Destroy()
	michel.model:Destroy()
	me.model:Destroy()
end)

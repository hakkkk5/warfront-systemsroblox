--!strict
-- WakeUp (~36 s): coming to on the farmhouse sofa by the fire. Michel and
-- Jason are kind, a little too kind: the phone is down, they'll drive you to
-- town in the morning, make yourself at home... and stay out of the basement.
-- Then they leave you to rest.
-- data: { eye, jason, michel, exit, doorway: CFrame }

local Players = game:GetService("Players")

local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local Effects = require(script.Parent.Parent.Effects)
local Util = require(game:GetService("ReplicatedStorage").Shared.Util)
local Stage = require(script.Parent.Stage)
local Cast = require(script.Parent.Cast)

local rgb = Color3.fromRGB
local CF = CFrame.new
local rad = math.rad
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
	local function H(x: number, z: number): Vector3
		return (houseCF * CF(x, 0, z)).Position
	end

	Effects.setRain(false) -- indoors
	Stage.letterbox(true, 0)
	Stage.setBlack(1)
	Stage.eyes(0, 0)
	Stage.blur(18)

	-- warm firelight on their faces
	local glow = Stage.part(Vector3.one, eye * CF(0, 0.4, -6.5), rgb(0, 0, 0), nil, { Transparency = 1 })
	local fire = Instance.new("PointLight")
	fire.Color = rgb(255, 160, 90)
	fire.Range = 18
	fire.Brightness = 0.9
	fire.Shadows = true
	fire.Parent = glow
	Stage.go(function()
		while true do
			fire.Brightness = 0.8 + math.noise(os.clock() * 4) * 0.3
			sleep(0)
		end
	end)

	local jason = Cast.actor("Jason", Stage.cf(data.jason, eye * CF(-3.6, -3.9, -4.9)), "HostTemplates")
	local michel = Cast.actor("Michel", Stage.cf(data.michel, eye * CF(3.4, -3.9, -3.8)), "HostTemplates")
	Cast.play(jason, "idle")
	Cast.play(michel, "idle")
	Cast.pose(jason, "neck", Cast.neck(jason, -0.18, 0, 0), 0)

	-- the camera is your head: lying on the sofa at first, then sitting up
	local offsetV = Instance.new("Vector3Value")
	offsetV.Value = Vector3.new(0, -1.3, 0.6)
	offsetV.Parent = Stage.folder()
	local rollV = Stage.numberValue(rad(72))
	local focusFn: () -> Vector3 = function()
		return Cast.head(michel)
	end
	local focus = focusFn()
	local rate = 1.2
	local function lookAt(fn: () -> Vector3, r: number)
		focusFn = fn
		rate = r
	end
	local function michelHead(): Vector3
		return Cast.head(michel)
	end
	local function jasonHead(): Vector3
		return Cast.head(jason)
	end
	Stage.track(function(dt)
		focus = focus:Lerp(focusFn(), 1 - math.exp(-rate * dt))
		local p = eye * offsetV.Value
		return CFrame.lookAt(p, focus) * CFrame.Angles(0, 0, rollV.Value)
	end)
	Stage.zoom(66, 0)
	Stage.sway(0.5)

	Stage.resetClock()
	Stage.fadeTo(0, 0.5)
	at(1.2)
	Stage.eyes(0.25, 1.2)
	at(2.6)
	Stage.eyes(0, 0.3)
	at(3.3)
	Stage.eyes(0.55, 1.2)
	Stage.blurTo(8, 2.5)
	-- Michel leans over the sofa
	Cast.pose(michel, "waist", Cast.waist(michel, 0.32), 1.4)
	Cast.pose(michel, "neck", Cast.neck(michel, -0.3, 0, 0), 1.4)
	at(3.8)
	HUD.subtitle("Michel", "There you are. You gave us quite a scare.", 3.4)
	at(6.4)
	Stage.blink(0.18, 0.2, 0.5, 1)
	Stage.blurTo(2, 2)
	at(7.6)
	HUD.subtitle("You", "Wh… where am I…?", 2.4)
	at(9.4)
	lookAt(jasonHead, 1.3)
	Cast.pose(jason, "neck", Cast.neck(jason, -0.12, 0, 0), 0.6)
	at(9.6)
	HUD.subtitle("Jason", "Our place. Your car wrapped itself around a pine on Hollow Road.", 3.6)
	at(13.2)
	-- sit up
	Util.tween(offsetV, 2.2, { Value = Vector3.zero }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	Util.tween(rollV, 2.2, { Value = 0.03 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	Cast.pose(michel, "waist", CFrame.identity, 1.6)
	Cast.pose(michel, "neck", Cast.neck(michel, -0.12, 0, 0), 1.6)
	lookAt(michelHead, 1.1)
	at(13.8)
	if alone then
		HUD.subtitle("Michel", "Your friends…? Sweetheart, you were the only one in that car.", 4)
	else
		HUD.subtitle("Michel", "Your friends are fine. A few bruises, that's all.", 3.6)
	end
	at(17.9)
	if alone then
		HUD.subtitle("You", "No… no, they were right there next to me…", 2.8)
	else
		HUD.subtitle("You", "Thank you… both of you.", 2.4)
	end
	at(20.4)
	lookAt(jasonHead, 1.2)
	HUD.subtitle("Jason", "Phone line's down with the storm. We'll drive you into town come morning.", 3.8)
	at(24.2)
	lookAt(michelHead, 1.2)
	HUD.subtitle("Michel", "Make yourself at home. There's stew on the stove.", 3)
	at(27.2)
	-- the smile slips
	Stage.zoom(56, 2)
	Cast.pose(michel, "neck", Cast.neck(michel, -0.2, 0, 0.06), 1)
	Stage.sfx("Thunder", nil, nil, 0.35, 0.8)
	HUD.subtitle("Michel", "Just… stay out of the basement. It floods.", 3.6)
	at(31)
	Stage.zoom(66, 1.4)
	lookAt(jasonHead, 1.2)
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
	lookAt(function()
		return Cast.head(michel)
	end, 1.4)
	at(36.2)
	Stage.fadeTo(1, 0.9)
	sleep(1)
	Stage.stopCamera()
	jason.model:Destroy()
	michel.model:Destroy()
end)

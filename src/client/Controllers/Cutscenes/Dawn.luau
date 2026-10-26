--!strict
-- Dawn (~22 s): the very end. The sky goes grey, the state police cruiser
-- pulls away down Pinecrest's Main Street with its lights going, and in the
-- church doorway the family stands and watches it go. Then the valley from
-- high up, the cruiser's lights getting smaller.
-- data: { cruiser: Model?, church: CFrame, trueEnding: boolean }

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.Parent.Parent.UI.HUD)
local Stage = require(script.Parent.Stage)

local at = Stage.at

return Stage.scene("Dawn", function(data: any)
	local church = Stage.cf(data.church, workspace.CurrentCamera.CFrame)
	local original = data.cruiser
	Stage.fadeWait(1, 0.4)
	Stage.letterbox(true, 0)

	-- dawn coming up
	local clock, brightness = Lighting.ClockTime, Lighting.Brightness
	Stage.cleanup(function()
		Lighting.ClockTime = clock
		Lighting.Brightness = brightness
	end)
	Lighting.ClockTime = 5.4
	Util.tween(Lighting, 20, { ClockTime = 6.6, Brightness = math.max(brightness, 1.6) })

	-- the cruiser we drive away (a copy; the real one stays parked)
	local car: Model? = nil
	local start = church * CFrame.new(4, 0, -104)
	if typeof(original) == "Instance" and original:IsA("Model") then
		local copy = original:Clone()
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		start = copy:GetPivot()
		copy.Parent = workspace
		for _, d in original:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			end
		end
		Stage.cleanup(function()
			copy:Destroy()
			for _, d in original:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				end
			end
		end)
		car = copy
	end

	-- the family in the church doorway, watching
	local templates = ReplicatedStorage:FindFirstChild("CannibalTemplates")
	if templates then
		local options = templates:GetChildren()
		for i = 1, math.min(4, #options) do
			local rig = options[i]:Clone()
			if rig:IsA("Model") then
				for _, d in rig:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
					end
				end
				local spot = church * CFrame.new(-4.5 + (i - 1) * 3, 4.8, -30.5) * CFrame.Angles(0, math.pi, 0)
				rig:PivotTo(spot)
				rig.Parent = workspace
				Stage.cleanup(function()
					rig:Destroy()
				end)
			end
		end
	end

	-- the drive: down Main Street toward the highway, away from the church
	local away = start.LookVector
	local t0 = os.clock()
	local done = false
	Stage.cleanup(function()
		done = true
	end)
	Stage.go(function()
		while not done do
			local t = os.clock() - t0
			local travel = math.max(0, t - 2) ^ 1.6 * 2.2
			local carCF = start + away * travel
			if car then
				car:PivotTo(carCF)
			end
			local camCF: CFrame
			if t < 8 then
				-- low on the road by the church steps, the car pulling away
				local eye = (church * CFrame.new(-6, 2.2, -40)).Position
				camCF = CFrame.lookAt(eye, carCF.Position + Vector3.new(0, 2, 0))
			elseif t < 14 then
				-- the family in the doorway, seen from the street
				local eye = (church * CFrame.new(2, 5, -52)).Position
				local look = (church * CFrame.new(0, 7, -30)).Position
				camCF = CFrame.lookAt(eye + Vector3.new(0, 0, -(t - 8) * 0.6), look)
			else
				-- high over the valley, the lights getting smaller
				local eye = carCF.Position + Vector3.new(0, 70 + (t - 14) * 6, 0) - away * 60
				camCF = CFrame.lookAt(eye, carCF.Position)
			end
			Stage.cut(camCF, if t < 14 then 55 else 65)
			RunService.RenderStepped:Wait()
		end
	end)

	Stage.loop("Siren", true, 0.4)
	Stage.cleanup(function()
		Stage.loop("Siren", false)
	end)
	Stage.resetClock()
	Stage.fadeTo(0, 1.2)
	at(1.4)
	HUD.subtitle("Trooper", "You're safe now. You're safe. What in God's name happened out there?", 4.4)
	at(6.2)
	if data.trueEnding then
		HUD.subtitle("Trooper", "The pilot flagged us down on the highway. And a ranger - Ellis - walked out of the woods an hour ago.", 5)
	else
		HUD.subtitle("You", "...don't stop. Whatever you do, don't stop the car.", 4)
	end
	at(9)
	HUD.subtitle("???", "...there's always room at the table...", 3.4)
	at(13.5)
	HUD.subtitle("You", if data.trueEnding then "Everyone made it. Everyone." else "They're still hungry.", 3.6)
	at(19)
	Stage.fadeTo(1, 2.5)
	at(21.8)
	done = true
end)

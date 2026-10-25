--!strict
-- Night-time lighting, fog and post processing. Clients add their own
-- dynamic effects (fear vignette, lightning, blur) on top.

local Lighting = game:GetService("Lighting")

local LightingSetup = {}

local function ensure(className: string, name: string): any
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

function LightingSetup.apply()
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)
	Lighting.ClockTime = 0.4
	Lighting.GeographicLatitude = 41
	Lighting.Brightness = 1.1 -- a bright moon: dark, but you can see where you are going
	Lighting.Ambient = Color3.fromRGB(28, 27, 32)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 78, 98)
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ExposureCompensation = 0.2
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.ColorShift_Top = Color3.fromRGB(110, 130, 170)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)

	local sky: Sky = ensure("Sky", "NightSky")
	sky.StarCount = 3500
	sky.MoonAngularSize = 14
	sky.SunAngularSize = 0
	sky.CelestialBodiesShown = true

	local atmosphere: Atmosphere = ensure("Atmosphere", "Fog")
	atmosphere.Density = 0.33
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(70, 78, 94)
	atmosphere.Decay = Color3.fromRGB(48, 52, 64)
	atmosphere.Glare = 0
	atmosphere.Haze = 2.4

	local grade: ColorCorrectionEffect = ensure("ColorCorrectionEffect", "Grade")
	grade.Brightness = 0.04
	grade.Contrast = 0.18
	grade.Saturation = -0.32
	grade.TintColor = Color3.fromRGB(222, 232, 240)

	local bloom: BloomEffect = ensure("BloomEffect", "Bloom")
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.6

	local dof: DepthOfFieldEffect = ensure("DepthOfFieldEffect", "Depth")
	dof.FarIntensity = 0.18
	dof.FocusDistance = 30
	dof.InFocusRadius = 40
	dof.NearIntensity = 0

	local rays: SunRaysEffect = ensure("SunRaysEffect", "MoonRays")
	rays.Intensity = 0.02
	rays.Spread = 0.6
end

return LightingSetup

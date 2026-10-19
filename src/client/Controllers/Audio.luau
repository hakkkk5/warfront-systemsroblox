--!strict
-- Sound effects (2D and positional), music with cross-fades and ambient
-- loops. Sound ids live in Shared.Assets; empty ids are skipped silently.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)

local Audio = {}

local VOLUMES: { [string]: number } = {
	Pickup = 0.6,
	Whoosh = 0.5,
	KnifeDraw = 0.7,
	Slash = 0.7,
	Impact = 0.9,
	Rain = 0.45,
	Heartbeat = 0.9,
	Crash = 1,
	Chop = 0.9,
	DoorOpen = 0.6,
	DoorLocked = 0.6,
	Unlock = 0.7,
	Growl = 1,
	Scream = 1,
	Jumpscare = 1,
	Explosion = 1,
	Generator = 0.8,
	HelicopterLoop = 1,
	Repair = 0.7,
}

local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "Music"
musicGroup.Volume = 0.55
musicGroup.Parent = SoundService

local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "SFX"
sfxGroup.Volume = 1
sfxGroup.Parent = SoundService

local reverb = Instance.new("ReverbSoundEffect")
reverb.DecayTime = 1.6
reverb.Density = 0.8
reverb.WetLevel = -14
reverb.Parent = sfxGroup

local function soundId(name: string): string
	return (Assets.Sounds :: any)[name] or ""
end

function Audio.play(name: string, position: Vector3?, volume: number?, pitch: number?): Sound?
	local id = soundId(name)
	if id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = (volume or VOLUMES[name] or 0.8)
	sound.PlaybackSpeed = pitch or (1 + (math.random() - 0.5) * 0.08)
	sound.SoundGroup = sfxGroup
	sound.Looped = false
	if position then
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.CFrame = CFrame.new(position)
		holder.Parent = workspace
		sound.RollOffMaxDistance = 220
		sound.RollOffMinDistance = 8
		sound.Parent = holder
		sound.Ended:Connect(function()
			holder:Destroy()
		end)
		task.delay(30, function()
			holder:Destroy()
		end)
	else
		sound.Parent = SoundService
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	end
	sound:Play()
	return sound
end

local loops: { [string]: Sound } = {}

function Audio.loop(name: string, on: boolean, volume: number?)
	local sound = loops[name]
	if on then
		if not sound then
			local id = soundId(name)
			if id == "" then
				return
			end
			local created = Instance.new("Sound")
			created.SoundId = id
			created.Looped = true
			created.Volume = 0
			created.SoundGroup = sfxGroup
			created.Parent = SoundService
			created:Play()
			loops[name] = created
			sound = created
		end
		Util.tween(sound :: Sound, 1.5, { Volume = volume or VOLUMES[name] or 0.6 })
	elseif sound then
		Util.tween(sound, 1.5, { Volume = 0 })
	end
end

function Audio.setLoopVolume(name: string, volume: number)
	local sound = loops[name]
	if sound then
		sound.Volume = volume
	end
end

local currentMusic: Sound? = nil
local currentTrack = ""

function Audio.music(track: string?, volume: number?)
	if (track or "") == currentTrack then
		return
	end
	currentTrack = track or ""
	local old = currentMusic
	if old then
		Util.tween(old, 2.5, { Volume = 0 }).Completed:Connect(function()
			old:Destroy()
		end)
	end
	currentMusic = nil
	if not track then
		return
	end
	local id = (Assets.Music :: any)[track]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService
	sound:Play()
	Util.tween(sound, 3, { Volume = volume or 0.5 })
	currentMusic = sound
end

function Audio.setMasterVolume(v: number)
	musicGroup.Volume = 0.55 * v
	sfxGroup.Volume = v
end

function Audio.init()
	Net.event("Sound").OnClientEvent:Connect(function(name: string, position: Vector3?)
		if name == "Generator" or name == "HelicopterLoop" then
			Audio.loop(name, true)
		else
			Audio.play(name, position)
		end
	end)
end

return Audio

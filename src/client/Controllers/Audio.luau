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

-- played lower than recorded (a person's breath, made to sound like one of them)
local PITCHES: { [string]: number } = {
	Pant = 0.72,
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
	sound.PlaybackSpeed = pitch or ((PITCHES[name] or 1) * (1 + (math.random() - 0.5) * 0.08))
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
-- what each loop was last asked for, so asking again is free (callers ask
-- every frame; a fresh tween each time fought itself and cost a lot)
local asked: { [string]: number } = {}

function Audio.loop(name: string, on: boolean, volume: number?)
	local target = if on then volume or VOLUMES[name] or 0.6 else 0
	if asked[name] == target then
		return
	end
	asked[name] = target
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

-- A loop set straight to a level each frame by its caller (a drone that
-- swells, a heart that pounds): no fades of its own, the level is the fade.
function Audio.loopLevel(name: string, volume: number)
	local sound = loops[name]
	if not sound then
		if volume <= 0.001 then
			return
		end
		local id = soundId(name)
		if id == "" then
			return
		end
		local created = Instance.new("Sound")
		created.SoundId = id
		created.Looped = true
		created.SoundGroup = sfxGroup
		created.Parent = SoundService
		created:Play()
		loops[name] = created
		sound = created
	end
	asked[name] = nil
	;(sound :: Sound).Volume = math.max(0, volume)
end

-- Faster or slower (a heart racing as one of them closes in).
function Audio.setLoopPitch(name: string, pitch: number)
	local sound = loops[name]
	if sound then
		sound.PlaybackSpeed = pitch
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

local master = 1
local layer = 1 -- Presence: the music gives way as one of them closes in
local duck = Instance.new("NumberValue")
duck.Value = 1
duck.Changed:Connect(function(v: number)
	musicGroup.Volume = 0.55 * master * v * layer
end)

function Audio.setMasterVolume(v: number)
	master = v
	musicGroup.Volume = 0.55 * v * duck.Value * layer
	sfxGroup.Volume = v
end

-- How much of the music plays under everything else (1 all of it), so the
-- drone and the footsteps of whatever is coming cut through.
function Audio.setMusicLayer(v: number)
	layer = math.clamp(v, 0, 1)
	musicGroup.Volume = 0.55 * master * duck.Value * layer
end

-- Pulls the music down to `level` for `seconds`, then lets it back up: the
-- fear director's "silence" (it's scarier when the music stops).
local duckToken = 0
function Audio.duck(level: number, seconds: number)
	duckToken += 1
	local token = duckToken
	Util.tween(duck, 1.2, { Value = level })
	task.delay(seconds, function()
		if token == duckToken then
			Util.tween(duck, 3, { Value = 1 })
		end
	end)
end

-- Back to full volume at once (a scare cutting through a silence).
function Audio.unduck()
	duckToken += 1
	Util.tween(duck, 0.02, { Value = 1 })
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

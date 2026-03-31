--[[
	AudioController — Client-side audio management.

	Responsibilities:
	  - Maintain a SoundGroup under SoundService for master volume control.
	  - Provide playSound(soundName, position?) for spatial or 2D playback.
	  - Provide playLocalSound(soundName) for guaranteed 2D UI sounds.
	  - React to game events (weapon fire, reload, hit, death, pickups, etc.)
	    and play the matching sound from AudioData.
	  - Manage looped ambient music with volume controls.
	  - Clean up spatial sound parts after playback ends.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared

local AudioData = require(Shared.Data.AudioData)
local WeaponData = require(Shared.Data.WeaponData)
local EventNames = require(Shared.Network.EventNames)
local ClientNetwork = require(script.Parent.Parent.Network)

local AudioController = {}

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- SoundGroup setup
--------------------------------------------------------------------------------

local masterGroup: SoundGroup = nil
local musicGroup: SoundGroup = nil

-- Currently playing music Sound instance
local musicSound: Sound? = nil

-- Currently equipped weapon id (kept in sync via WeaponEquip events)
local currentWeaponId: string = ""

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

--- Resolve an AudioData entry by name, returning nil if not found.
local function getAudioEntry(soundName: string): { id: string, volume: number, looped: boolean? }?
	local entry = AudioData[soundName]
	if not entry then
		warn("[AudioController] Unknown sound name:", soundName)
	end
	return entry
end

--- Create a Sound instance from an AudioData entry.
local function createSound(entry: { id: string, volume: number, looped: boolean? }): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = entry.id
	sound.Volume = entry.volume
	sound.Looped = if entry.looped then true else false
	sound.SoundGroup = masterGroup
	return sound
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Play a sound by name. If `position` is provided the sound is played from a
--- temporary anchored part at that world position (spatial / 3D audio).
--- Otherwise the sound plays as a flat 2D sound under SoundService.
function AudioController.playSound(soundName: string, position: Vector3?)
	local entry = getAudioEntry(soundName)
	if not entry then
		return
	end

	local sound = createSound(entry)

	if position then
		-- Spatial audio: create a temporary invisible part
		local part = Instance.new("Part")
		part.Name = "SpatialSFX"
		part.Size = Vector3.new(1, 1, 1)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Position = position
		sound.Parent = part
		part.Parent = Workspace

		-- Clean up after the sound finishes
		sound.Ended:Once(function()
			part:Destroy()
		end)

		sound:Play()
	else
		-- 2D sound: parent to SoundService so it plays non-spatially
		sound.Parent = SoundService
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		sound:Play()
	end
end

--- Convenience wrapper that always plays a sound as 2D (no position).
--- Intended for UI clicks, pickups, and other non-positional feedback.
function AudioController.playLocalSound(soundName: string)
	AudioController.playSound(soundName, nil)
end

--------------------------------------------------------------------------------
-- Music controls
--------------------------------------------------------------------------------

--- Set the volume of the background music (0-1).
function AudioController.setMusicVolume(vol: number)
	if musicGroup then
		musicGroup.Volume = math.clamp(vol, 0, 1)
	end
end

--- Set the volume of all SFX (0-1). Adjusts the master group which
--- all non-music sounds belong to.
function AudioController.setSFXVolume(vol: number)
	if masterGroup then
		masterGroup.Volume = math.clamp(vol, 0, 1)
	end
end

--------------------------------------------------------------------------------
-- Event-driven sound playback
--------------------------------------------------------------------------------

--- Determine which fire sound to use based on the current weapon.
--- Checks for a weapon-specific sound first (e.g. "WeaponFire_MemorySMG"),
--- then falls back to the firingMode-based sound.
local function getWeaponFireSound(): string
	-- Check for a weapon-specific override
	local specificKey = "WeaponFire_" .. currentWeaponId
	if AudioData[specificKey] then
		return specificKey
	end

	local def = WeaponData[currentWeaponId]
	if not def then
		return "WeaponFire_Hitscan"
	end

	local mode = def.firingMode
	if mode == "Melee" then
		return "WeaponFire_Melee"
	elseif mode == "Projectile" then
		return "WeaponFire_Projectile"
	end
	-- Default to Hitscan for Hitscan, Spread, Burst, etc.
	return "WeaponFire_Hitscan"
end

--- Get the local player's current world position, or nil if unavailable.
local function getLocalPosition(): Vector3?
	local character = localPlayer.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		return (root :: BasePart).Position
	end
	return nil
end

local function hookEvents()
	-- Weapon fire: the client fires WeaponFire to the server; we hook the
	-- same outgoing call pattern. Since WeaponController calls fireServer for
	-- WeaponFire, we listen to the server echo / confirmation isn't needed —
	-- we play the sound locally when the server acknowledges via hit or we can
	-- hook the client-side event. The simplest approach: listen for the server
	-- event that notifies us of our own fire isn't available, so we listen on
	-- the outgoing event name. However the ClientNetwork only provides
	-- onServerEvent (incoming). Instead, we hook the WeaponEquip to track the
	-- current weapon and rely on the caller (WeaponController) or the init
	-- wiring to call playSound. For now, we listen for server-sent events.

	-- Track equipped weapon so we can pick the right fire sound
	ClientNetwork.onServerEvent(EventNames.WeaponEquip, function(weaponState)
		if weaponState and weaponState.weaponId then
			currentWeaponId = weaponState.weaponId
		end
	end)

	-- Hit confirmed — play impact sound at hit position
	-- Use explosion sound for projectile weapons, normal hit sound otherwise
	ClientNetwork.onServerEvent(EventNames.WeaponHitConfirm, function(data)
		local pos = if data and data.position then data.position else nil
		local def = WeaponData[currentWeaponId]
		if def and def.firingMode == "Projectile" then
			AudioController.playSound("WeaponHit_Explosion", pos)
		else
			AudioController.playSound("WeaponHit", pos)
		end
	end)

	-- Character died — play death sound
	ClientNetwork.onServerEvent(EventNames.CharacterDied, function()
		AudioController.playLocalSound("PlayerDeath")
	end)

	-- Kill occurred (broadcast to all clients) — play subtle kill chime for
	-- the local player if they are the killer
	ClientNetwork.onServerEvent(EventNames.KillOccurred, function(killerName: string, _victimName: string)
		if killerName == localPlayer.Name then
			AudioController.playLocalSound("WeaponHit")
		end
	end)

	-- Shard picked up
	ClientNetwork.onServerEvent(EventNames.ShardPickedUp, function()
		AudioController.playLocalSound("ShardPickup")
	end)

	-- Ability activation — we listen for the cooldown update as a proxy that
	-- an ability was successfully activated
	ClientNetwork.onServerEvent(EventNames.AbilityCooldownUpdate, function()
		AudioController.playLocalSound("AbilityGeneric")
	end)
end

--------------------------------------------------------------------------------
-- Public fire/reload helpers (called externally by other controllers)
--------------------------------------------------------------------------------

--- Play the appropriate weapon fire sound at the player's current position.
function AudioController.playWeaponFire()
	local soundName = getWeaponFireSound()
	AudioController.playSound(soundName, getLocalPosition())
end

--- Play the reload sound.
function AudioController.playWeaponReload()
	AudioController.playSound("WeaponReload", getLocalPosition())
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------

function AudioController.init()
	-- Create master SoundGroup for SFX volume control
	masterGroup = Instance.new("SoundGroup")
	masterGroup.Name = "MasterSFX"
	masterGroup.Volume = 1
	masterGroup.Parent = SoundService

	-- Create a separate SoundGroup for music
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "Music"
	musicGroup.Volume = 1
	musicGroup.Parent = SoundService

	-- Start ambient music
	local musicEntry = AudioData.AmbientMusic
	if musicEntry then
		musicSound = Instance.new("Sound")
		musicSound.Name = "AmbientMusic"
		musicSound.SoundId = musicEntry.id
		musicSound.Volume = musicEntry.volume
		musicSound.Looped = true
		musicSound.SoundGroup = musicGroup
		musicSound.Parent = SoundService
		musicSound:Play()
	end

	-- Hook game events for automatic sound playback
	hookEvents()

	print("[AudioController] Initialized")
end

return AudioController

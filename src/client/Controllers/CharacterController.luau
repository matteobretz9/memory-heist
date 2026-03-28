--[[
	CharacterController — Client-side character lifecycle and event handling.

	Responsibilities:
	  - Set up camera mode when the local character spawns.
	  - Listen for KillOccurred events from the server (for kill feed / UI).
	  - Listen for AbilitySlotUpdate events to keep local ability state in sync.
	  - Listen for CharacterSpawned / CharacterDied events.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local EventNames = require(Shared.Network.EventNames)
local ClientNetwork = require(script.Parent.Parent.Network)

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local CharacterController = {}

-- Local player reference (set during init)
local localPlayer: Player = Players.LocalPlayer

-- Cached local ability state kept in sync with the server
local abilitySlots: { any } = {}

-- Cached weapon state
local weaponState: { [string]: any }? = nil

---------------------------------------------------------------------------
-- Character spawn handling
---------------------------------------------------------------------------

local function onLocalCharacterAdded(character: Model)
	-- Wait for the humanoid so camera follow works correctly
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		warn("[CharacterController] Humanoid not found on local character")
		return
	end

	-- Use default Roblox third-person camera (Classic). This can be swapped
	-- later for a custom camera controller without touching this module.
	localPlayer.CameraMode = Enum.CameraMode.Classic
	localPlayer.CameraMaxZoomDistance = 40
	localPlayer.CameraMinZoomDistance = 5

	print("[CharacterController] Local character spawned")
end

---------------------------------------------------------------------------
-- Server event listeners
---------------------------------------------------------------------------

--- Called when the server confirms our character has spawned.
local function onCharacterSpawned()
	-- Placeholder for future spawn effects / UI resets
end

--- Called when the server tells us we died.
local function onCharacterDied()
	-- Placeholder for future death effects / respawn UI
	print("[CharacterController] Local character died — awaiting respawn")
end

--- Called when a kill occurs anywhere in the match.
--- @param killerName string — display name of the killer (empty string if no killer)
--- @param victimName string — display name of the victim
local function onKillOccurred(killerName: string, victimName: string)
	-- TODO: Feed this into a kill-feed UI controller
	if killerName == "" then
		print("[KillFeed]", victimName, "died")
	else
		print("[KillFeed]", killerName, "eliminated", victimName)
	end
end

--- Called when the server sends updated ability slot data.
local function onAbilitySlotUpdate(slots: { any })
	abilitySlots = slots
	-- TODO: Notify ability bar UI to refresh
end

--- Called when the server sends a weapon equip / update.
local function onWeaponEquip(weapon: { [string]: any })
	weaponState = weapon
	-- TODO: Notify weapon HUD to refresh
end

--- Called when the server sends an overload tier change.
local function onOverloadUpdate(tier: number)
	-- TODO: Update overload visual effects / UI
	if tier > 0 then
		print("[CharacterController] Overload tier:", tier)
	end
end

---------------------------------------------------------------------------
-- Public accessors (for other client modules)
---------------------------------------------------------------------------

--- Get the locally-cached ability slots.
function CharacterController.getAbilitySlots(): { any }
	return abilitySlots
end

--- Get the locally-cached weapon state.
function CharacterController.getWeaponState(): { [string]: any }?
	return weaponState
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function CharacterController.init()
	-- Make sure the client network is ready
	ClientNetwork.init()

	-- Listen for local character spawns
	localPlayer.CharacterAdded:Connect(onLocalCharacterAdded)

	-- If a character already exists handle it immediately
	if localPlayer.Character then
		task.spawn(onLocalCharacterAdded, localPlayer.Character)
	end

	-- Register server event listeners
	ClientNetwork.onServerEvent(EventNames.CharacterSpawned, onCharacterSpawned)
	ClientNetwork.onServerEvent(EventNames.CharacterDied, onCharacterDied)
	ClientNetwork.onServerEvent(EventNames.KillOccurred, onKillOccurred)
	ClientNetwork.onServerEvent(EventNames.AbilitySlotUpdate, onAbilitySlotUpdate)
	ClientNetwork.onServerEvent(EventNames.WeaponEquip, onWeaponEquip)
	ClientNetwork.onServerEvent(EventNames.OverloadUpdate, onOverloadUpdate)

	print("[CharacterController] Initialised")
end

return CharacterController

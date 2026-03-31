--[[
	AbilityService — Server-side ability activation and cooldown management.

	Responsibilities:
	  - Listen for AbilityActivate requests from clients and validate them.
	  - Delegate execution to per-ability modules in Services/Abilities/.
	  - Tick down cooldowns on all players' ability slots and sync to clients.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local AbilityData = require(Shared.Data.AbilityData)
local EventNames = require(Shared.Network.EventNames)

local CharacterService = require(script.Parent.CharacterService)
local ServerNetwork = require(script.Parent.Parent.Network)

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local AbilityService = {}

-- Cache of loaded ability modules: abilityId -> module
local abilityModules: { [string]: { execute: (Player, any) -> () } } = {}

---------------------------------------------------------------------------
-- Ability module loader
---------------------------------------------------------------------------

--- Lazily load and cache an ability module by id.
local function getAbilityModule(abilityId: string): { execute: (Player, any) -> () }?
	if abilityModules[abilityId] then
		return abilityModules[abilityId]
	end

	local abilitiesFolder = script.Parent.Abilities
	local moduleScript = abilitiesFolder:FindFirstChild(abilityId)
	if not moduleScript then
		-- No server-side module for this ability; that is acceptable for
		-- abilities that are purely client-driven or not yet implemented.
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn("[AbilityService] Failed to load ability module '" .. abilityId .. "':", result)
		return nil
	end

	abilityModules[abilityId] = result
	return result
end

---------------------------------------------------------------------------
-- Core activation logic
---------------------------------------------------------------------------

--- Attempt to activate an ability for a player at the given slot index.
--- Returns true if activation succeeded, false otherwise.
function AbilityService.activateAbility(player: Player, slotIndex: number, aimData: any?): boolean
	-- 1. Player must be alive
	if not CharacterService.isAlive(player) then
		return false
	end

	-- 2. Validate slot index
	local slots = CharacterService.getAbilitySlots(player)
	if not slots then
		return false
	end

	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > #slots then
		return false
	end

	slotIndex = math.floor(slotIndex) -- ensure integer

	local slot = slots[slotIndex]

	-- 3. Slot must not be empty
	if not slot or not slot.abilityId or slot.abilityId == "" then
		return false
	end

	-- 4. Cooldown must be zero
	if slot.cooldownRemaining > 0 then
		return false
	end

	-- 5. Slot must not be locked (overload)
	if slot.isLocked then
		return false
	end

	-- 6. Look up the ability definition
	local abilityDef = AbilityData[slot.abilityId]
	if not abilityDef then
		warn("[AbilityService] Unknown ability id in slot:", slot.abilityId)
		return false
	end

	-- 7. Load and execute the ability module
	local abilityModule = getAbilityModule(slot.abilityId)
	if not abilityModule then
		warn("[AbilityService] No module found for ability:", slot.abilityId)
		return false
	end

	local execOk, execErr = pcall(abilityModule.execute, player, abilityDef, aimData)
	if not execOk then
		warn("[AbilityService] Error executing ability '" .. slot.abilityId .. "':", execErr)
		return false
	end

	-- 7b. Broadcast VFX event to all clients
	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			ServerNetwork.fireAllClients(EventNames.AbilityVFX, {
				abilityId = slot.abilityId,
				playerName = player.Name,
				position = rootPart.Position,
				direction = rootPart.CFrame.LookVector,
			})
		end
	end

	-- 8. Set cooldown
	slot.cooldownRemaining = abilityDef.cooldown

	-- 9. Sync cooldown to client immediately
	ServerNetwork.fireClient(EventNames.AbilityCooldownUpdate, player, slotIndex, slot.cooldownRemaining)

	-- 10. Track ability usage for challenges
	local ok, ChallengeService = pcall(require, script.Parent.ChallengeService)
	if ok and ChallengeService.incrementStat then
		ChallengeService.incrementStat(player, "abilitiesUsed", 1)
	end

	return true
end

---------------------------------------------------------------------------
-- Cooldown tick loop
---------------------------------------------------------------------------

local COOLDOWN_SYNC_INTERVAL = 0.5 -- seconds between cooldown syncs to clients
local cooldownSyncTimer = 0

local function tickCooldowns(dt: number)
	cooldownSyncTimer += dt

	local shouldSync = cooldownSyncTimer >= COOLDOWN_SYNC_INTERVAL
	if shouldSync then
		cooldownSyncTimer -= COOLDOWN_SYNC_INTERVAL
	end

	for _, player in Players:GetPlayers() do
		local slots = CharacterService.getAbilitySlots(player)
		if not slots then
			continue
		end

		for i, slot in slots do
			if slot.cooldownRemaining > 0 then
				slot.cooldownRemaining = math.max(0, slot.cooldownRemaining - dt)

				-- Send periodic updates so the client stays in sync
				if shouldSync or slot.cooldownRemaining == 0 then
					ServerNetwork.fireClient(
						EventNames.AbilityCooldownUpdate,
						player,
						i,
						slot.cooldownRemaining
					)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Client event handler
---------------------------------------------------------------------------

local function onAbilityActivateRequest(player: Player, slotIndex: any, aimData: any?)
	-- Basic type validation on the wire data
	if type(slotIndex) ~= "number" then
		return
	end

	AbilityService.activateAbility(player, slotIndex, aimData)
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function AbilityService.init()
	-- Register the client listener for ability activation requests
	ServerNetwork.onClientEvent(EventNames.AbilityActivate, onAbilityActivateRequest)

	-- Start the cooldown tick loop via Heartbeat
	RunService.Heartbeat:Connect(tickCooldowns)

	print("[AbilityService] Initialised")
end

return AbilityService

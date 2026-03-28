--[[
	OverloadService — Server-side memory overload effect application.

	This service is passive: it does NOT compute or change the overloadTier
	(CharacterService handles that when abilities are added/removed).
	Instead it reads the current tier and applies gameplay penalties:
	  - Damage reduction via a DamageService modifier
	  - Movement speed reduction via Humanoid.WalkSpeed
	  - Random ability lockouts on a recurring timer
	  - Syncs the overload tier to the client for visual effects
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local OverloadData = require(Shared.Data.OverloadData)
local EventNames = require(Shared.Network.EventNames)

local CharacterService = require(script.Parent.CharacterService)
local DamageService = require(script.Parent.DamageService)
local ServerNetwork = require(script.Parent.Parent.Network)

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local DEFAULT_WALK_SPEED = 16

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Find the tier data table for a given tier number, or nil if tier is 0.
local function getTierData(tier: number): { [string]: any }?
	if tier <= 0 then
		return nil
	end
	for _, entry in OverloadData.tiers do
		if entry.tier == tier then
			return entry
		end
	end
	return nil
end

--- Get the Humanoid from a player's character, if available.
local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local OverloadService = {}

---------------------------------------------------------------------------
-- Damage modifier
---------------------------------------------------------------------------

--- Registered with DamageService during init(). Reduces damage dealt by
--- overloaded attackers according to their tier's damageReduction value.
local function overloadDamageModifier(
	attacker: Player,
	_target: Player,
	amount: number,
	_source: string
): number
	local state = CharacterService.getPlayerState(attacker)
	if not state then
		return amount
	end

	local tierData = getTierData(state.overloadTier)
	if not tierData then
		return amount -- no overload, no penalty
	end

	-- damageReduction is the fraction of damage REMOVED (e.g. 0.10 = 10% less)
	return amount * (1 - tierData.damageReduction)
end

---------------------------------------------------------------------------
-- Recurring overload check loop
---------------------------------------------------------------------------

--- Apply speed reduction and attempt random ability lockouts for one player.
local function processPlayerOverload(player: Player)
	local state = CharacterService.getPlayerState(player)
	if not state then
		return
	end

	local humanoid = getHumanoid(player)
	local tier = state.overloadTier
	local tierData = getTierData(tier)

	-- Speed adjustment
	if humanoid and humanoid.Health > 0 then
		if tierData then
			humanoid.WalkSpeed = DEFAULT_WALK_SPEED * (1 - tierData.speedReduction)
		else
			-- No overload — restore default speed
			humanoid.WalkSpeed = DEFAULT_WALK_SPEED
		end
	end

	-- If no overload, nothing else to do
	if not tierData then
		return
	end

	-- Fire the current tier to the client so it can update visual effects
	ServerNetwork.fireClient(EventNames.OverloadUpdate, player, tier)

	-- Random ability lockout roll
	if math.random() < tierData.abilityLockChance then
		local slots = state.abilitySlots

		-- Build a list of unlocked slot indices
		local unlocked: { number } = {}
		for i, slot in slots do
			if not slot.isLocked then
				table.insert(unlocked, i)
			end
		end

		if #unlocked > 0 then
			-- Pick a random unlocked slot
			local slotIndex = unlocked[math.random(1, #unlocked)]
			local slot = slots[slotIndex]

			-- Lock the ability
			slot.isLocked = true
			ServerNetwork.fireClient(EventNames.AbilityLocked, player, slotIndex, true, tierData.abilityLockDuration)

			-- Schedule the unlock
			task.delay(tierData.abilityLockDuration, function()
				-- Verify the player and slot still exist
				local currentState = CharacterService.getPlayerState(player)
				if currentState and currentState.abilitySlots[slotIndex] then
					currentState.abilitySlots[slotIndex].isLocked = false
					ServerNetwork.fireClient(EventNames.AbilityLocked, player, slotIndex, false, 0)
				end
			end)
		end
	end
end

--- Main loop that runs every checkInterval seconds.
local function startCheckLoop()
	while true do
		task.wait(OverloadData.checkInterval)

		for _, player in Players:GetPlayers() do
			-- Wrap in task.spawn so one player's error doesn't break the loop
			task.spawn(processPlayerOverload, player)
		end
	end
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function OverloadService.init()
	-- Register the damage modifier so overloaded players deal less damage
	DamageService.registerModifier("OverloadDamageReduction", overloadDamageModifier)

	-- Kick off the recurring overload check loop in a separate thread
	task.spawn(startCheckLoop)

	print("[OverloadService] Initialised")
end

return OverloadService

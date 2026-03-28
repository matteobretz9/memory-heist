--[[
	UpgradeService — Server-side upgrade processing for weapons and abilities.

	Responsibilities:
	  - Upgrade a player's currently equipped weapon (up to 3 tiers).
	  - Upgrade an ability in a specific slot (up to level 4).
	  - Provide upgrade info and multiplier lookups for other services.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local WeaponUpgradeData = require(Shared.Data.WeaponUpgradeData)
local EventNames = require(Shared.Network.EventNames)

local CharacterService = require(script.Parent.CharacterService)
local ServerNetwork = require(script.Parent.Parent.Network)

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

-- Ability upgrade caps: base level is 1, max is 4 (3 upgrade steps)
local MAX_ABILITY_LEVEL = 4

-- Pre-computed ability multipliers per upgrade level.
-- Each level increases damage by 20% and reduces cooldown by 15% from base.
local ABILITY_MULTIPLIERS = {
	[1] = { damageMultiplier = 1.0, cooldownMultiplier = 1.0 },
	[2] = { damageMultiplier = 1.2, cooldownMultiplier = 0.85 },
	[3] = { damageMultiplier = 1.4, cooldownMultiplier = 0.70 },
	[4] = { damageMultiplier = 1.6, cooldownMultiplier = 0.55 },
}

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local UpgradeService = {}

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function UpgradeService.init()
	-- Nothing needed for now; follows the service init() pattern.
	print("[UpgradeService] Initialised")
end

---------------------------------------------------------------------------
-- Weapon upgrades
---------------------------------------------------------------------------

--- Attempt to upgrade the player's currently equipped weapon by one tier.
--- Returns true on success, false if already at max level or invalid state.
function UpgradeService.upgradeWeapon(player: Player): boolean
	local state = CharacterService.getPlayerState(player)
	if not state then
		warn("[UpgradeService] No player state for", player.Name)
		return false
	end

	local weapon = state.weapon
	local weaponId = weapon.weaponId
	local currentLevel = weapon.upgradeLevel

	-- Look up available upgrades for this weapon
	local upgrades = WeaponUpgradeData[weaponId]
	if not upgrades then
		warn("[UpgradeService] No upgrade data for weapon:", weaponId)
		return false
	end

	-- upgradeLevel starts at 1 (base, no upgrades applied).
	-- Tier 1 upgrade is applied when going from level 1 -> 2, etc.
	-- Max level = #upgrades + 1 (base + all tiers).
	if currentLevel > #upgrades then
		-- Already at max upgrade tier
		return false
	end

	-- Apply the upgrade: increment level
	weapon.upgradeLevel += 1
	local newLevel = weapon.upgradeLevel

	-- Notify the client of the updated weapon state
	ServerNetwork.fireClient(EventNames.WeaponEquip, player, weapon)

	-- Notify the client that an upgrade was applied
	ServerNetwork.fireClient(EventNames.UpgradeApplied, player, {
		type = "Weapon",
		weaponId = weaponId,
		newLevel = newLevel,
	})

	return true
end

---------------------------------------------------------------------------
-- Ability upgrades
---------------------------------------------------------------------------

--- Attempt to upgrade the ability in the given slot index by one level.
--- Returns true on success, false if already at max or invalid input.
function UpgradeService.upgradeAbility(player: Player, slotIndex: number): boolean
	local state = CharacterService.getPlayerState(player)
	if not state then
		warn("[UpgradeService] No player state for", player.Name)
		return false
	end

	local slots = state.abilitySlots

	-- Validate slot index
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > #slots then
		warn("[UpgradeService] Invalid slot index:", slotIndex)
		return false
	end

	local slot = slots[slotIndex]

	-- Check if already at max upgrade level
	if slot.upgradeLevel >= MAX_ABILITY_LEVEL then
		return false
	end

	-- Apply the upgrade: increment level
	slot.upgradeLevel += 1
	local newLevel = slot.upgradeLevel

	-- Notify the client of the updated ability slots
	ServerNetwork.fireClient(EventNames.AbilitySlotUpdate, player, slots)

	-- Notify the client that an upgrade was applied
	ServerNetwork.fireClient(EventNames.UpgradeApplied, player, {
		type = "Ability",
		abilityId = slot.abilityId,
		slotIndex = slotIndex,
		newLevel = newLevel,
	})

	return true
end

---------------------------------------------------------------------------
-- Lookup helpers (for use by other services)
---------------------------------------------------------------------------

--- Returns the upgrade tier data for a weapon at the given level, or nil if
--- the weapon is still at base (level 1) or the weaponId is unknown.
--- Level 2 corresponds to tier 1 upgrades, level 3 to tier 2, etc.
function UpgradeService.getWeaponUpgradeInfo(weaponId: string, currentLevel: number): {
	tier: number,
	damageMultiplier: number,
	fireRateMultiplier: number,
	special: string?,
}?
	if currentLevel <= 1 then
		-- At base level, no upgrade data applies
		return nil
	end

	local upgrades = WeaponUpgradeData[weaponId]
	if not upgrades then
		return nil
	end

	-- Level 2 = tier index 1, level 3 = tier index 2, etc.
	local tierIndex = currentLevel - 1
	if tierIndex < 1 or tierIndex > #upgrades then
		return nil
	end

	return upgrades[tierIndex]
end

--- Returns damage and cooldown multipliers for a given ability upgrade level.
--- Useful for AbilityService when activating abilities.
function UpgradeService.getAbilityMultipliers(upgradeLevel: number): {
	damageMultiplier: number,
	cooldownMultiplier: number,
}
	local entry = ABILITY_MULTIPLIERS[upgradeLevel]
	if entry then
		return entry
	end

	-- Fallback: clamp to valid range
	if upgradeLevel < 1 then
		return ABILITY_MULTIPLIERS[1]
	end
	return ABILITY_MULTIPLIERS[MAX_ABILITY_LEVEL]
end

return UpgradeService

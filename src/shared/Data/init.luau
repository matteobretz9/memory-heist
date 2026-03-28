--[[
	Re-exports all data modules for convenient access.
	Usage: local Data = require(Shared.Data)
	       local sword = Data.Weapons.EnergySword
]]

local Data = {
	Abilities = require(script.AbilityData),
	Weapons = require(script.WeaponData),
	WeaponUpgrades = require(script.WeaponUpgradeData),
	Rarities = require(script.RarityData),
	Overload = require(script.OverloadData),
}

return Data

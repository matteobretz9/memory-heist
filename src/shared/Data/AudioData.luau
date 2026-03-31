--[[
	Central sound registry mapping sound names to asset IDs and default properties.
	All controllers reference this table so sound IDs are defined in one place.
]]

local AudioData = {
	-- Weapons
	WeaponFire_Hitscan = { id = "rbxassetid://314322896", volume = 0.1 },
	WeaponFire_MemorySMG = { id = "rbxassetid://314322896", volume = 0.1 },
	WeaponFire_Melee = { id = "rbxassetid://4374878756", volume = 0.1 },
	WeaponFire_EnergySword = { id = "rbxassetid://4374878756", volume = 0.1 },
	WeaponFire_PhaseKnife = { id = "rbxassetid://4374879236", volume = 0.1 },
	WeaponFire_Projectile = { id = "rbxassetid://12222095", volume = 0.1 },
	WeaponFire_Sniper = { id = "rbxassetid://168143115", volume = 0.15 },
	WeaponHit_Explosion = { id = "rbxassetid://3802269741", volume = 0.1 },
	WeaponReload = { id = "rbxassetid://130791000", volume = 0.1 },
	WeaponHit = { id = "rbxassetid://130791048", volume = 0.1 },

	-- Abilities
	AbilityDash = { id = "rbxassetid://130791048", volume = 0.5 },
	AbilityFireball = { id = "rbxassetid://130791043", volume = 0.6 },
	AbilityShield = { id = "rbxassetid://130791000", volume = 0.5 },
	AbilityHeal = { id = "rbxassetid://130791048", volume = 0.4 },
	AbilityGeneric = { id = "rbxassetid://130791048", volume = 0.4 },

	-- Combat
	PlayerDeath = { id = "rbxassetid://130791043", volume = 0.5 },
	Explosion = { id = "rbxassetid://130791043", volume = 0.7 },

	-- UI
	UIClick = { id = "rbxassetid://130791048", volume = 0.3 },
	ShardPickup = { id = "rbxassetid://130791000", volume = 0.5 },

	-- Ambient
	AmbientMusic = { id = "rbxassetid://130791000", volume = 0.15, looped = true },
}

table.freeze(AudioData)
return AudioData

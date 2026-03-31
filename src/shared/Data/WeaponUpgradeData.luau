--[[
	Weapon upgrade paths. Each weapon has 3 upgrade tiers.
	Multipliers are applied to the base weapon stats.
	Special effects unlock at certain tiers.
]]

local WeaponUpgradeData = {
	EnergySword = {
		{ tier = 1, damageMultiplier = 1.15, fireRateMultiplier = 1.10, special = nil },
		{ tier = 2, damageMultiplier = 1.30, fireRateMultiplier = 1.20, special = "LongerLunge" },
		{ tier = 3, damageMultiplier = 1.50, fireRateMultiplier = 1.30, special = "ChargedSlashWave" },
	},
	PulseBlaster = {
		{ tier = 1, damageMultiplier = 1.15, fireRateMultiplier = 1.10, special = nil },
		{ tier = 2, damageMultiplier = 1.25, fireRateMultiplier = 1.15, special = "LargerMag" },
		{ tier = 3, damageMultiplier = 1.40, fireRateMultiplier = 1.20, special = "RicochetShot" },
	},
	RailRifle = {
		{ tier = 1, damageMultiplier = 1.20, fireRateMultiplier = 1.00, special = "HeadshotBonus" },
		{ tier = 2, damageMultiplier = 1.35, fireRateMultiplier = 1.10, special = "WallPenetration" },
		{ tier = 3, damageMultiplier = 1.50, fireRateMultiplier = 1.15, special = "ShockOnHit" },
	},
	MemorySMG = {
		{ tier = 1, damageMultiplier = 1.10, fireRateMultiplier = 1.15, special = nil },
		{ tier = 2, damageMultiplier = 1.20, fireRateMultiplier = 1.25, special = "BetterHipfire" },
		{ tier = 3, damageMultiplier = 1.30, fireRateMultiplier = 1.35, special = "SpeedOnKill" },
	},
	GlitchShotgun = {
		{ tier = 1, damageMultiplier = 1.10, fireRateMultiplier = 1.10, special = "TighterSpread" },
		{ tier = 2, damageMultiplier = 1.25, fireRateMultiplier = 1.15, special = "MorePellets" },
		{ tier = 3, damageMultiplier = 1.35, fireRateMultiplier = 1.25, special = "KnockbackBlast" },
	},
	PhaseKnife = {
		{ tier = 1, damageMultiplier = 1.15, fireRateMultiplier = 1.10, special = "BackstabBonus" },
		{ tier = 2, damageMultiplier = 1.30, fireRateMultiplier = 1.20, special = "BlinkAttack" },
		{ tier = 3, damageMultiplier = 1.50, fireRateMultiplier = 1.30, special = "BleedEffect" },
	},
	ShockLauncher = {
		{ tier = 1, damageMultiplier = 1.15, fireRateMultiplier = 1.00, special = "BiggerBlast" },
		{ tier = 2, damageMultiplier = 1.30, fireRateMultiplier = 1.10, special = "StickyShot" },
		{ tier = 3, damageMultiplier = 1.45, fireRateMultiplier = 1.15, special = "EMPBlast" },
	},
	Sniper = {
		{ tier = 1, damageMultiplier = 1.15, fireRateMultiplier = 1.00, special = "SteadyAim" },
		{ tier = 2, damageMultiplier = 1.25, fireRateMultiplier = 1.10, special = "ArmorPiercing" },
		{ tier = 3, damageMultiplier = 1.40, fireRateMultiplier = 1.15, special = "ExplosiveRounds" },
	},
}

table.freeze(WeaponUpgradeData)
return WeaponUpgradeData

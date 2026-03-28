--[[
	Shared type definitions used across server, client, and shared modules.
]]

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type UseType = "Movement" | "Attack" | "Attack/AOE" | "Control" | "Defense"
	| "Support" | "Stealth" | "Trick" | "Projectile" | "Beam Attack"
	| "Movement/Attack" | "Movement/Buff" | "Control/Attack" | "Attack/Control"
	| "Trick/Defense" | "Trick/Control" | "Defense/Control" | "Area Control"
	| "Summon/Attack" | "Melee Attack" | "Stealth/Buff" | "Heavy Projectile"
	| "Ultimate/Buff" | "Control/Anti-Tech"

export type AbilityDef = {
	id: string,
	name: string,
	description: string,
	damage: number,
	cooldown: number,
	rarity: Rarity,
	button: string,
	useType: UseType,
	upgradeLevel: number?, -- nil = base level
}

export type WeaponType = "EnergySword" | "PulseBlaster" | "RailRifle"
	| "MemorySMG" | "GlitchShotgun" | "PhaseKnife" | "ShockLauncher"

export type FiringMode = "Hitscan" | "Projectile" | "Melee"

export type WeaponDef = {
	id: WeaponType,
	name: string,
	description: string,
	damage: number,
	fireRate: number, -- rounds per second
	range: number, -- studs
	firingMode: FiringMode,
	magazineSize: number,
	reloadTime: number,
	spread: number, -- degrees of inaccuracy
	projectileSpeed: number?, -- studs/sec, only for Projectile mode
}

export type AbilitySlot = {
	abilityId: string,
	upgradeLevel: number,
	cooldownRemaining: number,
	isLocked: boolean, -- true when disabled by overload
}

export type WeaponState = {
	weaponId: WeaponType,
	upgradeLevel: number,
	currentAmmo: number,
	isReloading: boolean,
}

export type PlayerState = {
	alive: boolean,
	abilitySlots: { AbilitySlot },
	weapon: WeaponState,
	overloadTier: number, -- 0 = none, 1-3 = escalating
	kills: number,
	deaths: number,
	score: number,
}

export type OverloadTier = {
	tier: number,
	minAbilities: number,
	speedReduction: number, -- fraction (0.1 = 10% slower)
	damageReduction: number,
	abilityLockChance: number, -- chance per tick that a random ability gets locked
	abilityLockDuration: number, -- seconds
}

export type StealChoice = "StealAbility" | "UpgradeAbility" | "UpgradeWeapon"

export type ShardData = {
	victimName: string,
	abilities: { AbilitySlot },
	position: Vector3,
	lifetime: number,
}

export type ProfileData = {
	credits: number,
	totalKills: number,
	totalDeaths: number,
	totalWins: number,
	ownedCosmetics: { string },
	equippedCosmetics: { [string]: string }, -- slot -> cosmetic id
	settings: { [string]: any },
}

return nil

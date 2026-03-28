--[[
	Central registry of all RemoteEvent and RemoteFunction names.
	Both server and client reference this to avoid magic strings.
]]

local EventNames = {
	-- Character
	CharacterSpawned = "CharacterSpawned",
	CharacterDied = "CharacterDied",
	RequestRespawn = "RequestRespawn",

	-- Weapons
	WeaponFire = "WeaponFire",
	WeaponHitConfirm = "WeaponHitConfirm",
	WeaponEquip = "WeaponEquip",
	WeaponReload = "WeaponReload",

	-- Abilities
	AbilityActivate = "AbilityActivate",
	AbilityCooldownUpdate = "AbilityCooldownUpdate",
	AbilitySlotUpdate = "AbilitySlotUpdate",
	AbilityLocked = "AbilityLocked", -- overload disabled an ability

	-- Damage
	DamageDealt = "DamageDealt",
	KillOccurred = "KillOccurred",

	-- Steal System
	ShardSpawned = "ShardSpawned",
	ShardDespawned = "ShardDespawned",
	ShardPickedUp = "ShardPickedUp",
	StealChoiceRequest = "StealChoiceRequest", -- server -> client: show choice UI
	StealChoiceResponse = "StealChoiceResponse", -- client -> server: player's choice

	-- Memory Overload
	OverloadUpdate = "OverloadUpdate",

	-- Upgrades
	UpgradeApplied = "UpgradeApplied",

	-- Game State
	GameStateChanged = "GameStateChanged",
	RoundTimerSync = "RoundTimerSync",
	ScoreUpdate = "ScoreUpdate",

	-- Player Data
	PlayerDataLoaded = "PlayerDataLoaded",
	CurrencyUpdate = "CurrencyUpdate",

	-- Lobby
	LobbyInfo = "LobbyInfo",
	MatchmakingStatus = "MatchmakingStatus",
}

table.freeze(EventNames)
return EventNames

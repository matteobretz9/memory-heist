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
	AbilityVFX = "AbilityVFX", -- server -> all clients: play ability visual effect

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
	RoundResults = "RoundResults",

	-- Player Data
	PlayerDataLoaded = "PlayerDataLoaded",
	CurrencyUpdate = "CurrencyUpdate",

	-- Sync
	RequestStateSync = "RequestStateSync", -- client -> server: resend my state

	-- Lobby
	LobbyInfo = "LobbyInfo",
	MatchmakingStatus = "MatchmakingStatus",

	-- Battle Pass
	BattlePassUpdate = "BattlePassUpdate",
	BattlePassClaimRequest = "BattlePassClaimRequest",
	BattlePassRewardClaimed = "BattlePassRewardClaimed",

	-- Challenges
	ChallengeSync = "ChallengeSync",
	ChallengeProgressUpdate = "ChallengeProgressUpdate",
	ChallengeCompleted = "ChallengeCompleted",
	ChallengeClaimRequest = "ChallengeClaimRequest",
	ChallengeRewardClaimed = "ChallengeRewardClaimed",

	-- Game Modes
	ModeChanged = "ModeChanged",
	TeamAssigned = "TeamAssigned",
	DuelChallenge = "DuelChallenge",
	DuelAccept = "DuelAccept",

	-- Glitch Zones
	GlitchZoneEnter = "GlitchZoneEnter",
	GlitchZoneExit = "GlitchZoneExit",

	-- Cosmetics Shop
	CosmeticPurchaseRequest = "CosmeticPurchaseRequest",
	CosmeticEquipRequest = "CosmeticEquipRequest",
	CosmeticPurchased = "CosmeticPurchased",
	CosmeticEquipped = "CosmeticEquipped",
	ShopDataSync = "ShopDataSync",
}

table.freeze(EventNames)
return EventNames

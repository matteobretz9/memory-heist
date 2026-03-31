--[[
	Server entry point.
	Initializes all server-side systems in dependency order.
]]

local ServerNetwork = require(script.Network)

-- Phase 0: Initialize networking first (creates RemoteEvents)
ServerNetwork.init()
print("[Server] Networking initialized")

-- Phase 0: Load player data system (non-blocking — may fail if ProfileService isn't available)
local profileOk, PlayerProfile = pcall(require, script.Data.PlayerProfile)
if profileOk then
	PlayerProfile.init()
	print("[Server] PlayerProfile initialized")
else
	warn("[Server] PlayerProfile failed to load (ProfileService not available). Persistence disabled.")
end

-- Phase 1: Core gameplay services
local DamageService = require(script.Services.DamageService)
DamageService.init()
print("[Server] DamageService initialized")

-- DISABLED: Weapons & abilities removed from game (files kept in repo)
-- local WeaponService = require(script.Services.WeaponService)
-- WeaponService.init()
-- print("[Server] WeaponService initialized")

local CharacterService = require(script.Services.CharacterService)
CharacterService.init()
print("[Server] CharacterService initialized")

-- DISABLED: Weapons & abilities removed from game (files kept in repo)
-- local AbilityService = require(script.Services.AbilityService)
-- AbilityService.init()
-- print("[Server] AbilityService initialized")

-- local OverloadService = require(script.Services.OverloadService)
-- OverloadService.init()
-- print("[Server] OverloadService initialized")

-- local UpgradeService = require(script.Services.UpgradeService)
-- UpgradeService.init()
-- print("[Server] UpgradeService initialized")

-- local StealService = require(script.Services.StealService)
-- StealService.init()
-- print("[Server] StealService initialized")

-- Phase 3: Game structure services
local MapService = require(script.Services.MapService)
MapService.init()
print("[Server] MapService initialized")

local GameStateService = require(script.Services.GameStateService)
GameStateService.init()
print("[Server] GameStateService initialized")

-- Phase 4: Content systems
-- DISABLED: Glitch zones removed from lobby (files kept in repo)
-- local GlitchZoneService = require(script.Services.GlitchZoneService)
-- GlitchZoneService.init()
-- print("[Server] GlitchZoneService initialized")

local ModeManager = require(script.Services.ModeManager)
ModeManager.init()
print("[Server] ModeManager initialized")

-- Phase 5: Monetization services
local CurrencyService = require(script.Services.CurrencyService)
CurrencyService.init()
print("[Server] CurrencyService initialized")

local CosmeticsService = require(script.Services.CosmeticsService)
CosmeticsService.init()
print("[Server] CosmeticsService initialized")

local BattlePassService = require(script.Services.BattlePassService)
BattlePassService.init()
print("[Server] BattlePassService initialized")

local ChallengeService = require(script.Services.ChallengeService)
ChallengeService.init()
print("[Server] ChallengeService initialized")

-- Phase 6: Polish services
local AntiCheatService = require(script.Services.AntiCheatService)
AntiCheatService.init()
print("[Server] AntiCheatService initialized")

local AnalyticsService = require(script.Services.AnalyticsService)
AnalyticsService.init()
print("[Server] AnalyticsService initialized")

print("[Server] Memory Heist server started!")

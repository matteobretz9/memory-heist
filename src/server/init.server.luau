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

local WeaponService = require(script.Services.WeaponService)
WeaponService.init()
print("[Server] WeaponService initialized")

local CharacterService = require(script.Services.CharacterService)
CharacterService.init()
print("[Server] CharacterService initialized")

local AbilityService = require(script.Services.AbilityService)
AbilityService.init()
print("[Server] AbilityService initialized")

local OverloadService = require(script.Services.OverloadService)
OverloadService.init()
print("[Server] OverloadService initialized")

local UpgradeService = require(script.Services.UpgradeService)
UpgradeService.init()
print("[Server] UpgradeService initialized")

local StealService = require(script.Services.StealService)
StealService.init()
print("[Server] StealService initialized")

print("[Server] Memory Heist server started!")

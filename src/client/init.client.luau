--[[
	Client entry point.
	Initializes all client-side systems after the server is ready.
]]

local ClientNetwork = require(script.Network)

-- Wait for networking to be ready (server creates the Remotes folder)
ClientNetwork.init()
print("[Client] Networking initialized")

-- Phase 1: Core gameplay controllers
local CharacterController = require(script.Controllers.CharacterController)
CharacterController.init()
print("[Client] CharacterController initialized")

-- DISABLED: Weapons & abilities removed from game (files kept in repo)
-- local WeaponController = require(script.Controllers.WeaponController)
-- WeaponController.init()
-- print("[Client] WeaponController initialized")

local HUD = require(script.UI.HUD)
HUD.init()
print("[Client] HUD initialized")

-- DISABLED: Weapons & abilities removed from game (files kept in repo)
-- local AbilityController = require(script.Controllers.AbilityController)
-- AbilityController.init()
-- print("[Client] AbilityController initialized")

-- local OverloadController = require(script.Controllers.OverloadController)
-- OverloadController.init()
-- print("[Client] OverloadController initialized")

-- local StealChoiceUI = require(script.UI.StealChoice)
-- StealChoiceUI.init()
-- print("[Client] StealChoiceUI initialized")

-- Phase 3: Game structure UI
local Scoreboard = require(script.UI.Scoreboard)
Scoreboard.init()
print("[Client] Scoreboard initialized")

local GameStateController = require(script.Controllers.GameStateController)
GameStateController.init()
print("[Client] GameStateController initialized")

-- Phase 4: Content controllers
-- DISABLED: Glitch zones removed from lobby (files kept in repo)
-- local GlitchZoneController = require(script.Controllers.GlitchZoneController)
-- GlitchZoneController.init()
-- print("[Client] GlitchZoneController initialized")

local ModeController = require(script.Controllers.ModeController)
ModeController.init()
print("[Client] ModeController initialized")

-- Phase 5: Monetization UI
local CurrencyDisplay = require(script.UI.HUD.CurrencyDisplay)
CurrencyDisplay.init()
print("[Client] CurrencyDisplay initialized")

local Shop = require(script.UI.Shop)
Shop.init()
print("[Client] Shop initialized")

local BattlePassUI = require(script.UI.BattlePass)
BattlePassUI.init()
print("[Client] BattlePass UI initialized")

local ChallengesUI = require(script.UI.Challenges)
ChallengesUI.init()
print("[Client] Challenges UI initialized")

-- Crouch
local CrouchController = require(script.Controllers.CrouchController)
CrouchController.init()
print("[Client] CrouchController initialized")

-- Phase 6: Polish systems
local AudioController = require(script.Controllers.AudioController)
AudioController.init()
print("[Client] AudioController initialized")

local TutorialController = require(script.Controllers.TutorialController)
TutorialController.init()
print("[Client] TutorialController initialized")

local SettingsUI = require(script.UI.Settings)
SettingsUI.init()
print("[Client] Settings UI initialized")

local DeathScreen = require(script.UI.DeathScreen)
DeathScreen.init()
print("[Client] DeathScreen initialized")

local CosmeticsController = require(script.Controllers.CosmeticsController)
CosmeticsController.init()
print("[Client] CosmeticsController initialized")

local VFXController = require(script.Controllers.VFXController)
VFXController.init()
print("[Client] VFXController initialized")

-- Request full state resync from server now that all listeners are ready
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventNames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"):WaitForChild("EventNames"))
ClientNetwork.fireServer(EventNames.RequestStateSync)
print("[Client] Requested state resync")

print("[Client] Memory Heist client started!")

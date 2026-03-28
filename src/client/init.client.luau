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

local WeaponController = require(script.Controllers.WeaponController)
WeaponController.init()
print("[Client] WeaponController initialized")

local HUD = require(script.UI.HUD)
HUD.init()
print("[Client] HUD initialized")

local AbilityController = require(script.Controllers.AbilityController)
AbilityController.init()
print("[Client] AbilityController initialized")

local OverloadController = require(script.Controllers.OverloadController)
OverloadController.init()
print("[Client] OverloadController initialized")

local StealChoiceUI = require(script.UI.StealChoice)
StealChoiceUI.init()
print("[Client] StealChoiceUI initialized")

-- Request full state resync from server now that all listeners are ready
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventNames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"):WaitForChild("EventNames"))
ClientNetwork.fireServer(EventNames.RequestStateSync)
print("[Client] Requested state resync")

print("[Client] Memory Heist client started!")

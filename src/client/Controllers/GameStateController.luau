--[[
	GameStateController — Tracks the current game state and round timer.

	Responsibilities:
	  - Listen for GameStateChanged events from the server.
	  - Listen for RoundTimerSync events to keep the local timer accurate.
	  - Expose getState() and getTimeRemaining() for other client modules.
	  - Notify the GameHUD whenever state or timer changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local EventNames = require(Shared:WaitForChild("Network"):WaitForChild("EventNames"))
local ClientNetwork = require(script.Parent.Parent:WaitForChild("Network"))

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local GameStateController = {}

-- Current game state: "Lobby" | "Countdown" | "Active" | "RoundEnd"
local currentState: string = "Lobby"

-- Remaining time in seconds (synced from server)
local timeRemaining: number = 0

-- Reference to GameHUD (lazy-loaded on first state change)
local GameHUD = nil

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

local function getGameHUD()
	if not GameHUD then
		GameHUD = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("GameHUD"))
	end
	return GameHUD
end

local function onGameStateChanged(newState: string, data: { [string]: any }?)
	currentState = newState
	local hud = getGameHUD()
	if hud then
		hud.onStateChanged(newState, data)
	end
	print("[GameStateController] State changed to:", newState)
end

local function onRoundTimerSync(seconds: number)
	timeRemaining = seconds
	local hud = getGameHUD()
	if hud then
		hud.onTimerUpdate(seconds)
	end
end

---------------------------------------------------------------------------
-- Public accessors
---------------------------------------------------------------------------

--- Get the current game state string.
function GameStateController.getState(): string
	return currentState
end

--- Get the remaining time in seconds.
function GameStateController.getTimeRemaining(): number
	return timeRemaining
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function GameStateController.init()
	-- Make sure the client network is ready
	ClientNetwork.init()

	-- Register server event listeners
	ClientNetwork.onServerEvent(EventNames.GameStateChanged, onGameStateChanged)
	ClientNetwork.onServerEvent(EventNames.RoundTimerSync, onRoundTimerSync)

	-- Initialise the GameHUD
	local hud = getGameHUD()
	if hud then
		hud.init()
	end

	print("[GameStateController] Initialised")
end

return GameStateController

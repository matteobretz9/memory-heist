--[[
	ModeController — Client-side game mode tracking.

	Responsibilities:
	  - Listen for ModeChanged and TeamAssigned events from the server.
	  - Track the current mode and team assignment locally.
	  - Expose getMode(), getTeam(), getTeamColor() for other client modules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventNames = require(Shared:WaitForChild("Network"):WaitForChild("EventNames"))
local ClientNetwork = require(script.Parent.Parent:WaitForChild("Network"))

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local ModeController = {}

-- Current mode key: "FFA" | "TDM" | "Duel"
local currentMode: string = "FFA"

-- Current mode display name
local currentModeName: string = "Free For All"

-- Team assignment (TDM only)
local myTeam: string? = nil
local myTeamColor: Color3? = nil

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

--- Show a brief notification to the player using Roblox's built-in system.
local function showNotification(title: string, text: string)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title,
			Text = text,
			Duration = 4,
		})
	end)
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------

local function onModeChanged(modeKey: string, modeName: string)
	currentMode = modeKey
	currentModeName = modeName

	-- Clear team assignment when mode changes
	myTeam = nil
	myTeamColor = nil

	showNotification("Mode Changed", modeName)
	print("[ModeController] Mode changed to:", modeKey, "-", modeName)
end

local function onTeamAssigned(teamName: string, teamColor: Color3)
	myTeam = teamName
	myTeamColor = teamColor

	showNotification("Team Assigned", "You are on team " .. teamName)
	print("[ModeController] Assigned to team:", teamName)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Returns the current mode key (e.g. "FFA", "TDM", "Duel").
function ModeController.getMode(): string
	return currentMode
end

--- Returns the display name for the current mode.
function ModeController.getModeName(): string
	return currentModeName
end

--- Returns the player's team name, or nil if not in a team mode.
function ModeController.getTeam(): string?
	return myTeam
end

--- Returns the player's team color, or nil if not in a team mode.
function ModeController.getTeamColor(): Color3?
	return myTeamColor
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function ModeController.init()
	ClientNetwork.onServerEvent(EventNames.ModeChanged, onModeChanged)
	ClientNetwork.onServerEvent(EventNames.TeamAssigned, onTeamAssigned)

	print("[ModeController] Initialised")
end

return ModeController

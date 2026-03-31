--[[
	ModeManager — Server-side game mode manager.

	Responsibilities:
	  - Track the current game mode (defaults to FFA).
	  - Validate mode changes against GameModeData.
	  - For TDM: team assignment, team scores, team kill tracking.
	  - For Duel: queue management, opponent tracking, active state.
	  - Broadcast ModeChanged to all clients on mode switch.
	  - Fire TeamAssigned to individual clients with team name + color.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameModeData = require(Shared.Data.GameModeData)
local EventNames = require(Shared.Network.EventNames)
local ServerNetwork = require(script.Parent.Parent.Network)

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local ModeManager = {}

-- Current mode key: "FFA" | "TDM" | "Duel"
local currentMode: string = "FFA"

---------------------------------------------------------------------------
-- TDM state
---------------------------------------------------------------------------

-- player UserId -> team name ("Red" | "Blue")
local teamAssignments: { [number]: string } = {}

-- team name -> kill count
local teamScores: { [string]: number } = {
	Red = 0,
	Blue = 0,
}

---------------------------------------------------------------------------
-- Duel state
---------------------------------------------------------------------------

-- Ordered queue of players waiting for a duel
local duelQueue: { Player } = {}

-- The two players currently dueling (nil if no duel active)
local duelPlayer1: Player? = nil
local duelPlayer2: Player? = nil
local duelActive: boolean = false

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

local function resetTeamState()
	teamAssignments = {}
	teamScores = { Red = 0, Blue = 0 }
end

local function resetDuelState()
	duelQueue = {}
	duelPlayer1 = nil
	duelPlayer2 = nil
	duelActive = false
end

--- Count how many players are on a given team.
local function getTeamCount(teamName: string): number
	local count = 0
	for _, team in teamAssignments do
		if team == teamName then
			count += 1
		end
	end
	return count
end

---------------------------------------------------------------------------
-- Public API — general
---------------------------------------------------------------------------

--- Returns the current mode key (e.g. "FFA", "TDM", "Duel").
function ModeManager.getCurrentMode(): string
	return currentMode
end

--- Returns the full config table for the current mode from GameModeData.
function ModeManager.getModeData(): { [string]: any }
	return GameModeData[currentMode]
end

--- Returns the config table for any mode by key.
function ModeManager.getModeDataByName(modeName: string): { [string]: any }?
	return GameModeData[modeName]
end

--- Switch to a new game mode. Returns true on success.
function ModeManager.setMode(modeName: string): boolean
	if not GameModeData[modeName] then
		warn("[ModeManager] Unknown mode:", modeName)
		return false
	end

	if modeName == currentMode then
		return true -- already in this mode
	end

	-- Clean up previous mode state
	resetTeamState()
	resetDuelState()

	currentMode = modeName
	print("[ModeManager] Mode ->", modeName)

	-- Broadcast to all clients
	local modeData = GameModeData[modeName]
	ServerNetwork.fireAllClients(EventNames.ModeChanged, modeName, modeData.name)

	return true
end

---------------------------------------------------------------------------
-- Public API — TDM
---------------------------------------------------------------------------

--- Assign a player to the team with fewer members. Returns the team name.
function ModeManager.assignTeam(player: Player): string
	if currentMode ~= "TDM" then
		warn("[ModeManager] assignTeam called outside TDM mode")
		return ""
	end

	-- If already assigned, return existing team
	local existing = teamAssignments[player.UserId]
	if existing then
		return existing
	end

	-- Assign to the team with fewer players
	local redCount = getTeamCount("Red")
	local blueCount = getTeamCount("Blue")
	local team: string
	if redCount <= blueCount then
		team = "Red"
	else
		team = "Blue"
	end

	teamAssignments[player.UserId] = team

	-- Notify the client of their team assignment
	local modeData = GameModeData.TDM
	ServerNetwork.fireClient(EventNames.TeamAssigned, player, team, modeData.teamColors[team])

	print("[ModeManager] Assigned", player.Name, "to team", team)
	return team
end

--- Get a player's team name, or nil if unassigned.
function ModeManager.getTeam(player: Player): string?
	return teamAssignments[player.UserId]
end

--- Returns the current team scores: { Red = number, Blue = number }.
function ModeManager.getTeamScores(): { [string]: number }
	return { Red = teamScores.Red, Blue = teamScores.Blue }
end

--- Increment the kill count for the team the given player belongs to.
function ModeManager.recordTeamKill(player: Player)
	local team = teamAssignments[player.UserId]
	if not team then
		warn("[ModeManager] recordTeamKill: player not on a team")
		return
	end

	teamScores[team] += 1
end

--- Remove a player's team assignment (e.g. on leave).
function ModeManager.removePlayer(player: Player)
	teamAssignments[player.UserId] = nil

	-- Also remove from duel queue if present
	for i, queued in duelQueue do
		if queued == player then
			table.remove(duelQueue, i)
			break
		end
	end

	-- If the player was in an active duel, end it
	if duelActive and (player == duelPlayer1 or player == duelPlayer2) then
		duelActive = false
		duelPlayer1 = nil
		duelPlayer2 = nil
	end
end

---------------------------------------------------------------------------
-- Public API — Duel
---------------------------------------------------------------------------

--- Add a player to the duel queue. If two players are queued, starts a duel.
--- Returns true if a duel was started.
function ModeManager.joinDuelQueue(player: Player): boolean
	if currentMode ~= "Duel" then
		warn("[ModeManager] joinDuelQueue called outside Duel mode")
		return false
	end

	-- Don't allow duplicate entries
	for _, queued in duelQueue do
		if queued == player then
			return false
		end
	end

	-- Don't allow joining if a duel is already active
	if duelActive then
		return false
	end

	table.insert(duelQueue, player)

	-- If we have two players, start the duel
	if #duelQueue >= 2 then
		duelPlayer1 = duelQueue[1]
		duelPlayer2 = duelQueue[2]
		duelQueue = {}
		duelActive = true
		print("[ModeManager] Duel started:", duelPlayer1.Name, "vs", duelPlayer2.Name)
		return true
	end

	return false
end

--- Returns the opponent for the given player in the current duel, or nil.
function ModeManager.getDuelOpponent(player: Player): Player?
	if not duelActive then
		return nil
	end

	if player == duelPlayer1 then
		return duelPlayer2
	elseif player == duelPlayer2 then
		return duelPlayer1
	end

	return nil
end

--- Returns true if a duel is currently active.
function ModeManager.isDuelActive(): boolean
	return duelActive
end

--- End the current duel and reset duel state.
function ModeManager.endDuel()
	duelActive = false
	duelPlayer1 = nil
	duelPlayer2 = nil
end

--- Returns the two duel participants, or nil if no duel is active.
function ModeManager.getDuelPlayers(): (Player?, Player?)
	if not duelActive then
		return nil, nil
	end
	return duelPlayer1, duelPlayer2
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function ModeManager.init()
	local Players = game:GetService("Players")

	-- Clean up when players leave
	Players.PlayerRemoving:Connect(function(player: Player)
		ModeManager.removePlayer(player)
	end)

	-- Default to FFA
	currentMode = "FFA"

	print("[ModeManager] Initialised (mode: FFA)")
end

return ModeManager

--[[
	GameStateService — Server-side round lifecycle and FFA scoring.

	Responsibilities:
	  - Manage a state machine: Lobby -> Countdown -> Active -> RoundEnd -> Lobby
	  - Lobby: wait for minimum 2 players, then transition to Countdown.
	  - Countdown: 10s timer with per-second broadcasts, then transition to Active.
	  - Active: 3-minute FFA round. Ends on timer expiry or first player to 10 kills.
	  - RoundEnd: 8s results screen, then back to Lobby.
	  - Track per-round kill scores by listening for KillOccurred.
	  - Broadcast GameStateChanged, RoundTimerSync, and RoundResults to all clients.
	  - Expose public API: getState(), getTimeRemaining(), getScoreboard().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EventNames = require(Shared.Network.EventNames)
local ServerNetwork = require(script.Parent.Parent.Network)

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local MIN_PLAYERS = 2
local COUNTDOWN_DURATION = 10 -- seconds
local ROUND_DURATION = 180 -- seconds (3 minutes)
local ROUND_END_DURATION = 8 -- seconds
local KILLS_TO_WIN = 10

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local GameStateService = {}

-- Current state: "Lobby" | "Countdown" | "Active" | "RoundEnd"
local currentState: string = "Lobby"

-- Time remaining in the current timed phase (Countdown, Active, RoundEnd)
local timeRemaining: number = 0

-- Per-round scoreboard: userId -> { playerName, kills }
local scoreboard: { [number]: { playerName: string, kills: number } } = {}

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

local function getPlayerCount(): number
	return #Players:GetPlayers()
end

--- Build a sorted standings array from the scoreboard for client consumption.
local function buildStandings(): { { playerName: string, kills: number, userId: number } }
	local standings = {}
	for userId, data in scoreboard do
		table.insert(standings, {
			playerName = data.playerName,
			kills = data.kills,
			userId = userId,
		})
	end
	-- Sort descending by kills
	table.sort(standings, function(a, b)
		return a.kills > b.kills
	end)
	return standings
end

--- Transition to a new state and broadcast to all clients.
local function setState(newState: string)
	currentState = newState
	ServerNetwork.fireAllClients(EventNames.GameStateChanged, newState)
	print("[GameStateService] State ->", newState)
end

--- Reset the scoreboard for a new round, registering all current players.
local function resetScoreboard()
	scoreboard = {}
	for _, player in Players:GetPlayers() do
		scoreboard[player.UserId] = {
			playerName = player.Name,
			kills = 0,
		}
	end
end

--- Register a single player into the scoreboard (for mid-round joins).
local function registerPlayer(player: Player)
	if not scoreboard[player.UserId] then
		scoreboard[player.UserId] = {
			playerName = player.Name,
			kills = 0,
		}
	end
end

--- Remove a player from the scoreboard when they leave.
local function unregisterPlayer(player: Player)
	scoreboard[player.UserId] = nil
end

---------------------------------------------------------------------------
-- State handlers — each returns when it is time to transition
---------------------------------------------------------------------------

local function runLobby()
	setState("Lobby")
	timeRemaining = 0

	-- Wait until we have enough players
	while getPlayerCount() < MIN_PLAYERS do
		task.wait(1)
	end
end

local function runCountdown()
	setState("Countdown")
	timeRemaining = COUNTDOWN_DURATION

	for i = COUNTDOWN_DURATION, 1, -1 do
		timeRemaining = i
		ServerNetwork.fireAllClients(EventNames.RoundTimerSync, i)
		task.wait(1)

		-- If players drop below minimum during countdown, abort back to lobby
		if getPlayerCount() < MIN_PLAYERS then
			return false -- signal: go back to lobby
		end
	end

	return true -- signal: proceed to active
end

local function runActive()
	-- Prepare scoreboard
	resetScoreboard()

	setState("Active")
	timeRemaining = ROUND_DURATION

	for i = ROUND_DURATION, 1, -1 do
		timeRemaining = i
		ServerNetwork.fireAllClients(EventNames.RoundTimerSync, i)
		task.wait(1)

		-- Check if any player has reached the kill threshold
		for _, data in scoreboard do
			if data.kills >= KILLS_TO_WIN then
				timeRemaining = 0
				return -- end round early
			end
		end
	end

	timeRemaining = 0
end

local function runRoundEnd()
	setState("RoundEnd")
	timeRemaining = ROUND_END_DURATION

	-- Send final standings to all clients
	local standings = buildStandings()
	ServerNetwork.fireAllClients(EventNames.RoundResults, standings)

	-- Phase 5: Award round-end credits, XP, and challenge progress
	do
		local okC, CurrencyService = pcall(require, script.Parent.CurrencyService)
		local okB, BattlePassService = pcall(require, script.Parent.BattlePassService)
		local okCh, ChallengeService = pcall(require, script.Parent.ChallengeService)

		-- All players get round participation rewards
		for _, player in Players:GetPlayers() do
			if okC then CurrencyService.addCredits(player, 5) end
			if okB then BattlePassService.awardRoundXP(player) end
			if okCh then ChallengeService.incrementStat(player, "roundsCompleted", 1) end
		end

		-- Winner gets bonus
		if #standings > 0 then
			local winnerName = standings[1].name
			for _, player in Players:GetPlayers() do
				if player.Name == winnerName then
					if okC then CurrencyService.addCredits(player, 50) end
					if okB then BattlePassService.awardWinXP(player) end
					if okCh then ChallengeService.incrementStat(player, "wins", 1) end
					break
				end
			end
		end
	end

	for i = ROUND_END_DURATION, 1, -1 do
		timeRemaining = i
		task.wait(1)
	end

	timeRemaining = 0
end

---------------------------------------------------------------------------
-- Main game loop (runs in a spawned thread so init() returns immediately)
---------------------------------------------------------------------------

local function gameLoop()
	while true do
		runLobby()

		local proceed = runCountdown()
		if proceed then
			runActive()
			runRoundEnd()
		end
		-- Loop back to Lobby regardless
	end
end

---------------------------------------------------------------------------
-- Event listeners
---------------------------------------------------------------------------

local function onKillOccurred(_player: Player, killerName: string, _victimName: string)
	-- KillOccurred is fired by CharacterService via fireAllClients, so this
	-- listener receives it through onClientEvent only if re-fired, but we
	-- actually need to hook into the server-side broadcast. Instead, we use
	-- a direct ServerNetwork listener pattern.
	-- NOTE: KillOccurred is broadcast via fireAllClients (server -> client).
	-- We cannot listen for that on the server. Instead we hook into the raw
	-- remote's OnServerEvent which won't fire for server-originated events.
	-- So we expose a public method for CharacterService to call directly.
	-- See recordKill() below.
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Called by other server services (e.g. CharacterService) when a kill happens.
function GameStateService.recordKill(killerPlayer: Player)
	if currentState ~= "Active" then
		return
	end

	registerPlayer(killerPlayer) -- ensure they're in the scoreboard
	local entry = scoreboard[killerPlayer.UserId]
	if entry then
		entry.kills += 1
	end
end

function GameStateService.getState(): string
	return currentState
end

function GameStateService.getTimeRemaining(): number
	return timeRemaining
end

function GameStateService.getScoreboard(): { { playerName: string, kills: number, userId: number } }
	return buildStandings()
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function GameStateService.init()
	-- Register players that join during Active state so they can spawn in
	Players.PlayerAdded:Connect(function(player: Player)
		if currentState == "Active" then
			registerPlayer(player)
		end
	end)

	-- Clean up when players leave
	Players.PlayerRemoving:Connect(function(player: Player)
		unregisterPlayer(player)
	end)

	-- Listen for KillOccurred via the RemoteEvent's OnServerEvent.
	-- CharacterService fires this with fireAllClients (server -> all clients),
	-- so clients receive it but the server does not. To track kills here we
	-- hook into the remote directly so that if any client re-fires it we
	-- ignore that (security). Instead, the recommended integration is for
	-- CharacterService to call GameStateService.recordKill() directly.
	-- We leave this hook as a no-op placeholder.

	-- Start the game loop in its own thread
	task.spawn(gameLoop)

	print("[GameStateService] Initialised")
end

return GameStateService

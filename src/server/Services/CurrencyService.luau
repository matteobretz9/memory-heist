--[[
	CurrencyService — Server-side credits currency management.

	Responsibilities:
	  - Track credits per player in memory (userId -> number).
	  - Provide getCredits / addCredits / removeCredits / hasEnough helpers.
	  - Award credits on gameplay events (kills, round participation, round wins).
	  - Fire CurrencyUpdate to the owning client on every balance change.
	  - Clean up on PlayerRemoving.

	NOTE: Uses in-memory storage with optional persistence through PlayerProfile.
	If ProfileService is available, credits are saved/loaded from player profiles.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EventNames = require(Shared.Network.EventNames)

local ServerNetwork = require(script.Parent.Parent.Network)

-- Try to load PlayerProfile for persistence (falls back to in-memory if unavailable)
local PlayerProfile = nil
do
	local ok, mod = pcall(require, script.Parent.Parent.Data.PlayerProfile)
	if ok then
		PlayerProfile = mod
	end
end

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local DEFAULT_CREDITS = 500
local CREDITS_PER_KILL = 25
local CREDITS_PER_ROUND = 5
local CREDITS_ROUND_WINNER = 50

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local CurrencyService = {}

-- userId -> credits (in-memory store)
local credits: { [number]: number } = {}

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

--- Push the current balance to the owning client.
local function syncCredits(player: Player)
	local balance = credits[player.UserId]
	if balance ~= nil then
		ServerNetwork.fireClient(EventNames.CurrencyUpdate, player, balance)
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Persist the in-memory balance to the player's profile (if available).
local function persistCredits(player: Player)
	if PlayerProfile and PlayerProfile.isLoaded(player) then
		PlayerProfile.setField(player, "credits", credits[player.UserId] or 0)
	end
end

--- Returns the player's current credit balance.
function CurrencyService.getCredits(player: Player): number
	return credits[player.UserId] or 0
end

--- Add credits to a player's balance. Fires CurrencyUpdate to the client.
function CurrencyService.addCredits(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local userId = player.UserId
	credits[userId] = (credits[userId] or 0) + amount
	persistCredits(player)
	syncCredits(player)
end

--- Remove credits from a player's balance if they have enough.
--- Returns true if the transaction succeeded, false otherwise.
--- Fires CurrencyUpdate to the client on success.
function CurrencyService.removeCredits(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end
	local userId = player.UserId
	local current = credits[userId] or 0
	if current < amount then
		return false
	end
	credits[userId] = current - amount
	persistCredits(player)
	syncCredits(player)
	return true
end

--- Check if the player has at least `amount` credits without removing any.
function CurrencyService.hasEnough(player: Player, amount: number): boolean
	return (credits[player.UserId] or 0) >= amount
end

--- Award kill credits. Called by CharacterService when a kill is attributed.
function CurrencyService.awardKillCredits(player: Player)
	CurrencyService.addCredits(player, CREDITS_PER_KILL)
end

---------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Load saved credits from profile, or use default for new players
	local savedCredits = nil
	if PlayerProfile and PlayerProfile.isLoaded(player) then
		savedCredits = PlayerProfile.getField(player, "credits")
	end
	credits[player.UserId] = savedCredits or DEFAULT_CREDITS

	-- Sync initial balance once the client is ready to receive events.
	-- A small delay ensures the client network has initialised.
	task.delay(1, function()
		if player.Parent and credits[player.UserId] then
			syncCredits(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	credits[player.UserId] = nil
end

---------------------------------------------------------------------------
-- Gameplay event listeners
---------------------------------------------------------------------------

--- Award participation credits to all players when a round ends.
local function onGameStateChanged(newState: string)
	if newState == "RoundEnd" then
		for _, player in Players:GetPlayers() do
			CurrencyService.addCredits(player, CREDITS_PER_ROUND)
		end
	end
end

--- Award bonus credits to the round winner (first entry in standings).
local function onRoundResults(standings: { any })
	if standings and #standings > 0 then
		local winnerEntry = standings[1]
		-- standings entries may be { player = Player, ... } or { Player, ... }
		local winnerPlayer: Player? = nil
		if typeof(winnerEntry) == "table" then
			winnerPlayer = winnerEntry.player or winnerEntry[1]
		elseif typeof(winnerEntry) == "Instance" then
			winnerPlayer = winnerEntry :: Player
		end
		if winnerPlayer and winnerPlayer:IsA("Player") and winnerPlayer.Parent then
			CurrencyService.addCredits(winnerPlayer, CREDITS_ROUND_WINNER)
		end
	end
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function CurrencyService.init()
	-- Player lifecycle
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players already in the game (studio quick-start)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- GameStateChanged and RoundResults are server->client only (fireAllClients),
	-- so we can't listen for them via OnServerEvent. Instead, we expose the
	-- handlers as public methods so GameStateService or a boot script can call them.
	CurrencyService.onGameStateChanged = onGameStateChanged
	CurrencyService.onRoundResults = onRoundResults

	print("[CurrencyService] Initialised — default credits:", DEFAULT_CREDITS)
end

return CurrencyService

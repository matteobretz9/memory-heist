--[[
	AnalyticsService — Server-side gameplay analytics tracking.

	Responsibilities:
	  - Track per-session global stats (kills, deaths, rounds, abilities used).
	  - Track ability pick rates and usage counts.
	  - Track weapon spawn, fire, and kill counts.
	  - Track player session times and average session duration.
	  - Track per-round stats (kills, duration, winner).
	  - Print a periodic summary to the server output every 60 seconds.
	  - Expose a public API for other services to record events.
]]

local Players = game:GetService("Players")

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local AnalyticsService = {}

---------------------------------------------------------------------------
-- Per-session global stats
---------------------------------------------------------------------------
local totalKills: number = 0
local totalDeaths: number = 0
local totalRoundsPlayed: number = 0
local totalAbilitiesUsed: number = 0

---------------------------------------------------------------------------
-- Ability tracking
---------------------------------------------------------------------------
local abilitySpawnCounts: { [string]: number } = {}
local abilityUseCounts: { [string]: number } = {}

---------------------------------------------------------------------------
-- Weapon tracking
---------------------------------------------------------------------------
local weaponSpawnCounts: { [string]: number } = {}
local weaponFireCounts: { [string]: number } = {}
local weaponKillCounts: { [string]: number } = {}

---------------------------------------------------------------------------
-- Player retention
---------------------------------------------------------------------------
-- userId -> session start time (os.clock())
local sessionStartTimes: { [number]: number } = {}

-- Total accumulated play time across all players who have left
local totalPlayTime: number = 0
local totalSessionsEnded: number = 0

---------------------------------------------------------------------------
-- Round stats history
---------------------------------------------------------------------------
type RoundRecord = {
	duration: number,
	winnerName: string,
	totalKills: number,
}

local roundHistory: { RoundRecord } = {}

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

--- Find the key with the highest value in a { [string]: number } table.
local function findTop(counts: { [string]: number }): (string, number)
	local topKey = "None"
	local topValue = 0
	for key, value in counts do
		if value > topValue then
			topKey = key
			topValue = value
		end
	end
	return topKey, topValue
end

---------------------------------------------------------------------------
-- Public API: Increment functions
---------------------------------------------------------------------------

function AnalyticsService.recordKill()
	totalKills += 1
end

function AnalyticsService.recordDeath()
	totalDeaths += 1
end

function AnalyticsService.recordRoundPlayed()
	totalRoundsPlayed += 1
end

function AnalyticsService.recordAbilityUsed()
	totalAbilitiesUsed += 1
end

---------------------------------------------------------------------------
-- Public API: Ability tracking
---------------------------------------------------------------------------

function AnalyticsService.recordAbilitySpawn(abilityId: string)
	abilitySpawnCounts[abilityId] = (abilitySpawnCounts[abilityId] or 0) + 1
end

function AnalyticsService.recordAbilityUse(abilityId: string)
	abilityUseCounts[abilityId] = (abilityUseCounts[abilityId] or 0) + 1
	totalAbilitiesUsed += 1
end

---------------------------------------------------------------------------
-- Public API: Weapon tracking
---------------------------------------------------------------------------

function AnalyticsService.recordWeaponSpawn(weaponId: string)
	weaponSpawnCounts[weaponId] = (weaponSpawnCounts[weaponId] or 0) + 1
end

function AnalyticsService.recordWeaponFire(weaponId: string)
	weaponFireCounts[weaponId] = (weaponFireCounts[weaponId] or 0) + 1
end

function AnalyticsService.recordWeaponKill(weaponId: string)
	weaponKillCounts[weaponId] = (weaponKillCounts[weaponId] or 0) + 1
end

---------------------------------------------------------------------------
-- Public API: Round stats
---------------------------------------------------------------------------

function AnalyticsService.recordRoundEnd(duration: number, winnerName: string, roundKills: number)
	totalRoundsPlayed += 1
	table.insert(roundHistory, {
		duration = duration,
		winnerName = winnerName,
		totalKills = roundKills,
	})
	print(
		string.format(
			"[Analytics] Round ended — Duration: %.1fs | Winner: %s | Kills: %d",
			duration,
			winnerName,
			roundKills
		)
	)
end

---------------------------------------------------------------------------
-- Public API: Player retention
---------------------------------------------------------------------------

function AnalyticsService.getAverageSessionTime(): number
	if totalSessionsEnded == 0 then
		return 0
	end
	return totalPlayTime / totalSessionsEnded
end

---------------------------------------------------------------------------
-- Public API: Full stats snapshot
---------------------------------------------------------------------------

function AnalyticsService.getStats(): {
	totalKills: number,
	totalDeaths: number,
	totalRoundsPlayed: number,
	totalAbilitiesUsed: number,
	abilitySpawnCounts: { [string]: number },
	abilityUseCounts: { [string]: number },
	weaponSpawnCounts: { [string]: number },
	weaponFireCounts: { [string]: number },
	weaponKillCounts: { [string]: number },
	averageSessionTime: number,
	roundHistory: { RoundRecord },
}
	return {
		totalKills = totalKills,
		totalDeaths = totalDeaths,
		totalRoundsPlayed = totalRoundsPlayed,
		totalAbilitiesUsed = totalAbilitiesUsed,
		abilitySpawnCounts = abilitySpawnCounts,
		abilityUseCounts = abilityUseCounts,
		weaponSpawnCounts = weaponSpawnCounts,
		weaponFireCounts = weaponFireCounts,
		weaponKillCounts = weaponKillCounts,
		averageSessionTime = AnalyticsService.getAverageSessionTime(),
		roundHistory = roundHistory,
	}
end

---------------------------------------------------------------------------
-- Player lifecycle hooks
---------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	sessionStartTimes[player.UserId] = os.clock()
end

local function onPlayerRemoving(player: Player)
	local startTime = sessionStartTimes[player.UserId]
	if startTime then
		local sessionDuration = os.clock() - startTime
		totalPlayTime += sessionDuration
		totalSessionsEnded += 1
		sessionStartTimes[player.UserId] = nil

		print(
			string.format(
				"[Analytics] %s left — Session: %.1fs | Avg session: %.1fs",
				player.Name,
				sessionDuration,
				AnalyticsService.getAverageSessionTime()
			)
		)
	end
end

---------------------------------------------------------------------------
-- Periodic summary
---------------------------------------------------------------------------

local function printSummary()
	local playerCount = #Players:GetPlayers()
	local topAbility, topAbilityUses = findTop(abilityUseCounts)
	local topWeapon, topWeaponFires = findTop(weaponFireCounts)
	local avgSession = AnalyticsService.getAverageSessionTime()

	print("[Analytics] === Server Stats ===")
	print(
		string.format(
			"Players: %d | Rounds: %d | Total Kills: %d",
			playerCount,
			totalRoundsPlayed,
			totalKills
		)
	)
	print(
		string.format(
			"Top Ability: %s (%d uses) | Top Weapon: %s (%d fires)",
			topAbility,
			topAbilityUses,
			topWeapon,
			topWeaponFires
		)
	)
	print(string.format("Avg Session: %.1fs", avgSession))
end

local function startSummaryLoop()
	task.spawn(function()
		while true do
			task.wait(60)
			printSummary()
		end
	end)
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function AnalyticsService.init()
	-- Hook player lifecycle events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players that joined before this module initialised (studio)
	for _, player in Players:GetPlayers() do
		if not sessionStartTimes[player.UserId] then
			sessionStartTimes[player.UserId] = os.clock()
		end
	end

	-- Start the periodic summary print loop
	startSummaryLoop()

	print("[AnalyticsService] Initialised")
end

return AnalyticsService

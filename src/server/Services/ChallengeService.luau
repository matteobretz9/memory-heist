--[[
	ChallengeService — Server-side daily/weekly challenge management.

	Responsibilities:
	  - On player join, randomly assign 3 daily and 2 weekly challenges.
	  - Track per-player progress in memory.
	  - Expose incrementStat() for other services to call when a stat changes.
	  - Handle claim requests from clients, awarding credits and XP.
	  - Sync challenge state to clients on join and on updates.
	  - Clean up on PlayerRemoving.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ChallengeData = require(Shared.Data.ChallengeData)
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
-- Types
---------------------------------------------------------------------------

type ChallengeEntry = {
	id: string,
	description: string,
	goal: number,
	stat: string,
	rewardCredits: number,
	rewardXP: number,
	progress: number,
	completed: boolean,
	claimed: boolean,
}

type PlayerChallenges = {
	dailies: { ChallengeEntry },
	weeklies: { ChallengeEntry },
}

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local ChallengeService = {}

-- userId -> PlayerChallenges
local playerChallenges: { [number]: PlayerChallenges } = {}

---------------------------------------------------------------------------
-- Random selection helpers
---------------------------------------------------------------------------

--- Pick `count` random entries from a list without replacement.
local function pickRandom(pool: { any }, count: number): { any }
	-- Clone the pool so we can modify it
	local available = table.clone(pool)
	local picked = {}

	for _ = 1, math.min(count, #available) do
		local index = math.random(1, #available)
		table.insert(picked, available[index])
		table.remove(available, index)
	end

	return picked
end

--- Create a ChallengeEntry from a template definition.
local function createEntry(template: any): ChallengeEntry
	return {
		id = template.id,
		description = template.description,
		goal = template.goal,
		stat = template.stat,
		rewardCredits = template.rewardCredits,
		rewardXP = template.rewardXP,
		progress = 0,
		completed = false,
		claimed = false,
	}
end

---------------------------------------------------------------------------
-- Persistence helpers
---------------------------------------------------------------------------

--- Persist challenge state to the player's profile (if available).
local function persistChallenges(player: Player, data: PlayerChallenges)
	if PlayerProfile and PlayerProfile.isLoaded(player) then
		PlayerProfile.setField(player, "challenges", {
			dailies = data.dailies,
			weeklies = data.weeklies,
			lastDailyReset = os.time(),
			lastWeeklyReset = os.time(),
		})
	end
end

---------------------------------------------------------------------------
-- Assign challenges for a player
---------------------------------------------------------------------------

local function assignChallenges(player: Player)
	local dailyTemplates = pickRandom(ChallengeData.Daily, 3)
	local weeklyTemplates = pickRandom(ChallengeData.Weekly, 2)

	local dailies = {}
	for _, template in dailyTemplates do
		table.insert(dailies, createEntry(template))
	end

	local weeklies = {}
	for _, template in weeklyTemplates do
		table.insert(weeklies, createEntry(template))
	end

	local data = {
		dailies = dailies,
		weeklies = weeklies,
	}
	playerChallenges[player.UserId] = data
	persistChallenges(player, data)
end

---------------------------------------------------------------------------
-- Serialise for network sync
---------------------------------------------------------------------------

local function serialiseChallenges(data: PlayerChallenges): any
	-- Already plain tables, just return a copy
	return {
		dailies = data.dailies,
		weeklies = data.weeklies,
	}
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--[[
	Get the full challenge state for a player (for syncing to client).
]]
function ChallengeService.getChallenges(player: Player): PlayerChallenges?
	return playerChallenges[player.UserId]
end

--[[
	Increment a stat for all of a player's active challenges that match.
	Called by other services (e.g. CharacterService on kill, AbilityService on use).

	@param player -- the player whose stat changed
	@param statName -- one of "kills", "abilitiesUsed", "roundsCompleted", "wins", "steals"
	@param amount -- how much to increment (default 1)
]]
function ChallengeService.incrementStat(player: Player, statName: string, amount: number?)
	local data = playerChallenges[player.UserId]
	if not data then
		return
	end

	local increment = amount or 1

	-- Check both dailies and weeklies
	local allChallenges = {}
	for _, entry in data.dailies do
		table.insert(allChallenges, entry)
	end
	for _, entry in data.weeklies do
		table.insert(allChallenges, entry)
	end

	for _, entry in allChallenges do
		if entry.stat == statName and not entry.completed then
			entry.progress = math.min(entry.progress + increment, entry.goal)

			-- Fire progress update to client
			ServerNetwork.fireClient(EventNames.ChallengeProgressUpdate, player, {
				id = entry.id,
				progress = entry.progress,
				goal = entry.goal,
			})

			-- Check for completion
			if entry.progress >= entry.goal then
				entry.completed = true
				ServerNetwork.fireClient(EventNames.ChallengeCompleted, player, {
					id = entry.id,
				})
			end
		end
	end

	persistChallenges(player, data)
end

--[[
	Claim a completed challenge's rewards.
	Validates that the challenge is completed and unclaimed before awarding.

	@param player -- the player claiming
	@param challengeId -- the id of the challenge to claim
]]
function ChallengeService.claimChallenge(player: Player, challengeId: string)
	local data = playerChallenges[player.UserId]
	if not data then
		warn("[ChallengeService] No challenge data for", player.Name)
		return
	end

	-- Find the challenge across dailies and weeklies
	local entry: ChallengeEntry? = nil
	for _, e in data.dailies do
		if e.id == challengeId then
			entry = e
			break
		end
	end
	if not entry then
		for _, e in data.weeklies do
			if e.id == challengeId then
				entry = e
				break
			end
		end
	end

	if not entry then
		warn("[ChallengeService] Challenge not found:", challengeId)
		return
	end

	if not entry.completed then
		warn("[ChallengeService] Challenge not completed:", challengeId)
		return
	end

	if entry.claimed then
		warn("[ChallengeService] Challenge already claimed:", challengeId)
		return
	end

	-- Mark as claimed
	entry.claimed = true
	persistChallenges(player, data)

	-- Award credits via CurrencyService
	local CurrencyService = require(script.Parent.CurrencyService)
	CurrencyService.addCredits(player, entry.rewardCredits)

	-- Award XP via BattlePassService
	local BattlePassService = require(script.Parent.BattlePassService)
	BattlePassService.addXP(player, entry.rewardXP)

	-- Notify client
	ServerNetwork.fireClient(EventNames.ChallengeRewardClaimed, player, {
		id = entry.id,
		rewardCredits = entry.rewardCredits,
		rewardXP = entry.rewardXP,
	})

	print("[ChallengeService]", player.Name, "claimed", challengeId, "->", entry.rewardCredits, "CR +", entry.rewardXP, "XP")
end

---------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Try to restore saved challenges from profile
	local restored = false
	if PlayerProfile and PlayerProfile.isLoaded(player) then
		local saved = PlayerProfile.getField(player, "challenges")
		if saved and saved.dailies and #saved.dailies > 0 then
			playerChallenges[player.UserId] = {
				dailies = saved.dailies,
				weeklies = saved.weeklies or {},
			}
			restored = true
		end
	end

	if not restored then
		assignChallenges(player)
	end

	-- Send initial sync after a short delay to ensure client UI is ready
	task.delay(2, function()
		local data = playerChallenges[player.UserId]
		if data then
			ServerNetwork.fireClient(EventNames.ChallengeSync, player, serialiseChallenges(data))
		end
	end)
end

local function onPlayerRemoving(player: Player)
	playerChallenges[player.UserId] = nil
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function ChallengeService.init()
	-- Hook player lifecycle events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players already in the game (studio)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Listen for claim requests from clients
	ServerNetwork.onClientEvent(EventNames.ChallengeClaimRequest, function(player: Player, challengeId: string)
		ChallengeService.claimChallenge(player, challengeId)
	end)

	print("[ChallengeService] Initialised")
end

return ChallengeService

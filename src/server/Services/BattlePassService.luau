--[[
	BattlePassService — Server-side progression tracking for the Battle Pass.

	Responsibilities:
	  - Track per-player progress in memory: current tier, XP, claimed tiers.
	  - Provide XP-award functions for other services (kills, rounds, wins).
	  - Handle tier-up logic (supports multi-tier level-ups in one call).
	  - Validate and grant reward claims (credits via CurrencyService,
	    cosmetics via CosmeticsService).
	  - Sync progress to the client via RemoteEvents.
	  - Clean up state on PlayerRemoving.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local BattlePassData = require(Shared.Data.BattlePassData)
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

local XP_PER_KILL = 15
local XP_PER_ROUND = 25
local XP_PER_WIN = 50

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local BattlePassService = {}

---------------------------------------------------------------------------
-- Per-player state
---------------------------------------------------------------------------

type BattlePassProgress = {
	currentTier: number,
	currentXP: number,
	claimedTiers: { [number]: boolean },
}

-- userId -> BattlePassProgress
local playerProgress: { [number]: BattlePassProgress } = {}

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

--- Create a fresh progress entry for a new player.
local function createDefaultProgress(): BattlePassProgress
	return {
		currentTier = 0,
		currentXP = 0,
		claimedTiers = {},
	}
end

--- Persist battle pass progress to the player's profile (if available).
local function persistProgress(player: Player, progress: BattlePassProgress)
	if PlayerProfile and PlayerProfile.isLoaded(player) then
		PlayerProfile.setField(player, "battlePassTier", progress.currentTier)
		PlayerProfile.setField(player, "battlePassXP", progress.currentXP)
		PlayerProfile.setField(player, "battlePassClaimedTiers", progress.claimedTiers)
	end
end

--- Build the payload sent to the client on every progress update.
local function buildProgressPayload(progress: BattlePassProgress)
	local xpToNext = BattlePassData.xpPerTier - progress.currentXP
	if progress.currentTier >= BattlePassData.maxTier then
		xpToNext = 0
	end

	return {
		currentTier = progress.currentTier,
		currentXP = progress.currentXP,
		xpToNext = xpToNext,
		claimedTiers = progress.claimedTiers,
	}
end

--- Push the latest progress to the owning client.
local function syncProgress(player: Player)
	local progress = playerProgress[player.UserId]
	if not progress then
		return
	end
	ServerNetwork.fireClient(EventNames.BattlePassUpdate, player, buildProgressPayload(progress))
end

---------------------------------------------------------------------------
-- Core XP / tier logic
---------------------------------------------------------------------------

--- Add XP and handle automatic tier-ups (can level multiple tiers at once).
function BattlePassService.addXP(player: Player, amount: number)
	local progress = playerProgress[player.UserId]
	if not progress then
		return
	end

	-- Already at max tier — nothing to do
	if progress.currentTier >= BattlePassData.maxTier then
		return
	end

	progress.currentXP += amount

	-- Level up as many times as the XP allows
	while progress.currentXP >= BattlePassData.xpPerTier and progress.currentTier < BattlePassData.maxTier do
		progress.currentXP -= BattlePassData.xpPerTier
		progress.currentTier += 1
	end

	-- Clamp leftover XP if we hit max tier
	if progress.currentTier >= BattlePassData.maxTier then
		progress.currentXP = 0
	end

	persistProgress(player, progress)
	syncProgress(player)
end

---------------------------------------------------------------------------
-- XP award helpers (called by other services)
---------------------------------------------------------------------------

--- Award XP for getting a kill.
function BattlePassService.awardKillXP(player: Player)
	BattlePassService.addXP(player, XP_PER_KILL)
end

--- Award XP for completing a round.
function BattlePassService.awardRoundXP(player: Player)
	BattlePassService.addXP(player, XP_PER_ROUND)
end

--- Award bonus XP for winning a round.
function BattlePassService.awardWinXP(player: Player)
	BattlePassService.addXP(player, XP_PER_WIN)
end

---------------------------------------------------------------------------
-- Reward claiming
---------------------------------------------------------------------------

--- Validate and grant a tier reward.
function BattlePassService.claimReward(player: Player, tier: number)
	local progress = playerProgress[player.UserId]
	if not progress then
		warn("[BattlePassService] No progress found for", player.Name)
		return
	end

	-- Validate tier number
	if tier < 1 or tier > BattlePassData.maxTier then
		warn("[BattlePassService] Invalid tier:", tier)
		return
	end

	-- Must have reached the tier
	if tier > progress.currentTier then
		warn("[BattlePassService] Player has not reached tier", tier)
		return
	end

	-- Must not have already claimed
	if progress.claimedTiers[tier] then
		warn("[BattlePassService] Tier", tier, "already claimed by", player.Name)
		return
	end

	-- Look up the reward definition
	local tierData = BattlePassData.tiers[tier]
	if not tierData then
		warn("[BattlePassService] No tier data for tier", tier)
		return
	end

	-- Grant the reward
	if tierData.rewardType == "credits" then
		-- Try to use CurrencyService if it exists
		local ok, CurrencyService = pcall(function()
			return require(script.Parent.CurrencyService)
		end)
		if ok and CurrencyService and CurrencyService.addCredits then
			CurrencyService.addCredits(player, tierData.amount)
		else
			warn("[BattlePassService] CurrencyService not available — credits reward for tier", tier, "not granted")
		end
	elseif tierData.rewardType == "cosmetic" then
		-- Try to use CosmeticsService if it exists
		local ok, CosmeticsService = pcall(function()
			return require(script.Parent.CosmeticsService)
		end)
		if ok and CosmeticsService and CosmeticsService.grantItem then
			CosmeticsService.grantItem(player, tierData.category, tierData.itemId)
		else
			warn("[BattlePassService] CosmeticsService not available — cosmetic reward for tier", tier, "not granted")
		end
	end

	-- Mark as claimed
	progress.claimedTiers[tier] = true
	persistProgress(player, progress)

	-- Notify the client that the reward was claimed
	ServerNetwork.fireClient(EventNames.BattlePassRewardClaimed, player, {
		tier = tier,
		reward = tierData.reward,
		rewardType = tierData.rewardType,
	})

	-- Also send updated progress
	syncProgress(player)
end

---------------------------------------------------------------------------
-- Progress getter (for other services)
---------------------------------------------------------------------------

--- Return the player's current Battle Pass progress.
function BattlePassService.getProgress(player: Player)
	local progress = playerProgress[player.UserId]
	if not progress then
		return nil
	end
	return buildProgressPayload(progress)
end

---------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Try to restore from saved profile
	if PlayerProfile and PlayerProfile.isLoaded(player) then
		local tier = PlayerProfile.getField(player, "battlePassTier")
		local xp = PlayerProfile.getField(player, "battlePassXP")
		local claimed = PlayerProfile.getField(player, "battlePassClaimedTiers")
		if tier then
			playerProgress[player.UserId] = {
				currentTier = tier,
				currentXP = xp or 0,
				claimedTiers = claimed or {},
			}
			return
		end
	end
	playerProgress[player.UserId] = createDefaultProgress()
end

local function onPlayerRemoving(player: Player)
	playerProgress[player.UserId] = nil
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function BattlePassService.init()
	-- Hook player lifecycle
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players already in game (studio)
	for _, player in Players:GetPlayers() do
		if not playerProgress[player.UserId] then
			onPlayerAdded(player)
		end
	end

	-- Listen for claim requests from clients
	ServerNetwork.onClientEvent(EventNames.BattlePassClaimRequest, function(player: Player, tier: number)
		BattlePassService.claimReward(player, tier)
	end)

	print("[BattlePassService] Initialised")
end

return BattlePassService

--[[
	Server-side player data management using ProfileService.
	Handles loading, saving, and accessing persistent player data.
]]

local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local ProfileService = require(ServerStorage.ServerPackages.ProfileService)

local PROFILE_STORE_NAME = "MemoryHeist_PlayerData_v1"

-- Default profile template — new players start with these values
local PROFILE_TEMPLATE = {
	-- Currency
	credits = 0,

	-- Lifetime stats
	totalKills = 0,
	totalDeaths = 0,
	totalWins = 0,
	totalMatches = 0,
	totalAbilitiesStolen = 0,

	-- Cosmetics
	ownedCosmetics = {},
	equippedCosmetics = {
		-- slot name -> cosmetic id
		weaponSkin = "",
		killEffect = "",
		playerTitle = "",
	},

	-- Battle pass
	battlePassTier = 0,
	battlePassXP = 0,
	battlePassPremium = false,
	battlePassClaimedTiers = {},

	-- Challenges (saved so progress survives reconnects)
	challenges = {
		dailies = {},
		weeklies = {},
		lastDailyReset = 0,
		lastWeeklyReset = 0,
	},

	-- Settings (synced to server for persistence)
	settings = {
		musicVolume = 0.5,
		sfxVolume = 0.8,
		sensitivity = 1.0,
	},
}

local PlayerProfile = {}
PlayerProfile._profileStore = nil
PlayerProfile._profiles = {} :: { [Player]: any }

function PlayerProfile.init()
	PlayerProfile._profileStore = ProfileService.GetProfileStore(
		PROFILE_STORE_NAME,
		PROFILE_TEMPLATE
	)

	-- Load profiles for players already in the game (in case of late init)
	for _, player in Players:GetPlayers() do
		task.spawn(PlayerProfile._loadProfile, player)
	end

	Players.PlayerAdded:Connect(function(player)
		PlayerProfile._loadProfile(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerProfile._releaseProfile(player)
	end)
end

function PlayerProfile._loadProfile(player: Player)
	local profile = PlayerProfile._profileStore:LoadProfileAsync(
		"Player_" .. player.UserId
	)

	if profile then
		profile:AddUserId(player.UserId)
		profile:Reconcile() -- fill in any missing template keys

		profile:ListenToRelease(function()
			PlayerProfile._profiles[player] = nil
			player:Kick("Your data profile was released. Please rejoin.")
		end)

		-- Check if player is still in game
		if player.Parent == Players then
			PlayerProfile._profiles[player] = profile
		else
			profile:Release()
		end
	else
		player:Kick("Failed to load your data. Please rejoin.")
	end
end

function PlayerProfile._releaseProfile(player: Player)
	local profile = PlayerProfile._profiles[player]
	if profile then
		profile:Release()
		PlayerProfile._profiles[player] = nil
	end
end

-- Get a player's profile data (returns nil if not loaded yet)
function PlayerProfile.getData(player: Player): typeof(PROFILE_TEMPLATE)?
	local profile = PlayerProfile._profiles[player]
	if profile then
		return profile.Data
	end
	return nil
end

-- Check if a player's profile is loaded
function PlayerProfile.isLoaded(player: Player): boolean
	return PlayerProfile._profiles[player] ~= nil
end

-- Increment a numeric stat
function PlayerProfile.incrementStat(player: Player, statName: string, amount: number?)
	local data = PlayerProfile.getData(player)
	if data and data[statName] ~= nil then
		data[statName] += (amount or 1)
	end
end

-- Add credits
function PlayerProfile.addCredits(player: Player, amount: number)
	local data = PlayerProfile.getData(player)
	if data then
		data.credits += amount
	end
end

-- Set a top-level key in the profile data
function PlayerProfile.setField(player: Player, key: string, value: any)
	local data = PlayerProfile.getData(player)
	if data then
		data[key] = value
	end
end

-- Get a top-level key from the profile data
function PlayerProfile.getField(player: Player, key: string): any
	local data = PlayerProfile.getData(player)
	if data then
		return data[key]
	end
	return nil
end

return PlayerProfile

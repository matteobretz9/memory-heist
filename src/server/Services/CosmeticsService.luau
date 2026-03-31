--[[
	CosmeticsService — Server-side cosmetic purchase and equip management.

	Tracks owned cosmetics per player in memory and handles purchase/equip
	requests from clients. Validates items exist, checks credits via
	CurrencyService, deducts credits on purchase, and syncs state to clients.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CosmeticsData = require(Shared.Data.CosmeticsData)
local EventNames = require(Shared.Network.EventNames)

local ServerNetwork = require(script.Parent.Parent.Network)
local CurrencyService = require(script.Parent.CurrencyService)

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

type EquippedCosmetics = {
	weaponSkin: string?,
	killEffect: string?,
}

type PlayerCosmeticState = {
	ownedItems: { [string]: { [string]: boolean } }, -- category -> { itemId -> true }
	equipped: EquippedCosmetics,
}

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local CosmeticsService = {}

-- userId -> PlayerCosmeticState
local playerCosmetics: { [number]: PlayerCosmeticState } = {}

---------------------------------------------------------------------------
-- Category to equipped-field mapping
---------------------------------------------------------------------------

local CATEGORY_TO_EQUIP_KEY: { [string]: string } = {
	WeaponSkins = "weaponSkin",
	KillEffects = "killEffect",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Validate that a category and item id exist in CosmeticsData.
local function validateItem(category: string, itemId: string): boolean
	local categoryData = CosmeticsData[category]
	if not categoryData then
		return false
	end
	return categoryData[itemId] ~= nil
end

--- Get or create the cosmetic state for a player.
local function getState(player: Player): PlayerCosmeticState?
	return playerCosmetics[player.UserId]
end

--- Persist cosmetic state to the player's profile (if available).
local function persistCosmetics(player: Player, state: PlayerCosmeticState)
	if PlayerProfile and PlayerProfile.isLoaded(player) then
		PlayerProfile.setField(player, "ownedCosmetics", state.ownedItems)
		PlayerProfile.setField(player, "equippedCosmetics", state.equipped)
	end
end

--- Check if a player owns a specific cosmetic.
local function ownsItem(state: PlayerCosmeticState, category: string, itemId: string): boolean
	local categoryOwned = state.ownedItems[category]
	if not categoryOwned then
		return false
	end
	return categoryOwned[itemId] == true
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Purchase a cosmetic item. Returns true on success, false + reason on failure.
function CosmeticsService.purchaseCosmetic(player: Player, category: string, itemId: string): (boolean, string?)
	-- Validate the item exists
	if not validateItem(category, itemId) then
		return false, "Invalid item"
	end

	local state = getState(player)
	if not state then
		return false, "Player not registered"
	end

	-- Check if already owned
	if ownsItem(state, category, itemId) then
		return false, "Already owned"
	end

	-- Get the price
	local itemDef = CosmeticsData[category][itemId]
	local price = itemDef.price

	-- Check and deduct credits
	local credits = CurrencyService.getCredits(player)
	if credits < price then
		return false, "Not enough credits"
	end

	local deducted = CurrencyService.removeCredits(player, price)
	if not deducted then
		return false, "Failed to deduct credits"
	end

	-- Add to owned items
	if not state.ownedItems[category] then
		state.ownedItems[category] = {}
	end
	state.ownedItems[category][itemId] = true
	persistCosmetics(player, state)

	-- Notify the client
	ServerNetwork.fireClient(EventNames.CosmeticPurchased, player, {
		category = category,
		itemId = itemId,
	})

	print("[CosmeticsService]", player.Name, "purchased", category, itemId)
	return true, nil
end

--- Equip a cosmetic item. Returns true on success, false + reason on failure.
function CosmeticsService.equipCosmetic(player: Player, category: string, itemId: string): (boolean, string?)
	-- Validate the item exists
	if not validateItem(category, itemId) then
		return false, "Invalid item"
	end

	local state = getState(player)
	if not state then
		return false, "Player not registered"
	end

	-- Check if owned
	if not ownsItem(state, category, itemId) then
		return false, "Not owned"
	end

	-- Get the equip key for this category
	local equipKey = CATEGORY_TO_EQUIP_KEY[category]
	if not equipKey then
		return false, "Invalid category"
	end

	-- Toggle off if already equipped, otherwise equip
	if state.equipped[equipKey] == itemId then
		state.equipped[equipKey] = nil
	else
		state.equipped[equipKey] = itemId
	end
	persistCosmetics(player, state)

	-- Notify the client
	ServerNetwork.fireClient(EventNames.CosmeticEquipped, player, {
		category = category,
		itemId = itemId,
		equipped = state.equipped,
	})

	print("[CosmeticsService]", player.Name, "equipped", category, itemId)
	return true, nil
end

--- Get the table of owned items for a player.
function CosmeticsService.getOwnedCosmetics(player: Player): { [string]: { [string]: boolean } }?
	local state = getState(player)
	if not state then
		return nil
	end
	return state.ownedItems
end

--- Get the equipped cosmetics table for a player.
function CosmeticsService.getEquipped(player: Player): EquippedCosmetics?
	local state = getState(player)
	if not state then
		return nil
	end
	return state.equipped
end

---------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Try to restore from saved profile
	local savedOwned = nil
	local savedEquipped = nil
	if PlayerProfile and PlayerProfile.isLoaded(player) then
		savedOwned = PlayerProfile.getField(player, "ownedCosmetics")
		savedEquipped = PlayerProfile.getField(player, "equippedCosmetics")
	end

	playerCosmetics[player.UserId] = {
		ownedItems = savedOwned or {},
		equipped = savedEquipped or {
			weaponSkin = nil,
			killEffect = nil,
		},
	}
end

local function onPlayerRemoving(player: Player)
	playerCosmetics[player.UserId] = nil
end

--- Sync full shop data to a requesting client.
local function syncShopData(player: Player)
	local state = getState(player)
	if not state then
		return
	end

	ServerNetwork.fireClient(EventNames.ShopDataSync, player, {
		ownedItems = state.ownedItems,
		equipped = state.equipped,
	})
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function CosmeticsService.init()
	-- Player lifecycle
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players already in the game (studio)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Listen for client purchase requests
	ServerNetwork.onClientEvent(EventNames.CosmeticPurchaseRequest, function(player: Player, data: any)
		if type(data) ~= "table" then
			return
		end
		local category = data.category
		local itemId = data.itemId
		if type(category) ~= "string" or type(itemId) ~= "string" then
			return
		end

		local success, reason = CosmeticsService.purchaseCosmetic(player, category, itemId)
		if not success then
			warn("[CosmeticsService] Purchase failed for", player.Name, ":", reason)
		end
	end)

	-- Listen for client equip requests
	ServerNetwork.onClientEvent(EventNames.CosmeticEquipRequest, function(player: Player, data: any)
		if type(data) ~= "table" then
			return
		end
		local category = data.category
		local itemId = data.itemId
		if type(category) ~= "string" or type(itemId) ~= "string" then
			return
		end

		local success, reason = CosmeticsService.equipCosmetic(player, category, itemId)
		if not success then
			warn("[CosmeticsService] Equip failed for", player.Name, ":", reason)
		end
	end)

	-- Listen for shop data sync requests
	ServerNetwork.onClientEvent(EventNames.ShopDataSync, function(player: Player)
		syncShopData(player)
	end)

	print("[CosmeticsService] Initialised")
end

return CosmeticsService

--[[
	CharacterService — Server-side character lifecycle management.

	Responsibilities:
	  - Track a PlayerState table per player (alive, abilities, weapon, stats).
	  - On PlayerAdded: register the player in the state map.
	  - On CharacterAdded: assign a random weapon + 1 random ability (weighted
	    by rarity spawn weights) and sync state to the client.
	  - On Humanoid.Died: attribute the kill via the "creator" ObjectValue tag,
	    fire KillOccurred to all clients, update stats, and respawn after 5 s.
	  - Expose getter / mutator helpers for other server services to use.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local AbilityData = require(Shared.Data.AbilityData)
local WeaponData = require(Shared.Data.WeaponData)
local RarityData = require(Shared.Data.RarityData)
local OverloadData = require(Shared.Data.OverloadData)
local EventNames = require(Shared.Network.EventNames)

local ServerNetwork = require(script.Parent.Parent.Network)

-- Type aliases for readability
type AbilitySlot = {
	abilityId: string,
	upgradeLevel: number,
	cooldownRemaining: number,
	isLocked: boolean,
}

type WeaponState = {
	weaponId: string,
	upgradeLevel: number,
	currentAmmo: number,
	isReloading: boolean,
}

type PlayerState = {
	alive: boolean,
	abilitySlots: { AbilitySlot },
	weapon: WeaponState,
	overloadTier: number,
	kills: number,
	deaths: number,
	score: number,
}

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local CharacterService = {}

-- userId -> PlayerState
local playerStates: { [number]: PlayerState } = {}

-- Connections we need to clean up when a player leaves
local playerConnections: { [number]: { RBXScriptConnection } } = {}

---------------------------------------------------------------------------
-- Weighted random ability selection
---------------------------------------------------------------------------

-- Build a flat list of { abilityId, weight } entries once at startup so we
-- don't re-compute every spawn.
local weightedAbilityPool: { { abilityId: string, weight: number } } = {}
local totalAbilityWeight: number = 0

local function buildAbilityPool()
	for id, def in AbilityData do
		local rarityInfo = RarityData[def.rarity]
		if rarityInfo then
			local weight = rarityInfo.spawnWeight
			table.insert(weightedAbilityPool, { abilityId = id, weight = weight })
			totalAbilityWeight += weight
		end
	end
end

--- Pick one random ability id from the weighted pool.
local function pickRandomAbility(): string
	local roll = math.random() * totalAbilityWeight
	local cumulative = 0
	for _, entry in weightedAbilityPool do
		cumulative += entry.weight
		if roll <= cumulative then
			return entry.abilityId
		end
	end
	-- Fallback (should not happen): return the last entry
	return weightedAbilityPool[#weightedAbilityPool].abilityId
end

---------------------------------------------------------------------------
-- Random weapon selection
---------------------------------------------------------------------------

-- Collect weapon ids into a simple list for uniform random selection.
local weaponIds: { string } = {}

local function buildWeaponList()
	for id, _ in WeaponData do
		table.insert(weaponIds, id)
	end
end

local function pickRandomWeapon(): string
	return weaponIds[math.random(1, #weaponIds)]
end

---------------------------------------------------------------------------
-- State factory helpers
---------------------------------------------------------------------------

local function createAbilitySlot(abilityId: string): AbilitySlot
	return {
		abilityId = abilityId,
		upgradeLevel = 1,
		cooldownRemaining = 0,
		isLocked = false,
	}
end

local function createWeaponState(weaponId: string): WeaponState
	local def = WeaponData[weaponId]
	return {
		weaponId = weaponId,
		upgradeLevel = 1,
		currentAmmo = if def then def.magazineSize else 0,
		isReloading = false,
	}
end

local function createDefaultPlayerState(): PlayerState
	local weaponId = pickRandomWeapon()
	local abilityId = pickRandomAbility()

	return {
		alive = true,
		abilitySlots = { createAbilitySlot(abilityId) },
		weapon = createWeaponState(weaponId),
		overloadTier = 0,
		kills = 0,
		deaths = 0,
		score = 0,
	}
end

---------------------------------------------------------------------------
-- Overload tier calculation
---------------------------------------------------------------------------

local function computeOverloadTier(slotCount: number): number
	if slotCount <= OverloadData.threshold then
		return 0
	end
	-- Walk tiers from highest to lowest and pick the first that applies.
	local best = 0
	for _, tier in OverloadData.tiers do
		if slotCount >= tier.minAbilities and tier.tier > best then
			best = tier.tier
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Sync helpers — push state changes to the owning client
---------------------------------------------------------------------------

local function syncAbilitySlots(player: Player)
	local state = playerStates[player.UserId]
	if not state then
		return
	end
	ServerNetwork.fireClient(EventNames.AbilitySlotUpdate, player, state.abilitySlots)
end

local function syncWeapon(player: Player)
	local state = playerStates[player.UserId]
	if not state then
		return
	end
	ServerNetwork.fireClient(EventNames.WeaponEquip, player, state.weapon)
end

local function syncOverload(player: Player)
	local state = playerStates[player.UserId]
	if not state then
		return
	end
	ServerNetwork.fireClient(EventNames.OverloadUpdate, player, state.overloadTier)
end

---------------------------------------------------------------------------
-- Character lifecycle
---------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local state = playerStates[player.UserId]
	if not state then
		return
	end

	-- Re-roll weapon and ability for the new life
	local weaponId = pickRandomWeapon()
	local abilityId = pickRandomAbility()

	state.alive = true
	state.weapon = createWeaponState(weaponId)
	state.abilitySlots = { createAbilitySlot(abilityId) }
	state.overloadTier = 0

	-- Notify the client of the loadout
	syncWeapon(player)
	syncAbilitySlots(player)
	syncOverload(player)
	ServerNetwork.fireClient(EventNames.CharacterSpawned, player)

	-- Listen for death
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local diedConn: RBXScriptConnection
	diedConn = humanoid.Died:Connect(function()
		diedConn:Disconnect()
		onCharacterDied(player, humanoid)
	end)

	-- Store connection so we can clean up if the player leaves mid-life
	table.insert(playerConnections[player.UserId], diedConn)
end

--- Handle a player death: attribute kill, broadcast, update stats, respawn.
function onCharacterDied(player: Player, humanoid: Humanoid)
	local state = playerStates[player.UserId]
	if not state then
		return
	end

	state.alive = false

	-- Determine killer via the standard "creator" ObjectValue tag
	local killerPlayer: Player? = nil
	local creatorTag = humanoid:FindFirstChild("creator")
	if creatorTag and creatorTag:IsA("ObjectValue") and creatorTag.Value then
		local killerInstance = creatorTag.Value
		if killerInstance:IsA("Player") then
			killerPlayer = killerInstance :: Player
		end
	end

	-- Update victim stats
	state.deaths += 1

	-- Update killer stats (if a valid killer exists and is not self)
	local killerName = ""
	if killerPlayer and killerPlayer ~= player then
		killerName = killerPlayer.Name
		local killerState = playerStates[killerPlayer.UserId]
		if killerState then
			killerState.kills += 1
			killerState.score += 100
			ServerNetwork.fireClient(EventNames.ScoreUpdate, killerPlayer, {
				kills = killerState.kills,
				deaths = killerState.deaths,
				score = killerState.score,
			})
		end
	end

	-- Broadcast the kill event to all clients
	ServerNetwork.fireAllClients(EventNames.KillOccurred, killerName, player.Name)

	-- Send updated stats to the victim
	ServerNetwork.fireClient(EventNames.CharacterDied, player)
	ServerNetwork.fireClient(EventNames.ScoreUpdate, player, {
		kills = state.kills,
		deaths = state.deaths,
		score = state.score,
	})

	-- Respawn after a delay
	task.delay(5, function()
		-- Make sure the player is still in the game
		if player.Parent and playerStates[player.UserId] then
			player:LoadCharacter()
		end
	end)
end

---------------------------------------------------------------------------
-- Player join / leave
---------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Initialise state and connection tracking
	playerStates[player.UserId] = createDefaultPlayerState()
	playerConnections[player.UserId] = {}

	-- Character lifecycle
	local charConn = player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	table.insert(playerConnections[player.UserId], charConn)

	-- If a character already exists (studio quick-start), handle it now
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	-- Clean up connections
	local conns = playerConnections[player.UserId]
	if conns then
		for _, conn in conns do
			conn:Disconnect()
		end
	end
	playerConnections[player.UserId] = nil
	playerStates[player.UserId] = nil
end

---------------------------------------------------------------------------
-- Public getters
---------------------------------------------------------------------------

function CharacterService.getPlayerState(player: Player): PlayerState?
	return playerStates[player.UserId]
end

function CharacterService.getAbilitySlots(player: Player): { AbilitySlot }?
	local state = playerStates[player.UserId]
	return if state then state.abilitySlots else nil
end

function CharacterService.getWeapon(player: Player): WeaponState?
	local state = playerStates[player.UserId]
	return if state then state.weapon else nil
end

function CharacterService.isAlive(player: Player): boolean
	local state = playerStates[player.UserId]
	return if state then state.alive else false
end

---------------------------------------------------------------------------
-- Public mutators
---------------------------------------------------------------------------

--- Add an ability to the player's loadout. Returns true on success.
function CharacterService.addAbility(player: Player, abilityId: string): boolean
	local state = playerStates[player.UserId]
	if not state then
		return false
	end

	-- Validate that the ability exists
	if not AbilityData[abilityId] then
		warn("[CharacterService] Unknown ability id:", abilityId)
		return false
	end

	-- Enforce slot cap
	if #state.abilitySlots >= OverloadData.maxSlots then
		warn("[CharacterService] Player already at max ability slots")
		return false
	end

	table.insert(state.abilitySlots, createAbilitySlot(abilityId))

	-- Recalculate overload tier
	state.overloadTier = computeOverloadTier(#state.abilitySlots)

	syncAbilitySlots(player)
	syncOverload(player)
	return true
end

--- Remove an ability by slot index (1-based). Returns true on success.
function CharacterService.removeAbility(player: Player, slotIndex: number): boolean
	local state = playerStates[player.UserId]
	if not state then
		return false
	end

	if slotIndex < 1 or slotIndex > #state.abilitySlots then
		warn("[CharacterService] Invalid slot index:", slotIndex)
		return false
	end

	table.remove(state.abilitySlots, slotIndex)

	-- Recalculate overload tier
	state.overloadTier = computeOverloadTier(#state.abilitySlots)

	syncAbilitySlots(player)
	syncOverload(player)
	return true
end

--- Replace the player's weapon. Returns true on success.
function CharacterService.setWeapon(player: Player, weaponId: string): boolean
	local state = playerStates[player.UserId]
	if not state then
		return false
	end

	if not WeaponData[weaponId] then
		warn("[CharacterService] Unknown weapon id:", weaponId)
		return false
	end

	state.weapon = createWeaponState(weaponId)
	syncWeapon(player)
	return true
end

--- Increment the player's kill count and add score.
function CharacterService.incrementKills(player: Player)
	local state = playerStates[player.UserId]
	if not state then
		return
	end
	state.kills += 1
	state.score += 100
end

--- Increment the player's death count.
function CharacterService.incrementDeaths(player: Player)
	local state = playerStates[player.UserId]
	if not state then
		return
	end
	state.deaths += 1
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function CharacterService.init()
	-- Build lookup tables used for random selection
	buildAbilityPool()
	buildWeaponList()

	-- Hook player lifecycle events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players that joined before this module initialised (studio)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	print("[CharacterService] Initialised")
end

return CharacterService

--[[
	StealService — Server-side steal system and memory shard management.

	Responsibilities:
	  - Detect player kills by listening to Humanoid.Died + creator tags.
	  - Spawn a "memory shard" (neon sphere) at the victim's death position
	    containing the victim's ability loadout.
	  - Handle shard pickup (Touched) and send StealChoiceRequest to the
	    touching player.
	  - Process StealChoiceResponse: steal ability (with rarity-based chance),
	    upgrade an existing ability, or upgrade the player's weapon.
	  - Clean up shards after a 15-second lifetime.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local AbilityData = require(Shared.Data.AbilityData)
local RarityData = require(Shared.Data.RarityData)
local OverloadData = require(Shared.Data.OverloadData)
local EventNames = require(Shared.Network.EventNames)

local ServerNetwork = require(script.Parent.Parent.Network)
local CharacterService = require(script.Parent.CharacterService)

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local SHARD_LIFETIME = 15 -- seconds before a shard auto-despawns
local SHARD_SIZE = Vector3.new(3, 3, 3)
local CHOICE_TIMEOUT = 10 -- seconds the player has to make a choice

-- Rarity priority for determining shard glow color (higher = better)
local RARITY_ORDER = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythic = 5,
}

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local StealService = {}

-- Track active shards so we can clean up: shardPart -> shardData
local activeShards: { [BasePart]: {
	victimName: string,
	victimAbilities: { any }, -- copy of the victim's ability slots at death
	killerPlayer: Player?,
	claimed: boolean, -- true once someone has touched it
} } = {}

-- Track player connections for cleanup
local playerConnections: { [number]: { RBXScriptConnection } } = {}

-- Players currently in a steal choice flow (prevent double-pickups)
local playersChoosing: { [number]: boolean } = {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Determine the best (highest rarity) ability from a list of slots and
--- return the corresponding RarityData color for the shard glow.
local function getBestRarityColor(abilitySlots: { any }): Color3
	local bestOrder = 0
	local bestRarity = "Common"

	for _, slot in abilitySlots do
		local def = AbilityData[slot.abilityId]
		if def then
			local order = RARITY_ORDER[def.rarity] or 0
			if order > bestOrder then
				bestOrder = order
				bestRarity = def.rarity
			end
		end
	end

	local rarityInfo = RarityData[bestRarity]
	return if rarityInfo then rarityInfo.color else Color3.fromRGB(180, 180, 180)
end

--- Deep-copy an array of ability slot tables so mutations don't affect the
--- victim's state after death.
local function copyAbilitySlots(slots: { any }): { any }
	local copy = {}
	for _, slot in slots do
		table.insert(copy, {
			abilityId = slot.abilityId,
			upgradeLevel = slot.upgradeLevel,
			cooldownRemaining = slot.cooldownRemaining,
			isLocked = slot.isLocked,
		})
	end
	return copy
end

--- Build a serialisable summary of abilities for the client UI.
local function serializeAbilitiesForClient(slots: { any }): { any }
	local result = {}
	for i, slot in slots do
		local def = AbilityData[slot.abilityId]
		table.insert(result, {
			slotIndex = i,
			abilityId = slot.abilityId,
			name = if def then def.name else slot.abilityId,
			rarity = if def then def.rarity else "Common",
			damage = if def then def.damage else 0,
			cooldown = if def then def.cooldown else 0,
			upgradeLevel = slot.upgradeLevel,
		})
	end
	return result
end

---------------------------------------------------------------------------
-- Shard creation
---------------------------------------------------------------------------

--- Spawn a memory shard at the given world position.
local function spawnShard(
	position: Vector3,
	victimName: string,
	victimAbilities: { any },
	killerPlayer: Player?
)
	-- Nothing to steal if the victim had no abilities
	if #victimAbilities == 0 then
		return
	end

	local shardColor = getBestRarityColor(victimAbilities)

	-- Create the physical shard (anchored, non-collidable sphere)
	local part = Instance.new("Part")
	part.Name = "MemoryShard"
	part.Shape = Enum.PartType.Ball
	part.Size = SHARD_SIZE
	part.Position = position + Vector3.new(0, 2, 0) -- float slightly above ground
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = shardColor
	part.CastShadow = false

	-- Point light for a glowing effect
	local light = Instance.new("PointLight")
	light.Color = shardColor
	light.Brightness = 2
	light.Range = 12
	light.Parent = part

	-- BillboardGui showing "Memory Shard" and the victim's name
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ShardLabel"
	billboard.Size = UDim2.new(0, 160, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.5, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 14
	titleLabel.TextColor3 = Color3.fromRGB(0, 255, 255)
	titleLabel.Text = "MEMORY SHARD"
	titleLabel.Parent = billboard

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "VictimName"
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.Position = UDim2.new(0, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = shardColor
	nameLabel.Text = victimName
	nameLabel.Parent = billboard

	-- Register shard data
	local shardData = {
		victimName = victimName,
		victimAbilities = victimAbilities,
		killerPlayer = killerPlayer,
		claimed = false,
	}
	activeShards[part] = shardData

	-- Parent to workspace
	part.Parent = workspace

	-- Notify all clients
	ServerNetwork.fireAllClients(EventNames.ShardSpawned, {
		position = position + Vector3.new(0, 2, 0),
		victimName = victimName,
		shardColor = { shardColor.R, shardColor.G, shardColor.B },
	})

	-- Touch detection
	local touchConnection: RBXScriptConnection
	touchConnection = part.Touched:Connect(function(otherPart: BasePart)
		-- Make sure the shard hasn't already been claimed
		if shardData.claimed then
			return
		end

		-- Determine which player touched it
		local character = otherPart.Parent
		if not character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		local touchPlayer = Players:GetPlayerFromCharacter(character)
		if not touchPlayer then
			return
		end

		-- Prevent players already in a choice flow from picking up another
		if playersChoosing[touchPlayer.UserId] then
			return
		end

		-- Claim the shard
		shardData.claimed = true
		touchConnection:Disconnect()

		-- Notify all clients that this shard was picked up
		ServerNetwork.fireAllClients(EventNames.ShardPickedUp, {
			position = part.Position,
			playerName = touchPlayer.Name,
		})

		-- Start the steal choice flow
		StealService._beginStealChoice(touchPlayer, shardData, part)
	end)

	-- Auto-despawn after SHARD_LIFETIME seconds
	task.delay(SHARD_LIFETIME, function()
		if not shardData.claimed then
			shardData.claimed = true -- prevent further touch processing
			touchConnection:Disconnect()
			activeShards[part] = nil
			if part.Parent then
				part:Destroy()
			end
			ServerNetwork.fireAllClients(EventNames.ShardDespawned, {
				position = part.Position,
			})
		end
	end)
end

---------------------------------------------------------------------------
-- Steal choice flow
---------------------------------------------------------------------------

--- Send the steal choice UI to a player and wait for their response.
function StealService._beginStealChoice(
	player: Player,
	shardData: any,
	shardPart: BasePart
)
	playersChoosing[player.UserId] = true

	-- Gather data the client needs to render the choice UI
	local playerState = CharacterService.getPlayerState(player)
	local playerAbilities = if playerState
		then serializeAbilitiesForClient(playerState.abilitySlots)
		else {}
	local playerWeapon = if playerState then playerState.weapon else nil
	local victimAbilities = serializeAbilitiesForClient(shardData.victimAbilities)

	-- Fire choice request to the touching player
	ServerNetwork.fireClient(EventNames.StealChoiceRequest, player, {
		victimName = shardData.victimName,
		victimAbilities = victimAbilities,
		playerAbilities = playerAbilities,
		playerWeapon = playerWeapon,
	})

	-- Wait for the client's response with a timeout
	local responded = false
	local choiceData = nil

	-- Get the raw remote so we can set up a one-shot listener
	local remote = ServerNetwork.getRemote(EventNames.StealChoiceResponse)
	if not remote then
		warn("[StealService] StealChoiceResponse remote not found")
		playersChoosing[player.UserId] = nil
		StealService._destroyShard(shardPart)
		return
	end

	local responseConnection: RBXScriptConnection
	local timeoutThread: thread

	responseConnection = (remote :: RemoteEvent).OnServerEvent:Connect(
		function(respondingPlayer: Player, data: any)
			if respondingPlayer ~= player then
				return
			end
			responded = true
			choiceData = data
			responseConnection:Disconnect()
			if timeoutThread then
				task.cancel(timeoutThread)
			end
		end
	)

	-- Timeout: if the player doesn't respond in time, clean up
	timeoutThread = task.delay(CHOICE_TIMEOUT, function()
		if not responded then
			responded = true -- prevent double processing
			responseConnection:Disconnect()
		end
	end)

	-- Yield until either the player responds or the timeout fires.
	-- We poll briefly to keep things simple and avoid complex signal wiring.
	local elapsed = 0
	while not responded and elapsed < CHOICE_TIMEOUT + 1 do
		task.wait(0.1)
		elapsed += 0.1
	end

	-- Process the choice (if any)
	if choiceData then
		StealService._processChoice(player, choiceData, shardData)
	end

	-- Cleanup
	playersChoosing[player.UserId] = nil
	StealService._destroyShard(shardPart)
end

--- Destroy a shard part and remove it from tracking.
function StealService._destroyShard(shardPart: BasePart)
	activeShards[shardPart] = nil
	if shardPart and shardPart.Parent then
		local position = shardPart.Position
		shardPart:Destroy()
		ServerNetwork.fireAllClients(EventNames.ShardDespawned, {
			position = position,
		})
	end
end

---------------------------------------------------------------------------
-- Choice processing
---------------------------------------------------------------------------

--[[
	Process the player's steal choice.

	Expected choiceData shapes:
	  { choice = "StealAbility", abilityId = string, replaceSlotIndex = number? }
	  { choice = "UpgradeAbility", slotIndex = number }
	  { choice = "UpgradeWeapon" }
]]
function StealService._processChoice(
	player: Player,
	choiceData: any,
	shardData: any
)
	local playerState = CharacterService.getPlayerState(player)
	if not playerState then
		warn("[StealService] No player state for", player.Name)
		return
	end

	local choice = choiceData.choice

	if choice == "StealAbility" then
		StealService._processStealAbility(player, playerState, choiceData, shardData)
	elseif choice == "UpgradeAbility" then
		StealService._processUpgradeAbility(player, playerState, choiceData)
	elseif choice == "UpgradeWeapon" then
		StealService._processUpgradeWeapon(player, playerState)
	else
		warn("[StealService] Unknown choice:", tostring(choice))
	end
end

--- Attempt to steal an ability from the shard (rarity-based chance roll).
function StealService._processStealAbility(
	player: Player,
	playerState: any,
	choiceData: any,
	shardData: any
)
	local abilityId = choiceData.abilityId
	if not abilityId then
		warn("[StealService] StealAbility missing abilityId")
		return
	end

	-- Validate the ability was actually in the shard
	local foundInShard = false
	for _, slot in shardData.victimAbilities do
		if slot.abilityId == abilityId then
			foundInShard = true
			break
		end
	end
	if not foundInShard then
		warn("[StealService] Ability", abilityId, "not found in shard")
		return
	end

	-- Look up ability definition for the rarity roll
	local abilityDef = AbilityData[abilityId]
	if not abilityDef then
		warn("[StealService] Unknown ability:", abilityId)
		return
	end

	-- Roll against rarity steal chance
	local rarityInfo = RarityData[abilityDef.rarity]
	local stealChance = if rarityInfo then rarityInfo.stealChance else 1.0
	local roll = math.random()

	if roll > stealChance then
		-- Steal failed
		ServerNetwork.fireClient(EventNames.UpgradeApplied, player, {
			success = false,
			message = "Steal failed! (" .. math.floor(stealChance * 100) .. "% chance)",
		})
		return
	end

	-- Steal succeeded — add the ability
	local currentSlotCount = #playerState.abilitySlots
	local replaceSlotIndex = choiceData.replaceSlotIndex

	if currentSlotCount >= OverloadData.maxSlots then
		-- Slots are full: must replace an existing ability
		if not replaceSlotIndex
			or replaceSlotIndex < 1
			or replaceSlotIndex > currentSlotCount
		then
			warn("[StealService] Slots full but no valid replaceSlotIndex")
			return
		end
		CharacterService.removeAbility(player, replaceSlotIndex)
	end

	local added = CharacterService.addAbility(player, abilityId)
	if added then
		ServerNetwork.fireClient(EventNames.UpgradeApplied, player, {
			success = true,
			message = "Stolen: " .. (abilityDef.name or abilityId),
		})
		-- AbilitySlotUpdate is already fired by CharacterService.addAbility
	end
end

--- Upgrade one of the player's existing abilities (increment upgradeLevel).
function StealService._processUpgradeAbility(
	player: Player,
	playerState: any,
	choiceData: any
)
	local slotIndex = choiceData.slotIndex
	if not slotIndex then
		warn("[StealService] UpgradeAbility missing slotIndex")
		return
	end

	local slots = playerState.abilitySlots
	if slotIndex < 1 or slotIndex > #slots then
		warn("[StealService] Invalid slotIndex:", slotIndex)
		return
	end

	-- Increment upgrade level directly on the player state
	local slot = slots[slotIndex]
	slot.upgradeLevel += 1

	-- Sync updated ability slots to the client
	ServerNetwork.fireClient(EventNames.AbilitySlotUpdate, player, slots)
	ServerNetwork.fireClient(EventNames.UpgradeApplied, player, {
		success = true,
		message = "Upgraded: "
			.. (AbilityData[slot.abilityId] and AbilityData[slot.abilityId].name or slot.abilityId)
			.. " (Lv " .. slot.upgradeLevel .. ")",
	})
end

--- Upgrade the player's weapon (increment weapon upgradeLevel).
function StealService._processUpgradeWeapon(
	player: Player,
	playerState: any
)
	local weapon = playerState.weapon
	if not weapon then
		warn("[StealService] Player has no weapon state")
		return
	end

	weapon.upgradeLevel += 1

	-- Sync updated weapon state to the client
	ServerNetwork.fireClient(EventNames.WeaponEquip, player, weapon)
	ServerNetwork.fireClient(EventNames.UpgradeApplied, player, {
		success = true,
		message = "Weapon upgraded (Lv " .. weapon.upgradeLevel .. ")",
	})
end

---------------------------------------------------------------------------
-- Kill detection
---------------------------------------------------------------------------

--- Called when a player's character dies. Reads the "creator" tag to find
--- the killer and spawns a memory shard at the death location.
local function onCharacterDied(victimPlayer: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Read the creator tag set by DamageService
	local killerPlayer: Player? = nil
	local creatorTag = humanoid:FindFirstChild("creator")
	if creatorTag and creatorTag:IsA("ObjectValue") and creatorTag.Value then
		local killerInstance = creatorTag.Value
		if killerInstance:IsA("Player") and killerInstance ~= victimPlayer then
			killerPlayer = killerInstance :: Player
		end
	end

	-- Only spawn a shard if there was a valid killer (no shard on suicide/fall)
	if not killerPlayer then
		return
	end

	-- Get the victim's ability loadout at the time of death
	local victimSlots = CharacterService.getAbilitySlots(victimPlayer)
	if not victimSlots or #victimSlots == 0 then
		return
	end

	-- Copy the slots so respawn resets don't affect the shard data
	local slotsCopy = copyAbilitySlots(victimSlots)

	-- Get the death position from the character's root part
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local deathPosition = if rootPart then rootPart.Position else Vector3.new(0, 5, 0)

	-- Spawn the shard
	spawnShard(deathPosition, victimPlayer.Name, slotsCopy, killerPlayer)
end

--- Hook into a character's Humanoid.Died event.
local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end

	local conn = humanoid.Died:Connect(function()
		onCharacterDied(player, character)
	end)

	-- Store connection for cleanup
	local conns = playerConnections[player.UserId]
	if conns then
		table.insert(conns, conn)
	end
end

local function onPlayerAdded(player: Player)
	playerConnections[player.UserId] = {}

	-- Hook current character (if it exists already, e.g. in Studio)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	-- Hook future characters
	local charConn = player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	table.insert(playerConnections[player.UserId], charConn)
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
	playersChoosing[player.UserId] = nil
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Can be called externally (e.g. from init.server.luau) to manually
--- trigger a kill event without relying on Humanoid.Died detection.
function StealService.handleKill(killer: Player, victim: Player)
	local victimSlots = CharacterService.getAbilitySlots(victim)
	if not victimSlots or #victimSlots == 0 then
		return
	end

	local slotsCopy = copyAbilitySlots(victimSlots)

	local rootPart = if victim.Character
		then victim.Character:FindFirstChild("HumanoidRootPart")
		else nil
	local deathPosition = if rootPart then rootPart.Position else Vector3.new(0, 5, 0)

	spawnShard(deathPosition, victim.Name, slotsCopy, killer)
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function StealService.init()
	-- Hook player lifecycle for Humanoid.Died listening
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players already in the game (Studio quick-start)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	print("[StealService] Initialised")
end

return StealService

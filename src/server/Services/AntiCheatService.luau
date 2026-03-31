--[[
	AntiCheatService — Server-side validation and rate-limiting for player actions.

	Responsibilities:
	  - Validate weapon fire rates against WeaponData definitions.
	  - Cap and validate damage amounts through a DamageService modifier.
	  - Detect speed hacking via periodic Heartbeat checks.
	  - Detect teleport exploits by tracking position deltas.
	  - Rate-limit RemoteEvent traffic per player.
	  - Flag and kick players who accumulate too many violations.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponData = require(ReplicatedStorage.Shared.Data.WeaponData)
local DamageService = require(script.Parent.DamageService)
local CharacterService = require(script.Parent.CharacterService)
local ServerNetwork = require(script.Parent.Parent.Network)

local AntiCheatService = {}

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local MAX_DAMAGE_PER_HIT = 60
local FIRE_RATE_TOLERANCE = 0.9 -- allow 90% of cooldown to account for latency

local SPEED_CHECK_INTERVAL = 2 -- seconds between speed checks
local SPEED_THRESHOLD_MULTIPLIER = 1.5
local SPEED_CONSECUTIVE_FAILS_TO_FLAG = 3

local TELEPORT_DISTANCE_THRESHOLD = 100 -- studs
local TELEPORT_TIME_THRESHOLD = 0.5 -- seconds
local TELEPORT_CHECK_INTERVAL = 0.5 -- how often we sample positions

-- Abilities that legitimately cause large position changes
local TELEPORT_ABILITY_WHITELIST: { [string]: boolean } = {
	Teleport = true,
	Dash = true,
	PulseDash = true,
	RocketJump = true,
}

local FLAG_KICK_THRESHOLD = 5
local KICK_MESSAGE = "Disconnected: Suspicious activity detected"

local RATE_LIMIT_MAX_EVENTS_PER_SECOND = 30
local RATE_LIMIT_COOLDOWN_DURATION = 5 -- seconds to ignore a rate-limited player

---------------------------------------------------------------------------
-- Per-player tracking state
---------------------------------------------------------------------------

-- Fire rate tracking: Player -> { [weaponId]: lastFireTime }
local fireRateTracker: { [Player]: { [string]: number } } = {}

-- Speed check tracking: Player -> { consecutiveFails: number }
local speedTracker: { [Player]: { consecutiveFails: number } } = {}

-- Teleport tracking: Player -> { position: Vector3, time: number }
local positionTracker: { [Player]: { position: Vector3, time: number } } = {}

-- Flag counts: Player -> number
local flagCounts: { [Player]: number } = {}

-- Rate limiting: Player -> { [eventName]: { count: number, windowStart: number } }
local eventCounts: { [Player]: { [string]: { count: number, windowStart: number } } } = {}

-- Rate limit cooldowns: Player -> expiry timestamp (0 means not limited)
local rateLimitExpiry: { [Player]: number } = {}

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

local function flagPlayer(player: Player, reason: string)
	local count = (flagCounts[player] or 0) + 1
	flagCounts[player] = count
	warn("[AntiCheat] Flag #" .. count .. " for " .. player.Name .. ": " .. reason)

	if count >= FLAG_KICK_THRESHOLD then
		warn("[AntiCheat] Kicking " .. player.Name .. " after " .. count .. " flags")
		player:Kick(KICK_MESSAGE)
	end
end

--- Check if a player currently has any teleport-whitelist ability equipped.
local function hasWhitelistedAbility(player: Player): boolean
	local slots = CharacterService.getAbilitySlots(player)
	if not slots then
		return false
	end

	for _, slot in slots do
		if slot and slot.abilityId and TELEPORT_ABILITY_WHITELIST[slot.abilityId] then
			return true
		end
	end

	return false
end

local function getHumanoidRootPosition(player: Player): Vector3?
	local char = player.Character
	if not char then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	return root.Position
end

local function getHumanoidWalkSpeed(player: Player): number?
	local char = player.Character
	if not char then
		return nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	return humanoid.WalkSpeed
end

local function isPlayerAlive(player: Player): boolean
	return CharacterService.isAlive(player)
end

---------------------------------------------------------------------------
-- 1. Fire rate validation
---------------------------------------------------------------------------

--[[
	Returns true if the fire attempt is valid (enough time has passed since
	the last shot for this weapon). Returns false if firing too fast.
]]
function AntiCheatService.validateFireRate(player: Player, weaponId: string): boolean
	local weaponDef = WeaponData[weaponId]
	if not weaponDef then
		warn("[AntiCheat] Unknown weapon in fire rate check:", weaponId)
		return false
	end

	local now = tick()
	local fireCooldown = 1.0 / weaponDef.fireRate

	local playerTracker = fireRateTracker[player]
	if not playerTracker then
		playerTracker = {}
		fireRateTracker[player] = playerTracker
	end

	local lastFire = playerTracker[weaponId] or 0
	local elapsed = now - lastFire

	if elapsed < fireCooldown * FIRE_RATE_TOLERANCE then
		warn("[AntiCheat] Fire rate violation for " .. player.Name .. " with " .. weaponId
			.. " (elapsed: " .. string.format("%.3f", elapsed)
			.. "s, min: " .. string.format("%.3f", fireCooldown * FIRE_RATE_TOLERANCE) .. "s)")
		return false
	end

	playerTracker[weaponId] = now
	return true
end

---------------------------------------------------------------------------
-- 2. Damage validation
---------------------------------------------------------------------------

--[[
	Returns true if the damage amount is within legitimate bounds.
	Rejects if:
	  - Amount exceeds MAX_DAMAGE_PER_HIT
	  - Attacker is dead
]]
function AntiCheatService.validateDamage(attacker: Player, amount: number): boolean
	-- Reject if attacker is dead
	if not isPlayerAlive(attacker) then
		warn("[AntiCheat] Damage rejected: attacker " .. attacker.Name .. " is dead")
		return false
	end

	-- Cap maximum damage per single hit
	if amount > MAX_DAMAGE_PER_HIT then
		warn("[AntiCheat] Damage rejected: " .. attacker.Name .. " attempted " .. amount
			.. " damage (max " .. MAX_DAMAGE_PER_HIT .. ")")
		return false
	end

	return true
end

--[[
	DamageService modifier that enforces anti-cheat damage rules.
	Registered in init(). Runs inline in the damage pipeline.
]]
local function damageModifier(
	attacker: Player,
	target: Player,
	amount: number,
	source: string
): number
	-- Reject damage from dead attackers
	if not isPlayerAlive(attacker) then
		warn("[AntiCheat] Modifier blocked damage: attacker " .. attacker.Name .. " is dead")
		return 0
	end

	-- Reject self-damage from weapon sources (ability self-damage may be intentional)
	if attacker == target then
		-- Only block weapon-sourced self damage; weapon IDs exist in WeaponData
		if WeaponData[source] then
			warn("[AntiCheat] Modifier blocked self-damage from weapon: " .. source)
			return 0
		end
	end

	-- Cap maximum damage per single hit
	if amount > MAX_DAMAGE_PER_HIT then
		warn("[AntiCheat] Modifier capped damage from " .. attacker.Name
			.. ": " .. amount .. " -> " .. MAX_DAMAGE_PER_HIT)
		flagPlayer(attacker, "excessive damage (" .. amount .. ")")
		return MAX_DAMAGE_PER_HIT
	end

	return amount
end

---------------------------------------------------------------------------
-- 3. Movement speed validation (Heartbeat loop)
---------------------------------------------------------------------------

local speedCheckAccumulator = 0

local function checkMovementSpeeds(dt: number)
	speedCheckAccumulator += dt
	if speedCheckAccumulator < SPEED_CHECK_INTERVAL then
		return
	end
	speedCheckAccumulator -= SPEED_CHECK_INTERVAL

	for _, player in Players:GetPlayers() do
		if not isPlayerAlive(player) then
			-- Reset consecutive fails if they are dead
			if speedTracker[player] then
				speedTracker[player].consecutiveFails = 0
			end
			continue
		end

		local char = player.Character
		if not char then
			continue
		end

		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end

		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			continue
		end

		-- Compute actual speed from the root part velocity (horizontal only)
		local velocity = root.AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

		local expectedMax = humanoid.WalkSpeed * SPEED_THRESHOLD_MULTIPLIER

		local tracker = speedTracker[player]
		if not tracker then
			tracker = { consecutiveFails = 0 }
			speedTracker[player] = tracker
		end

		if horizontalSpeed > expectedMax then
			tracker.consecutiveFails += 1

			if tracker.consecutiveFails >= SPEED_CONSECUTIVE_FAILS_TO_FLAG then
				flagPlayer(player, "speed hack detected (actual: "
					.. string.format("%.1f", horizontalSpeed)
					.. ", max: " .. string.format("%.1f", expectedMax) .. ")")
				tracker.consecutiveFails = 0 -- reset after flagging
			end
		else
			tracker.consecutiveFails = 0
		end
	end
end

---------------------------------------------------------------------------
-- 4. Teleport validation (runs on a faster tick)
---------------------------------------------------------------------------

local teleportCheckAccumulator = 0

local function checkTeleports(dt: number)
	teleportCheckAccumulator += dt
	if teleportCheckAccumulator < TELEPORT_CHECK_INTERVAL then
		return
	end
	teleportCheckAccumulator -= TELEPORT_CHECK_INTERVAL

	local now = tick()

	for _, player in Players:GetPlayers() do
		if not isPlayerAlive(player) then
			-- Clear position tracking for dead players so respawn doesn't trigger
			positionTracker[player] = nil
			continue
		end

		local currentPos = getHumanoidRootPosition(player)
		if not currentPos then
			continue
		end

		local prev = positionTracker[player]
		if prev then
			local timeDelta = now - prev.time
			if timeDelta > 0 and timeDelta <= TELEPORT_TIME_THRESHOLD then
				local distance = (currentPos - prev.position).Magnitude

				if distance > TELEPORT_DISTANCE_THRESHOLD then
					-- Check if player has a teleport-whitelist ability equipped
					if not hasWhitelistedAbility(player) then
						flagPlayer(player, "teleport detected ("
							.. string.format("%.1f", distance)
							.. " studs in "
							.. string.format("%.2f", timeDelta) .. "s)")
					end
				end
			end
		end

		positionTracker[player] = {
			position = currentPos,
			time = now,
		}
	end
end

---------------------------------------------------------------------------
-- 5. Rate limiting
---------------------------------------------------------------------------

--[[
	Record that a player fired a RemoteEvent. Call this from the network
	layer or from individual service handlers.
	Returns true if the event should be processed, false if rate-limited.
]]
local function recordEventFire(player: Player, eventName: string): boolean
	-- Check if player is currently in a rate-limit cooldown
	local expiry = rateLimitExpiry[player]
	if expiry and tick() < expiry then
		return false
	elseif expiry and tick() >= expiry then
		-- Cooldown expired, clear it
		rateLimitExpiry[player] = nil
	end

	local now = tick()

	local playerEvents = eventCounts[player]
	if not playerEvents then
		playerEvents = {}
		eventCounts[player] = playerEvents
	end

	local entry = playerEvents[eventName]
	if not entry then
		entry = { count = 0, windowStart = now }
		playerEvents[eventName] = entry
	end

	-- Reset window if more than 1 second has elapsed
	if now - entry.windowStart >= 1 then
		entry.count = 0
		entry.windowStart = now
	end

	entry.count += 1

	if entry.count > RATE_LIMIT_MAX_EVENTS_PER_SECOND then
		warn("[AntiCheat] Rate limiting " .. player.Name
			.. " — event '" .. eventName .. "' fired " .. entry.count .. " times in 1 second")
		rateLimitExpiry[player] = now + RATE_LIMIT_COOLDOWN_DURATION
		return false
	end

	return true
end

--[[
	Returns true if the player is currently rate-limited (their events
	should be ignored).
]]
function AntiCheatService.isRateLimited(player: Player): boolean
	local expiry = rateLimitExpiry[player]
	if not expiry then
		return false
	end
	if tick() >= expiry then
		rateLimitExpiry[player] = nil
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- 6. Public API
---------------------------------------------------------------------------

-- validateFireRate: defined above
-- validateDamage: defined above
-- isRateLimited: defined above

--[[
	Returns the number of anti-cheat flags accumulated by the player.
]]
function AntiCheatService.getFlagCount(player: Player): number
	return flagCounts[player] or 0
end

--[[
	Manually record a remote event fire for rate-limiting purposes.
	Returns true if the event should be processed, false if blocked.
]]
AntiCheatService.recordEventFire = recordEventFire

---------------------------------------------------------------------------
-- 7. Initialisation and cleanup
---------------------------------------------------------------------------

function AntiCheatService.init()
	-- Register the damage modifier with DamageService
	DamageService.registerModifier("AntiCheat", damageModifier)

	-- Set up the Heartbeat loop for speed and teleport checks
	RunService.Heartbeat:Connect(function(dt: number)
		checkMovementSpeeds(dt)
		checkTeleports(dt)
	end)

	-- Clean up player data on leave
	Players.PlayerRemoving:Connect(function(player: Player)
		fireRateTracker[player] = nil
		speedTracker[player] = nil
		positionTracker[player] = nil
		flagCounts[player] = nil
		eventCounts[player] = nil
		rateLimitExpiry[player] = nil
	end)

	print("[AntiCheatService] Initialized")
end

return AntiCheatService

--[[
	Server-side weapon management.
	Validates fire/reload requests, performs hit detection,
	and delegates damage to DamageService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ServerNetwork = require(script.Parent.Parent.Network)
local EventNames = require(ReplicatedStorage.Shared.Network.EventNames)
local WeaponData = require(ReplicatedStorage.Shared.Data.WeaponData)
local DamageService = require(script.Parent.DamageService)

local WeaponService = {}

--------------------------------------------------------------------------------
-- Per-player weapon state
--------------------------------------------------------------------------------

-- Tracks runtime weapon state for every player currently in the game.
-- Key = Player, value = { weaponId, currentAmmo, lastFireTime, isReloading }
local playerStates: {
	[Player]: {
		weaponId: string,
		currentAmmo: number,
		lastFireTime: number,
		isReloading: boolean,
	},
} = {}

-- RaycastParams shared by all hit-detection casts
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--[[
	Return the weapon definition for a player, or nil if none is assigned.
]]
local function getWeaponDef(player: Player)
	local state = playerStates[player]
	if not state then
		return nil
	end
	return WeaponData[state.weaponId]
end

--[[
	Build a fresh RaycastParams that ignores the attacker's character.
]]
local function buildRayParams(attackerChar: Model): RaycastParams
	rayParams.FilterDescendantsInstances = { attackerChar }
	return rayParams
end

--[[
	Resolve a RaycastResult into the Player who was hit (if any),
	and whether the hit part was the head.
]]
local function getPlayerFromHit(hit: Instance): (Player?, boolean)
	local char = hit:FindFirstAncestorOfClass("Model")
	if char then
		local player = Players:GetPlayerFromCharacter(char)
		local isHeadshot = hit.Name == "Head"
		return player, isHeadshot
	end
	return nil, false
end

--[[
	Apply random spread to a direction vector.
	spreadDeg is the half-cone angle in degrees.
]]
local function applySpread(direction: Vector3, spreadDeg: number): Vector3
	if spreadDeg <= 0 then
		return direction
	end
	local spreadRad = math.rad(spreadDeg)
	local angle = math.random() * spreadRad
	local rotation = math.random() * math.pi * 2

	-- Build a coordinate frame around the direction
	local cf = CFrame.lookAt(Vector3.zero, direction)
	local offset = CFrame.Angles(0, 0, rotation) * CFrame.Angles(angle, 0, 0)
	local spreadCF = cf * offset

	return spreadCF.LookVector
end

--------------------------------------------------------------------------------
-- Hit detection per firing mode
--------------------------------------------------------------------------------

--[[
	Hitscan: single ray (or multiple for shotguns).
	Returns a list of { player: Player, position: Vector3, isHeadshot: boolean } for confirmed hits.
]]
local function hitscanDetect(
	attacker: Player,
	origin: Vector3,
	direction: Vector3,
	weaponDef: any
): { { player: Player, position: Vector3, isHeadshot: boolean } }
	local attackerChar = attacker.Character
	if not attackerChar then
		return {}
	end

	local params = buildRayParams(attackerChar)
	local range = weaponDef.range
	local spread = weaponDef.spread
	local pellets = weaponDef.pelletsPerShot or 1

	local hits: { { player: Player, position: Vector3, isHeadshot: boolean } } = {}
	local alreadyHit: { [Player]: boolean } = {} -- one hit per target per shot for shotguns

	for _ = 1, pellets do
		local dir = applySpread(direction, spread)
		local result = Workspace:Raycast(origin, dir * range, params)
		if result then
			local hitPlayer, isHeadshot = getPlayerFromHit(result.Instance)
			if hitPlayer and hitPlayer ~= attacker and not alreadyHit[hitPlayer] then
				-- For shotguns each pellet damages independently, so we
				-- do NOT mark alreadyHit when pelletsPerShot > 1.
				if pellets == 1 then
					alreadyHit[hitPlayer] = true
				end
				table.insert(hits, { player = hitPlayer, position = result.Position, isHeadshot = isHeadshot })
			end
		end
	end

	return hits
end

--[[
	Melee: find characters in front of the attacker within range.
	Also detects backstabs by comparing attacker and target facing directions.
]]
local function meleeDetect(
	attacker: Player,
	weaponDef: any
): { { player: Player, position: Vector3, isBackstab: boolean } }
	local attackerChar = attacker.Character
	if not attackerChar then
		return {}
	end

	local rootPart = attackerChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return {}
	end

	local origin = rootPart.Position
	local forward = rootPart.CFrame.LookVector
	local range = weaponDef.range
	local rangeSq = range * range

	local hits: { { player: Player, position: Vector3, isBackstab: boolean } } = {}

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == attacker then
			continue
		end
		local otherChar = otherPlayer.Character
		if not otherChar then
			continue
		end
		local otherRoot = otherChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not otherRoot then
			continue
		end
		local otherHumanoid = otherChar:FindFirstChildOfClass("Humanoid")
		if not otherHumanoid or otherHumanoid.Health <= 0 then
			continue
		end

		local toTarget = otherRoot.Position - origin
		local distSq = toTarget.X ^ 2 + toTarget.Y ^ 2 + toTarget.Z ^ 2
		if distSq > rangeSq then
			continue
		end

		-- Dot product check: target must be roughly in front of the attacker
		local dot = forward:Dot(toTarget.Unit)
		if dot > 0.4 then -- ~66 degree half-cone
			-- Backstab check: if both characters face the same direction
			-- (dot product of forward vectors > 0.5), attacker is behind the target
			local targetForward = otherRoot.CFrame.LookVector
			local facingDot = forward:Dot(targetForward)
			local isBackstab = facingDot > 0.5

			table.insert(hits, { player = otherPlayer, position = otherRoot.Position, isBackstab = isBackstab })
		end
	end

	return hits
end

--[[
	Projectile: for now, same as hitscan but using full range.
	Actual projectile physics can be added later.
]]
local function projectileDetect(
	attacker: Player,
	origin: Vector3,
	direction: Vector3,
	weaponDef: any
): { { player: Player, position: Vector3, isHeadshot: boolean } }
	-- Reuse hitscan logic with full range (no spread for launchers usually)
	return hitscanDetect(attacker, origin, direction, weaponDef)
end

--------------------------------------------------------------------------------
-- Fire handling
--------------------------------------------------------------------------------

--[[
	Validate and process a fire request from a client.
]]
local function handleWeaponFire(player: Player, data: { origin: Vector3, direction: Vector3 })
	local state = playerStates[player]
	if not state then
		return
	end

	local weaponDef = WeaponData[state.weaponId]
	if not weaponDef then
		return
	end

	-- Player must be alive
	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Cannot fire while reloading
	if state.isReloading then
		return
	end

	-- Ammo check (melee weapons have magazineSize == 0, meaning unlimited)
	if weaponDef.magazineSize > 0 and state.currentAmmo <= 0 then
		return
	end

	-- Fire rate cooldown
	local now = tick()
	local fireCooldown = 1.0 / weaponDef.fireRate
	if (now - state.lastFireTime) < fireCooldown * 0.9 then
		-- 0.9 multiplier gives a small tolerance for network jitter
		return
	end
	state.lastFireTime = now

	-- Consume ammo
	if weaponDef.magazineSize > 0 then
		state.currentAmmo -= 1
	end

	-- Normalize the direction the client sent
	local direction = data.direction
	if direction.Magnitude == 0 then
		return
	end
	direction = direction.Unit

	-- Perform hit detection based on firing mode
	if weaponDef.firingMode == "Hitscan" then
		local hits = hitscanDetect(player, data.origin, direction, weaponDef)
		for _, hit in hits do
			local damage = weaponDef.damage
			if hit.isHeadshot then
				local multiplier = weaponDef.headshotMultiplier or 2.0
				damage = damage * multiplier
			end

			DamageService.processDamage(player, hit.player, damage, weaponDef.id)

			ServerNetwork.fireClient(EventNames.WeaponHitConfirm, player, {
				targetName = hit.player.Name,
				position = hit.position,
				isHeadshot = hit.isHeadshot,
			})
		end
	elseif weaponDef.firingMode == "Melee" then
		local hits = meleeDetect(player, weaponDef)
		for _, hit in hits do
			local damage = weaponDef.damage
			if hit.isBackstab then
				damage = damage * 2.0
			end

			DamageService.processDamage(player, hit.player, damage, weaponDef.id)

			ServerNetwork.fireClient(EventNames.WeaponHitConfirm, player, {
				targetName = hit.player.Name,
				position = hit.position,
				isBackstab = hit.isBackstab,
			})
		end
	elseif weaponDef.firingMode == "Projectile" then
		local hits = projectileDetect(player, data.origin, direction, weaponDef)
		for _, hit in hits do
			local damage = weaponDef.damage
			if hit.isHeadshot then
				local multiplier = weaponDef.headshotMultiplier or 2.0
				damage = damage * multiplier
			end

			DamageService.processDamage(player, hit.player, damage, weaponDef.id)

			ServerNetwork.fireClient(EventNames.WeaponHitConfirm, player, {
				targetName = hit.player.Name,
				position = hit.position,
				isHeadshot = hit.isHeadshot,
			})
		end
	end
end

--------------------------------------------------------------------------------
-- Reload handling
--------------------------------------------------------------------------------

--[[
	Validate and process a reload request from a client.
]]
local function handleWeaponReload(player: Player)
	local state = playerStates[player]
	if not state then
		return
	end

	local weaponDef = WeaponData[state.weaponId]
	if not weaponDef then
		return
	end

	-- Melee weapons don't reload
	if weaponDef.magazineSize <= 0 then
		return
	end

	-- Already reloading or magazine is full
	if state.isReloading then
		return
	end
	if state.currentAmmo >= weaponDef.magazineSize then
		return
	end

	state.isReloading = true

	-- Wait for the reload duration, then restore ammo
	task.delay(weaponDef.reloadTime, function()
		-- Make sure the player is still in the game and state hasn't been cleared
		if not playerStates[player] then
			return
		end
		state.currentAmmo = weaponDef.magazineSize
		state.isReloading = false
	end)
end

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Default weapon assignment. Other systems can change this later via
	-- WeaponService.setPlayerWeapon().
	local defaultWeapon = "PulseBlaster"
	local weaponDef = WeaponData[defaultWeapon]

	playerStates[player] = {
		weaponId = defaultWeapon,
		currentAmmo = weaponDef.magazineSize,
		lastFireTime = 0,
		isReloading = false,
	}
end

local function onPlayerRemoving(player: Player)
	playerStates[player] = nil
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
	Change a player's equipped weapon at runtime.
	Resets ammo and reload state for the new weapon.
]]
function WeaponService.setPlayerWeapon(player: Player, weaponId: string)
	local weaponDef = WeaponData[weaponId]
	if not weaponDef then
		warn("[WeaponService] Unknown weapon:", weaponId)
		return
	end

	playerStates[player] = {
		weaponId = weaponId,
		currentAmmo = weaponDef.magazineSize,
		lastFireTime = 0,
		isReloading = false,
	}
end

--[[
	Get the current weapon state for a player (read-only copy).
]]
function WeaponService.getPlayerState(player: Player)
	local state = playerStates[player]
	if not state then
		return nil
	end
	return {
		weaponId = state.weaponId,
		currentAmmo = state.currentAmmo,
		isReloading = state.isReloading,
	}
end

function WeaponService.init()
	-- Wire up network listeners
	ServerNetwork.onClientEvent(EventNames.WeaponFire, handleWeaponFire)
	ServerNetwork.onClientEvent(EventNames.WeaponReload, handleWeaponReload)

	-- Track player join/leave for state management
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players that joined before this script ran
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	print("[WeaponService] Initialized")
end

return WeaponService

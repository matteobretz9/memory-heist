--[[
	GlitchZoneService — Server-side Glitch Zone management.

	Responsibilities:
	  - Spawn 3-4 zone Parts in Workspace at predefined positions.
	  - Track which players are inside which zones via Touched/TouchEnded.
	  - Apply gameplay modifiers while players are inside:
	      SpeedZone: increase Humanoid.WalkSpeed
	      DamageZone: register a damage modifier with DamageService
	      LowGravZone: per-player gravity reduction via BodyForce (legacy, compatible)
	      GlitchStorm: reduce speed + boost damage
	  - Restore all values when a player leaves a zone.
	  - Fire GlitchZoneEnter / GlitchZoneExit events to affected clients.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local GlitchZoneData = require(Shared.Data.GlitchZoneData)
local EventNames = require(Shared.Network.EventNames)
local ServerNetwork = require(script.Parent.Parent.Network)
local DamageService = require(script.Parent.DamageService)

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local DEFAULT_WALK_SPEED = 16 -- Roblox default
local DEFAULT_GRAVITY = 196.2 -- workspace.Gravity default

-- Predefined spawn positions for zones (spread across the map)
local ZONE_SPAWN_POSITIONS = {
	Vector3.new(80, 5, 80),
	Vector3.new(-80, 5, -80),
	Vector3.new(80, 5, -80),
	Vector3.new(-80, 5, 80),
}

-- Which zone types to spawn (pick 3-4 from the data)
local ZONE_SPAWN_ORDER = { "SpeedZone", "DamageZone", "LowGravZone" }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

-- Map of player UserId -> set of zone type strings they are currently inside
-- e.g. { [12345] = { SpeedZone = true, LowGravZone = true } }
local playerZones: { [number]: { [string]: boolean } } = {}

-- Zone Part instances keyed by zone type
local zoneParts: { [string]: BasePart } = {}

-- Connections for cleanup
local connections: { RBXScriptConnection } = {}

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local GlitchZoneService = {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Get the Humanoid for a player's character, or nil.
local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

--- Get or create a BodyForce named "GlitchGravity" in the player's HumanoidRootPart.
local function getOrCreateBodyForce(player: Player): BodyForce?
	local character = player.Character
	if not character then
		return nil
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end
	local bf = rootPart:FindFirstChild("GlitchGravity")
	if not bf then
		bf = Instance.new("BodyForce")
		bf.Name = "GlitchGravity"
		bf.Force = Vector3.new(0, 0, 0)
		bf.Parent = rootPart
	end
	return bf :: BodyForce
end

--- Remove the GlitchGravity BodyForce from a player's character.
local function removeBodyForce(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end
	local bf = rootPart:FindFirstChild("GlitchGravity")
	if bf then
		bf:Destroy()
	end
end

--- Recalculate the combined speed multiplier from all zones the player is in.
local function recalcSpeed(player: Player)
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end

	local zones = playerZones[player.UserId]
	if not zones then
		humanoid.WalkSpeed = DEFAULT_WALK_SPEED
		return
	end

	local multiplier = 1.0
	for zoneType, active in zones do
		if active then
			local data = GlitchZoneData[zoneType]
			if data and data.speedMultiplier then
				multiplier *= data.speedMultiplier
			end
		end
	end

	humanoid.WalkSpeed = DEFAULT_WALK_SPEED * multiplier
end

--- Recalculate the gravity effect from all zones the player is in.
local function recalcGravity(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local zones = playerZones[player.UserId]
	local needsGravityChange = false
	local gravityMultiplier = 1.0

	if zones then
		for zoneType, active in zones do
			if active then
				local data = GlitchZoneData[zoneType]
				if data and data.gravityMultiplier then
					gravityMultiplier *= data.gravityMultiplier
					needsGravityChange = true
				end
			end
		end
	end

	if needsGravityChange then
		-- Use a BodyForce to counteract a portion of gravity for this player.
		-- Force needed = mass * gravity * (1 - multiplier), pointing upward.
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end

		-- Calculate total mass of the character assembly
		local mass = 0
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				mass += part:GetMass()
			end
		end

		local counterForce = mass * DEFAULT_GRAVITY * (1 - gravityMultiplier)
		local bf = getOrCreateBodyForce(player)
		if bf then
			bf.Force = Vector3.new(0, counterForce, 0)
		end
	else
		removeBodyForce(player)
	end
end

---------------------------------------------------------------------------
-- Zone enter / exit logic
---------------------------------------------------------------------------

local function onPlayerEnterZone(player: Player, zoneType: string)
	local userId = player.UserId

	-- Initialise the player's zone set if needed
	if not playerZones[userId] then
		playerZones[userId] = {}
	end

	-- Already in this zone? Skip.
	if playerZones[userId][zoneType] then
		return
	end

	playerZones[userId][zoneType] = true

	local data = GlitchZoneData[zoneType]
	if not data then
		return
	end

	-- Apply speed changes
	recalcSpeed(player)

	-- Apply gravity changes
	recalcGravity(player)

	-- Store damage multiplier as an attribute so the damage modifier can read it
	if data.damageMultiplier and data.damageMultiplier ~= 1.0 then
		local current = player:GetAttribute("GlitchDamageMultiplier") or 1.0
		player:SetAttribute("GlitchDamageMultiplier", current * data.damageMultiplier)
	end

	-- Notify the client
	ServerNetwork.fireClient(EventNames.GlitchZoneEnter, player, {
		zoneType = zoneType,
		name = data.name,
		color = { data.color.R, data.color.G, data.color.B },
	})
end

local function onPlayerExitZone(player: Player, zoneType: string)
	local userId = player.UserId

	if not playerZones[userId] then
		return
	end

	-- Not in this zone? Skip.
	if not playerZones[userId][zoneType] then
		return
	end

	playerZones[userId][zoneType] = nil

	local data = GlitchZoneData[zoneType]
	if not data then
		return
	end

	-- Restore speed
	recalcSpeed(player)

	-- Restore gravity
	recalcGravity(player)

	-- Remove damage multiplier contribution
	if data.damageMultiplier and data.damageMultiplier ~= 1.0 then
		local current = player:GetAttribute("GlitchDamageMultiplier") or 1.0
		local restored = current / data.damageMultiplier
		-- Clean up floating point: if close to 1.0, set exactly 1.0
		if math.abs(restored - 1.0) < 0.001 then
			player:SetAttribute("GlitchDamageMultiplier", nil)
		else
			player:SetAttribute("GlitchDamageMultiplier", restored)
		end
	end

	-- Notify the client
	ServerNetwork.fireClient(EventNames.GlitchZoneExit, player, {
		zoneType = zoneType,
		name = data.name,
		color = { data.color.R, data.color.G, data.color.B },
	})
end

---------------------------------------------------------------------------
-- Zone Part creation
---------------------------------------------------------------------------

local function createZonePart(zoneType: string, position: Vector3): BasePart
	local data = GlitchZoneData[zoneType]
	assert(data, "[GlitchZoneService] Unknown zone type: " .. zoneType)

	local part = Instance.new("Part")
	part.Name = "GlitchZone_" .. zoneType
	part.Size = data.size
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = data.color
	part.Transparency = 0.7
	part.Shape = Enum.PartType.Block
	part.Parent = workspace

	-- Add a BillboardGui label above the zone so players can see the name
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ZoneLabel"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, data.size.Y / 2 + 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = data.color
	label.TextStrokeTransparency = 0.5
	label.Text = data.name
	label.Parent = billboard

	-- Track touches using Touched/TouchEnded
	part.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		onPlayerEnterZone(player, zoneType)
	end)

	part.TouchEnded:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		-- Only exit if no other parts of the character are still touching.
		-- We use a brief delay to avoid flickering from multiple body parts.
		task.defer(function()
			-- Check if the player is still overlapping the zone
			local stillInside = false
			local playerChar = player.Character
			if playerChar then
				local rootPart = playerChar:FindFirstChild("HumanoidRootPart")
				if rootPart then
					local zp = zoneParts[zoneType]
					if zp then
						local relative = zp.CFrame:PointToObjectSpace(rootPart.Position)
						local halfSize = zp.Size / 2
						if math.abs(relative.X) <= halfSize.X
							and math.abs(relative.Y) <= halfSize.Y
							and math.abs(relative.Z) <= halfSize.Z
						then
							stillInside = true
						end
					end
				end
			end

			if not stillInside then
				onPlayerExitZone(player, zoneType)
			end
		end)
	end)

	return part
end

---------------------------------------------------------------------------
-- Heartbeat loop (reserved for future per-tick zone effects)
---------------------------------------------------------------------------

local function onHeartbeat(_dt: number)
	-- No per-tick effects currently active
end

---------------------------------------------------------------------------
-- Player cleanup
---------------------------------------------------------------------------

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	playerZones[userId] = nil
end

local function onCharacterRemoving(player: Player)
	-- When the character dies/respawns, clear their zone state and
	-- restore any modified attributes
	local userId = player.UserId
	local zones = playerZones[userId]
	if zones then
		for zoneType, active in zones do
			if active then
				local data = GlitchZoneData[zoneType]
				if data then
					-- No need to restore humanoid speed/gravity since the
					-- character is being destroyed; just clean up state
				end
			end
		end
	end
	playerZones[userId] = nil
	player:SetAttribute("GlitchDamageMultiplier", nil)
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function GlitchZoneService.init()
	-- Create zone parts at predefined positions
	local numZones = math.min(#ZONE_SPAWN_ORDER, #ZONE_SPAWN_POSITIONS)
	for i = 1, numZones do
		local zoneType = ZONE_SPAWN_ORDER[i]
		local position = ZONE_SPAWN_POSITIONS[i]
		zoneParts[zoneType] = createZonePart(zoneType, position)
	end

	-- Register a damage modifier with DamageService that reads the player attribute
	DamageService.registerModifier("GlitchZone", function(
		attacker: Player,
		_target: Player,
		amount: number,
		_source: string
	): number
		local multiplier = attacker:GetAttribute("GlitchDamageMultiplier")
		if multiplier and multiplier ~= 1.0 then
			return amount * multiplier
		end
		return amount
	end)

	-- Start the Heartbeat loop for heal ticks
	table.insert(connections, RunService.Heartbeat:Connect(onHeartbeat))

	-- Clean up player state on leave
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Clean up zone state when characters are removed (death/respawn)
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterRemoving:Connect(function()
			onCharacterRemoving(player)
		end)
	end)

	-- Handle players already in the game (studio)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			onCharacterRemoving(player)
		end)
	end

	print("[GlitchZoneService] Initialised — spawned", numZones, "zones")
end

return GlitchZoneService

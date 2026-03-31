--[[
	AbilityController — Client-side ability input and state management.

	Responsibilities:
	  - Bind keyboard input to ability slots (Q, E, R, F, Z).
	  - Maintain a local copy of ability slot state for responsive UI.
	  - Optimistically predict cooldowns so the HUD feels instant.
	  - Listen for authoritative server updates (cooldowns, locks, slot changes).
	  - Tick cooldowns every frame via RunService.Heartbeat.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local EventNames = require(Shared.Network.EventNames)
local AbilityData = require(Shared.Data.AbilityData)
local ClientNetwork = require(script.Parent.Parent.Network)
local HUD = require(script.Parent.Parent.UI.HUD)

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local AbilityController = {}

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

-- Map KeyCode to the button string used in AbilityData
local KEYCODE_TO_BUTTON: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Q] = "Q",
	[Enum.KeyCode.E] = "E",
	[Enum.KeyCode.F] = "F",
	[Enum.KeyCode.Z] = "Z",
	[Enum.KeyCode.Space] = "Space",
}

-- Minimum interval between HUD refreshes to avoid spamming UI updates
local HUD_UPDATE_INTERVAL = 0.1

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

-- Local copy of ability slots. Each entry is:
--   { abilityId: string, upgradeLevel: number, cooldownRemaining: number, isLocked: boolean }
-- Nil entries represent empty slots.
local abilitySlots: { any } = {}

-- Accumulator for throttled HUD updates during cooldown ticks
local hudUpdateTimer: number = 0

-- Whether any slot is currently cooling down (avoids unnecessary HUD updates)
local hasCooldowns: boolean = false

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

--- Refresh the HUD with current slot state.
local function pushHudUpdate()
	HUD.updateAbilitySlots(abilitySlots)
end

--- Look up the base cooldown for an ability by id.
local function getBaseCooldown(abilityId: string): number
	local def = AbilityData[abilityId]
	return if def then def.cooldown else 0
end

---------------------------------------------------------------------------
-- Input handling
---------------------------------------------------------------------------

--- Find the slot index whose ability's button matches the pressed key.
local function findSlotByButton(button: string): number?
	for i, slot in abilitySlots do
		if slot then
			local def = AbilityData[slot.abilityId]
			if def and def.button == button then
				return i
			end
		end
	end
	return nil
end

--- Called on every key press. Finds the ability whose button matches the
--- pressed key, then sends AbilityActivate to the server.
local function onInputBegan(input: InputObject, gameProcessedEvent: boolean)
	-- Only care about keyboard input
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	-- Ignore input consumed by the engine (e.g. chat, text boxes),
	-- EXCEPT for Space which Roblox always marks as processed (jump).
	if gameProcessedEvent and input.KeyCode ~= Enum.KeyCode.Space then
		return
	end

	local button = KEYCODE_TO_BUTTON[input.KeyCode]
	if not button then
		return
	end

	local slotIndex = findSlotByButton(button)
	if not slotIndex then
		return
	end

	local slot = abilitySlots[slotIndex]

	-- Must not be on cooldown
	if slot.cooldownRemaining > 0 then
		return
	end

	-- Must not be locked (e.g. by overload)
	if slot.isLocked then
		return
	end

	-- All checks passed — fire the event to the server with aim data
	local cam = workspace.CurrentCamera
	local aimData = nil
	if cam then
		aimData = {
			origin = cam.CFrame.Position,
			direction = cam.CFrame.LookVector,
		}
	end
	ClientNetwork.fireServer(EventNames.AbilityActivate, slotIndex, aimData)

	-- Optimistic cooldown prediction: set local cooldown immediately so the
	-- HUD reacts without waiting for the server round-trip. The server will
	-- send the authoritative value via AbilityCooldownUpdate.
	local baseCooldown = getBaseCooldown(slot.abilityId)
	if baseCooldown > 0 then
		slot.cooldownRemaining = baseCooldown
		hasCooldowns = true
	end

	pushHudUpdate()
end

---------------------------------------------------------------------------
-- Server event handlers
---------------------------------------------------------------------------

--- Server sends the full ability slots array (e.g. on spawn, loadout change).
local function onAbilitySlotUpdate(slots: { any })
	abilitySlots = slots

	-- Check if any slot has a non-zero cooldown
	hasCooldowns = false
	for _, slot in abilitySlots do
		if slot and slot.cooldownRemaining > 0 then
			hasCooldowns = true
			break
		end
	end

	pushHudUpdate()
end

--- Server corrects the cooldown for a specific slot.
local function onAbilityCooldownUpdate(slotIndex: number, cooldownRemaining: number)
	local slot = abilitySlots[slotIndex]
	if not slot then
		return
	end

	slot.cooldownRemaining = cooldownRemaining

	if cooldownRemaining > 0 then
		hasCooldowns = true
	end

	pushHudUpdate()
end

--- Server notifies that an ability was locked or unlocked (overload system).
local function onAbilityLocked(slotIndex: number, isLocked: boolean, _duration: number)
	local slot = abilitySlots[slotIndex]
	if not slot then
		return
	end

	slot.isLocked = isLocked
	pushHudUpdate()
end

---------------------------------------------------------------------------
-- Cooldown tick (runs every frame)
---------------------------------------------------------------------------

--- Decrement all local cooldowns by deltaTime. Periodically push updates
--- to the HUD so cooldown overlays animate smoothly without spamming.
local function onHeartbeat(deltaTime: number)
	if not hasCooldowns then
		return
	end

	local anyCooldown = false

	for _, slot in abilitySlots do
		if slot and slot.cooldownRemaining > 0 then
			slot.cooldownRemaining = math.max(0, slot.cooldownRemaining - deltaTime)
			if slot.cooldownRemaining > 0 then
				anyCooldown = true
			end
		end
	end

	hasCooldowns = anyCooldown

	-- Throttled HUD refresh
	hudUpdateTimer += deltaTime
	if hudUpdateTimer >= HUD_UPDATE_INTERVAL then
		hudUpdateTimer = 0
		pushHudUpdate()
	elseif not anyCooldown then
		-- All cooldowns just finished — push one final update immediately
		hudUpdateTimer = 0
		pushHudUpdate()
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Returns the current cached ability slots array.
function AbilityController.getAbilitySlots(): { any }
	return abilitySlots
end

--- Returns the remaining cooldown for a specific slot (0 if ready or empty).
function AbilityController.getSlotCooldown(slotIndex: number): number
	local slot = abilitySlots[slotIndex]
	if not slot then
		return 0
	end
	return slot.cooldownRemaining
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function AbilityController.init()
	-- Bind keyboard input
	UserInputService.InputBegan:Connect(onInputBegan)

	-- Listen for server events
	ClientNetwork.onServerEvent(EventNames.AbilitySlotUpdate, onAbilitySlotUpdate)
	ClientNetwork.onServerEvent(EventNames.AbilityCooldownUpdate, onAbilityCooldownUpdate)
	ClientNetwork.onServerEvent(EventNames.AbilityLocked, onAbilityLocked)

	-- Start the per-frame cooldown tick
	RunService.Heartbeat:Connect(onHeartbeat)

	print("[AbilityController] Initialised")
end

return AbilityController

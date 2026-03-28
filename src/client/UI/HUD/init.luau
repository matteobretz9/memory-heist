--[[
	Main HUD module for Memory Heist.
	Creates and manages the heads-up display: health bar, ability slots,
	weapon info, kill feed, and overload meter.

	All UI is built programmatically with pure Roblox Instances (no Roact/Fusion).
	Cyberpunk visual style: dark backgrounds, neon cyan accents, GothamBold font.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityData = require(Shared:WaitForChild("Data"):WaitForChild("AbilityData"))
local RarityData = require(Shared:WaitForChild("Data"):WaitForChild("RarityData"))
local EventNames = require(Shared:WaitForChild("Network"):WaitForChild("EventNames"))
local ClientNetwork = require(script.Parent.Parent:WaitForChild("Network"))

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- Style constants
-- ============================================================================

local COLORS = {
	bg = Color3.fromRGB(10, 10, 20),
	cyan = Color3.fromRGB(0, 255, 255),
	healthGreen = Color3.fromRGB(0, 230, 100),
	healthYellow = Color3.fromRGB(230, 200, 0),
	healthRed = Color3.fromRGB(230, 40, 40),
	white = Color3.fromRGB(255, 255, 255),
	dimText = Color3.fromRGB(120, 120, 140),
	slotEmpty = Color3.fromRGB(40, 40, 60),
	reloading = Color3.fromRGB(255, 80, 80),
}

local FONT = Enum.Font.GothamBold
local CORNER_RADIUS = UDim.new(0, 4)
local BG_TRANSPARENCY = 0.3

-- Keybind order for the 5 ability slots
local SLOT_KEYBINDS = { "Q", "E", "R", "F", "Z" }

-- ============================================================================
-- Module table
-- ============================================================================

local HUD = {}

-- References to UI elements we need to update after creation
local refs = {
	screenGui = nil :: ScreenGui?,
	-- Health
	healthFill = nil :: Frame?,
	healthLabel = nil :: TextLabel?,
	-- Ability slots (arrays indexed 1-5)
	abilityFrames = {} :: { Frame },
	abilityNames = {} :: { TextLabel },
	abilityKeybinds = {} :: { TextLabel },
	abilityCooldownOverlays = {} :: { Frame },
	abilityStrokes = {} :: { UIStroke },
	-- Weapon
	weaponNameLabel = nil :: TextLabel?,
	ammoLabel = nil :: TextLabel?,
	reloadingLabel = nil :: TextLabel?,
	-- Kill feed
	killFeedContainer = nil :: Frame?,
	-- Overload
	overloadContainer = nil :: Frame?,
	overloadFill = nil :: Frame?,
	overloadLabel = nil :: TextLabel?,
}

-- Track the Humanoid connection so we can disconnect on respawn
local healthConnection: RBXScriptConnection? = nil

-- ============================================================================
-- Helper: apply cyberpunk corner + stroke to a frame
-- ============================================================================

local function applyCorner(parent: GuiObject, radius: UDim?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or CORNER_RADIUS
	corner.Parent = parent
	return corner
end

local function applyStroke(parent: GuiObject, color: Color3?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or COLORS.cyan
	stroke.Thickness = thickness or 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

-- ============================================================================
-- Health Bar (bottom center)
-- ============================================================================

local function createHealthBar(parent: Frame)
	local container = Instance.new("Frame")
	container.Name = "HealthBar"
	container.Size = UDim2.new(0, 300, 0, 24)
	container.Position = UDim2.new(0.5, -150, 1, -36)
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = BG_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Parent = parent
	applyCorner(container)
	applyStroke(container, COLORS.cyan, 1)

	-- Fill bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0) -- starts full
	fill.Position = UDim2.new(0, 0, 0, 0)
	fill.BackgroundColor3 = COLORS.healthGreen
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.Parent = container
	applyCorner(fill)

	-- Health text overlay
	local label = Instance.new("TextLabel")
	label.Name = "HealthText"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = 14
	label.TextColor3 = COLORS.white
	label.Text = "100/100"
	label.ZIndex = 2
	label.Parent = container

	refs.healthFill = fill
	refs.healthLabel = label
end

-- ============================================================================
-- Ability Slots Bar (bottom center, above health bar)
-- ============================================================================

local function createAbilitySlots(parent: Frame)
	local SLOT_SIZE = 64
	local SLOT_GAP = 6
	local TOTAL_WIDTH = SLOT_SIZE * 5 + SLOT_GAP * 4

	local container = Instance.new("Frame")
	container.Name = "AbilitySlots"
	container.Size = UDim2.new(0, TOTAL_WIDTH, 0, SLOT_SIZE)
	container.Position = UDim2.new(0.5, -TOTAL_WIDTH / 2, 1, -36 - 10 - SLOT_SIZE)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	for i = 1, 5 do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		slot.BackgroundColor3 = COLORS.bg
		slot.BackgroundTransparency = BG_TRANSPARENCY
		slot.BorderSizePixel = 0
		slot.LayoutOrder = i
		slot.Parent = container
		applyCorner(slot)

		-- Rarity border stroke (default dim)
		local stroke = applyStroke(slot, COLORS.slotEmpty, 2)

		-- Ability name label
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "AbilityName"
		nameLabel.Size = UDim2.new(1, -4, 0.6, 0)
		nameLabel.Position = UDim2.new(0, 2, 0, 2)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = FONT
		nameLabel.TextSize = 11
		nameLabel.TextColor3 = COLORS.white
		nameLabel.TextWrapped = true
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Text = "Empty"
		nameLabel.ZIndex = 2
		nameLabel.Parent = slot

		-- Keybind label (bottom-right corner)
		local keybindLabel = Instance.new("TextLabel")
		keybindLabel.Name = "Keybind"
		keybindLabel.Size = UDim2.new(0, 20, 0, 16)
		keybindLabel.Position = UDim2.new(1, -22, 1, -18)
		keybindLabel.BackgroundColor3 = COLORS.bg
		keybindLabel.BackgroundTransparency = 0.4
		keybindLabel.Font = FONT
		keybindLabel.TextSize = 11
		keybindLabel.TextColor3 = COLORS.cyan
		keybindLabel.Text = SLOT_KEYBINDS[i]
		keybindLabel.ZIndex = 3
		keybindLabel.Parent = slot
		applyCorner(keybindLabel)

		-- Cooldown overlay (dark overlay that scales from full height -> 0)
		local cooldownOverlay = Instance.new("Frame")
		cooldownOverlay.Name = "CooldownOverlay"
		cooldownOverlay.Size = UDim2.new(1, 0, 0, 0) -- starts hidden (0 height)
		cooldownOverlay.Position = UDim2.new(0, 0, 1, 0)
		cooldownOverlay.AnchorPoint = Vector2.new(0, 1)
		cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		cooldownOverlay.BackgroundTransparency = 0.4
		cooldownOverlay.BorderSizePixel = 0
		cooldownOverlay.ZIndex = 2
		cooldownOverlay.Parent = slot
		applyCorner(cooldownOverlay)

		refs.abilityFrames[i] = slot
		refs.abilityNames[i] = nameLabel
		refs.abilityKeybinds[i] = keybindLabel
		refs.abilityCooldownOverlays[i] = cooldownOverlay
		refs.abilityStrokes[i] = stroke
	end
end

-- ============================================================================
-- Weapon Info (bottom right)
-- ============================================================================

local function createWeaponInfo(parent: Frame)
	local container = Instance.new("Frame")
	container.Name = "WeaponInfo"
	container.Size = UDim2.new(0, 180, 0, 60)
	container.Position = UDim2.new(1, -190, 1, -70)
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = BG_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Parent = parent
	applyCorner(container)
	applyStroke(container, COLORS.cyan, 1)

	-- Weapon name
	local weaponName = Instance.new("TextLabel")
	weaponName.Name = "WeaponName"
	weaponName.Size = UDim2.new(1, -10, 0, 20)
	weaponName.Position = UDim2.new(0, 5, 0, 4)
	weaponName.BackgroundTransparency = 1
	weaponName.Font = FONT
	weaponName.TextSize = 13
	weaponName.TextColor3 = COLORS.cyan
	weaponName.TextXAlignment = Enum.TextXAlignment.Left
	weaponName.Text = ""
	weaponName.Parent = container

	-- Ammo display
	local ammoLabel = Instance.new("TextLabel")
	ammoLabel.Name = "Ammo"
	ammoLabel.Size = UDim2.new(1, -10, 0, 20)
	ammoLabel.Position = UDim2.new(0, 5, 0, 24)
	ammoLabel.BackgroundTransparency = 1
	ammoLabel.Font = FONT
	ammoLabel.TextSize = 16
	ammoLabel.TextColor3 = COLORS.white
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Left
	ammoLabel.Text = ""
	ammoLabel.Parent = container

	-- Reloading indicator
	local reloadingLabel = Instance.new("TextLabel")
	reloadingLabel.Name = "Reloading"
	reloadingLabel.Size = UDim2.new(1, -10, 0, 16)
	reloadingLabel.Position = UDim2.new(0, 5, 0, 44)
	reloadingLabel.BackgroundTransparency = 1
	reloadingLabel.Font = FONT
	reloadingLabel.TextSize = 12
	reloadingLabel.TextColor3 = COLORS.reloading
	reloadingLabel.TextXAlignment = Enum.TextXAlignment.Left
	reloadingLabel.Text = ""
	reloadingLabel.Visible = false
	reloadingLabel.Parent = container

	refs.weaponNameLabel = weaponName
	refs.ammoLabel = ammoLabel
	refs.reloadingLabel = reloadingLabel
end

-- ============================================================================
-- Kill Feed (top right)
-- ============================================================================

local function createKillFeed(parent: Frame)
	local container = Instance.new("Frame")
	container.Name = "KillFeed"
	container.Size = UDim2.new(0, 300, 0, 130)
	container.Position = UDim2.new(1, -310, 0, 10)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	refs.killFeedContainer = container
end

-- ============================================================================
-- Overload Meter (left side)
-- ============================================================================

local function createOverloadMeter(parent: Frame)
	local container = Instance.new("Frame")
	container.Name = "OverloadMeter"
	container.Size = UDim2.new(0, 30, 0, 120)
	container.Position = UDim2.new(0, 16, 0.5, -60)
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = BG_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Visible = false -- hidden at tier 0
	container.Parent = parent
	applyCorner(container)
	applyStroke(container, COLORS.cyan, 1)

	-- Fill bar (grows upward from bottom)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, -4, 0, 0)
	fill.Position = UDim2.new(0, 2, 1, -2)
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.BackgroundColor3 = COLORS.cyan
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.Parent = container
	applyCorner(fill)

	-- "OVERLOAD" label above the bar
	local label = Instance.new("TextLabel")
	label.Name = "OverloadLabel"
	label.Size = UDim2.new(0, 80, 0, 18)
	label.Position = UDim2.new(0.5, 0, 0, -22)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = 12
	label.TextColor3 = COLORS.cyan
	label.Text = "OVERLOAD 0"
	label.Parent = container

	refs.overloadContainer = container
	refs.overloadFill = fill
	refs.overloadLabel = label
end

-- ============================================================================
-- Health color helper
-- ============================================================================

local function getHealthColor(fraction: number): Color3
	if fraction > 0.6 then
		return COLORS.healthGreen
	elseif fraction > 0.3 then
		return COLORS.healthYellow
	else
		return COLORS.healthRed
	end
end

-- ============================================================================
-- Character health connection
-- ============================================================================

local function connectToCharacterHealth()
	-- Disconnect previous connection if any
	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end

	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- Initial update
	HUD.updateHealth(humanoid.Health, humanoid.MaxHealth)

	healthConnection = humanoid.HealthChanged:Connect(function(newHealth: number)
		HUD.updateHealth(newHealth, humanoid.MaxHealth)
	end)
end

-- ============================================================================
-- Public API
-- ============================================================================

--[[
	Initialize the HUD. Creates the ScreenGui, all components, and connects
	to network events and character health.
]]
function HUD.init()
	-- Create the ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MemoryHeistHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	refs.screenGui = screenGui

	-- Main container (full screen)
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "HUDFrame"
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.BackgroundTransparency = 1
	mainFrame.Parent = screenGui

	-- Build all components
	createHealthBar(mainFrame)
	createAbilitySlots(mainFrame)
	createWeaponInfo(mainFrame)
	createKillFeed(mainFrame)
	createOverloadMeter(mainFrame)

	-- Connect to character health (now and on future respawns)
	task.spawn(connectToCharacterHealth)
	LocalPlayer.CharacterAdded:Connect(function()
		task.spawn(connectToCharacterHealth)
	end)

	-- Listen for network events
	ClientNetwork.onServerEvent(EventNames.KillOccurred, function(killerName: string, victimName: string)
		HUD.addKillFeedEntry(killerName, victimName)
	end)

	ClientNetwork.onServerEvent(EventNames.OverloadUpdate, function(tier: number)
		HUD.updateOverloadTier(tier)
	end)

	ClientNetwork.onServerEvent(EventNames.AbilitySlotUpdate, function(slots)
		HUD.updateAbilitySlots(slots)
	end)
end

--[[
	Update the health bar fill and text.
	@param current -- current health value
	@param max -- maximum health value
]]
function HUD.updateHealth(current: number, max: number)
	local fraction = if max > 0 then math.clamp(current / max, 0, 1) else 0
	local fill = refs.healthFill
	local label = refs.healthLabel

	if fill then
		fill.Size = UDim2.new(fraction, 0, 1, 0)
		fill.BackgroundColor3 = getHealthColor(fraction)
	end

	if label then
		label.Text = string.format("%d/%d", math.ceil(current), math.ceil(max))
	end
end

--[[
	Update all 5 ability slots from an array of AbilitySlot or nil entries.
	@param slots -- array of up to 5 AbilitySlot tables (nil for empty)
]]
function HUD.updateAbilitySlots(slots: { any })
	for i = 1, 5 do
		local slotData = slots[i] -- AbilitySlot or nil
		local nameLabel = refs.abilityNames[i]
		local keybindLabel = refs.abilityKeybinds[i]
		local cooldownOverlay = refs.abilityCooldownOverlays[i]
		local stroke = refs.abilityStrokes[i]
		local frame = refs.abilityFrames[i]

		if not nameLabel then
			continue
		end

		if slotData == nil then
			-- Empty slot
			nameLabel.Text = "Empty"
			nameLabel.TextColor3 = COLORS.dimText
			stroke.Color = COLORS.slotEmpty
			cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
			if frame then
				frame.BackgroundTransparency = 0.5
			end
		else
			-- Populated slot: look up ability data
			local abilityDef = AbilityData[slotData.abilityId]
			local abilityName = if abilityDef then abilityDef.name else slotData.abilityId
			local rarity = if abilityDef then abilityDef.rarity else "Common"
			local rarityInfo = RarityData[rarity]
			local cooldown = if abilityDef then abilityDef.cooldown else 0

			-- Set ability name
			nameLabel.Text = abilityName
			nameLabel.TextColor3 = if slotData.isLocked then COLORS.dimText else COLORS.white

			-- Rarity border color
			stroke.Color = if rarityInfo then rarityInfo.color else COLORS.cyan

			-- Keybind text (use the ability's defined button)
			if keybindLabel and abilityDef then
				keybindLabel.Text = abilityDef.button
			end

			-- Background transparency
			if frame then
				frame.BackgroundTransparency = if slotData.isLocked then 0.5 else BG_TRANSPARENCY
			end

			-- Cooldown overlay: scale height as fraction of cooldown remaining
			if cooldownOverlay then
				local cdFraction = 0
				if cooldown > 0 and slotData.cooldownRemaining > 0 then
					cdFraction = math.clamp(slotData.cooldownRemaining / cooldown, 0, 1)
				end
				cooldownOverlay.Size = UDim2.new(1, 0, cdFraction, 0)
			end
		end
	end
end

--[[
	Update the weapon info panel.
	@param weaponName -- display name of the weapon
	@param currentAmmo -- current ammo count
	@param maxAmmo -- magazine size
	@param isReloading -- whether the weapon is currently reloading
]]
function HUD.updateWeaponInfo(weaponName: string, currentAmmo: number, maxAmmo: number, isReloading: boolean)
	if refs.weaponNameLabel then
		refs.weaponNameLabel.Text = weaponName
	end

	if refs.ammoLabel then
		if maxAmmo > 0 then
			refs.ammoLabel.Text = string.format("%d / %d", currentAmmo, maxAmmo)
		else
			-- Melee weapon, no ammo display
			refs.ammoLabel.Text = ""
		end
	end

	if refs.reloadingLabel then
		refs.reloadingLabel.Visible = isReloading
		refs.reloadingLabel.Text = "RELOADING"
	end
end

--[[
	Add a kill feed entry that fades out and is destroyed after 5 seconds.
	@param killerName -- name of the player who got the kill
	@param victimName -- name of the eliminated player
]]
function HUD.addKillFeedEntry(killerName: string, victimName: string)
	local container = refs.killFeedContainer
	if not container then
		return
	end

	-- Enforce max 5 visible entries by removing the oldest if needed
	local children = {}
	for _, child in container:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(children, child)
		end
	end
	if #children >= 5 then
		-- Remove the oldest (lowest LayoutOrder)
		table.sort(children, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		children[1]:Destroy()
	end

	-- Create the entry
	local entry = Instance.new("TextLabel")
	entry.Name = "KillEntry"
	entry.Size = UDim2.new(1, 0, 0, 22)
	entry.BackgroundColor3 = COLORS.bg
	entry.BackgroundTransparency = 0.5
	entry.Font = FONT
	entry.TextSize = 13
	entry.TextColor3 = COLORS.white
	entry.TextXAlignment = Enum.TextXAlignment.Right
	entry.Text = killerName .. " eliminated " .. victimName
	entry.LayoutOrder = tick() -- use timestamp for ordering
	entry.Parent = container
	applyCorner(entry)

	-- Fade out and destroy after 5 seconds
	task.delay(4, function()
		if entry and entry.Parent then
			local fadeInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = TweenService:Create(entry, fadeInfo, {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			})
			tween:Play()
			tween.Completed:Connect(function()
				if entry and entry.Parent then
					entry:Destroy()
				end
			end)
		end
	end)
end

--[[
	Update the overload meter display.
	@param tier -- overload tier (0 = hidden, 1-3 = escalating)
]]
function HUD.updateOverloadTier(tier: number)
	local container = refs.overloadContainer
	local fill = refs.overloadFill
	local label = refs.overloadLabel

	if not container then
		return
	end

	if tier <= 0 then
		container.Visible = false
		return
	end

	container.Visible = true

	-- Update label
	if label then
		label.Text = "OVERLOAD " .. tier
	end

	-- Fill: 33% per tier (of the available inner height)
	local innerHeight = 120 - 4 -- container height minus padding
	local fillFraction = math.clamp(tier / 3, 0, 1)
	if fill then
		local targetHeight = math.floor(innerHeight * fillFraction)
		fill.Size = UDim2.new(1, -4, 0, targetHeight)
	end

	-- Glow effect: increase stroke thickness and brightness at higher tiers
	local stroke = container:FindFirstChildOfClass("UIStroke")
	if stroke then
		if tier >= 3 then
			stroke.Color = Color3.fromRGB(255, 50, 50)
			stroke.Thickness = 3
		elseif tier >= 2 then
			stroke.Color = Color3.fromRGB(255, 150, 0)
			stroke.Thickness = 2
		else
			stroke.Color = COLORS.cyan
			stroke.Thickness = 1
		end
	end

	-- Fill color intensifies with tier
	if fill then
		if tier >= 3 then
			fill.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
			fill.BackgroundTransparency = 0
		elseif tier >= 2 then
			fill.BackgroundColor3 = Color3.fromRGB(255, 150, 0)
			fill.BackgroundTransparency = 0.05
		else
			fill.BackgroundColor3 = COLORS.cyan
			fill.BackgroundTransparency = 0.1
		end
	end
end

return HUD

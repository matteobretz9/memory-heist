--[[
	Main HUD module for Memory Heist.
	Creates and manages the heads-up display: health bar, ability slots,
	weapon info, kill feed, and overload meter.

	All UI is built programmatically with pure Roblox Instances (no Roact/Fusion).
	Cyberpunk visual style: dark backgrounds, neon cyan accents, GothamBold font.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
-- DISABLED: Weapons & abilities removed from game (files kept in repo)
-- local AbilityData = require(Shared:WaitForChild("Data"):WaitForChild("AbilityData"))
-- local RarityData = require(Shared:WaitForChild("Data"):WaitForChild("RarityData"))
-- local WeaponData = require(Shared:WaitForChild("Data"):WaitForChild("WeaponData"))
local EventNames = require(Shared:WaitForChild("Network"):WaitForChild("EventNames"))
local ClientNetwork = require(script.Parent.Parent:WaitForChild("Network"))

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- Style constants
-- ============================================================================

local COLORS = {
	bg = Color3.fromRGB(10, 10, 20),
	bgLight = Color3.fromRGB(20, 20, 35),
	cyan = Color3.fromRGB(0, 255, 255),
	healthGreen = Color3.fromRGB(0, 230, 100),
	healthYellow = Color3.fromRGB(230, 200, 0),
	healthRed = Color3.fromRGB(230, 40, 40),
	white = Color3.fromRGB(255, 255, 255),
	dimText = Color3.fromRGB(120, 120, 140),
	slotEmpty = Color3.fromRGB(40, 40, 60),
	reloading = Color3.fromRGB(255, 80, 80),
	cooldownBg = Color3.fromRGB(0, 0, 0),
	purple = Color3.fromRGB(160, 50, 255),
	purpleBright = Color3.fromRGB(200, 100, 255),
	purpleDim = Color3.fromRGB(80, 20, 140),
	magenta = Color3.fromRGB(220, 60, 255),
}

local FONT = Enum.Font.GothamBold
local FONT_REGULAR = Enum.Font.Gotham
local CORNER_RADIUS = UDim.new(0, 4)
local SLOT_CORNER_RADIUS = UDim.new(0, 6)
local BG_TRANSPARENCY = 0.3

-- Keybind order for the 4 ability slots
local SLOT_KEYBINDS = { "Q", "E", "F", "Z" }

-- ============================================================================
-- Module table
-- ============================================================================

local HUD = {}

-- Capture the UI folder reference for use in button click handlers
local uiFolder = script.Parent

-- References to UI elements we need to update after creation
local refs = {
	screenGui = nil :: ScreenGui?,
	-- Health
	healthFill = nil :: Frame?,
	healthLabel = nil :: TextLabel?,
	healthIcon = nil :: TextLabel?,
	-- Ability slots (arrays indexed 1-4)
	abilityFrames = {} :: { Frame },
	abilityNames = {} :: { TextLabel },
	abilityKeybinds = {} :: { TextLabel },
	abilityCooldownOverlays = {} :: { Frame },
	abilityCooldownTimers = {} :: { TextLabel },
	abilityStrokes = {} :: { UIStroke },
	abilityTypeLabels = {} :: { TextLabel },
	abilityGlows = {} :: { UIStroke },
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

-- Track cooldown data for the timer display
local slotCooldownData: { [number]: { total: number, remaining: number } } = {}

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
-- Health Bar (bottom left) — improved with icon and glow
-- ============================================================================

local function createHealthBar(parent: Frame)
	local container = Instance.new("Frame")
	container.Name = "HealthBar"
	container.Size = UDim2.new(0, 220, 0, 28)
	container.Position = UDim2.new(0, 10, 1, -90)
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = BG_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Parent = parent
	applyCorner(container, UDim.new(0, 6))
	applyStroke(container, COLORS.cyan, 1)

	-- Health icon (left side)
	local icon = Instance.new("TextLabel")
	icon.Name = "HealthIcon"
	icon.Size = UDim2.new(0, 28, 1, 0)
	icon.Position = UDim2.new(0, 0, 0, 0)
	icon.BackgroundColor3 = COLORS.bg
	icon.BackgroundTransparency = 0.2
	icon.Font = FONT
	icon.TextSize = 16
	icon.TextColor3 = COLORS.healthGreen
	icon.Text = "+"
	icon.ZIndex = 3
	icon.Parent = container
	applyCorner(icon, UDim.new(0, 6))
	refs.healthIcon = icon

	-- Fill bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, -30, 1, -4)
	fill.Position = UDim2.new(0, 30, 0, 2)
	fill.BackgroundColor3 = COLORS.healthGreen
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.Parent = container
	applyCorner(fill, UDim.new(0, 4))

	-- Health text overlay
	local label = Instance.new("TextLabel")
	label.Name = "HealthText"
	label.Size = UDim2.new(1, -34, 1, 0)
	label.Position = UDim2.new(0, 32, 0, 0)
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
-- Ability Slots Bar (bottom center) — redesigned with icons, timers, glow
-- ============================================================================

local function createAbilitySlots(parent: Frame)
	local SLOT_WIDTH = 74
	local SLOT_HEIGHT = 80
	local SLOT_GAP = 8
	local TOTAL_WIDTH = SLOT_WIDTH * 4 + SLOT_GAP * 3

	local container = Instance.new("Frame")
	container.Name = "AbilitySlots"
	container.Size = UDim2.new(0, TOTAL_WIDTH, 0, SLOT_HEIGHT)
	container.Position = UDim2.new(0.5, -TOTAL_WIDTH / 2, 1, -40 - 12 - SLOT_HEIGHT)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	for i = 1, 4 do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.Size = UDim2.new(0, SLOT_WIDTH, 0, SLOT_HEIGHT)
		slot.BackgroundColor3 = COLORS.bg
		slot.BackgroundTransparency = BG_TRANSPARENCY
		slot.BorderSizePixel = 0
		slot.LayoutOrder = i
		slot.ClipsDescendants = true
		slot.Parent = container
		applyCorner(slot, SLOT_CORNER_RADIUS)

		-- Rarity border stroke (default dim)
		local stroke = applyStroke(slot, COLORS.slotEmpty, 2)

		-- Outer glow stroke (layered behind, thicker, more transparent)
		local glowFrame = Instance.new("Frame")
		glowFrame.Name = "GlowFrame"
		glowFrame.Size = UDim2.new(1, 4, 1, 4)
		glowFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		glowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		glowFrame.BackgroundTransparency = 1
		glowFrame.BorderSizePixel = 0
		glowFrame.ZIndex = 0
		glowFrame.Parent = slot
		applyCorner(glowFrame, UDim.new(0, 8))
		local glowStroke = applyStroke(glowFrame, COLORS.slotEmpty, 3)
		glowStroke.Transparency = 0.7

		-- Ability name label (centered in upper area)
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "AbilityName"
		nameLabel.Size = UDim2.new(1, -6, 0, 36)
		nameLabel.Position = UDim2.new(0, 3, 0, 6)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = FONT
		nameLabel.TextSize = 11
		nameLabel.TextColor3 = COLORS.white
		nameLabel.TextWrapped = true
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Text = "Empty"
		nameLabel.ZIndex = 2
		nameLabel.Parent = slot

		-- UseType label (below name)
		local typeLabel = Instance.new("TextLabel")
		typeLabel.Name = "TypeLabel"
		typeLabel.Size = UDim2.new(1, -6, 0, 12)
		typeLabel.Position = UDim2.new(0, 3, 0, 42)
		typeLabel.BackgroundTransparency = 1
		typeLabel.Font = FONT_REGULAR
		typeLabel.TextSize = 9
		typeLabel.TextColor3 = COLORS.dimText
		typeLabel.TextTruncate = Enum.TextTruncate.AtEnd
		typeLabel.Text = ""
		typeLabel.ZIndex = 2
		typeLabel.Parent = slot

		-- Keybind badge (bottom-right corner, pill shaped)
		local keybindBg = Instance.new("Frame")
		keybindBg.Name = "KeybindBg"
		keybindBg.Size = UDim2.new(0, 22, 0, 16)
		keybindBg.Position = UDim2.new(1, -25, 1, -19)
		keybindBg.BackgroundColor3 = COLORS.cyan
		keybindBg.BackgroundTransparency = 0.7
		keybindBg.BorderSizePixel = 0
		keybindBg.ZIndex = 4
		keybindBg.Parent = slot
		applyCorner(keybindBg, UDim.new(0, 4))

		local keybindLabel = Instance.new("TextLabel")
		keybindLabel.Name = "Keybind"
		keybindLabel.Size = UDim2.new(1, 0, 1, 0)
		keybindLabel.BackgroundTransparency = 1
		keybindLabel.Font = FONT
		keybindLabel.TextSize = 11
		keybindLabel.TextColor3 = COLORS.white
		keybindLabel.Text = SLOT_KEYBINDS[i]
		keybindLabel.ZIndex = 5
		keybindLabel.Parent = keybindBg

		-- Cooldown overlay (dark overlay that scales from full height -> 0)
		local cooldownOverlay = Instance.new("Frame")
		cooldownOverlay.Name = "CooldownOverlay"
		cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
		cooldownOverlay.Position = UDim2.new(0, 0, 1, 0)
		cooldownOverlay.AnchorPoint = Vector2.new(0, 1)
		cooldownOverlay.BackgroundColor3 = COLORS.cooldownBg
		cooldownOverlay.BackgroundTransparency = 0.35
		cooldownOverlay.BorderSizePixel = 0
		cooldownOverlay.ZIndex = 3
		cooldownOverlay.Parent = slot
		applyCorner(cooldownOverlay, SLOT_CORNER_RADIUS)

		-- Cooldown timer text (centered, shows seconds remaining)
		local cdTimer = Instance.new("TextLabel")
		cdTimer.Name = "CooldownTimer"
		cdTimer.Size = UDim2.new(1, 0, 1, 0)
		cdTimer.BackgroundTransparency = 1
		cdTimer.Font = FONT
		cdTimer.TextSize = 22
		cdTimer.TextColor3 = COLORS.white
		cdTimer.TextTransparency = 0.2
		cdTimer.Text = ""
		cdTimer.Visible = false
		cdTimer.ZIndex = 4
		cdTimer.Parent = slot

		refs.abilityFrames[i] = slot
		refs.abilityNames[i] = nameLabel
		refs.abilityKeybinds[i] = keybindLabel
		refs.abilityCooldownOverlays[i] = cooldownOverlay
		refs.abilityCooldownTimers[i] = cdTimer
		refs.abilityStrokes[i] = stroke
		refs.abilityTypeLabels[i] = typeLabel
		refs.abilityGlows[i] = glowStroke
	end
end

-- ============================================================================
-- Menu Buttons (below ability bar)
-- ============================================================================

local function createMenuButtons(parent: Frame)
	local BTN_WIDTH = 120
	local BTN_HEIGHT = 48
	local BUTTON_GAP = 6
	local BTN_COUNT = 3 -- Play, Pass, Tasks

	local TOTAL_WIDTH = BTN_WIDTH * BTN_COUNT + BUTTON_GAP * (BTN_COUNT - 1)

	local container = Instance.new("Frame")
	container.Name = "MenuButtons"
	container.Size = UDim2.new(0, TOTAL_WIDTH, 0, BTN_HEIGHT)
	container.Position = UDim2.new(0.5, -TOTAL_WIDTH / 2, 1, -56)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, BUTTON_GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	-- ── Play Button (first in row) ──────────────────────────────────────
	local playBtn = Instance.new("TextButton")
	playBtn.Name = "PlayButton"
	playBtn.Size = UDim2.new(0, BTN_WIDTH, 0, BTN_HEIGHT)
	playBtn.BackgroundColor3 = Color3.fromRGB(15, 8, 30)
	playBtn.BackgroundTransparency = 0.15
	playBtn.BorderSizePixel = 0
	playBtn.Text = ""
	playBtn.AutoButtonColor = false
	playBtn.LayoutOrder = 0
	playBtn.Parent = container
	applyCorner(playBtn, UDim.new(0, 8))

	-- Outer glow stroke (purple neon)
	local btnGlow = applyStroke(playBtn, COLORS.purple, 2)
	btnGlow.Transparency = 0.1

	-- Inner glow layer
	local innerGlowFrame = Instance.new("Frame")
	innerGlowFrame.Name = "InnerGlow"
	innerGlowFrame.Size = UDim2.new(1, -4, 1, -4)
	innerGlowFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	innerGlowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	innerGlowFrame.BackgroundTransparency = 1
	innerGlowFrame.BorderSizePixel = 0
	innerGlowFrame.Parent = playBtn
	applyCorner(innerGlowFrame, UDim.new(0, 6))
	local innerStroke = applyStroke(innerGlowFrame, COLORS.purpleBright, 1)
	innerStroke.Transparency = 0.5

	-- Play arrow container
	local arrowContainer = Instance.new("Frame")
	arrowContainer.Name = "ArrowContainer"
	arrowContainer.Size = UDim2.new(0, 34, 0, 34)
	arrowContainer.Position = UDim2.new(0, 10, 0.5, 0)
	arrowContainer.AnchorPoint = Vector2.new(0, 0.5)
	arrowContainer.BackgroundColor3 = COLORS.purpleDim
	arrowContainer.BackgroundTransparency = 0.6
	arrowContainer.BorderSizePixel = 0
	arrowContainer.Parent = playBtn
	applyCorner(arrowContainer, UDim.new(0, 6))
	local arrowGlow = applyStroke(arrowContainer, COLORS.purple, 1.5)
	arrowGlow.Transparency = 0.2

	-- Arrow triangle
	local arrowLabel = Instance.new("TextLabel")
	arrowLabel.Name = "Arrow"
	arrowLabel.Size = UDim2.new(1, 0, 1, 0)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Font = FONT
	arrowLabel.TextSize = 22
	arrowLabel.TextColor3 = COLORS.magenta
	arrowLabel.Text = "\u{25B6}"
	arrowLabel.Parent = arrowContainer

	-- "PLAY" text
	local playText = Instance.new("TextLabel")
	playText.Name = "PlayText"
	playText.Size = UDim2.new(1, -50, 1, 0)
	playText.Position = UDim2.new(0, 48, 0, 0)
	playText.BackgroundTransparency = 1
	playText.Font = FONT
	playText.TextSize = 22
	playText.TextColor3 = COLORS.white
	playText.TextXAlignment = Enum.TextXAlignment.Left
	playText.Text = "PLAY"
	playText.Parent = playBtn

	-- Play button hover
	playBtn.MouseEnter:Connect(function()
		playBtn.BackgroundTransparency = 0.05
		btnGlow.Color = COLORS.magenta
		btnGlow.Thickness = 3
		arrowGlow.Color = COLORS.magenta
		arrowLabel.TextColor3 = COLORS.purpleBright
		playText.TextColor3 = COLORS.purpleBright
	end)
	playBtn.MouseLeave:Connect(function()
		playBtn.BackgroundTransparency = 0.15
		btnGlow.Color = COLORS.purple
		btnGlow.Thickness = 2
		arrowGlow.Color = COLORS.purple
		arrowLabel.TextColor3 = COLORS.magenta
		playText.TextColor3 = COLORS.white
	end)

	-- Play button click
	playBtn.MouseButton1Click:Connect(function()
		local flashInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local flash = TweenService:Create(playBtn, flashInfo, {
			BackgroundColor3 = COLORS.purple,
			BackgroundTransparency = 0.3,
		})
		flash:Play()
		flash.Completed:Connect(function()
			TweenService:Create(playBtn, flashInfo, {
				BackgroundColor3 = Color3.fromRGB(15, 8, 30),
				BackgroundTransparency = 0.15,
			}):Play()
		end)
		ClientNetwork.fireServer(EventNames.MatchmakingStatus, "ready")
	end)

	-- Pulsing glow on play button
	task.spawn(function()
		while true do
			local dimInfo = TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local brightInfo = TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

			local dim = TweenService:Create(btnGlow, dimInfo, { Transparency = 0.5 })
			TweenService:Create(arrowGlow, dimInfo, { Transparency = 0.6 }):Play()
			TweenService:Create(arrowLabel, dimInfo, { TextTransparency = 0.3 }):Play()
			dim:Play()
			dim.Completed:Wait()

			local bright = TweenService:Create(btnGlow, brightInfo, { Transparency = 0.1 })
			TweenService:Create(arrowGlow, brightInfo, { Transparency = 0.2 }):Play()
			TweenService:Create(arrowLabel, brightInfo, { TextTransparency = 0 }):Play()
			bright:Play()
			bright.Completed:Wait()
		end
	end)

	-- ── PASS Button (red, SSL rank style icon) ─────────────────────────
	do
		local passBtn = Instance.new("TextButton")
		passBtn.Name = "BattlePass"
		passBtn.Size = UDim2.new(0, BTN_WIDTH, 0, BTN_HEIGHT)
		passBtn.BackgroundColor3 = Color3.fromRGB(30, 8, 8)
		passBtn.BackgroundTransparency = 0.15
		passBtn.BorderSizePixel = 0
		passBtn.Text = ""
		passBtn.AutoButtonColor = false
		passBtn.LayoutOrder = 1
		passBtn.Parent = container
		applyCorner(passBtn, UDim.new(0, 8))

		local passGlow = applyStroke(passBtn, Color3.fromRGB(220, 30, 30), 2)
		passGlow.Transparency = 0.1

		-- Inner glow
		local passInner = Instance.new("Frame")
		passInner.Name = "InnerGlow"
		passInner.Size = UDim2.new(1, -4, 1, -4)
		passInner.Position = UDim2.new(0.5, 0, 0.5, 0)
		passInner.AnchorPoint = Vector2.new(0.5, 0.5)
		passInner.BackgroundTransparency = 1
		passInner.BorderSizePixel = 0
		passInner.Parent = passBtn
		applyCorner(passInner, UDim.new(0, 6))
		local passInnerStroke = applyStroke(passInner, Color3.fromRGB(255, 80, 80), 1)
		passInnerStroke.Transparency = 0.5

		-- SSL rank icon container (diamond/shield shape via text)
		local rankContainer = Instance.new("Frame")
		rankContainer.Name = "RankIcon"
		rankContainer.Size = UDim2.new(0, 34, 0, 34)
		rankContainer.Position = UDim2.new(0, 10, 0.5, 0)
		rankContainer.AnchorPoint = Vector2.new(0, 0.5)
		rankContainer.BackgroundColor3 = Color3.fromRGB(50, 5, 5)
		rankContainer.BackgroundTransparency = 0.5
		rankContainer.BorderSizePixel = 0
		rankContainer.Parent = passBtn
		applyCorner(rankContainer, UDim.new(0, 6))
		applyStroke(rankContainer, Color3.fromRGB(220, 30, 30), 1.5).Transparency = 0.2

		-- SSL-style diamond/star symbol
		local rankLabel = Instance.new("TextLabel")
		rankLabel.Name = "RankSymbol"
		rankLabel.Size = UDim2.new(1, 0, 1, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Font = FONT
		rankLabel.TextSize = 20
		rankLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
		rankLabel.Text = "\u{2666}"
		rankLabel.Parent = rankContainer

		-- Small "S" overlaid on the diamond
		local sLabel = Instance.new("TextLabel")
		sLabel.Name = "SLabel"
		sLabel.Size = UDim2.new(1, 0, 1, 0)
		sLabel.BackgroundTransparency = 1
		sLabel.Font = FONT
		sLabel.TextSize = 11
		sLabel.TextColor3 = Color3.fromRGB(255, 200, 200)
		sLabel.Text = "S"
		sLabel.Parent = rankContainer

		-- "PASS" text
		local passText = Instance.new("TextLabel")
		passText.Name = "PassText"
		passText.Size = UDim2.new(1, -50, 1, 0)
		passText.Position = UDim2.new(0, 48, 0, 0)
		passText.BackgroundTransparency = 1
		passText.Font = FONT
		passText.TextSize = 22
		passText.TextColor3 = Color3.fromRGB(255, 220, 220)
		passText.TextXAlignment = Enum.TextXAlignment.Left
		passText.Text = "PASS"
		passText.Parent = passBtn

		-- Hover
		passBtn.MouseEnter:Connect(function()
			passBtn.BackgroundTransparency = 0.05
			passGlow.Color = Color3.fromRGB(255, 60, 60)
			passGlow.Thickness = 3
			passText.TextColor3 = COLORS.white
			rankLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		end)
		passBtn.MouseLeave:Connect(function()
			passBtn.BackgroundTransparency = 0.15
			passGlow.Color = Color3.fromRGB(220, 30, 30)
			passGlow.Thickness = 2
			passText.TextColor3 = Color3.fromRGB(255, 220, 220)
			rankLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
		end)

		-- Click
		passBtn.MouseButton1Click:Connect(function()
			local flashInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(passBtn, flashInfo, {
				BackgroundColor3 = Color3.fromRGB(200, 30, 30),
				BackgroundTransparency = 0.3,
			}):Play()
			task.delay(0.15, function()
				TweenService:Create(passBtn, flashInfo, {
					BackgroundColor3 = Color3.fromRGB(30, 8, 8),
					BackgroundTransparency = 0.15,
				}):Play()
			end)
			local ok, err = pcall(function()
				local BattlePassUI = require(uiFolder.BattlePass)
				BattlePassUI.toggle()
			end)
			if not ok then
				warn("[HUD] Pass button error:", err)
			end
		end)
	end

	-- ── TASKS Button (cyan, scroll/script icon) ─────────────────────────
	do
		local tasksBtn = Instance.new("TextButton")
		tasksBtn.Name = "Challenges"
		tasksBtn.Size = UDim2.new(0, BTN_WIDTH, 0, BTN_HEIGHT)
		tasksBtn.BackgroundColor3 = Color3.fromRGB(8, 15, 30)
		tasksBtn.BackgroundTransparency = 0.15
		tasksBtn.BorderSizePixel = 0
		tasksBtn.Text = ""
		tasksBtn.AutoButtonColor = false
		tasksBtn.LayoutOrder = 2
		tasksBtn.Parent = container
		applyCorner(tasksBtn, UDim.new(0, 8))

		local tasksGlow = applyStroke(tasksBtn, COLORS.cyan, 2)
		tasksGlow.Transparency = 0.1

		-- Inner glow
		local tasksInner = Instance.new("Frame")
		tasksInner.Name = "InnerGlow"
		tasksInner.Size = UDim2.new(1, -4, 1, -4)
		tasksInner.Position = UDim2.new(0.5, 0, 0.5, 0)
		tasksInner.AnchorPoint = Vector2.new(0.5, 0.5)
		tasksInner.BackgroundTransparency = 1
		tasksInner.BorderSizePixel = 0
		tasksInner.Parent = tasksBtn
		applyCorner(tasksInner, UDim.new(0, 6))
		local tasksInnerStroke = applyStroke(tasksInner, Color3.fromRGB(100, 255, 255), 1)
		tasksInnerStroke.Transparency = 0.5

		-- Script/scroll icon container
		local scrollContainer = Instance.new("Frame")
		scrollContainer.Name = "ScrollIcon"
		scrollContainer.Size = UDim2.new(0, 34, 0, 34)
		scrollContainer.Position = UDim2.new(0, 10, 0.5, 0)
		scrollContainer.AnchorPoint = Vector2.new(0, 0.5)
		scrollContainer.BackgroundColor3 = Color3.fromRGB(5, 20, 40)
		scrollContainer.BackgroundTransparency = 0.5
		scrollContainer.BorderSizePixel = 0
		scrollContainer.Parent = tasksBtn
		applyCorner(scrollContainer, UDim.new(0, 6))
		applyStroke(scrollContainer, COLORS.cyan, 1.5).Transparency = 0.2

		-- Script/scroll symbol (paper with lines)
		local scrollLabel = Instance.new("TextLabel")
		scrollLabel.Name = "ScrollSymbol"
		scrollLabel.Size = UDim2.new(1, 0, 1, 0)
		scrollLabel.BackgroundTransparency = 1
		scrollLabel.Font = FONT
		scrollLabel.TextSize = 20
		scrollLabel.TextColor3 = COLORS.cyan
		scrollLabel.Text = "\u{1F4DC}"
		scrollLabel.Parent = scrollContainer

		-- "TASKS" text
		local tasksText = Instance.new("TextLabel")
		tasksText.Name = "TasksText"
		tasksText.Size = UDim2.new(1, -50, 1, 0)
		tasksText.Position = UDim2.new(0, 48, 0, 0)
		tasksText.BackgroundTransparency = 1
		tasksText.Font = FONT
		tasksText.TextSize = 20
		tasksText.TextColor3 = Color3.fromRGB(220, 255, 255)
		tasksText.TextXAlignment = Enum.TextXAlignment.Left
		tasksText.Text = "TASKS"
		tasksText.Parent = tasksBtn

		-- Hover
		tasksBtn.MouseEnter:Connect(function()
			tasksBtn.BackgroundTransparency = 0.05
			tasksGlow.Color = Color3.fromRGB(100, 255, 255)
			tasksGlow.Thickness = 3
			tasksText.TextColor3 = COLORS.white
			scrollLabel.TextColor3 = Color3.fromRGB(150, 255, 255)
		end)
		tasksBtn.MouseLeave:Connect(function()
			tasksBtn.BackgroundTransparency = 0.15
			tasksGlow.Color = COLORS.cyan
			tasksGlow.Thickness = 2
			tasksText.TextColor3 = Color3.fromRGB(220, 255, 255)
			scrollLabel.TextColor3 = COLORS.cyan
		end)

		-- Click
		tasksBtn.MouseButton1Click:Connect(function()
			local flashInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(tasksBtn, flashInfo, {
				BackgroundColor3 = COLORS.cyan,
				BackgroundTransparency = 0.3,
			}):Play()
			task.delay(0.15, function()
				TweenService:Create(tasksBtn, flashInfo, {
					BackgroundColor3 = Color3.fromRGB(8, 15, 30),
					BackgroundTransparency = 0.15,
				}):Play()
			end)
			local ok, err = pcall(function()
				local ChallengesUI = require(uiFolder.Challenges)
				ChallengesUI.toggle()
			end)
			if not ok then
				warn("[HUD] Tasks button error:", err)
			end
		end)
	end
end

-- ============================================================================
-- Settings Cogwheel (top right, Rivals-style)
-- ============================================================================

local function createSettingsButton(parent: Frame)
	local SIZE = 40

	local btn = Instance.new("ImageButton")
	btn.Name = "SettingsGear"
	btn.Size = UDim2.new(0, SIZE, 0, SIZE)
	btn.Position = UDim2.new(1, -SIZE - 12, 0, 12)
	btn.BackgroundColor3 = COLORS.bg
	btn.BackgroundTransparency = 0.4
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Image = "rbxassetid://6031280882"
	btn.ImageColor3 = Color3.fromRGB(200, 200, 210)
	btn.ScaleType = Enum.ScaleType.Fit
	btn.Parent = parent
	applyCorner(btn, UDim.new(0, 8))

	-- Hover
	btn.MouseEnter:Connect(function()
		btn.ImageColor3 = COLORS.white
		btn.BackgroundTransparency = 0.2
	end)
	btn.MouseLeave:Connect(function()
		btn.ImageColor3 = Color3.fromRGB(200, 200, 210)
		btn.BackgroundTransparency = 0.4
	end)

	-- Click
	btn.MouseButton1Click:Connect(function()
		local ok, err = pcall(function()
			local SettingsUI = require(uiFolder.Settings)
			SettingsUI.toggle()
		end)
		if not ok then
			warn("[HUD] Settings button error:", err)
		end
	end)
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
	container.Visible = false
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
	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end

	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	HUD.updateHealth(humanoid.Health, humanoid.MaxHealth)

	healthConnection = humanoid.HealthChanged:Connect(function(newHealth: number)
		HUD.updateHealth(newHealth, humanoid.MaxHealth)
	end)
end

-- ============================================================================
-- Cooldown tick (updates timer text every frame)
-- ============================================================================

local function onHeartbeat(dt: number)
	for i = 1, 4 do
		local cdData = slotCooldownData[i]
		local cdTimer = refs.abilityCooldownTimers[i]
		local cdOverlay = refs.abilityCooldownOverlays[i]

		if not cdData or not cdTimer then
			continue
		end

		if cdData.remaining > 0 then
			cdData.remaining = math.max(0, cdData.remaining - dt)

			-- Update timer text
			cdTimer.Visible = true
			if cdData.remaining >= 1 then
				cdTimer.Text = string.format("%.0f", math.ceil(cdData.remaining))
			else
				cdTimer.Text = string.format("%.1f", cdData.remaining)
			end

			-- Update overlay height
			if cdOverlay and cdData.total > 0 then
				local frac = math.clamp(cdData.remaining / cdData.total, 0, 1)
				cdOverlay.Size = UDim2.new(1, 0, frac, 0)
			end
		else
			cdTimer.Visible = false
			cdTimer.Text = ""
			if cdOverlay then
				cdOverlay.Size = UDim2.new(1, 0, 0, 0)
			end
		end
	end
end

-- ============================================================================
-- Public API
-- ============================================================================

function HUD.init()
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
	-- DISABLED: Weapons & abilities removed from game (files kept in repo)
	-- createAbilitySlots(mainFrame)
	createMenuButtons(mainFrame)
	createSettingsButton(mainFrame)
	-- createWeaponInfo(mainFrame)
	createKillFeed(mainFrame)
	-- createOverloadMeter(mainFrame)

	-- Connect to character health
	task.spawn(connectToCharacterHealth)
	LocalPlayer.CharacterAdded:Connect(function()
		task.spawn(connectToCharacterHealth)
	end)

	-- DISABLED: Weapons & abilities removed from game (files kept in repo)
	-- RunService.Heartbeat:Connect(onHeartbeat)

	-- Listen for network events
	ClientNetwork.onServerEvent(EventNames.KillOccurred, function(killerName: string, victimName: string)
		HUD.addKillFeedEntry(killerName, victimName)
	end)

	-- DISABLED: Weapons & abilities removed from game (files kept in repo)
	-- ClientNetwork.onServerEvent(EventNames.OverloadUpdate, function(tier: number)
	-- 	HUD.updateOverloadTier(tier)
	-- end)

	-- ClientNetwork.onServerEvent(EventNames.AbilitySlotUpdate, function(slots)
	-- 	HUD.updateAbilitySlots(slots)
	-- end)

	-- ClientNetwork.onServerEvent(EventNames.WeaponEquip, function(weaponState)
	-- 	local def = WeaponData[weaponState.weaponId]
	-- 	local weaponName = if def then def.name else weaponState.weaponId
	-- 	local maxAmmo = if def then def.magazineSize else 0
	-- 	HUD.updateWeaponInfo(weaponName, weaponState.currentAmmo, maxAmmo, weaponState.isReloading)
	-- end)
end

function HUD.updateHealth(current: number, max: number)
	local fraction = if max > 0 then math.clamp(current / max, 0, 1) else 0
	local fill = refs.healthFill
	local label = refs.healthLabel
	local icon = refs.healthIcon
	local color = getHealthColor(fraction)

	if fill then
		fill.Size = UDim2.new(fraction, 0, 1, -4)
		fill.BackgroundColor3 = color
	end

	if label then
		label.Text = string.format("%d/%d", math.ceil(current), math.ceil(max))
	end

	if icon then
		icon.TextColor3 = color
	end
end

function HUD.updateAbilitySlots(slots: { any })
	for i = 1, 4 do
		local slotData = slots[i]
		local nameLabel = refs.abilityNames[i]
		local keybindLabel = refs.abilityKeybinds[i]
		local cooldownOverlay = refs.abilityCooldownOverlays[i]
		local cdTimer = refs.abilityCooldownTimers[i]
		local stroke = refs.abilityStrokes[i]
		local frame = refs.abilityFrames[i]
		local typeLabel = refs.abilityTypeLabels[i]
		local glowStroke = refs.abilityGlows[i]

		if not nameLabel then
			continue
		end

		if slotData == nil then
			-- Empty slot
			nameLabel.Text = "Empty"
			nameLabel.TextColor3 = COLORS.dimText
			if keybindLabel then
				keybindLabel.Text = SLOT_KEYBINDS[i]
			end
			if typeLabel then
				typeLabel.Text = ""
			end
			stroke.Color = COLORS.slotEmpty
			if glowStroke then
				glowStroke.Color = COLORS.slotEmpty
				glowStroke.Transparency = 0.9
			end
			if cooldownOverlay then
				cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
			end
			if cdTimer then
				cdTimer.Visible = false
			end
			if frame then
				frame.BackgroundTransparency = 0.5
			end
			slotCooldownData[i] = nil
		else
			-- Populated slot
			local abilityDef = AbilityData[slotData.abilityId]
			local abilityName = if abilityDef then abilityDef.name else slotData.abilityId
			local rarity = if abilityDef then abilityDef.rarity else "Common"
			local rarityInfo = RarityData[rarity]
			local rarityColor = if rarityInfo then rarityInfo.color else COLORS.cyan
			local cooldown = if abilityDef then abilityDef.cooldown else 0
			local useType = if abilityDef then abilityDef.useType else ""

			-- Ability name
			nameLabel.Text = abilityName
			nameLabel.TextColor3 = if slotData.isLocked then COLORS.dimText else COLORS.white

			-- UseType label
			if typeLabel then
				typeLabel.Text = string.upper(useType)
				typeLabel.TextColor3 = if slotData.isLocked then COLORS.dimText else Color3.new(
					rarityColor.R * 0.6 + 0.4 * COLORS.dimText.R,
					rarityColor.G * 0.6 + 0.4 * COLORS.dimText.G,
					rarityColor.B * 0.6 + 0.4 * COLORS.dimText.B
				)
			end

			-- Rarity border color
			stroke.Color = if slotData.isLocked then COLORS.dimText else rarityColor

			-- Glow
			if glowStroke then
				glowStroke.Color = rarityColor
				if slotData.isLocked then
					glowStroke.Transparency = 0.9
				elseif rarity == "Mythic" then
					glowStroke.Transparency = 0.3
				elseif rarity == "Legendary" then
					glowStroke.Transparency = 0.45
				elseif rarity == "Epic" then
					glowStroke.Transparency = 0.55
				else
					glowStroke.Transparency = 0.7
				end
			end

			-- Keybind text
			if keybindLabel and abilityDef then
				keybindLabel.Text = abilityDef.button
			end

			-- Background
			if frame then
				frame.BackgroundTransparency = if slotData.isLocked then 0.5 else BG_TRANSPARENCY
			end

			-- Cooldown tracking
			if cooldown > 0 and slotData.cooldownRemaining and slotData.cooldownRemaining > 0 then
				slotCooldownData[i] = {
					total = cooldown,
					remaining = slotData.cooldownRemaining,
				}
			else
				slotCooldownData[i] = { total = cooldown, remaining = 0 }
				if cdTimer then
					cdTimer.Visible = false
				end
				if cooldownOverlay then
					cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
				end
			end
		end
	end
end

function HUD.updateWeaponInfo(weaponName: string, currentAmmo: number, maxAmmo: number, isReloading: boolean)
	if refs.weaponNameLabel then
		refs.weaponNameLabel.Text = weaponName
	end

	if refs.ammoLabel then
		if maxAmmo > 0 then
			refs.ammoLabel.Text = string.format("%d / %d", currentAmmo, maxAmmo)
		else
			refs.ammoLabel.Text = ""
		end
	end

	if refs.reloadingLabel then
		refs.reloadingLabel.Visible = isReloading
		refs.reloadingLabel.Text = "RELOADING"
	end
end

function HUD.addKillFeedEntry(killerName: string, victimName: string)
	local container = refs.killFeedContainer
	if not container then
		return
	end

	-- Enforce max 5 visible entries
	local children = {}
	for _, child in container:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(children, child)
		end
	end
	if #children >= 5 then
		table.sort(children, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		children[1]:Destroy()
	end

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
	entry.LayoutOrder = tick()
	entry.Parent = container
	applyCorner(entry)

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

	if label then
		label.Text = "OVERLOAD " .. tier
	end

	local innerHeight = 120 - 4
	local fillFraction = math.clamp(tier / 3, 0, 1)
	if fill then
		local targetHeight = math.floor(innerHeight * fillFraction)
		fill.Size = UDim2.new(1, -4, 0, targetHeight)
	end

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

--[[
	StealChoice — Client-side modal UI for the memory shard steal system.

	When the server sends StealChoiceRequest, this module shows a centered
	modal with three options:
	  1. Steal Ability — pick one of the victim's abilities to take.
	  2. Upgrade Ability — pick one of your own abilities to level up.
	  3. Upgrade Weapon — upgrade your current weapon.

	A 10-second countdown auto-dismisses the modal if no choice is made.

	Visual style matches the cyberpunk HUD: dark backgrounds, neon cyan
	accents, GothamBold font, UICorner 4px, UIStroke borders.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RarityData = require(Shared:WaitForChild("Data"):WaitForChild("RarityData"))
local EventNames = require(Shared:WaitForChild("Network"):WaitForChild("EventNames"))
local ClientNetwork = require(script.Parent.Parent:WaitForChild("Network"))

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------------
-- Style constants (matching HUD cyberpunk theme)
---------------------------------------------------------------------------

local COLORS = {
	bg = Color3.fromRGB(10, 10, 20),
	bgLight = Color3.fromRGB(20, 20, 40),
	cyan = Color3.fromRGB(0, 255, 255),
	white = Color3.fromRGB(255, 255, 255),
	dimText = Color3.fromRGB(120, 120, 140),
	red = Color3.fromRGB(255, 60, 60),
	green = Color3.fromRGB(0, 230, 100),
	yellow = Color3.fromRGB(255, 200, 0),
	buttonHover = Color3.fromRGB(30, 30, 60),
}

local FONT = Enum.Font.GothamBold
local CORNER_RADIUS = UDim.new(0, 4)
local BG_TRANSPARENCY = 0.3

local CHOICE_TIMEOUT = 10 -- seconds

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local StealChoice = {}

-- UI references
local screenGui: ScreenGui? = nil
local modalFrame: Frame? = nil
local timerLabel: TextLabel? = nil
local contentFrame: Frame? = nil

-- State
local isVisible = false
local countdownThread: thread? = nil
local currentData: any = nil -- the payload from StealChoiceRequest

---------------------------------------------------------------------------
-- Helpers: create styled UI elements
---------------------------------------------------------------------------

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

--- Create a styled text button.
local function createButton(
	parent: GuiObject,
	text: string,
	size: UDim2,
	position: UDim2,
	layoutOrder: number?,
	bgColor: Color3?
): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = size
	btn.Position = position
	btn.BackgroundColor3 = bgColor or COLORS.bgLight
	btn.BackgroundTransparency = BG_TRANSPARENCY
	btn.BorderSizePixel = 0
	btn.Font = FONT
	btn.TextSize = 14
	btn.TextColor3 = COLORS.cyan
	btn.Text = text
	btn.AutoButtonColor = false
	btn.LayoutOrder = layoutOrder or 0
	btn.Parent = parent
	applyCorner(btn)
	applyStroke(btn, COLORS.cyan, 1)

	-- Hover feedback
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = COLORS.buttonHover
		btn.BackgroundTransparency = 0.15
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = bgColor or COLORS.bgLight
		btn.BackgroundTransparency = BG_TRANSPARENCY
	end)

	return btn
end

--- Get the rarity color for an ability entry.
local function getRarityColor(rarity: string): Color3
	local info = RarityData[rarity]
	return if info then info.color else COLORS.dimText
end

---------------------------------------------------------------------------
-- Build the base modal (created once in init)
---------------------------------------------------------------------------

local function buildModal()
	-- ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StealChoiceUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10 -- above HUD
	screenGui.IgnoreGuiInset = false
	screenGui.Enabled = false
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Semi-transparent backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 1
	backdrop.Parent = screenGui

	-- Main modal frame (centered)
	modalFrame = Instance.new("Frame")
	modalFrame.Name = "ModalFrame"
	modalFrame.Size = UDim2.new(0, 520, 0, 420)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = COLORS.bg
	modalFrame.BackgroundTransparency = 0.1
	modalFrame.BorderSizePixel = 0
	modalFrame.ZIndex = 2
	modalFrame.Parent = screenGui
	applyCorner(modalFrame, UDim.new(0, 8))
	applyStroke(modalFrame, COLORS.cyan, 2)

	-- Title label
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 32)
	title.Position = UDim2.new(0, 10, 0, 10)
	title.BackgroundTransparency = 1
	title.Font = FONT
	title.TextSize = 22
	title.TextColor3 = COLORS.cyan
	title.Text = "MEMORY SHARD"
	title.ZIndex = 3
	title.Parent = modalFrame

	-- Timer label (top right)
	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.Size = UDim2.new(0, 60, 0, 24)
	timerLabel.Position = UDim2.new(1, -70, 0, 12)
	timerLabel.BackgroundColor3 = COLORS.bg
	timerLabel.BackgroundTransparency = 0.4
	timerLabel.Font = FONT
	timerLabel.TextSize = 16
	timerLabel.TextColor3 = COLORS.red
	timerLabel.Text = "10"
	timerLabel.ZIndex = 3
	timerLabel.Parent = modalFrame
	applyCorner(timerLabel)

	-- Content area (everything below the title, rebuilt each time)
	contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, -20, 1, -52)
	contentFrame.Position = UDim2.new(0, 10, 0, 46)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.ZIndex = 3
	contentFrame.ClipsDescendants = true
	contentFrame.Parent = modalFrame
end

---------------------------------------------------------------------------
-- Clear dynamic content
---------------------------------------------------------------------------

local function clearContent()
	if contentFrame then
		for _, child in contentFrame:GetChildren() do
			child:Destroy()
		end
	end
end

---------------------------------------------------------------------------
-- Send choice to server and dismiss
---------------------------------------------------------------------------

local function sendChoice(data: any)
	if not isVisible then
		return
	end
	ClientNetwork.fireServer(EventNames.StealChoiceResponse, data)
	StealChoice.hide()
end

---------------------------------------------------------------------------
-- Sub-views
---------------------------------------------------------------------------

--- Show the main three-option menu.
local function showMainMenu()
	clearContent()
	if not contentFrame or not currentData then
		return
	end

	-- Victim info line
	local victimLabel = Instance.new("TextLabel")
	victimLabel.Size = UDim2.new(1, 0, 0, 20)
	victimLabel.Position = UDim2.new(0, 0, 0, 0)
	victimLabel.BackgroundTransparency = 1
	victimLabel.Font = FONT
	victimLabel.TextSize = 14
	victimLabel.TextColor3 = COLORS.dimText
	victimLabel.TextXAlignment = Enum.TextXAlignment.Left
	victimLabel.Text = "From: " .. (currentData.victimName or "Unknown")
	victimLabel.ZIndex = 4
	victimLabel.Parent = contentFrame

	-- Three main choice buttons
	local btnY = 30
	local btnHeight = 50
	local btnGap = 8

	local stealBtn = createButton(
		contentFrame,
		"STEAL ABILITY",
		UDim2.new(1, 0, 0, btnHeight),
		UDim2.new(0, 0, 0, btnY)
	)
	stealBtn.ZIndex = 4

	-- Sub-text for steal button
	local stealSub = Instance.new("TextLabel")
	stealSub.Size = UDim2.new(1, -10, 0, 14)
	stealSub.Position = UDim2.new(0, 5, 1, -18)
	stealSub.BackgroundTransparency = 1
	stealSub.Font = Enum.Font.Gotham
	stealSub.TextSize = 11
	stealSub.TextColor3 = COLORS.dimText
	stealSub.Text = "Take one of the victim's abilities (rarity-based chance)"
	stealSub.ZIndex = 5
	stealSub.Parent = stealBtn

	btnY += btnHeight + btnGap

	local upgradeAbilityBtn = createButton(
		contentFrame,
		"UPGRADE ABILITY",
		UDim2.new(1, 0, 0, btnHeight),
		UDim2.new(0, 0, 0, btnY)
	)
	upgradeAbilityBtn.ZIndex = 4

	local upgAbSub = Instance.new("TextLabel")
	upgAbSub.Size = UDim2.new(1, -10, 0, 14)
	upgAbSub.Position = UDim2.new(0, 5, 1, -18)
	upgAbSub.BackgroundTransparency = 1
	upgAbSub.Font = Enum.Font.Gotham
	upgAbSub.TextSize = 11
	upgAbSub.TextColor3 = COLORS.dimText
	upgAbSub.Text = "Level up one of your current abilities"
	upgAbSub.ZIndex = 5
	upgAbSub.Parent = upgradeAbilityBtn

	btnY += btnHeight + btnGap

	local upgradeWeaponBtn = createButton(
		contentFrame,
		"UPGRADE WEAPON",
		UDim2.new(1, 0, 0, btnHeight),
		UDim2.new(0, 0, 0, btnY)
	)
	upgradeWeaponBtn.ZIndex = 4

	local upgWpSub = Instance.new("TextLabel")
	upgWpSub.Size = UDim2.new(1, -10, 0, 14)
	upgWpSub.Position = UDim2.new(0, 5, 1, -18)
	upgWpSub.BackgroundTransparency = 1
	upgWpSub.Font = Enum.Font.Gotham
	upgWpSub.TextSize = 11
	upgWpSub.TextColor3 = COLORS.dimText
	upgWpSub.Text = if currentData.playerWeapon
		then "Upgrade " .. currentData.playerWeapon.weaponId .. " (Lv " .. currentData.playerWeapon.upgradeLevel .. ")"
		else "Upgrade your weapon"
	upgWpSub.ZIndex = 5
	upgWpSub.Parent = upgradeWeaponBtn

	-- Button actions
	stealBtn.MouseButton1Click:Connect(function()
		showStealAbilityList()
	end)

	upgradeAbilityBtn.MouseButton1Click:Connect(function()
		showUpgradeAbilityList()
	end)

	upgradeWeaponBtn.MouseButton1Click:Connect(function()
		sendChoice({ choice = "UpgradeWeapon" })
	end)
end

--- Show the list of victim abilities to steal.
local function showStealAbilityList()
	clearContent()
	if not contentFrame or not currentData then
		return
	end

	-- Back button
	local backBtn = createButton(
		contentFrame,
		"< BACK",
		UDim2.new(0, 80, 0, 28),
		UDim2.new(0, 0, 0, 0)
	)
	backBtn.TextSize = 12
	backBtn.ZIndex = 4
	backBtn.MouseButton1Click:Connect(showMainMenu)

	-- Header
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -90, 0, 28)
	header.Position = UDim2.new(0, 90, 0, 0)
	header.BackgroundTransparency = 1
	header.Font = FONT
	header.TextSize = 16
	header.TextColor3 = COLORS.cyan
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = "SELECT ABILITY TO STEAL"
	header.ZIndex = 4
	header.Parent = contentFrame

	-- Scrolling frame for ability list
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "AbilityList"
	scrollFrame.Size = UDim2.new(1, 0, 1, -36)
	scrollFrame.Position = UDim2.new(0, 0, 0, 34)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLORS.cyan
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0) -- auto-sized by layout
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.ZIndex = 4
	scrollFrame.Parent = contentFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scrollFrame

	local playerSlotCount = if currentData.playerAbilities then #currentData.playerAbilities else 0
	local needsReplace = playerSlotCount >= 5 -- OverloadData.maxSlots

	for i, ability in currentData.victimAbilities do
		local rarityColor = getRarityColor(ability.rarity)
		local stealChance = 100
		local rarityInfo = RarityData[ability.rarity]
		if rarityInfo then
			stealChance = math.floor(rarityInfo.stealChance * 100)
		end

		local entryBtn = createButton(
			scrollFrame,
			"",
			UDim2.new(1, -8, 0, 52),
			UDim2.new(0, 0, 0, 0),
			i
		)
		entryBtn.ZIndex = 5

		-- Ability name + rarity
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.6, 0, 0, 20)
		nameLabel.Position = UDim2.new(0, 8, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = FONT
		nameLabel.TextSize = 14
		nameLabel.TextColor3 = rarityColor
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = ability.name .. "  [" .. ability.rarity .. "]"
		nameLabel.ZIndex = 6
		nameLabel.Parent = entryBtn

		-- Stats line
		local statsLabel = Instance.new("TextLabel")
		statsLabel.Size = UDim2.new(1, -16, 0, 14)
		statsLabel.Position = UDim2.new(0, 8, 0, 26)
		statsLabel.BackgroundTransparency = 1
		statsLabel.Font = Enum.Font.Gotham
		statsLabel.TextSize = 11
		statsLabel.TextColor3 = COLORS.dimText
		statsLabel.TextXAlignment = Enum.TextXAlignment.Left
		statsLabel.Text = "DMG: " .. ability.damage .. "  CD: " .. ability.cooldown .. "s  Lv" .. ability.upgradeLevel
		statsLabel.ZIndex = 6
		statsLabel.Parent = entryBtn

		-- Steal chance badge
		local chanceBadge = Instance.new("TextLabel")
		chanceBadge.Size = UDim2.new(0, 60, 0, 20)
		chanceBadge.Position = UDim2.new(1, -68, 0, 4)
		chanceBadge.BackgroundColor3 = COLORS.bg
		chanceBadge.BackgroundTransparency = 0.4
		chanceBadge.Font = FONT
		chanceBadge.TextSize = 12
		chanceBadge.TextColor3 = if stealChance >= 70 then COLORS.green
			elseif stealChance >= 25 then COLORS.yellow
			else COLORS.red
		chanceBadge.Text = stealChance .. "%"
		chanceBadge.ZIndex = 6
		chanceBadge.Parent = entryBtn
		applyCorner(chanceBadge)

		-- Click handler
		local abilityId = ability.abilityId
		entryBtn.MouseButton1Click:Connect(function()
			if needsReplace then
				-- Need to pick a slot to replace
				showReplaceSlotList(abilityId)
			else
				sendChoice({ choice = "StealAbility", abilityId = abilityId })
			end
		end)
	end
end

--- Show the player's own abilities to pick one to replace (when slots are full).
function showReplaceSlotList(stealAbilityId: string)
	clearContent()
	if not contentFrame or not currentData then
		return
	end

	-- Back button
	local backBtn = createButton(
		contentFrame,
		"< BACK",
		UDim2.new(0, 80, 0, 28),
		UDim2.new(0, 0, 0, 0)
	)
	backBtn.TextSize = 12
	backBtn.ZIndex = 4
	backBtn.MouseButton1Click:Connect(showStealAbilityList)

	-- Header
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -90, 0, 28)
	header.Position = UDim2.new(0, 90, 0, 0)
	header.BackgroundTransparency = 1
	header.Font = FONT
	header.TextSize = 16
	header.TextColor3 = COLORS.yellow
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = "SLOTS FULL - REPLACE WHICH?"
	header.ZIndex = 4
	header.Parent = contentFrame

	-- Player ability list
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ReplaceList"
	scrollFrame.Size = UDim2.new(1, 0, 1, -36)
	scrollFrame.Position = UDim2.new(0, 0, 0, 34)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLORS.cyan
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.ZIndex = 4
	scrollFrame.Parent = contentFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scrollFrame

	for i, ability in currentData.playerAbilities do
		local rarityColor = getRarityColor(ability.rarity)

		local entryBtn = createButton(
			scrollFrame,
			"",
			UDim2.new(1, -8, 0, 44),
			UDim2.new(0, 0, 0, 0),
			i
		)
		entryBtn.ZIndex = 5

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -16, 0, 18)
		nameLabel.Position = UDim2.new(0, 8, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = FONT
		nameLabel.TextSize = 13
		nameLabel.TextColor3 = rarityColor
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = ability.name .. "  [" .. ability.rarity .. "]  Lv" .. ability.upgradeLevel
		nameLabel.ZIndex = 6
		nameLabel.Parent = entryBtn

		local statsLabel = Instance.new("TextLabel")
		statsLabel.Size = UDim2.new(1, -16, 0, 14)
		statsLabel.Position = UDim2.new(0, 8, 0, 24)
		statsLabel.BackgroundTransparency = 1
		statsLabel.Font = Enum.Font.Gotham
		statsLabel.TextSize = 11
		statsLabel.TextColor3 = COLORS.dimText
		statsLabel.TextXAlignment = Enum.TextXAlignment.Left
		statsLabel.Text = "DMG: " .. ability.damage .. "  CD: " .. ability.cooldown .. "s"
		statsLabel.ZIndex = 6
		statsLabel.Parent = entryBtn

		local slotIndex = ability.slotIndex
		entryBtn.MouseButton1Click:Connect(function()
			sendChoice({
				choice = "StealAbility",
				abilityId = stealAbilityId,
				replaceSlotIndex = slotIndex,
			})
		end)
	end
end

--- Show the list of player's own abilities to upgrade.
local function showUpgradeAbilityList()
	clearContent()
	if not contentFrame or not currentData then
		return
	end

	-- Back button
	local backBtn = createButton(
		contentFrame,
		"< BACK",
		UDim2.new(0, 80, 0, 28),
		UDim2.new(0, 0, 0, 0)
	)
	backBtn.TextSize = 12
	backBtn.ZIndex = 4
	backBtn.MouseButton1Click:Connect(showMainMenu)

	-- Header
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -90, 0, 28)
	header.Position = UDim2.new(0, 90, 0, 0)
	header.BackgroundTransparency = 1
	header.Font = FONT
	header.TextSize = 16
	header.TextColor3 = COLORS.cyan
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = "SELECT ABILITY TO UPGRADE"
	header.ZIndex = 4
	header.Parent = contentFrame

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "UpgradeList"
	scrollFrame.Size = UDim2.new(1, 0, 1, -36)
	scrollFrame.Position = UDim2.new(0, 0, 0, 34)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLORS.cyan
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.ZIndex = 4
	scrollFrame.Parent = contentFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scrollFrame

	if not currentData.playerAbilities or #currentData.playerAbilities == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.new(1, 0, 0, 40)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Font = FONT
		emptyLabel.TextSize = 14
		emptyLabel.TextColor3 = COLORS.dimText
		emptyLabel.Text = "No abilities to upgrade"
		emptyLabel.ZIndex = 5
		emptyLabel.Parent = scrollFrame
		return
	end

	for i, ability in currentData.playerAbilities do
		local rarityColor = getRarityColor(ability.rarity)

		local entryBtn = createButton(
			scrollFrame,
			"",
			UDim2.new(1, -8, 0, 52),
			UDim2.new(0, 0, 0, 0),
			i
		)
		entryBtn.ZIndex = 5

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.7, 0, 0, 20)
		nameLabel.Position = UDim2.new(0, 8, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = FONT
		nameLabel.TextSize = 14
		nameLabel.TextColor3 = rarityColor
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = ability.name .. "  [" .. ability.rarity .. "]"
		nameLabel.ZIndex = 6
		nameLabel.Parent = entryBtn

		local statsLabel = Instance.new("TextLabel")
		statsLabel.Size = UDim2.new(1, -16, 0, 14)
		statsLabel.Position = UDim2.new(0, 8, 0, 26)
		statsLabel.BackgroundTransparency = 1
		statsLabel.Font = Enum.Font.Gotham
		statsLabel.TextSize = 11
		statsLabel.TextColor3 = COLORS.dimText
		statsLabel.TextXAlignment = Enum.TextXAlignment.Left
		statsLabel.Text = "DMG: " .. ability.damage .. "  CD: " .. ability.cooldown .. "s"
		statsLabel.ZIndex = 6
		statsLabel.Parent = entryBtn

		-- Current level badge
		local levelBadge = Instance.new("TextLabel")
		levelBadge.Size = UDim2.new(0, 80, 0, 20)
		levelBadge.Position = UDim2.new(1, -88, 0, 4)
		levelBadge.BackgroundColor3 = COLORS.bg
		levelBadge.BackgroundTransparency = 0.4
		levelBadge.Font = FONT
		levelBadge.TextSize = 12
		levelBadge.TextColor3 = COLORS.green
		levelBadge.Text = "Lv" .. ability.upgradeLevel .. " -> " .. (ability.upgradeLevel + 1)
		levelBadge.ZIndex = 6
		levelBadge.Parent = entryBtn
		applyCorner(levelBadge)

		local slotIndex = ability.slotIndex
		entryBtn.MouseButton1Click:Connect(function()
			sendChoice({ choice = "UpgradeAbility", slotIndex = slotIndex })
		end)
	end
end

---------------------------------------------------------------------------
-- Countdown timer
---------------------------------------------------------------------------

local function startCountdown()
	-- Cancel any existing countdown
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end

	countdownThread = task.spawn(function()
		local remaining = CHOICE_TIMEOUT
		while remaining > 0 and isVisible do
			if timerLabel then
				timerLabel.Text = tostring(math.ceil(remaining))
				-- Flash red when low
				timerLabel.TextColor3 = if remaining <= 3 then COLORS.red else COLORS.yellow
			end
			task.wait(0.1)
			remaining -= 0.1
		end

		-- Time ran out — auto-dismiss without sending a choice
		if isVisible then
			StealChoice.hide()
		end
	end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--[[
	Show the steal choice modal with the given data.
	@param victimAbilities -- serialised list of the victim's abilities
	@param playerAbilities -- serialised list of the player's abilities
	@param playerWeapon -- the player's weapon state table
]]
function StealChoice.show(data: any)
	if isVisible then
		StealChoice.hide()
	end

	currentData = data
	isVisible = true

	if screenGui then
		screenGui.Enabled = true
	end

	-- Build the main menu view
	showMainMenu()

	-- Start the countdown
	startCountdown()
end

--[[
	Hide and reset the steal choice modal.
]]
function StealChoice.hide()
	isVisible = false
	currentData = nil

	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end

	clearContent()

	if screenGui then
		screenGui.Enabled = false
	end
end

--[[
	Initialise the StealChoice UI module. Creates the base ScreenGui and
	listens for StealChoiceRequest events from the server.
]]
function StealChoice.init()
	-- Build the modal shell (only once)
	buildModal()

	-- Listen for the server's steal choice request
	ClientNetwork.onServerEvent(EventNames.StealChoiceRequest, function(data: any)
		StealChoice.show(data)
	end)

	print("[StealChoice] Initialised")
end

return StealChoice

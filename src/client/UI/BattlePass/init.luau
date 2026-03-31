--[[
	BattlePass — Client-side UI for the Battle Pass progression screen.

	Opened / closed with the N key. Displays a horizontal scrolling tier
	track with per-tier reward cards, an XP progress bar, and claim buttons
	for reached-but-unclaimed tiers.

	Visual style matches the cyberpunk HUD: dark backgrounds, neon cyan
	accents, GothamBold font, UICorner 4px, UIStroke borders.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattlePassData = require(Shared:WaitForChild("Data"):WaitForChild("BattlePassData"))
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
	grey = Color3.fromRGB(60, 60, 80),
	gold = Color3.fromRGB(255, 200, 0),
	green = Color3.fromRGB(0, 230, 100),
	barBg = Color3.fromRGB(30, 30, 50),
}

local FONT = Enum.Font.GothamBold
local FONT_REGULAR = Enum.Font.Gotham
local CORNER_RADIUS = UDim.new(0, 4)
local BG_TRANSPARENCY = 0.1

local CARD_WIDTH = 80
local CARD_HEIGHT = 100
local CARD_GAP = 8

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local BattlePass = {}

---------------------------------------------------------------------------
-- UI references
---------------------------------------------------------------------------

local screenGui: ScreenGui? = nil
local mainFrame: Frame? = nil
local xpBarFill: Frame? = nil
local xpBarLabel: TextLabel? = nil
local tierContainer: ScrollingFrame? = nil
local tierCards: { [number]: Frame } = {}
local claimButtons: { [number]: TextButton } = {}

-- State
local isVisible = false
local currentProgress = {
	currentTier = 0,
	currentXP = 0,
	xpToNext = BattlePassData.xpPerTier,
	claimedTiers = {},
}

-- Pulse tween tracking
local activePulseTween: Tween? = nil
local activePulseStroke: UIStroke? = nil

---------------------------------------------------------------------------
-- Helpers
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

--- Get a short icon/label string for the reward type.
local function getRewardTypeIcon(tierData: any): string
	if tierData.rewardType == "credits" then
		return "CREDITS"
	elseif tierData.category == "WeaponSkins" then
		return "SKIN"
	elseif tierData.category == "KillEffects" then
		return "EFFECT"
	end
	return "ITEM"
end

---------------------------------------------------------------------------
-- Build the UI (called once in init)
---------------------------------------------------------------------------

local function buildUI()
	-- ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BattlePassUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 8
	screenGui.IgnoreGuiInset = false
	screenGui.Enabled = false
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Full-screen backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 1
	backdrop.Parent = screenGui

	-- Main panel (centered, large)
	mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainPanel"
	mainFrame.Size = UDim2.new(0.85, 0, 0.75, 0)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.BackgroundColor3 = COLORS.bg
	mainFrame.BackgroundTransparency = BG_TRANSPARENCY
	mainFrame.BorderSizePixel = 0
	mainFrame.ZIndex = 2
	mainFrame.Parent = screenGui
	applyCorner(mainFrame, UDim.new(0, 8))
	applyStroke(mainFrame, COLORS.cyan, 2)

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -100, 0, 40)
	title.Position = UDim2.new(0, 20, 0, 12)
	title.BackgroundTransparency = 1
	title.Font = FONT
	title.TextSize = 24
	title.TextColor3 = COLORS.cyan
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = string.upper(BattlePassData.seasonName)
	title.ZIndex = 3
	title.Parent = mainFrame

	-- Close button (X) top right
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -48, 0, 12)
	closeBtn.BackgroundColor3 = COLORS.bgLight
	closeBtn.BackgroundTransparency = 0.3
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = FONT
	closeBtn.TextSize = 20
	closeBtn.TextColor3 = COLORS.white
	closeBtn.Text = "X"
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 4
	closeBtn.Parent = mainFrame
	applyCorner(closeBtn)
	applyStroke(closeBtn, COLORS.cyan, 1)

	closeBtn.MouseButton1Click:Connect(function()
		BattlePass.hide()
	end)

	closeBtn.MouseEnter:Connect(function()
		closeBtn.BackgroundColor3 = Color3.fromRGB(80, 20, 20)
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.BackgroundColor3 = COLORS.bgLight
	end)

	-- XP progress bar
	local xpBarContainer = Instance.new("Frame")
	xpBarContainer.Name = "XPBar"
	xpBarContainer.Size = UDim2.new(1, -40, 0, 24)
	xpBarContainer.Position = UDim2.new(0, 20, 0, 60)
	xpBarContainer.BackgroundColor3 = COLORS.barBg
	xpBarContainer.BackgroundTransparency = 0.2
	xpBarContainer.BorderSizePixel = 0
	xpBarContainer.ZIndex = 3
	xpBarContainer.Parent = mainFrame
	applyCorner(xpBarContainer)
	applyStroke(xpBarContainer, COLORS.grey, 1)

	xpBarFill = Instance.new("Frame")
	xpBarFill.Name = "Fill"
	xpBarFill.Size = UDim2.new(0, 0, 1, 0)
	xpBarFill.BackgroundColor3 = COLORS.cyan
	xpBarFill.BackgroundTransparency = 0.15
	xpBarFill.BorderSizePixel = 0
	xpBarFill.ZIndex = 4
	xpBarFill.Parent = xpBarContainer
	applyCorner(xpBarFill)

	xpBarLabel = Instance.new("TextLabel")
	xpBarLabel.Name = "XPText"
	xpBarLabel.Size = UDim2.new(1, 0, 1, 0)
	xpBarLabel.BackgroundTransparency = 1
	xpBarLabel.Font = FONT
	xpBarLabel.TextSize = 13
	xpBarLabel.TextColor3 = COLORS.white
	xpBarLabel.Text = "0 / 100 XP"
	xpBarLabel.ZIndex = 5
	xpBarLabel.Parent = xpBarContainer

	-- Tier track (horizontal scrolling)
	tierContainer = Instance.new("ScrollingFrame")
	tierContainer.Name = "TierTrack"
	tierContainer.Size = UDim2.new(1, -40, 1, -110)
	tierContainer.Position = UDim2.new(0, 20, 0, 96)
	tierContainer.BackgroundTransparency = 1
	tierContainer.BorderSizePixel = 0
	tierContainer.ScrollBarThickness = 6
	tierContainer.ScrollBarImageColor3 = COLORS.cyan
	tierContainer.ScrollingDirection = Enum.ScrollingDirection.X
	tierContainer.AutomaticCanvasSize = Enum.AutomaticSize.X
	tierContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
	tierContainer.ZIndex = 3
	tierContainer.Parent = mainFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = tierContainer

	-- Padding so first/last cards have some breathing room
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = tierContainer

	-- Build a card for each tier
	for _, tierData in BattlePassData.tiers do
		local tierNum = tierData.tier

		local card = Instance.new("Frame")
		card.Name = "Tier" .. tierNum
		card.Size = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT)
		card.BackgroundColor3 = COLORS.bgLight
		card.BackgroundTransparency = 0.2
		card.BorderSizePixel = 0
		card.LayoutOrder = tierNum
		card.ZIndex = 4
		card.Parent = tierContainer
		applyCorner(card)

		-- Border stroke (updated dynamically based on state)
		local stroke = applyStroke(card, COLORS.grey, 1)
		stroke.Name = "BorderStroke"

		-- Tier number
		local tierLabel = Instance.new("TextLabel")
		tierLabel.Name = "TierNum"
		tierLabel.Size = UDim2.new(1, 0, 0, 18)
		tierLabel.Position = UDim2.new(0, 0, 0, 4)
		tierLabel.BackgroundTransparency = 1
		tierLabel.Font = FONT
		tierLabel.TextSize = 12
		tierLabel.TextColor3 = COLORS.dimText
		tierLabel.Text = "TIER " .. tierNum
		tierLabel.ZIndex = 5
		tierLabel.Parent = card

		-- Reward type icon/label
		local typeLabel = Instance.new("TextLabel")
		typeLabel.Name = "TypeLabel"
		typeLabel.Size = UDim2.new(1, -8, 0, 16)
		typeLabel.Position = UDim2.new(0, 4, 0, 24)
		typeLabel.BackgroundTransparency = 1
		typeLabel.Font = FONT
		typeLabel.TextSize = 10
		typeLabel.TextColor3 = COLORS.cyan
		typeLabel.Text = getRewardTypeIcon(tierData)
		typeLabel.ZIndex = 5
		typeLabel.Parent = card

		-- Reward name (wrapped)
		local rewardLabel = Instance.new("TextLabel")
		rewardLabel.Name = "RewardName"
		rewardLabel.Size = UDim2.new(1, -8, 0, 30)
		rewardLabel.Position = UDim2.new(0, 4, 0, 40)
		rewardLabel.BackgroundTransparency = 1
		rewardLabel.Font = FONT_REGULAR
		rewardLabel.TextSize = 11
		rewardLabel.TextColor3 = COLORS.white
		rewardLabel.TextWrapped = true
		rewardLabel.TextTruncate = Enum.TextTruncate.AtEnd
		rewardLabel.Text = tierData.reward
		rewardLabel.ZIndex = 5
		rewardLabel.Parent = card

		-- Checkmark (hidden by default, shown when claimed)
		local checkmark = Instance.new("TextLabel")
		checkmark.Name = "Checkmark"
		checkmark.Size = UDim2.new(0, 20, 0, 20)
		checkmark.Position = UDim2.new(1, -22, 0, 2)
		checkmark.BackgroundTransparency = 1
		checkmark.Font = FONT
		checkmark.TextSize = 16
		checkmark.TextColor3 = COLORS.green
		checkmark.Text = "✓"
		checkmark.Visible = false
		checkmark.ZIndex = 6
		checkmark.Parent = card

		-- CLAIM button (hidden by default)
		local claimBtn = Instance.new("TextButton")
		claimBtn.Name = "ClaimBtn"
		claimBtn.Size = UDim2.new(1, -8, 0, 20)
		claimBtn.Position = UDim2.new(0, 4, 1, -24)
		claimBtn.BackgroundColor3 = COLORS.gold
		claimBtn.BackgroundTransparency = 0.15
		claimBtn.BorderSizePixel = 0
		claimBtn.Font = FONT
		claimBtn.TextSize = 11
		claimBtn.TextColor3 = COLORS.bg
		claimBtn.Text = "CLAIM"
		claimBtn.AutoButtonColor = false
		claimBtn.Visible = false
		claimBtn.ZIndex = 6
		claimBtn.Parent = card
		applyCorner(claimBtn)

		claimBtn.MouseEnter:Connect(function()
			claimBtn.BackgroundTransparency = 0
		end)
		claimBtn.MouseLeave:Connect(function()
			claimBtn.BackgroundTransparency = 0.15
		end)

		-- Click fires claim request to server
		claimBtn.MouseButton1Click:Connect(function()
			ClientNetwork.fireServer(EventNames.BattlePassClaimRequest, tierNum)
		end)

		-- Mini XP bar at bottom (for current tier only, hidden by default)
		local miniBar = Instance.new("Frame")
		miniBar.Name = "MiniXPBar"
		miniBar.Size = UDim2.new(1, -8, 0, 4)
		miniBar.Position = UDim2.new(0, 4, 1, -6)
		miniBar.BackgroundColor3 = COLORS.barBg
		miniBar.BackgroundTransparency = 0.3
		miniBar.BorderSizePixel = 0
		miniBar.Visible = false
		miniBar.ZIndex = 6
		miniBar.Parent = card
		applyCorner(miniBar, UDim.new(0, 2))

		local miniFill = Instance.new("Frame")
		miniFill.Name = "Fill"
		miniFill.Size = UDim2.new(0, 0, 1, 0)
		miniFill.BackgroundColor3 = COLORS.cyan
		miniFill.BackgroundTransparency = 0.1
		miniFill.BorderSizePixel = 0
		miniFill.ZIndex = 7
		miniFill.Parent = miniBar
		applyCorner(miniFill, UDim.new(0, 2))

		tierCards[tierNum] = card
		claimButtons[tierNum] = claimBtn
	end
end

---------------------------------------------------------------------------
-- Update card visuals based on current progress
---------------------------------------------------------------------------

local function stopPulseTween()
	if activePulseTween then
		activePulseTween:Cancel()
		activePulseTween = nil
	end
	if activePulseStroke then
		activePulseStroke.Thickness = 1
		activePulseStroke = nil
	end
end

local function refreshCards()
	stopPulseTween()

	for _, tierData in BattlePassData.tiers do
		local tierNum = tierData.tier
		local card = tierCards[tierNum]
		if not card then
			continue
		end

		local stroke = card:FindFirstChild("BorderStroke") :: UIStroke
		local checkmark = card:FindFirstChild("Checkmark") :: TextLabel
		local claimBtn = claimButtons[tierNum]
		local tierLabel = card:FindFirstChild("TierNum") :: TextLabel
		local rewardLabel = card:FindFirstChild("RewardName") :: TextLabel
		local miniBar = card:FindFirstChild("MiniXPBar") :: Frame
		local typeLabel = card:FindFirstChild("TypeLabel") :: TextLabel

		local isReached = tierNum <= currentProgress.currentTier
		local isClaimed = currentProgress.claimedTiers[tierNum] == true
		local isCurrentTier = tierNum == currentProgress.currentTier + 1

		if isClaimed then
			-- Completed and claimed: cyan border, checkmark
			if stroke then
				stroke.Color = COLORS.cyan
				stroke.Thickness = 2
			end
			if checkmark then
				checkmark.Visible = true
			end
			if claimBtn then
				claimBtn.Visible = false
			end
			if miniBar then
				miniBar.Visible = false
			end
			card.BackgroundTransparency = 0.2
			if tierLabel then
				tierLabel.TextColor3 = COLORS.cyan
			end
			if rewardLabel then
				rewardLabel.TextColor3 = COLORS.white
			end
			if typeLabel then
				typeLabel.TextColor3 = COLORS.cyan
			end
		elseif isReached and not isClaimed then
			-- Reached but unclaimed: gold border, CLAIM button
			if stroke then
				stroke.Color = COLORS.gold
				stroke.Thickness = 2
			end
			if checkmark then
				checkmark.Visible = false
			end
			if claimBtn then
				claimBtn.Visible = true
			end
			if miniBar then
				miniBar.Visible = false
			end
			card.BackgroundTransparency = 0.15
			if tierLabel then
				tierLabel.TextColor3 = COLORS.gold
			end
			if rewardLabel then
				rewardLabel.TextColor3 = COLORS.white
			end
			if typeLabel then
				typeLabel.TextColor3 = COLORS.gold
			end
		elseif isCurrentTier and currentProgress.currentTier < BattlePassData.maxTier then
			-- Current tier being worked on: pulsing border, mini XP bar
			if stroke then
				stroke.Color = COLORS.cyan
				stroke.Thickness = 2

				-- Start a pulsing tween on the stroke thickness
				activePulseStroke = stroke
				local pulseInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
				activePulseTween = TweenService:Create(stroke, pulseInfo, { Thickness = 3 })
				activePulseTween:Play()
			end
			if checkmark then
				checkmark.Visible = false
			end
			if claimBtn then
				claimBtn.Visible = false
			end
			if miniBar then
				miniBar.Visible = true
				local fill = miniBar:FindFirstChild("Fill") :: Frame
				if fill then
					local fraction = if BattlePassData.xpPerTier > 0
						then math.clamp(currentProgress.currentXP / BattlePassData.xpPerTier, 0, 1)
						else 0
					fill.Size = UDim2.new(fraction, 0, 1, 0)
				end
			end
			card.BackgroundTransparency = 0.15
			if tierLabel then
				tierLabel.TextColor3 = COLORS.cyan
			end
			if rewardLabel then
				rewardLabel.TextColor3 = COLORS.white
			end
			if typeLabel then
				typeLabel.TextColor3 = COLORS.cyan
			end
		else
			-- Locked: dimmed, grey border
			if stroke then
				stroke.Color = COLORS.grey
				stroke.Thickness = 1
			end
			if checkmark then
				checkmark.Visible = false
			end
			if claimBtn then
				claimBtn.Visible = false
			end
			if miniBar then
				miniBar.Visible = false
			end
			card.BackgroundTransparency = 0.5
			if tierLabel then
				tierLabel.TextColor3 = COLORS.dimText
			end
			if rewardLabel then
				rewardLabel.TextColor3 = COLORS.dimText
			end
			if typeLabel then
				typeLabel.TextColor3 = COLORS.dimText
			end
		end
	end
end

---------------------------------------------------------------------------
-- Update the top XP bar
---------------------------------------------------------------------------

local function refreshXPBar()
	if not xpBarFill or not xpBarLabel then
		return
	end

	if currentProgress.currentTier >= BattlePassData.maxTier then
		xpBarFill.Size = UDim2.new(1, 0, 1, 0)
		xpBarLabel.Text = "MAX TIER REACHED"
	else
		local fraction = if BattlePassData.xpPerTier > 0
			then math.clamp(currentProgress.currentXP / BattlePassData.xpPerTier, 0, 1)
			else 0
		xpBarFill.Size = UDim2.new(fraction, 0, 1, 0)
		xpBarLabel.Text = string.format(
			"Tier %d  |  %d / %d XP",
			currentProgress.currentTier,
			currentProgress.currentXP,
			BattlePassData.xpPerTier
		)
	end
end

---------------------------------------------------------------------------
-- Show / hide
---------------------------------------------------------------------------

function BattlePass.show()
	if isVisible then
		return
	end
	isVisible = true

	refreshCards()
	refreshXPBar()

	if screenGui then
		screenGui.Enabled = true
	end
end

function BattlePass.hide()
	if not isVisible then
		return
	end
	isVisible = false
	stopPulseTween()

	if screenGui then
		screenGui.Enabled = false
	end
end

function BattlePass.toggle()
	if isVisible then
		BattlePass.hide()
	else
		BattlePass.show()
	end
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function BattlePass.init()
	-- Build the UI shell
	buildUI()

	-- N key toggles the Battle Pass
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.N then
			BattlePass.toggle()
		end
	end)

	-- Listen for progress updates from the server
	ClientNetwork.onServerEvent(EventNames.BattlePassUpdate, function(progressData: any)
		currentProgress.currentTier = progressData.currentTier or 0
		currentProgress.currentXP = progressData.currentXP or 0
		currentProgress.xpToNext = progressData.xpToNext or BattlePassData.xpPerTier
		currentProgress.claimedTiers = progressData.claimedTiers or {}

		if isVisible then
			refreshCards()
			refreshXPBar()
		end
	end)

	-- Listen for reward claimed confirmations
	ClientNetwork.onServerEvent(EventNames.BattlePassRewardClaimed, function(data: any)
		if data and data.tier then
			currentProgress.claimedTiers[data.tier] = true

			if isVisible then
				refreshCards()
			end
		end
	end)

	print("[BattlePass] Initialised")
end

return BattlePass

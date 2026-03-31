--[[
	AbilityFeedback — Shows a cyberpunk-styled activation popup when the player
	uses an ability. Displays the ability name, a category icon/symbol, rarity,
	and cooldown info. Fades in fast, holds briefly, fades out.
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityData = require(Shared:WaitForChild("Data"):WaitForChild("AbilityData"))
local RarityData = require(Shared:WaitForChild("Data"):WaitForChild("RarityData"))

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- Style
-- ============================================================================

local COLORS = {
	bg = Color3.fromRGB(10, 10, 20),
	bgCard = Color3.fromRGB(14, 14, 28),
	cyan = Color3.fromRGB(0, 255, 255),
	white = Color3.fromRGB(255, 255, 255),
	dimText = Color3.fromRGB(120, 120, 140),
}

local FONT = Enum.Font.GothamBold
local FONT_REGULAR = Enum.Font.Gotham
local CORNER_RADIUS = UDim.new(0, 8)

-- How long each phase lasts (seconds)
local FADE_IN = 0.1
local HOLD = 0.9
local FADE_OUT = 0.35

-- Category symbols
local CATEGORY_SYMBOLS: { [string]: string } = {
	Movement = ">>",
	Attack = "X",
	Defense = "(O)",
	Support = "+",
	Control = "~",
	Stealth = "///",
	Trick = "?!",
	Projectile = "-->",
	Beam = "===",
	Summon = "@",
	Ultimate = "***",
	Heavy = "##",
	Area = "{ }",
	Melee = "/X\\",
	Buff = "^",
	AOE = "((*))",
}

local function getSymbolForUseType(useType: string): string
	if CATEGORY_SYMBOLS[useType] then
		return CATEGORY_SYMBOLS[useType]
	end
	for keyword, symbol in CATEGORY_SYMBOLS do
		if string.find(useType, keyword) then
			return symbol
		end
	end
	return "<>"
end

-- ============================================================================
-- Module
-- ============================================================================

local AbilityFeedback = {}

local screenGui: ScreenGui? = nil

-- Track active tweens so we can cancel overlapping popups
local activeTween: Tween? = nil
local activeCleanup: thread? = nil

-- ============================================================================
-- Build the static UI frame (hidden by default)
-- ============================================================================

local refs = {
	outerFrame = nil :: Frame?,
	symbolBg = nil :: Frame?,
	symbolLabel = nil :: TextLabel?,
	nameLabel = nil :: TextLabel?,
	typeLabel = nil :: TextLabel?,
	rarityLabel = nil :: TextLabel?,
	cooldownLabel = nil :: TextLabel?,
	topLine = nil :: Frame?,
	bottomLine = nil :: Frame?,
	stroke = nil :: UIStroke?,
	innerGlow = nil :: UIStroke?,
}

local function buildUI()
	local sg = Instance.new("ScreenGui")
	sg.Name = "AbilityFeedbackGui"
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.IgnoreGuiInset = false
	sg.DisplayOrder = 5
	sg.Parent = LocalPlayer:WaitForChild("PlayerGui")
	screenGui = sg

	-- Container centered on screen, slightly above middle
	local outer = Instance.new("Frame")
	outer.Name = "FeedbackCard"
	outer.Size = UDim2.new(0, 340, 0, 80)
	outer.Position = UDim2.new(0.5, 0, 0.32, 0)
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.BackgroundColor3 = COLORS.bgCard
	outer.BackgroundTransparency = 1
	outer.BorderSizePixel = 0
	outer.Parent = sg
	refs.outerFrame = outer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = CORNER_RADIUS
	corner.Parent = outer

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.cyan
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = outer
	refs.stroke = stroke

	-- Top accent line
	local topLine = Instance.new("Frame")
	topLine.Name = "TopAccent"
	topLine.Size = UDim2.new(0.6, 0, 0, 2)
	topLine.Position = UDim2.new(0.2, 0, 0, 0)
	topLine.BackgroundColor3 = COLORS.cyan
	topLine.BackgroundTransparency = 1
	topLine.BorderSizePixel = 0
	topLine.Parent = outer
	refs.topLine = topLine

	-- Symbol background (left, square with rounded corners)
	local symbolBg = Instance.new("Frame")
	symbolBg.Name = "SymbolBg"
	symbolBg.Size = UDim2.new(0, 60, 0, 60)
	symbolBg.Position = UDim2.new(0, 10, 0.5, 0)
	symbolBg.AnchorPoint = Vector2.new(0, 0.5)
	symbolBg.BackgroundColor3 = COLORS.bg
	symbolBg.BackgroundTransparency = 1
	symbolBg.BorderSizePixel = 0
	symbolBg.Parent = outer
	refs.symbolBg = symbolBg

	local symbolCorner = Instance.new("UICorner")
	symbolCorner.CornerRadius = UDim.new(0, 6)
	symbolCorner.Parent = symbolBg

	local innerGlow = Instance.new("UIStroke")
	innerGlow.Color = COLORS.cyan
	innerGlow.Thickness = 1
	innerGlow.Transparency = 1
	innerGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	innerGlow.Parent = symbolBg
	refs.innerGlow = innerGlow

	-- Symbol text
	local symbolLabel = Instance.new("TextLabel")
	symbolLabel.Name = "Symbol"
	symbolLabel.Size = UDim2.new(1, 0, 1, 0)
	symbolLabel.BackgroundTransparency = 1
	symbolLabel.Font = FONT
	symbolLabel.TextSize = 26
	symbolLabel.TextColor3 = COLORS.cyan
	symbolLabel.TextTransparency = 1
	symbolLabel.Text = ">>"
	symbolLabel.Parent = symbolBg
	refs.symbolLabel = symbolLabel

	-- Ability name (large text, right of symbol)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "AbilityName"
	nameLabel.Size = UDim2.new(1, -86, 0, 28)
	nameLabel.Position = UDim2.new(0, 78, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = FONT
	nameLabel.TextSize = 22
	nameLabel.TextColor3 = COLORS.white
	nameLabel.TextTransparency = 1
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = ""
	nameLabel.Parent = outer
	refs.nameLabel = nameLabel

	-- UseType label (below name, left)
	local typeLabel = Instance.new("TextLabel")
	typeLabel.Name = "UseType"
	typeLabel.Size = UDim2.new(0, 120, 0, 16)
	typeLabel.Position = UDim2.new(0, 78, 0, 40)
	typeLabel.BackgroundTransparency = 1
	typeLabel.Font = FONT_REGULAR
	typeLabel.TextSize = 12
	typeLabel.TextColor3 = COLORS.dimText
	typeLabel.TextTransparency = 1
	typeLabel.TextXAlignment = Enum.TextXAlignment.Left
	typeLabel.Text = ""
	typeLabel.Parent = outer
	refs.typeLabel = typeLabel

	-- Rarity label (below name, right of type)
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "Rarity"
	rarityLabel.Size = UDim2.new(0, 80, 0, 16)
	rarityLabel.Position = UDim2.new(0, 200, 0, 40)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Font = FONT
	rarityLabel.TextSize = 11
	rarityLabel.TextColor3 = COLORS.cyan
	rarityLabel.TextTransparency = 1
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	rarityLabel.Text = ""
	rarityLabel.Parent = outer
	refs.rarityLabel = rarityLabel

	-- Cooldown label (below type row)
	local cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.Name = "Cooldown"
	cooldownLabel.Size = UDim2.new(0, 120, 0, 14)
	cooldownLabel.Position = UDim2.new(0, 78, 0, 56)
	cooldownLabel.BackgroundTransparency = 1
	cooldownLabel.Font = FONT_REGULAR
	cooldownLabel.TextSize = 10
	cooldownLabel.TextColor3 = COLORS.dimText
	cooldownLabel.TextTransparency = 1
	cooldownLabel.TextXAlignment = Enum.TextXAlignment.Left
	cooldownLabel.Text = ""
	cooldownLabel.Parent = outer
	refs.cooldownLabel = cooldownLabel

	-- Bottom accent line
	local bottomLine = Instance.new("Frame")
	bottomLine.Name = "BottomAccent"
	bottomLine.Size = UDim2.new(0.8, 0, 0, 2)
	bottomLine.Position = UDim2.new(0.1, 0, 1, -1)
	bottomLine.BackgroundColor3 = COLORS.cyan
	bottomLine.BackgroundTransparency = 1
	bottomLine.BorderSizePixel = 0
	bottomLine.Parent = outer
	refs.bottomLine = bottomLine
end

-- ============================================================================
-- Animation
-- ============================================================================

local function cancelActive()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	if activeCleanup then
		task.cancel(activeCleanup)
		activeCleanup = nil
	end
end

local function setAllTransparency(t: number)
	local outer = refs.outerFrame
	if not outer then return end

	outer.BackgroundTransparency = 0.12 + (0.88 * t)
	refs.stroke.Transparency = t
	refs.symbolLabel.TextTransparency = t
	refs.symbolBg.BackgroundTransparency = 0.3 + (0.7 * t)
	refs.innerGlow.Transparency = 0.3 + (0.7 * t)
	refs.nameLabel.TextTransparency = t
	refs.typeLabel.TextTransparency = math.min(1, t + 0.15)
	refs.rarityLabel.TextTransparency = math.min(1, t + 0.1)
	refs.cooldownLabel.TextTransparency = math.min(1, t + 0.25)
	refs.topLine.BackgroundTransparency = t
	refs.bottomLine.BackgroundTransparency = t
end

-- ============================================================================
-- Public API
-- ============================================================================

function AbilityFeedback.show(abilityId: string)
	local def = AbilityData[abilityId]
	if not def then
		return
	end

	local rarityInfo = RarityData[def.rarity]
	local rarityColor = if rarityInfo then rarityInfo.color else COLORS.cyan
	local symbol = getSymbolForUseType(def.useType)

	cancelActive()

	-- Update content
	refs.nameLabel.Text = string.upper(def.name)
	refs.typeLabel.Text = string.upper(def.useType)
	refs.rarityLabel.Text = string.upper(def.rarity)
	refs.symbolLabel.Text = symbol
	refs.cooldownLabel.Text = if def.cooldown > 0 then ("CD: " .. def.cooldown .. "s") else "NO COOLDOWN"

	-- Apply rarity color to accents
	refs.stroke.Color = rarityColor
	refs.symbolLabel.TextColor3 = rarityColor
	refs.innerGlow.Color = rarityColor
	refs.topLine.BackgroundColor3 = rarityColor
	refs.bottomLine.BackgroundColor3 = rarityColor
	refs.rarityLabel.TextColor3 = rarityColor

	-- Snap to invisible, then animate in
	setAllTransparency(1)

	-- Fade in via proxy
	local fadeInInfo = TweenInfo.new(FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local proxy = Instance.new("NumberValue")
	proxy.Value = 1

	proxy.Changed:Connect(function(val)
		setAllTransparency(val)
	end)

	local tweenIn = TweenService:Create(proxy, fadeInInfo, { Value = 0 })
	tweenIn:Play()
	activeTween = tweenIn

	-- Schedule hold + fade out
	activeCleanup = task.spawn(function()
		tweenIn.Completed:Wait()

		task.wait(HOLD)

		local fadeOutInfo = TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local tweenOut = TweenService:Create(proxy, fadeOutInfo, { Value = 1 })
		tweenOut:Play()
		activeTween = tweenOut
		tweenOut.Completed:Wait()

		proxy:Destroy()
		activeTween = nil
		activeCleanup = nil
	end)
end

function AbilityFeedback.init()
	buildUI()
	print("[AbilityFeedback] Initialised")
end

return AbilityFeedback

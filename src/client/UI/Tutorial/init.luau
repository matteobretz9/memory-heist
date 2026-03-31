--[[
	Tutorial / Onboarding UI for Memory Heist.
	Guided first-join walkthrough that introduces core game mechanics step by step.

	Shows once per session (tracked via BoolValue under the player).
	All UI is built programmatically with pure Roblox Instances (no Roact/Fusion).
	Cyberpunk visual style: dark backgrounds, neon cyan accents, GothamBold font.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- Style constants (matches HUD)
-- ============================================================================

local COLORS = {
	bg = Color3.fromRGB(10, 10, 20),
	cyan = Color3.fromRGB(0, 255, 255),
	white = Color3.fromRGB(255, 255, 255),
	dimText = Color3.fromRGB(120, 120, 140),
}

local FONT = Enum.Font.GothamBold
local CORNER_RADIUS = UDim.new(0, 4)

-- ============================================================================
-- Tutorial steps
-- ============================================================================

local STEPS = {
	{
		title = "WELCOME TO MEMORY HEIST",
		description = "A cyberpunk FFA combat game",
	},
	{
		title = "MOVEMENT",
		description = "Use WASD to move, Space to jump. Some abilities grant double jump.",
	},
	{
		title = "COMBAT",
		description = "Left Click to attack with your weapon. Press R to reload.",
	},
	{
		title = "ABILITIES",
		description = "Press Q, E, F, or Z to use abilities. Each has a cooldown shown in the HUD.",
	},
	{
		title = "MEMORY STEAL",
		description = "When you eliminate a player, a Memory Shard drops. Pick it up to steal their ability or upgrade yours.",
	},
	{
		title = "MEMORY OVERLOAD",
		description = "Holding too many abilities causes Overload \u{2014} you'll slow down and abilities may lock. Choose wisely!",
	},
	{
		title = "SHOP & PROGRESSION",
		description = "Press B for Shop, N for Battle Pass, J for Challenges. Earn credits by playing!",
	},
	{
		title = "GOOD LUCK, HACKER",
		description = "",
		isFinal = true,
	},
}

-- ============================================================================
-- Helpers
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
-- Module table
-- ============================================================================

local Tutorial = {}

-- Internal refs
local screenGui: ScreenGui? = nil
local overlay: Frame? = nil
local panel: Frame? = nil
local titleLabel: TextLabel? = nil
local descLabel: TextLabel? = nil
local nextButton: TextButton? = nil
local skipButton: TextButton? = nil
local dotsContainer: Frame? = nil
local dotFrames: { Frame } = {}

local currentStep = 1

-- ============================================================================
-- Completion tracking
-- ============================================================================

local COMPLETED_FLAG_NAME = "TutorialCompleted"

local function isCompleted(): boolean
	return LocalPlayer:FindFirstChild(COMPLETED_FLAG_NAME) ~= nil
end

local function markCompleted()
	if not LocalPlayer:FindFirstChild(COMPLETED_FLAG_NAME) then
		local flag = Instance.new("BoolValue")
		flag.Name = COMPLETED_FLAG_NAME
		flag.Value = true
		flag.Parent = LocalPlayer
	end
end

-- ============================================================================
-- Step rendering
-- ============================================================================

local function updateDots()
	for i, dot in dotFrames do
		if i == currentStep then
			dot.BackgroundColor3 = COLORS.cyan
			dot.BackgroundTransparency = 0
		else
			dot.BackgroundColor3 = COLORS.dimText
			dot.BackgroundTransparency = 0.5
		end
	end
end

local function showStep(stepIndex: number)
	local step = STEPS[stepIndex]
	if not step then
		return
	end

	currentStep = stepIndex

	-- Fade out current content
	if titleLabel and panel then
		local fadeOut = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tweenTitle = TweenService:Create(titleLabel, fadeOut, { TextTransparency = 1 })
		local tweenDesc = TweenService:Create(descLabel, fadeOut, { TextTransparency = 1 })
		tweenTitle:Play()
		tweenDesc:Play()

		tweenTitle.Completed:Wait()

		-- Update text
		titleLabel.Text = step.title
		descLabel.Text = step.description

		-- Update button text for final step
		if nextButton then
			if step.isFinal then
				nextButton.Text = "START PLAYING"
			else
				nextButton.Text = "NEXT >"
			end
		end

		-- Update dots
		updateDots()

		-- Fade in new content
		local fadeIn = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local tweenTitleIn = TweenService:Create(titleLabel, fadeIn, { TextTransparency = 0 })
		local tweenDescIn = TweenService:Create(descLabel, fadeIn, { TextTransparency = 0 })
		tweenTitleIn:Play()
		tweenDescIn:Play()
	end
end

-- ============================================================================
-- Close / destroy
-- ============================================================================

local function closeTutorial()
	markCompleted()

	if screenGui then
		-- Fade out overlay
		local fadeOut = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		if overlay then
			local tween = TweenService:Create(overlay, fadeOut, { BackgroundTransparency = 1 })
			tween:Play()
		end
		if panel then
			local tween = TweenService:Create(panel, fadeOut, { BackgroundTransparency = 1 })
			tween:Play()
		end
		if titleLabel then
			TweenService:Create(titleLabel, fadeOut, { TextTransparency = 1 }):Play()
		end
		if descLabel then
			TweenService:Create(descLabel, fadeOut, { TextTransparency = 1 }):Play()
		end

		task.delay(0.35, function()
			if screenGui and screenGui.Parent then
				screenGui:Destroy()
			end
			screenGui = nil
			overlay = nil
			panel = nil
			titleLabel = nil
			descLabel = nil
			nextButton = nil
			skipButton = nil
			dotsContainer = nil
			dotFrames = {}
			currentStep = 1
		end)
	end
end

-- ============================================================================
-- Advance / skip handlers
-- ============================================================================

local function onNext()
	if currentStep >= #STEPS then
		closeTutorial()
	else
		showStep(currentStep + 1)
	end
end

local function onSkip()
	closeTutorial()
end

-- ============================================================================
-- Build UI
-- ============================================================================

local function buildUI()
	-- ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 100 -- render above HUD
	gui.IgnoreGuiInset = true
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	screenGui = gui

	-- Full-screen dark overlay
	local bg = Instance.new("Frame")
	bg.Name = "Overlay"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BackgroundTransparency = 0.7
	bg.BorderSizePixel = 0
	bg.ZIndex = 1
	bg.Parent = gui
	overlay = bg

	-- Center panel
	local PANEL_WIDTH = 500
	local PANEL_HEIGHT = 300

	local pnl = Instance.new("Frame")
	pnl.Name = "TutorialPanel"
	pnl.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	pnl.Position = UDim2.new(0.5, 0, 0.5, 0)
	pnl.AnchorPoint = Vector2.new(0.5, 0.5)
	pnl.BackgroundColor3 = COLORS.bg
	pnl.BackgroundTransparency = 0.1
	pnl.BorderSizePixel = 0
	pnl.ZIndex = 2
	pnl.Parent = gui
	applyCorner(pnl, UDim.new(0, 8))
	applyStroke(pnl, COLORS.cyan, 2)
	panel = pnl

	-- Title label (large cyan text, upper area of panel)
	local title = Instance.new("TextLabel")
	title.Name = "TitleLabel"
	title.Size = UDim2.new(1, -40, 0, 60)
	title.Position = UDim2.new(0, 20, 0, 40)
	title.BackgroundTransparency = 1
	title.Font = FONT
	title.TextSize = 28
	title.TextColor3 = COLORS.cyan
	title.TextWrapped = true
	title.Text = ""
	title.ZIndex = 3
	title.Parent = pnl
	titleLabel = title

	-- Description label (white, smaller, below title)
	local desc = Instance.new("TextLabel")
	desc.Name = "DescLabel"
	desc.Size = UDim2.new(1, -40, 0, 80)
	desc.Position = UDim2.new(0, 20, 0, 110)
	desc.BackgroundTransparency = 1
	desc.Font = FONT
	desc.TextSize = 16
	desc.TextColor3 = COLORS.white
	desc.TextWrapped = true
	desc.Text = ""
	desc.ZIndex = 3
	desc.Parent = pnl
	descLabel = desc

	-- Step indicator dots (bottom center of panel)
	local DOT_SIZE = 10
	local DOT_GAP = 8
	local TOTAL_DOTS_WIDTH = DOT_SIZE * #STEPS + DOT_GAP * (#STEPS - 1)

	local dotsFrame = Instance.new("Frame")
	dotsFrame.Name = "StepDots"
	dotsFrame.Size = UDim2.new(0, TOTAL_DOTS_WIDTH, 0, DOT_SIZE)
	dotsFrame.Position = UDim2.new(0.5, 0, 1, -40)
	dotsFrame.AnchorPoint = Vector2.new(0.5, 0)
	dotsFrame.BackgroundTransparency = 1
	dotsFrame.BorderSizePixel = 0
	dotsFrame.ZIndex = 3
	dotsFrame.Parent = pnl
	dotsContainer = dotsFrame

	local dotsLayout = Instance.new("UIListLayout")
	dotsLayout.FillDirection = Enum.FillDirection.Horizontal
	dotsLayout.Padding = UDim.new(0, DOT_GAP)
	dotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dotsLayout.Parent = dotsFrame

	dotFrames = {}
	for i = 1, #STEPS do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.Size = UDim2.new(0, DOT_SIZE, 0, DOT_SIZE)
		dot.BackgroundColor3 = COLORS.dimText
		dot.BackgroundTransparency = 0.5
		dot.BorderSizePixel = 0
		dot.LayoutOrder = i
		dot.ZIndex = 3
		dot.Parent = dotsFrame
		applyCorner(dot, UDim.new(0.5, 0)) -- circle
		dotFrames[i] = dot
	end

	-- NEXT button (bottom right of panel)
	local nextBtn = Instance.new("TextButton")
	nextBtn.Name = "NextButton"
	nextBtn.Size = UDim2.new(0, 120, 0, 36)
	nextBtn.Position = UDim2.new(1, -20, 1, -20)
	nextBtn.AnchorPoint = Vector2.new(1, 1)
	nextBtn.BackgroundColor3 = COLORS.bg
	nextBtn.BackgroundTransparency = 0.2
	nextBtn.Font = FONT
	nextBtn.TextSize = 14
	nextBtn.TextColor3 = COLORS.cyan
	nextBtn.Text = "NEXT >"
	nextBtn.AutoButtonColor = false
	nextBtn.BorderSizePixel = 0
	nextBtn.ZIndex = 3
	nextBtn.Parent = pnl
	applyCorner(nextBtn)
	applyStroke(nextBtn, COLORS.cyan, 1)
	nextButton = nextBtn

	-- Hover effects for NEXT button
	nextBtn.MouseEnter:Connect(function()
		nextBtn.BackgroundTransparency = 0
		nextBtn.TextColor3 = COLORS.white
	end)
	nextBtn.MouseLeave:Connect(function()
		nextBtn.BackgroundTransparency = 0.2
		nextBtn.TextColor3 = COLORS.cyan
	end)

	nextBtn.MouseButton1Click:Connect(onNext)

	-- SKIP button (bottom left of panel, dim text, no border)
	local skipBtn = Instance.new("TextButton")
	skipBtn.Name = "SkipButton"
	skipBtn.Size = UDim2.new(0, 80, 0, 36)
	skipBtn.Position = UDim2.new(0, 20, 1, -20)
	skipBtn.AnchorPoint = Vector2.new(0, 1)
	skipBtn.BackgroundTransparency = 1
	skipBtn.Font = FONT
	skipBtn.TextSize = 13
	skipBtn.TextColor3 = COLORS.dimText
	skipBtn.Text = "SKIP"
	skipBtn.AutoButtonColor = false
	skipBtn.BorderSizePixel = 0
	skipBtn.ZIndex = 3
	skipBtn.Parent = pnl
	skipButton = skipBtn

	-- Hover effects for SKIP button
	skipBtn.MouseEnter:Connect(function()
		skipBtn.TextColor3 = COLORS.white
	end)
	skipBtn.MouseLeave:Connect(function()
		skipBtn.TextColor3 = COLORS.dimText
	end)

	skipBtn.MouseButton1Click:Connect(onSkip)
end

-- ============================================================================
-- Public API
-- ============================================================================

--[[
	Initialize and show the tutorial if the player has not completed it this session.
	If already completed, this is a no-op.
]]
function Tutorial.init()
	if isCompleted() then
		return
	end

	Tutorial.show()
end

--[[
	Force-show the tutorial (used for re-triggering from settings menu).
	Builds the UI and starts at step 1.
]]
function Tutorial.show()
	-- Destroy any existing tutorial GUI first
	if screenGui and screenGui.Parent then
		screenGui:Destroy()
		screenGui = nil
	end

	currentStep = 1
	dotFrames = {}

	buildUI()

	-- Set initial step content directly (no fade for the first step)
	if titleLabel then
		titleLabel.Text = STEPS[1].title
	end
	if descLabel then
		descLabel.Text = STEPS[1].description
	end
	updateDots()
end

return Tutorial

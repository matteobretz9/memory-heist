--[[
	Challenges — Client-side UI for daily and weekly challenges.

	Toggled with the J key. Slides a panel in/out on the right side of the
	screen showing active challenges, progress bars, and claim buttons.

	Visual style matches the cyberpunk HUD: dark backgrounds, neon cyan
	accents, GothamBold font, UICorner 4px, UIStroke borders.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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
	green = Color3.fromRGB(0, 230, 100),
	gold = Color3.fromRGB(255, 200, 0),
	progressBg = Color3.fromRGB(30, 30, 50),
	progressFill = Color3.fromRGB(0, 200, 200),
}

local FONT = Enum.Font.GothamBold
local FONT_REGULAR = Enum.Font.Gotham
local CORNER_RADIUS = UDim.new(0, 4)
local BG_TRANSPARENCY = 0.15

local PANEL_WIDTH = 300
local PANEL_HEIGHT = 450
local SLIDE_TIME = 0.25

local TOGGLE_KEY = Enum.KeyCode.J

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local Challenges = {}

-- UI references
local screenGui: ScreenGui? = nil
local panelFrame: Frame? = nil
local contentFrame: ScrollingFrame? = nil

-- Per-challenge UI refs: challengeId -> { frame, progressFill, progressLabel, claimBtn, checkmark }
local challengeRefs: { [string]: any } = {}

-- State
local isOpen = false
local challengeState: any = nil -- { dailies = {...}, weeklies = {...} }

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

---------------------------------------------------------------------------
-- Build the panel (created once in init)
---------------------------------------------------------------------------

local function buildPanel()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ChallengesUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 8
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Main panel (starts off-screen to the right)
	panelFrame = Instance.new("Frame")
	panelFrame.Name = "ChallengesPanel"
	panelFrame.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	panelFrame.Position = UDim2.new(1, 0, 0.5, -PANEL_HEIGHT / 2) -- off-screen
	panelFrame.BackgroundColor3 = COLORS.bg
	panelFrame.BackgroundTransparency = BG_TRANSPARENCY
	panelFrame.BorderSizePixel = 0
	panelFrame.ClipsDescendants = true
	panelFrame.Parent = screenGui
	applyCorner(panelFrame, UDim.new(0, 6))
	applyStroke(panelFrame, COLORS.cyan, 2)

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0, 32)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = FONT
	title.TextSize = 20
	title.TextColor3 = COLORS.cyan
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "CHALLENGES"
	title.Parent = panelFrame

	-- Keybind hint
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Size = UDim2.new(0, 30, 0, 20)
	hint.Position = UDim2.new(1, -38, 0, 12)
	hint.BackgroundColor3 = COLORS.bgLight
	hint.BackgroundTransparency = 0.4
	hint.Font = FONT
	hint.TextSize = 12
	hint.TextColor3 = COLORS.cyan
	hint.Text = "J"
	hint.Parent = panelFrame
	applyCorner(hint)

	-- Scrolling content area
	contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, -16, 1, -48)
	contentFrame.Position = UDim2.new(0, 8, 0, 44)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 4
	contentFrame.ScrollBarImageColor3 = COLORS.cyan
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	contentFrame.Parent = panelFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = contentFrame
end

---------------------------------------------------------------------------
-- Challenge entry UI builder
---------------------------------------------------------------------------

local function createSectionHeader(text: string, layoutOrder: number): TextLabel
	local header = Instance.new("TextLabel")
	header.Name = "Header_" .. text
	header.Size = UDim2.new(1, 0, 0, 24)
	header.BackgroundTransparency = 1
	header.Font = FONT
	header.TextSize = 14
	header.TextColor3 = COLORS.cyan
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = text
	header.LayoutOrder = layoutOrder
	header.Parent = contentFrame
	return header
end

local function createChallengeEntry(entry: any, layoutOrder: number): Frame
	local ENTRY_HEIGHT = 64

	local frame = Instance.new("Frame")
	frame.Name = "Challenge_" .. entry.id
	frame.Size = UDim2.new(1, 0, 0, ENTRY_HEIGHT)
	frame.BackgroundColor3 = COLORS.bgLight
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.LayoutOrder = layoutOrder
	frame.Parent = contentFrame
	applyCorner(frame)
	applyStroke(frame, COLORS.dimText, 1)

	-- Description
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.Size = UDim2.new(1, -10, 0, 18)
	desc.Position = UDim2.new(0, 6, 0, 4)
	desc.BackgroundTransparency = 1
	desc.Font = FONT
	desc.TextSize = 12
	desc.TextColor3 = COLORS.white
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Text = entry.description
	desc.Parent = frame

	-- Progress bar background
	local progressBg = Instance.new("Frame")
	progressBg.Name = "ProgressBg"
	progressBg.Size = UDim2.new(1, -12, 0, 10)
	progressBg.Position = UDim2.new(0, 6, 0, 24)
	progressBg.BackgroundColor3 = COLORS.progressBg
	progressBg.BackgroundTransparency = 0.2
	progressBg.BorderSizePixel = 0
	progressBg.Parent = frame
	applyCorner(progressBg, UDim.new(0, 3))

	-- Progress bar fill
	local progress = entry.progress or 0
	local goal = entry.goal or 1
	local fraction = math.clamp(progress / goal, 0, 1)

	local progressFill = Instance.new("Frame")
	progressFill.Name = "ProgressFill"
	progressFill.Size = UDim2.new(fraction, 0, 1, 0)
	progressFill.BackgroundColor3 = if entry.completed then COLORS.green else COLORS.progressFill
	progressFill.BackgroundTransparency = 0.1
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBg
	applyCorner(progressFill, UDim.new(0, 3))

	-- Progress text
	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressText"
	progressLabel.Size = UDim2.new(0, 60, 0, 12)
	progressLabel.Position = UDim2.new(1, -66, 0, 22)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = FONT
	progressLabel.TextSize = 10
	progressLabel.TextColor3 = COLORS.dimText
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.Text = progress .. "/" .. goal
	progressLabel.Parent = frame

	-- Reward text
	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "Reward"
	rewardLabel.Size = UDim2.new(0.5, -6, 0, 16)
	rewardLabel.Position = UDim2.new(0, 6, 0, 40)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Font = FONT_REGULAR
	rewardLabel.TextSize = 11
	rewardLabel.TextColor3 = COLORS.gold
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.Text = entry.rewardCredits .. " CR + " .. entry.rewardXP .. " XP"
	rewardLabel.Parent = frame

	-- Claim button (visible only when completed and unclaimed)
	local claimBtn = Instance.new("TextButton")
	claimBtn.Name = "ClaimBtn"
	claimBtn.Size = UDim2.new(0, 60, 0, 20)
	claimBtn.Position = UDim2.new(1, -66, 0, 38)
	claimBtn.BackgroundColor3 = COLORS.gold
	claimBtn.BackgroundTransparency = 0.1
	claimBtn.BorderSizePixel = 0
	claimBtn.Font = FONT
	claimBtn.TextSize = 12
	claimBtn.TextColor3 = COLORS.bg
	claimBtn.Text = "CLAIM"
	claimBtn.AutoButtonColor = false
	claimBtn.Visible = entry.completed and not entry.claimed
	claimBtn.Parent = frame
	applyCorner(claimBtn, UDim.new(0, 3))

	-- Hover feedback for claim button
	claimBtn.MouseEnter:Connect(function()
		claimBtn.BackgroundTransparency = 0
	end)
	claimBtn.MouseLeave:Connect(function()
		claimBtn.BackgroundTransparency = 0.1
	end)

	-- Click handler
	claimBtn.MouseButton1Click:Connect(function()
		ClientNetwork.fireServer(EventNames.ChallengeClaimRequest, entry.id)
	end)

	-- Checkmark (visible only when claimed)
	local checkmark = Instance.new("TextLabel")
	checkmark.Name = "Checkmark"
	checkmark.Size = UDim2.new(0, 60, 0, 20)
	checkmark.Position = UDim2.new(1, -66, 0, 38)
	checkmark.BackgroundColor3 = COLORS.green
	checkmark.BackgroundTransparency = 0.3
	checkmark.BorderSizePixel = 0
	checkmark.Font = FONT
	checkmark.TextSize = 12
	checkmark.TextColor3 = COLORS.white
	checkmark.Text = "DONE"
	checkmark.Visible = entry.claimed == true
	checkmark.Parent = frame
	applyCorner(checkmark, UDim.new(0, 3))

	-- Store refs for updates
	challengeRefs[entry.id] = {
		frame = frame,
		progressFill = progressFill,
		progressBg = progressBg,
		progressLabel = progressLabel,
		claimBtn = claimBtn,
		checkmark = checkmark,
		goal = goal,
	}

	return frame
end

---------------------------------------------------------------------------
-- Rebuild the full challenge list from state
---------------------------------------------------------------------------

local function rebuildContent()
	if not contentFrame or not challengeState then
		return
	end

	-- Clear existing content
	challengeRefs = {}
	for _, child in contentFrame:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local order = 0

	-- Daily section
	createSectionHeader("DAILY", order)
	order += 1

	if challengeState.dailies then
		for _, entry in challengeState.dailies do
			createChallengeEntry(entry, order)
			order += 1
		end
	end

	-- Spacer
	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.Size = UDim2.new(1, 0, 0, 8)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = order
	spacer.Parent = contentFrame
	order += 1

	-- Weekly section
	createSectionHeader("WEEKLY", order)
	order += 1

	if challengeState.weeklies then
		for _, entry in challengeState.weeklies do
			createChallengeEntry(entry, order)
			order += 1
		end
	end
end

---------------------------------------------------------------------------
-- Update helpers (called by network events)
---------------------------------------------------------------------------

local function updateProgress(challengeId: string, progress: number, goal: number)
	-- Update local state
	if challengeState then
		for _, list in { challengeState.dailies, challengeState.weeklies } do
			if list then
				for _, entry in list do
					if entry.id == challengeId then
						entry.progress = progress
						break
					end
				end
			end
		end
	end

	-- Update UI
	local refs = challengeRefs[challengeId]
	if not refs then
		return
	end

	local fraction = math.clamp(progress / goal, 0, 1)
	refs.progressFill.Size = UDim2.new(fraction, 0, 1, 0)
	refs.progressLabel.Text = progress .. "/" .. goal
end

local function markCompleted(challengeId: string)
	-- Update local state
	if challengeState then
		for _, list in { challengeState.dailies, challengeState.weeklies } do
			if list then
				for _, entry in list do
					if entry.id == challengeId then
						entry.completed = true
						break
					end
				end
			end
		end
	end

	-- Update UI
	local refs = challengeRefs[challengeId]
	if not refs then
		return
	end

	refs.progressFill.BackgroundColor3 = COLORS.green
	refs.claimBtn.Visible = true

	-- Flash the stroke to draw attention
	local stroke = refs.frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = COLORS.gold
		stroke.Thickness = 2
		task.delay(2, function()
			if stroke and stroke.Parent then
				stroke.Color = COLORS.dimText
				stroke.Thickness = 1
			end
		end)
	end
end

local function markClaimed(challengeId: string)
	-- Update local state
	if challengeState then
		for _, list in { challengeState.dailies, challengeState.weeklies } do
			if list then
				for _, entry in list do
					if entry.id == challengeId then
						entry.claimed = true
						break
					end
				end
			end
		end
	end

	-- Update UI
	local refs = challengeRefs[challengeId]
	if not refs then
		return
	end

	refs.claimBtn.Visible = false
	refs.checkmark.Visible = true

	-- Dim the entry slightly
	local stroke = refs.frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = COLORS.green
		stroke.Thickness = 1
	end
end

---------------------------------------------------------------------------
-- Slide in/out animation
---------------------------------------------------------------------------

local function slideIn()
	if not panelFrame then
		return
	end

	isOpen = true
	local targetPos = UDim2.new(1, -(PANEL_WIDTH + 10), 0.5, -PANEL_HEIGHT / 2)
	local tweenInfo = TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(panelFrame, tweenInfo, { Position = targetPos })
	tween:Play()
end

local function slideOut()
	if not panelFrame then
		return
	end

	isOpen = false
	local targetPos = UDim2.new(1, 0, 0.5, -PANEL_HEIGHT / 2)
	local tweenInfo = TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(panelFrame, tweenInfo, { Position = targetPos })
	tween:Play()
end

local function toggle()
	if isOpen then
		slideOut()
	else
		slideIn()
	end
end

function Challenges.toggle()
	toggle()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--[[
	Initialise the Challenges UI. Creates the ScreenGui, panel, and
	connects to network events and keybind.
]]
function Challenges.init()
	buildPanel()

	-- Keybind: J toggles the panel
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			toggle()
		end
	end)

	-- Listen for initial sync
	ClientNetwork.onServerEvent(EventNames.ChallengeSync, function(data: any)
		challengeState = data
		rebuildContent()
	end)

	-- Listen for progress updates
	ClientNetwork.onServerEvent(EventNames.ChallengeProgressUpdate, function(data: any)
		if data and data.id then
			updateProgress(data.id, data.progress, data.goal)
		end
	end)

	-- Listen for completion
	ClientNetwork.onServerEvent(EventNames.ChallengeCompleted, function(data: any)
		if data and data.id then
			markCompleted(data.id)
		end
	end)

	-- Listen for reward claimed
	ClientNetwork.onServerEvent(EventNames.ChallengeRewardClaimed, function(data: any)
		if data and data.id then
			markClaimed(data.id)
		end
	end)

	print("[Challenges] Initialised")
end

return Challenges

--[[
	GameHUD — Game state overlay UI for Memory Heist.

	Shows contextual information based on the current game phase:
	  - Lobby: "WAITING FOR PLAYERS" with player count
	  - Countdown: Large countdown number with scaling animation
	  - Active: Compact round timer at top center
	  - RoundEnd: "ROUND OVER" with winner info and next-round countdown

	Cyberpunk visual style: dark backgrounds, neon cyan accents, GothamBold font.
	All UI is built programmatically with pure Roblox Instances (no Roact/Fusion).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventNames = require(Shared:WaitForChild("Network"):WaitForChild("EventNames"))
local ClientNetwork = require(script.Parent.Parent:WaitForChild("Network"))

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- Style constants (matching HUD)
-- ============================================================================

local COLORS = {
	bg = Color3.fromRGB(10, 10, 20),
	cyan = Color3.fromRGB(0, 255, 255),
	white = Color3.fromRGB(255, 255, 255),
	dimText = Color3.fromRGB(120, 120, 140),
	gold = Color3.fromRGB(255, 215, 0),
}

local FONT = Enum.Font.GothamBold
local CORNER_RADIUS = UDim.new(0, 6)
local BG_TRANSPARENCY = 0.3
local MIN_PLAYERS = 2
local MAX_PLAYERS = 12

-- ============================================================================
-- Module table
-- ============================================================================

local GameHUD = {}

-- UI element references
local refs = {
	screenGui = nil :: ScreenGui?,
	mainFrame = nil :: Frame?,

	-- Lobby
	lobbyContainer = nil :: Frame?,

	-- Countdown
	countdownContainer = nil :: Frame?,
	countdownNumber = nil :: TextLabel?,
	countdownSubtext = nil :: TextLabel?,

	-- Active
	timerContainer = nil :: Frame?,
	timerLabel = nil :: TextLabel?,

	-- RoundEnd
	roundEndContainer = nil :: Frame?,
	roundOverLabel = nil :: TextLabel?,
	winnerLabel = nil :: TextLabel?,
	nextRoundLabel = nil :: TextLabel?,
}

-- Current state for internal tracking
-- (moved up for use by showLobby/hideAll)

-- Current state for internal tracking
local currentState: string = "Lobby"

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

local function formatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%d:%02d", mins, secs)
end

-- ============================================================================
-- Lobby UI
-- ============================================================================

local function createLobbyUI(_parent: Frame)
	-- Lobby container no longer needed; Play button lives in the HUD menu bar
end

local function updatePlayerCount()
	local count = #Players:GetPlayers()
	if refs.playerCountLabel then
		refs.playerCountLabel.Text = count .. "/" .. MAX_PLAYERS .. " Players"
	end
	if refs.needMoreLabel then
		local needed = MIN_PLAYERS - count
		if needed > 0 then
			refs.needMoreLabel.Text = "Need " .. needed .. " more to start"
			refs.needMoreLabel.Visible = true
		else
			refs.needMoreLabel.Text = ""
			refs.needMoreLabel.Visible = false
		end
	end
end

-- ============================================================================
-- Countdown UI
-- ============================================================================

local function createCountdownUI(parent: Frame)
	local container = Instance.new("Frame")
	container.Name = "CountdownContainer"
	container.Size = UDim2.new(0, 300, 0, 200)
	container.Position = UDim2.new(0.5, 0, 0.4, 0)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Visible = false
	container.Parent = parent

	-- Big countdown number
	local countdownNumber = Instance.new("TextLabel")
	countdownNumber.Name = "CountdownNumber"
	countdownNumber.Size = UDim2.new(1, 0, 0, 120)
	countdownNumber.Position = UDim2.new(0, 0, 0, 0)
	countdownNumber.BackgroundTransparency = 1
	countdownNumber.Font = FONT
	countdownNumber.TextSize = 96
	countdownNumber.TextColor3 = COLORS.cyan
	countdownNumber.Text = "10"
	countdownNumber.Parent = container

	-- "ROUND STARTING" subtext
	local subtext = Instance.new("TextLabel")
	subtext.Name = "Subtext"
	subtext.Size = UDim2.new(1, 0, 0, 30)
	subtext.Position = UDim2.new(0, 0, 0, 125)
	subtext.BackgroundTransparency = 1
	subtext.Font = FONT
	subtext.TextSize = 22
	subtext.TextColor3 = COLORS.white
	subtext.Text = "ROUND STARTING"
	subtext.Parent = container

	refs.countdownContainer = container
	refs.countdownNumber = countdownNumber
	refs.countdownSubtext = subtext
end

-- Animate the countdown number with a scale pop effect
local function animateCountdownNumber(seconds: number)
	local label = refs.countdownNumber
	if not label then
		return
	end

	label.Text = tostring(seconds)

	-- Reset scale and animate
	label.TextSize = 120
	label.TextTransparency = 0

	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	-- Start large and shrink to target size for a pop-in effect
	label.TextSize = 48
	local scaleTween = TweenService:Create(label, tweenInfo, {
		TextSize = 96,
	})
	scaleTween:Play()
end

-- ============================================================================
-- Active Round Timer UI
-- ============================================================================

local function createTimerUI(parent: Frame)
	local container = Instance.new("Frame")
	container.Name = "TimerContainer"
	container.Size = UDim2.new(0, 120, 0, 36)
	container.Position = UDim2.new(0.5, 0, 0, 8)
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = BG_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Visible = false
	container.Parent = parent
	applyCorner(container)
	applyStroke(container, COLORS.cyan, 1)

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, 0, 1, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = FONT
	timerLabel.TextSize = 20
	timerLabel.TextColor3 = COLORS.white
	timerLabel.Text = "3:00"
	timerLabel.Parent = container

	refs.timerContainer = container
	refs.timerLabel = timerLabel
end

-- ============================================================================
-- Round End UI
-- ============================================================================

local function createRoundEndUI(parent: Frame)
	local container = Instance.new("Frame")
	container.Name = "RoundEndContainer"
	container.Size = UDim2.new(0, 420, 0, 180)
	container.Position = UDim2.new(0.5, 0, 0.4, 0)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = BG_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Visible = false
	container.Parent = parent
	applyCorner(container)
	applyStroke(container, COLORS.cyan, 2)

	-- "ROUND OVER"
	local roundOverLabel = Instance.new("TextLabel")
	roundOverLabel.Name = "RoundOver"
	roundOverLabel.Size = UDim2.new(1, 0, 0, 40)
	roundOverLabel.Position = UDim2.new(0, 0, 0, 16)
	roundOverLabel.BackgroundTransparency = 1
	roundOverLabel.Font = FONT
	roundOverLabel.TextSize = 32
	roundOverLabel.TextColor3 = COLORS.cyan
	roundOverLabel.Text = "ROUND OVER"
	roundOverLabel.Parent = container

	-- Winner name + score
	local winnerLabel = Instance.new("TextLabel")
	winnerLabel.Name = "Winner"
	winnerLabel.Size = UDim2.new(1, -20, 0, 30)
	winnerLabel.Position = UDim2.new(0, 10, 0, 65)
	winnerLabel.BackgroundTransparency = 1
	winnerLabel.Font = FONT
	winnerLabel.TextSize = 20
	winnerLabel.TextColor3 = COLORS.gold
	winnerLabel.Text = ""
	winnerLabel.Parent = container

	-- "Next round in Xs"
	local nextRoundLabel = Instance.new("TextLabel")
	nextRoundLabel.Name = "NextRound"
	nextRoundLabel.Size = UDim2.new(1, 0, 0, 24)
	nextRoundLabel.Position = UDim2.new(0, 0, 0, 110)
	nextRoundLabel.BackgroundTransparency = 1
	nextRoundLabel.Font = FONT
	nextRoundLabel.TextSize = 16
	nextRoundLabel.TextColor3 = COLORS.dimText
	nextRoundLabel.Text = ""
	nextRoundLabel.Parent = container

	refs.roundEndContainer = container
	refs.roundOverLabel = roundOverLabel
	refs.winnerLabel = winnerLabel
	refs.nextRoundLabel = nextRoundLabel
end

-- ============================================================================
-- State visibility management
-- ============================================================================

local function hideAll()
	if refs.lobbyContainer then
		refs.lobbyContainer.Visible = false
	end
	if refs.countdownContainer then
		refs.countdownContainer.Visible = false
	end
	if refs.timerContainer then
		refs.timerContainer.Visible = false
	end
	if refs.roundEndContainer then
		refs.roundEndContainer.Visible = false
	end

	-- Stop pulse when leaving lobby
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
end

local function showLobby()
	hideAll()
end

local function showCountdown()
	hideAll()
	if refs.countdownContainer then
		refs.countdownContainer.Visible = true
	end
end

local function showActive()
	hideAll()
	if refs.timerContainer then
		refs.timerContainer.Visible = true
	end
end

local function showRoundEnd()
	hideAll()
	if refs.roundEndContainer then
		refs.roundEndContainer.Visible = true
	end
end

-- ============================================================================
-- Public API
-- ============================================================================

--[[
	Called by GameStateController when the game state changes.
	@param newState -- "Lobby" | "Countdown" | "Active" | "RoundEnd"
	@param data -- optional data payload from the server
]]
function GameHUD.onStateChanged(newState: string, data: { [string]: any }?)
	currentState = newState

	if newState == "Lobby" then
		showLobby()
	elseif newState == "Countdown" then
		showCountdown()
	elseif newState == "Active" then
		showActive()
	elseif newState == "RoundEnd" then
		showRoundEnd()
	end
end

--[[
	Called by GameStateController when a timer sync arrives from the server.
	@param seconds -- remaining seconds
]]
function GameHUD.onTimerUpdate(seconds: number)
	if currentState == "Active" then
		-- Update the round timer
		if refs.timerLabel then
			refs.timerLabel.Text = formatTime(seconds)

			-- Flash red when time is low
			if seconds <= 30 then
				refs.timerLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
			else
				refs.timerLabel.TextColor3 = COLORS.white
			end
		end
	elseif currentState == "Countdown" then
		-- Show the countdown number with animation
		local whole = math.ceil(seconds)
		animateCountdownNumber(whole)
	elseif currentState == "RoundEnd" then
		-- Show "Next round in Xs"
		if refs.nextRoundLabel then
			local whole = math.ceil(seconds)
			refs.nextRoundLabel.Text = "Next round in " .. whole .. "s"
		end
	end
end

--[[
	Initialize the GameHUD. Creates the ScreenGui and all phase containers.
]]
function GameHUD.init()
	-- Create the ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GameStateHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 5 -- above the main HUD
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	refs.screenGui = screenGui

	-- Main container (full screen)
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "GameHUDFrame"
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.BackgroundTransparency = 1
	mainFrame.Parent = screenGui
	refs.mainFrame = mainFrame

	-- Build all phase UIs
	createLobbyUI(mainFrame)
	createCountdownUI(mainFrame)
	createTimerUI(mainFrame)
	createRoundEndUI(mainFrame)

	-- Listen for RoundResults to show winner info
	ClientNetwork.onServerEvent(EventNames.RoundResults, function(results: { any })
		if results and #results > 0 then
			local winner = results[1] -- sorted by score, first is the winner
			if refs.winnerLabel then
				refs.winnerLabel.Text = winner.name .. " — " .. winner.score .. " pts"
			end
		else
			if refs.winnerLabel then
				refs.winnerLabel.Text = "No winner"
			end
		end
	end)

	-- Start in lobby state
	showLobby()

	print("[GameHUD] Initialised")
end

return GameHUD

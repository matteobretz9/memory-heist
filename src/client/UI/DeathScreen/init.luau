--[[
	DeathScreen — Full-screen overlay shown when the local player is eliminated.

	Displays the killer's name and a respawn countdown, then fades out when the
	server fires CharacterSpawned. Purely event-driven; no public toggle needed.

	Cyberpunk visual style matching the rest of the Memory Heist UI.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventNames = require(Shared:WaitForChild("Network"):WaitForChild("EventNames"))
local ClientNetwork = require(script.Parent.Parent:WaitForChild("Network"))

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- Style constants
-- ============================================================================

local COLORS = {
	bg = Color3.fromRGB(10, 10, 20),
	red = Color3.fromRGB(255, 40, 40),
	white = Color3.fromRGB(255, 255, 255),
	dimText = Color3.fromRGB(180, 180, 200),
	overlayTint = Color3.fromRGB(20, 5, 5),
	vignette = Color3.fromRGB(80, 0, 0),
}

local FONT = Enum.Font.GothamBold
local RESPAWN_SECONDS = 5
local FADE_IN_TIME = 0.3
local FADE_OUT_TIME = 0.2

-- ============================================================================
-- Module table
-- ============================================================================

local DeathScreen = {}

-- UI references
local screenGui: ScreenGui = nil
local overlay: Frame = nil
local eliminatedLabel: TextLabel = nil
local killerLabel: TextLabel = nil
local countdownLabel: TextLabel = nil

-- State
local killerName: string = "" -- captured from KillOccurred before CharacterDied fires
local countdownThread: thread? = nil

-- ============================================================================
-- Helpers
-- ============================================================================

local function applyCorner(parent: GuiObject, radius: UDim?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 4)
	corner.Parent = parent
	return corner
end

-- ============================================================================
-- Vignette effect — dark-red gradient around the screen edges
-- ============================================================================

local function createVignette(parent: Frame)
	-- We layer four gradient frames (top, bottom, left, right) to simulate a
	-- vignette without needing ImageLabels or asset IDs.

	local function makeEdge(name: string, size: UDim2, position: UDim2, rotation: number)
		local edge = Instance.new("Frame")
		edge.Name = name
		edge.Size = size
		edge.Position = position
		edge.BackgroundColor3 = COLORS.vignette
		edge.BackgroundTransparency = 0.3
		edge.BorderSizePixel = 0
		edge.ZIndex = 1
		edge.Parent = parent

		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Rotation = rotation
		gradient.Parent = edge

		return edge
	end

	-- Top edge: gradient fading downward
	makeEdge("VignetteTop", UDim2.new(1, 0, 0.18, 0), UDim2.new(0, 0, 0, 0), 90)
	-- Bottom edge: gradient fading upward
	makeEdge("VignetteBottom", UDim2.new(1, 0, 0.18, 0), UDim2.new(0, 0, 0.82, 0), -90)
	-- Left edge: gradient fading rightward
	makeEdge("VignetteLeft", UDim2.new(0.15, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0)
	-- Right edge: gradient fading leftward
	makeEdge("VignetteRight", UDim2.new(0.15, 0, 1, 0), UDim2.new(0.85, 0, 0, 0), 180)
end

-- ============================================================================
-- Build the UI tree (called once in init)
-- ============================================================================

local function buildUI()
	-- ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DeathScreen"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 10 -- above the HUD
	screenGui.Enabled = false
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Full-screen overlay
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = COLORS.overlayTint
	overlay.BackgroundTransparency = 1 -- starts invisible; tweened in
	overlay.BorderSizePixel = 0
	overlay.Parent = screenGui

	-- Vignette
	createVignette(overlay)

	-- Center content container
	local center = Instance.new("Frame")
	center.Name = "CenterContent"
	center.Size = UDim2.new(0, 400, 0, 180)
	center.Position = UDim2.new(0.5, 0, 0.45, 0)
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.BackgroundTransparency = 1
	center.BorderSizePixel = 0
	center.Parent = overlay

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = center

	-- "ELIMINATED" title
	eliminatedLabel = Instance.new("TextLabel")
	eliminatedLabel.Name = "EliminatedLabel"
	eliminatedLabel.Size = UDim2.new(1, 0, 0, 50)
	eliminatedLabel.BackgroundTransparency = 1
	eliminatedLabel.Font = FONT
	eliminatedLabel.TextSize = 42
	eliminatedLabel.TextColor3 = COLORS.red
	eliminatedLabel.Text = "ELIMINATED"
	eliminatedLabel.LayoutOrder = 1
	eliminatedLabel.Parent = center

	-- Red glow stroke behind the title
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = COLORS.red
	titleStroke.Thickness = 1.5
	titleStroke.Transparency = 0.5
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = eliminatedLabel

	-- Killer info
	killerLabel = Instance.new("TextLabel")
	killerLabel.Name = "KillerLabel"
	killerLabel.Size = UDim2.new(1, 0, 0, 28)
	killerLabel.BackgroundTransparency = 1
	killerLabel.Font = FONT
	killerLabel.TextSize = 20
	killerLabel.TextColor3 = COLORS.white
	killerLabel.Text = ""
	killerLabel.LayoutOrder = 2
	killerLabel.Parent = center

	-- Respawn countdown
	countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "CountdownLabel"
	countdownLabel.Size = UDim2.new(1, 0, 0, 24)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Font = FONT
	countdownLabel.TextSize = 18
	countdownLabel.TextColor3 = COLORS.dimText
	countdownLabel.Text = ""
	countdownLabel.LayoutOrder = 3
	countdownLabel.Parent = center

	-- Decorative separator line below the title
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.Size = UDim2.new(0, 200, 0, 2)
	separator.BackgroundColor3 = COLORS.red
	separator.BackgroundTransparency = 0.5
	separator.BorderSizePixel = 0
	separator.LayoutOrder = 4
	separator.Parent = center
	applyCorner(separator, UDim.new(0, 1))
end

-- ============================================================================
-- Show / Hide with tweens
-- ============================================================================

local function show()
	screenGui.Enabled = true

	-- Set killer text
	if killerName ~= "" then
		killerLabel.Text = "Killed by: " .. killerName
	else
		killerLabel.Text = ""
	end

	-- Reset transparency for fade-in
	overlay.BackgroundTransparency = 1
	eliminatedLabel.TextTransparency = 1
	killerLabel.TextTransparency = 1
	countdownLabel.TextTransparency = 1

	-- Fade in
	local fadeInfo = TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(overlay, fadeInfo, { BackgroundTransparency = 0.5 }):Play()
	TweenService:Create(eliminatedLabel, fadeInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(killerLabel, fadeInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(countdownLabel, fadeInfo, { TextTransparency = 0 }):Play()

	-- Start countdown
	if countdownThread then
		task.cancel(countdownThread)
	end

	countdownThread = task.spawn(function()
		for i = RESPAWN_SECONDS, 1, -1 do
			countdownLabel.Text = "Respawning in " .. i .. "..."
			task.wait(1)
		end
		countdownLabel.Text = "Respawning..."
	end)
end

local function hide()
	-- Cancel any running countdown
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end

	-- Fade out
	local fadeInfo = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(overlay, fadeInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(eliminatedLabel, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(killerLabel, fadeInfo, { TextTransparency = 1 }):Play()

	local countdownTween = TweenService:Create(countdownLabel, fadeInfo, { TextTransparency = 1 })
	countdownTween:Play()
	countdownTween.Completed:Connect(function()
		screenGui.Enabled = false
		-- Reset killer for next death
		killerName = ""
	end)
end

-- ============================================================================
-- Event handlers
-- ============================================================================

local function onKillOccurred(killer: string, victim: string)
	-- Capture killer name when we are the victim
	if victim == LocalPlayer.Name then
		killerName = killer
	end
end

local function onCharacterDied()
	show()
end

local function onCharacterSpawned()
	hide()
end

-- ============================================================================
-- Public API
-- ============================================================================

--[[
	Initialize the death screen. Creates all UI and connects to network events.
	Call once during client startup.
]]
function DeathScreen.init()
	buildUI()

	-- KillOccurred fires before CharacterDied, so we capture the killer name first
	ClientNetwork.onServerEvent(EventNames.KillOccurred, onKillOccurred)
	ClientNetwork.onServerEvent(EventNames.CharacterDied, onCharacterDied)
	ClientNetwork.onServerEvent(EventNames.CharacterSpawned, onCharacterSpawned)
end

return DeathScreen

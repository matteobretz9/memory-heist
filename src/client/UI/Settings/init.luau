--[[
	Settings — Client-side settings panel for Memory Heist.

	Opened/closed with the P key. Full-screen overlay with sliders,
	toggles, and buttons for audio, display, and gameplay settings.

	Visual style matches the cyberpunk HUD: dark backgrounds, neon cyan
	accents, GothamBold font, UICorner 4px, UIStroke borders.

	Settings are session-only (not persisted to server).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

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
}

local FONT = Enum.Font.GothamBold
local FONT_REGULAR = Enum.Font.Gotham
local CORNER_RADIUS = UDim.new(0, 4)
local BG_TRANSPARENCY = 0.3

local PANEL_WIDTH = 450
local PANEL_HEIGHT = 500

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local Settings = {}

-- UI references
local screenGui: ScreenGui? = nil
local isVisible = false

---------------------------------------------------------------------------
-- Settings data store (session only)
---------------------------------------------------------------------------

local settingsData: { [string]: any } = {
	-- Audio
	MasterVolume = 80,
	MusicVolume = 50,
	SFXVolume = 80,
	-- Display
	ShowKillFeed = true,
	ShowDamageNumbers = true,
	HUDScale = 100,
	-- Gameplay
	MouseSensitivity = 50,
}

-- Callbacks registered by other modules when a setting changes
local changeCallbacks: { [string]: { (value: any) -> () } } = {}

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

local function fireChangeCallbacks(key: string, value: any)
	local callbacks = changeCallbacks[key]
	if callbacks then
		for _, cb in callbacks do
			task.spawn(cb, value)
		end
	end
end

---------------------------------------------------------------------------
-- UI component builders
---------------------------------------------------------------------------

--[[
	Creates a section header label (e.g. "AUDIO", "DISPLAY").
]]
local function createSectionHeader(parent: GuiObject, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Section_" .. text
	label.Size = UDim2.new(1, 0, 0, 24)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = 14
	label.TextColor3 = COLORS.cyan
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

--[[
	Creates a row label (setting name) on the left side.
]]
local function createRowLabel(parent: GuiObject, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(0, 160, 1, 0)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = FONT_REGULAR
	label.TextSize = 13
	label.TextColor3 = COLORS.white
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
	return label
end

--[[
	Creates a slider control.
	Returns the row frame. The slider is wired to update settingsData[key].
]]
local function createSlider(
	parent: GuiObject,
	labelText: string,
	key: string,
	min: number,
	max: number,
	default: number,
	suffix: string?
): Frame
	local row = Instance.new("Frame")
	row.Name = "Slider_" .. key
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundTransparency = 1
	row.Parent = parent

	createRowLabel(row, labelText)

	-- Value label (right side)
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Size = UDim2.new(0, 40, 1, 0)
	valueLabel.Position = UDim2.new(1, -40, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = FONT
	valueLabel.TextSize = 13
	valueLabel.TextColor3 = COLORS.cyan
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = tostring(default) .. (suffix or "")
	valueLabel.Parent = row

	-- Track background
	local TRACK_WIDTH = 180
	local TRACK_HEIGHT = 6
	local KNOB_SIZE = 14

	local trackContainer = Instance.new("Frame")
	trackContainer.Name = "TrackContainer"
	trackContainer.Size = UDim2.new(0, TRACK_WIDTH, 0, KNOB_SIZE)
	trackContainer.Position = UDim2.new(1, -40 - 8 - TRACK_WIDTH, 0.5, 0)
	trackContainer.AnchorPoint = Vector2.new(0, 0.5)
	trackContainer.BackgroundTransparency = 1
	trackContainer.Parent = row

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, TRACK_HEIGHT)
	track.Position = UDim2.new(0, 0, 0.5, 0)
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.BackgroundColor3 = COLORS.bgLight
	track.BackgroundTransparency = 0
	track.BorderSizePixel = 0
	track.Parent = trackContainer
	applyCorner(track, UDim.new(0, 3))

	-- Cyan fill
	local initialFraction = math.clamp((default - min) / (max - min), 0, 1)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(initialFraction, 0, 1, 0)
	fill.BackgroundColor3 = COLORS.cyan
	fill.BackgroundTransparency = 0.2
	fill.BorderSizePixel = 0
	fill.Parent = track
	applyCorner(fill, UDim.new(0, 3))

	-- Draggable knob
	local knob = Instance.new("TextButton")
	knob.Name = "Knob"
	knob.Size = UDim2.new(0, KNOB_SIZE, 0, KNOB_SIZE)
	knob.Position = UDim2.new(initialFraction, 0, 0.5, 0)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = COLORS.cyan
	knob.BackgroundTransparency = 0
	knob.BorderSizePixel = 0
	knob.Text = ""
	knob.AutoButtonColor = false
	knob.ZIndex = 2
	knob.Parent = trackContainer
	applyCorner(knob, UDim.new(0.5, 0))

	-- Drag logic
	local dragging = false

	local function updateSlider(fraction: number)
		fraction = math.clamp(fraction, 0, 1)
		local value = math.round(min + fraction * (max - min))
		settingsData[key] = value
		fill.Size = UDim2.new(fraction, 0, 1, 0)
		knob.Position = UDim2.new(fraction, 0, 0.5, 0)
		valueLabel.Text = tostring(value) .. (suffix or "")
		fireChangeCallbacks(key, value)
	end

	knob.MouseButton1Down:Connect(function()
		dragging = true
	end)

	-- Also allow clicking anywhere on the track
	track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			local absPos = trackContainer.AbsolutePosition.X
			local absSize = trackContainer.AbsoluteSize.X
			local fraction = math.clamp((input.Position.X - absPos) / absSize, 0, 1)
			updateSlider(fraction)
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local absPos = trackContainer.AbsolutePosition.X
			local absSize = trackContainer.AbsoluteSize.X
			local fraction = math.clamp((input.Position.X - absPos) / absSize, 0, 1)
			updateSlider(fraction)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return row
end

--[[
	Creates a toggle control (ON/OFF rectangular button).
	Returns the row frame.
]]
local function createToggle(parent: GuiObject, labelText: string, key: string, default: boolean): Frame
	local row = Instance.new("Frame")
	row.Name = "Toggle_" .. key
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundTransparency = 1
	row.Parent = parent

	createRowLabel(row, labelText)

	local btn = Instance.new("TextButton")
	btn.Name = "ToggleBtn"
	btn.Size = UDim2.new(0, 50, 0, 22)
	btn.Position = UDim2.new(1, -40 - 8 - 50, 0.5, 0)
	btn.AnchorPoint = Vector2.new(0, 0.5)
	btn.BorderSizePixel = 0
	btn.Font = FONT
	btn.TextSize = 12
	btn.AutoButtonColor = false
	btn.Parent = row
	applyCorner(btn)
	applyStroke(btn, COLORS.cyan, 1)

	local function refreshToggle()
		local val = settingsData[key]
		if val then
			btn.Text = "ON"
			btn.BackgroundColor3 = COLORS.cyan
			btn.BackgroundTransparency = 0.2
			btn.TextColor3 = COLORS.bg
		else
			btn.Text = "OFF"
			btn.BackgroundColor3 = COLORS.bg
			btn.BackgroundTransparency = BG_TRANSPARENCY
			btn.TextColor3 = COLORS.dimText
		end
	end

	refreshToggle()

	btn.MouseButton1Click:Connect(function()
		settingsData[key] = not settingsData[key]
		refreshToggle()
		fireChangeCallbacks(key, settingsData[key])
	end)

	return row
end

--[[
	Creates an action button (e.g. "REPLAY TUTORIAL").
	Returns the row frame.
]]
local function createActionButton(parent: GuiObject, labelText: string, buttonText: string, onClick: () -> ()): Frame
	local row = Instance.new("Frame")
	row.Name = "Action_" .. labelText
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundTransparency = 1
	row.Parent = parent

	createRowLabel(row, labelText)

	local btn = Instance.new("TextButton")
	btn.Name = "ActionBtn"
	btn.Size = UDim2.new(0, 140, 0, 22)
	btn.Position = UDim2.new(1, -40 - 8 - 140, 0.5, 0)
	btn.AnchorPoint = Vector2.new(0, 0.5)
	btn.BackgroundColor3 = COLORS.bg
	btn.BackgroundTransparency = BG_TRANSPARENCY
	btn.BorderSizePixel = 0
	btn.Font = FONT
	btn.TextSize = 12
	btn.TextColor3 = COLORS.cyan
	btn.Text = buttonText
	btn.AutoButtonColor = false
	btn.Parent = row
	applyCorner(btn)
	applyStroke(btn, COLORS.cyan, 1)

	btn.MouseEnter:Connect(function()
		btn.BackgroundTransparency = 0.1
		btn.TextColor3 = COLORS.white
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundTransparency = BG_TRANSPARENCY
		btn.TextColor3 = COLORS.cyan
	end)

	btn.MouseButton1Click:Connect(function()
		onClick()
	end)

	return row
end

---------------------------------------------------------------------------
-- Build the settings panel (created once in init)
---------------------------------------------------------------------------

local function buildSettingsUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SettingsUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 20 -- above HUD and shop
	screenGui.IgnoreGuiInset = false
	screenGui.Enabled = false
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Semi-transparent full-screen backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.85
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 1
	backdrop.Parent = screenGui

	-- Main panel (centered)
	local mainPanel = Instance.new("Frame")
	mainPanel.Name = "MainPanel"
	mainPanel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	mainPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	mainPanel.BackgroundColor3 = COLORS.bg
	mainPanel.BackgroundTransparency = 0.05
	mainPanel.BorderSizePixel = 0
	mainPanel.ZIndex = 2
	mainPanel.Parent = screenGui
	applyCorner(mainPanel, UDim.new(0, 8))
	applyStroke(mainPanel, COLORS.cyan, 2)

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -60, 0, 36)
	title.Position = UDim2.new(0, 16, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = FONT
	title.TextSize = 24
	title.TextColor3 = COLORS.cyan
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "SETTINGS"
	title.ZIndex = 3
	title.Parent = mainPanel

	-- Close button (top right)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -40, 0, 8)
	closeBtn.BackgroundColor3 = COLORS.bgLight
	closeBtn.BackgroundTransparency = BG_TRANSPARENCY
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = FONT
	closeBtn.TextSize = 18
	closeBtn.TextColor3 = COLORS.red
	closeBtn.Text = "X"
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 3
	closeBtn.Parent = mainPanel
	applyCorner(closeBtn)
	applyStroke(closeBtn, COLORS.red, 1)

	closeBtn.MouseEnter:Connect(function()
		closeBtn.BackgroundTransparency = 0.1
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.BackgroundTransparency = BG_TRANSPARENCY
	end)
	closeBtn.MouseButton1Click:Connect(function()
		Settings.hide()
	end)

	-- Scrolling content area
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "Content"
	scrollFrame.Size = UDim2.new(1, -32, 1, -56)
	scrollFrame.Position = UDim2.new(0, 16, 0, 48)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLORS.cyan
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.ZIndex = 3
	scrollFrame.Parent = mainPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scrollFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scrollFrame

	-- Track layout order
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- === AUDIO SECTION ===
	local audioHeader = createSectionHeader(scrollFrame, "AUDIO")
	audioHeader.LayoutOrder = nextOrder()

	local masterSlider = createSlider(scrollFrame, "Master Volume", "MasterVolume", 0, 100, settingsData.MasterVolume)
	masterSlider.LayoutOrder = nextOrder()

	local musicSlider = createSlider(scrollFrame, "Music Volume", "MusicVolume", 0, 100, settingsData.MusicVolume)
	musicSlider.LayoutOrder = nextOrder()

	local sfxSlider = createSlider(scrollFrame, "SFX Volume", "SFXVolume", 0, 100, settingsData.SFXVolume)
	sfxSlider.LayoutOrder = nextOrder()

	-- Spacer
	local spacer1 = Instance.new("Frame")
	spacer1.Name = "Spacer"
	spacer1.Size = UDim2.new(1, 0, 0, 8)
	spacer1.BackgroundTransparency = 1
	spacer1.LayoutOrder = nextOrder()
	spacer1.Parent = scrollFrame

	-- === DISPLAY SECTION ===
	local displayHeader = createSectionHeader(scrollFrame, "DISPLAY")
	displayHeader.LayoutOrder = nextOrder()

	local killFeedToggle = createToggle(scrollFrame, "Show Kill Feed", "ShowKillFeed", settingsData.ShowKillFeed)
	killFeedToggle.LayoutOrder = nextOrder()

	local dmgNumToggle = createToggle(scrollFrame, "Show Damage Numbers", "ShowDamageNumbers", settingsData.ShowDamageNumbers)
	dmgNumToggle.LayoutOrder = nextOrder()

	local hudScaleSlider = createSlider(scrollFrame, "HUD Scale", "HUDScale", 50, 150, settingsData.HUDScale, "%")
	hudScaleSlider.LayoutOrder = nextOrder()

	-- Spacer
	local spacer2 = Instance.new("Frame")
	spacer2.Name = "Spacer"
	spacer2.Size = UDim2.new(1, 0, 0, 8)
	spacer2.BackgroundTransparency = 1
	spacer2.LayoutOrder = nextOrder()
	spacer2.Parent = scrollFrame

	-- === GAMEPLAY SECTION ===
	local gameplayHeader = createSectionHeader(scrollFrame, "GAMEPLAY")
	gameplayHeader.LayoutOrder = nextOrder()

	local sensSlider = createSlider(scrollFrame, "Mouse Sensitivity", "MouseSensitivity", 1, 100, settingsData.MouseSensitivity)
	sensSlider.LayoutOrder = nextOrder()

	local tutorialBtn = createActionButton(scrollFrame, "Show Tutorial", "REPLAY TUTORIAL", function()
		-- Lazy-require Tutorial to avoid circular dependency
		local ok, Tutorial = pcall(function()
			return require(script.Parent.Parent.Tutorial)
		end)
		if ok and Tutorial and Tutorial.show then
			Settings.hide()
			Tutorial.show()
		else
			warn("[Settings] Tutorial module not available")
		end
	end)
	tutorialBtn.LayoutOrder = nextOrder()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--[[
	Read a setting value by key.
	@param key -- the setting key (e.g. "MasterVolume", "ShowKillFeed")
	@return the current value, or nil if the key does not exist
]]
function Settings.get(key: string): any
	return settingsData[key]
end

--[[
	Write a setting value by key.
	@param key -- the setting key
	@param value -- the new value
]]
function Settings.set(key: string, value: any)
	settingsData[key] = value
	fireChangeCallbacks(key, value)
end

--[[
	Register a callback that fires whenever a setting changes.
	@param key -- the setting key to watch
	@param callback -- function(newValue) called on change
]]
function Settings.onChange(key: string, callback: (value: any) -> ())
	if not changeCallbacks[key] then
		changeCallbacks[key] = {}
	end
	table.insert(changeCallbacks[key], callback)
end

function Settings.show()
	if isVisible then
		return
	end
	isVisible = true
	if screenGui then
		screenGui.Enabled = true
	end
end

function Settings.hide()
	if not isVisible then
		return
	end
	isVisible = false
	if screenGui then
		screenGui.Enabled = false
	end
end

function Settings.toggle()
	if isVisible then
		Settings.hide()
	else
		Settings.show()
	end
end

function Settings.isVisible(): boolean
	return isVisible
end

--[[
	Initialize the Settings UI. Builds the panel and wires the P key toggle.
]]
function Settings.init()
	buildSettingsUI()

	-- P key to toggle settings
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.P then
			Settings.toggle()
		end
	end)

	print("[Settings] Initialised")
end

return Settings

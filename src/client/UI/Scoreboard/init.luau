--[[
	Scoreboard — Client-side Tab-toggle scoreboard for Memory Heist.

	Hold Tab to show, release to hide. Displays all players ranked by score
	with columns: Rank, Player, Kills, Deaths, Score.

	Data sources:
	  - ScoreUpdate (server -> client): updates local player's kills, deaths, score
	  - KillOccurred (server -> client): increments killer kills / victim deaths
	  - Players service: tracks join/leave

	Visual style matches the cyberpunk HUD: dark backgrounds, neon cyan
	accents, GothamBold font, UICorner 4px, UIStroke borders.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventNames = require(Shared:WaitForChild("Network"):WaitForChild("EventNames"))
local ClientNetwork = require(script.Parent.Parent:WaitForChild("Network"))

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- Style constants (matching HUD cyberpunk theme)
-- ============================================================================

local COLORS = {
	bg = Color3.fromRGB(10, 10, 20),
	bgLight = Color3.fromRGB(20, 20, 40),
	cyan = Color3.fromRGB(0, 255, 255),
	white = Color3.fromRGB(255, 255, 255),
	dimText = Color3.fromRGB(120, 120, 140),
	localHighlight = Color3.fromRGB(0, 255, 255),
}

local FONT = Enum.Font.GothamBold
local CORNER_RADIUS = UDim.new(0, 4)
local BG_TRANSPARENCY = 0.1

local BOARD_WIDTH = 500
local BOARD_HEIGHT = 400
local HEADER_HEIGHT = 40
local COLUMN_HEADER_HEIGHT = 28
local ROW_HEIGHT = 26

-- Column widths as fractions of the content width
local COLUMNS = {
	{ name = "RANK",   width = 0.12 },
	{ name = "PLAYER", width = 0.40 },
	{ name = "KILLS",  width = 0.16 },
	{ name = "DEATHS", width = 0.16 },
	{ name = "SCORE",  width = 0.16 },
}

-- ============================================================================
-- Module table
-- ============================================================================

local Scoreboard = {}

-- UI references
local screenGui: ScreenGui? = nil
local boardFrame: Frame? = nil
local rowContainer: Frame? = nil

-- Player data: userId -> { name, kills, deaths, score }
local playerData: { [number]: { name: string, kills: number, deaths: number, score: number } } = {}

-- Row instances: userId -> Frame
local rowFrames: { [number]: Frame } = {}

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
-- Sorting & ranking
-- ============================================================================

local function getSortedPlayers(): { { userId: number, name: string, kills: number, deaths: number, score: number } }
	local list = {}
	for userId, data in playerData do
		table.insert(list, {
			userId = userId,
			name = data.name,
			kills = data.kills,
			deaths = data.deaths,
			score = data.score,
		})
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.name < b.name
	end)
	return list
end

-- ============================================================================
-- Row creation
-- ============================================================================

local function createRowFrame(parent: GuiObject, userId: number): Frame
	local row = Instance.new("Frame")
	row.Name = "Row_" .. userId
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = COLORS.bgLight
	row.BackgroundTransparency = 0.6
	row.BorderSizePixel = 0
	row.Parent = parent
	applyCorner(row)

	-- Highlight local player row
	if userId == LocalPlayer.UserId then
		row.BackgroundColor3 = COLORS.localHighlight
		row.BackgroundTransparency = 0.85
	end

	-- Create cell labels
	local xOffset = 0
	for i, col in COLUMNS do
		local label = Instance.new("TextLabel")
		label.Name = col.name
		label.Size = UDim2.new(col.width, 0, 1, 0)
		label.Position = UDim2.new(xOffset, 0, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = FONT
		label.TextSize = 13
		label.TextColor3 = if i == 1 then COLORS.dimText else COLORS.white
		label.TextXAlignment = if i == 2 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
		label.Text = ""
		label.Parent = row
		xOffset += col.width
	end

	return row
end

local function updateRowData(row: Frame, rank: number, data: { name: string, kills: number, deaths: number, score: number })
	local rankLabel = row:FindFirstChild("RANK") :: TextLabel?
	local playerLabel = row:FindFirstChild("PLAYER") :: TextLabel?
	local killsLabel = row:FindFirstChild("KILLS") :: TextLabel?
	local deathsLabel = row:FindFirstChild("DEATHS") :: TextLabel?
	local scoreLabel = row:FindFirstChild("SCORE") :: TextLabel?

	if rankLabel then
		rankLabel.Text = "#" .. rank
	end
	if playerLabel then
		playerLabel.Text = data.name
	end
	if killsLabel then
		killsLabel.Text = tostring(data.kills)
	end
	if deathsLabel then
		deathsLabel.Text = tostring(data.deaths)
	end
	if scoreLabel then
		scoreLabel.Text = tostring(data.score)
		scoreLabel.TextColor3 = COLORS.cyan
	end
end

-- ============================================================================
-- Refresh the entire scoreboard display
-- ============================================================================

local function refreshBoard()
	if not rowContainer then
		return
	end

	local sorted = getSortedPlayers()

	-- Update layout order and data for each row
	for rank, entry in sorted do
		local row = rowFrames[entry.userId]
		if not row then
			row = createRowFrame(rowContainer, entry.userId)
			rowFrames[entry.userId] = row
		end
		row.LayoutOrder = rank
		updateRowData(row, rank, entry)
	end
end

-- ============================================================================
-- Player tracking
-- ============================================================================

local function addPlayer(player: Player)
	if playerData[player.UserId] then
		return
	end
	playerData[player.UserId] = {
		name = player.DisplayName,
		kills = 0,
		deaths = 0,
		score = 0,
	}
end

local function removePlayer(player: Player)
	playerData[player.UserId] = nil
	local row = rowFrames[player.UserId]
	if row then
		row:Destroy()
		rowFrames[player.UserId] = nil
	end
end

-- ============================================================================
-- Build the scoreboard UI
-- ============================================================================

local function buildScoreboard()
	-- ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ScoreboardUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 5
	screenGui.IgnoreGuiInset = false
	screenGui.Enabled = false
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Main board frame (centered)
	boardFrame = Instance.new("Frame")
	boardFrame.Name = "BoardFrame"
	boardFrame.Size = UDim2.new(0, BOARD_WIDTH, 0, BOARD_HEIGHT)
	boardFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	boardFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	boardFrame.BackgroundColor3 = COLORS.bg
	boardFrame.BackgroundTransparency = BG_TRANSPARENCY
	boardFrame.BorderSizePixel = 0
	boardFrame.Parent = screenGui
	applyCorner(boardFrame, UDim.new(0, 8))
	applyStroke(boardFrame, COLORS.cyan, 2)

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, HEADER_HEIGHT)
	title.Position = UDim2.new(0, 10, 0, 6)
	title.BackgroundTransparency = 1
	title.Font = FONT
	title.TextSize = 22
	title.TextColor3 = COLORS.cyan
	title.Text = "SCOREBOARD"
	title.Parent = boardFrame

	-- Column headers
	local headerRow = Instance.new("Frame")
	headerRow.Name = "HeaderRow"
	headerRow.Size = UDim2.new(1, -20, 0, COLUMN_HEADER_HEIGHT)
	headerRow.Position = UDim2.new(0, 10, 0, HEADER_HEIGHT + 8)
	headerRow.BackgroundColor3 = COLORS.bgLight
	headerRow.BackgroundTransparency = 0.4
	headerRow.BorderSizePixel = 0
	headerRow.Parent = boardFrame
	applyCorner(headerRow)

	local xOffset = 0
	for i, col in COLUMNS do
		local label = Instance.new("TextLabel")
		label.Name = "Header_" .. col.name
		label.Size = UDim2.new(col.width, 0, 1, 0)
		label.Position = UDim2.new(xOffset, 0, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = FONT
		label.TextSize = 12
		label.TextColor3 = COLORS.dimText
		label.TextXAlignment = if i == 2 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
		label.Text = col.name
		label.Parent = headerRow
		xOffset += col.width
	end

	-- Scrolling row container
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "RowContainer"
	scrollFrame.Size = UDim2.new(1, -20, 1, -(HEADER_HEIGHT + COLUMN_HEADER_HEIGHT + 24))
	scrollFrame.Position = UDim2.new(0, 10, 0, HEADER_HEIGHT + COLUMN_HEADER_HEIGHT + 16)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLORS.cyan
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = boardFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scrollFrame

	rowContainer = scrollFrame
end

-- ============================================================================
-- Tab key toggle
-- ============================================================================

local function connectInputEvents()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab then
			if screenGui then
				screenGui.Enabled = true
				refreshBoard()
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Tab then
			if screenGui then
				screenGui.Enabled = false
			end
		end
	end)
end

-- ============================================================================
-- Network event handlers
-- ============================================================================

local function connectNetworkEvents()
	-- ScoreUpdate: authoritative data for the local player
	ClientNetwork.onServerEvent(EventNames.ScoreUpdate, function(data: { kills: number, deaths: number, score: number })
		local entry = playerData[LocalPlayer.UserId]
		if entry then
			entry.kills = data.kills
			entry.deaths = data.deaths
			entry.score = data.score
		end
		-- Refresh if visible
		if screenGui and screenGui.Enabled then
			refreshBoard()
		end
	end)

	-- KillOccurred: track kills/deaths for all players from the kill feed
	ClientNetwork.onServerEvent(EventNames.KillOccurred, function(killerName: string, victimName: string)
		-- Find players by DisplayName and increment counts
		for userId, data in playerData do
			if data.name == killerName then
				-- Don't override local player's kills (ScoreUpdate is authoritative)
				if userId ~= LocalPlayer.UserId then
					data.kills += 1
				end
			end
			if data.name == victimName then
				if userId ~= LocalPlayer.UserId then
					data.deaths += 1
				end
			end
		end
		-- Refresh if visible
		if screenGui and screenGui.Enabled then
			refreshBoard()
		end
	end)
end

-- ============================================================================
-- Public API
-- ============================================================================

--[[
	Initialise the Scoreboard UI module. Creates the ScreenGui, populates
	initial player list, and connects input + network events.
]]
function Scoreboard.init()
	-- Build the UI shell
	buildScoreboard()

	-- Populate with current players
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end

	-- Listen for player join/leave
	Players.PlayerAdded:Connect(function(player: Player)
		addPlayer(player)
		if screenGui and screenGui.Enabled then
			refreshBoard()
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		removePlayer(player)
		if screenGui and screenGui.Enabled then
			refreshBoard()
		end
	end)

	-- Connect input and network
	connectInputEvents()
	connectNetworkEvents()

	print("[Scoreboard] Initialised")
end

return Scoreboard

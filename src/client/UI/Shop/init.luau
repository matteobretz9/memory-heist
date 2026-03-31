--[[
	Shop — Client-side cosmetics shop UI.

	Opened/closed with the B key. Full-screen overlay with category tabs
	(Weapon Skins, Kill Effects) and a grid of purchasable items.

	Visual style matches the cyberpunk HUD: dark backgrounds, neon cyan
	accents, GothamBold font, UICorner 4px, UIStroke borders.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CosmeticsData = require(Shared:WaitForChild("Data"):WaitForChild("CosmeticsData"))
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
	green = Color3.fromRGB(0, 230, 100),
	gold = Color3.fromRGB(255, 200, 0),
	red = Color3.fromRGB(255, 60, 60),
	buttonHover = Color3.fromRGB(30, 30, 60),
}

local FONT = Enum.Font.GothamBold
local FONT_REGULAR = Enum.Font.Gotham
local CORNER_RADIUS = UDim.new(0, 4)
local BG_TRANSPARENCY = 0.3

-- Grid layout
local CARD_WIDTH = 120
local CARD_HEIGHT = 140
local CARD_GAP = 8
local CARDS_PER_ROW = 4

-- Category definitions (display name -> data key)
local CATEGORIES = {
	{ display = "Weapon Skins", key = "WeaponSkins" },
	{ display = "Kill Effects", key = "KillEffects" },
}

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local Shop = {}

-- UI references
local screenGui: ScreenGui? = nil
local contentFrame: Frame? = nil
local tabButtons: { [string]: TextButton } = {}

-- State
local isVisible = false
local activeCategory: string = "WeaponSkins"
local ownedItems: { [string]: { [string]: boolean } } = {}
local equippedItems = {
	weaponSkin = nil :: string?,
	killEffect = nil :: string?,
}

-- Category to equipped-field mapping (mirrors server)
local CATEGORY_TO_EQUIP_KEY: { [string]: string } = {
	WeaponSkins = "weaponSkin",
	KillEffects = "killEffect",
}

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

local function getRarityColor(rarity: string): Color3
	local info = RarityData[rarity]
	return if info then info.color else COLORS.dimText
end

local function isOwned(category: string, itemId: string): boolean
	local categoryOwned = ownedItems[category]
	if not categoryOwned then
		return false
	end
	return categoryOwned[itemId] == true
end

local function isEquipped(category: string, itemId: string): boolean
	local equipKey = CATEGORY_TO_EQUIP_KEY[category]
	if not equipKey then
		return false
	end
	return equippedItems[equipKey] == itemId
end

---------------------------------------------------------------------------
-- Build the item grid for the active category
---------------------------------------------------------------------------

local function clearContent()
	if contentFrame then
		for _, child in contentFrame:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
end

local function buildItemGrid()
	clearContent()
	if not contentFrame then
		return
	end

	local categoryData = CosmeticsData[activeCategory]
	if not categoryData then
		return
	end

	-- Update tab highlight
	for key, btn in tabButtons do
		if key == activeCategory then
			btn.BackgroundColor3 = COLORS.cyan
			btn.TextColor3 = COLORS.bg
			btn.BackgroundTransparency = 0.1
		else
			btn.BackgroundColor3 = COLORS.bgLight
			btn.TextColor3 = COLORS.cyan
			btn.BackgroundTransparency = BG_TRANSPARENCY
		end
	end

	-- Scrolling frame for the grid
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemGrid"
	scrollFrame.Size = UDim2.new(1, 0, 1, 0)
	scrollFrame.Position = UDim2.new(0, 0, 0, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLORS.cyan
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = contentFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT)
	gridLayout.CellPadding = UDim2.new(0, CARD_GAP, 0, CARD_GAP)
	gridLayout.FillDirection = Enum.FillDirection.Horizontal
	gridLayout.FillDirectionMaxCells = CARDS_PER_ROW
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scrollFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingTop = UDim.new(0, 4)
	padding.Parent = scrollFrame

	-- Build cards
	local layoutOrder = 0
	for itemId, itemDef in categoryData do
		layoutOrder += 1

		local owned = isOwned(activeCategory, itemId)
		local equipped = isEquipped(activeCategory, itemId)
		local rarityColor = getRarityColor(itemDef.rarity)

		-- Card frame
		local card = Instance.new("Frame")
		card.Name = itemId
		card.Size = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT)
		card.BackgroundColor3 = COLORS.bg
		card.BackgroundTransparency = 0.15
		card.BorderSizePixel = 0
		card.LayoutOrder = layoutOrder
		card.Parent = scrollFrame
		applyCorner(card, UDim.new(0, 6))
		applyStroke(card, rarityColor, 1)

		-- Item name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "ItemName"
		nameLabel.Size = UDim2.new(1, -8, 0, 32)
		nameLabel.Position = UDim2.new(0, 4, 0, 6)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = FONT
		nameLabel.TextSize = 12
		nameLabel.TextColor3 = COLORS.white
		nameLabel.TextWrapped = true
		nameLabel.TextYAlignment = Enum.TextYAlignment.Top
		nameLabel.Text = itemDef.name
		nameLabel.Parent = card

		-- Rarity label
		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.Name = "Rarity"
		rarityLabel.Size = UDim2.new(1, -8, 0, 14)
		rarityLabel.Position = UDim2.new(0, 4, 0, 40)
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.Font = FONT_REGULAR
		rarityLabel.TextSize = 10
		rarityLabel.TextColor3 = rarityColor
		rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
		rarityLabel.Text = itemDef.rarity
		rarityLabel.Parent = card

		-- Description
		local descLabel = Instance.new("TextLabel")
		descLabel.Name = "Description"
		descLabel.Size = UDim2.new(1, -8, 0, 24)
		descLabel.Position = UDim2.new(0, 4, 0, 56)
		descLabel.BackgroundTransparency = 1
		descLabel.Font = FONT_REGULAR
		descLabel.TextSize = 9
		descLabel.TextColor3 = COLORS.dimText
		descLabel.TextWrapped = true
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Text = itemDef.description
		descLabel.Parent = card

		-- Price line
		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "Price"
		priceLabel.Size = UDim2.new(1, -8, 0, 14)
		priceLabel.Position = UDim2.new(0, 4, 0, 82)
		priceLabel.BackgroundTransparency = 1
		priceLabel.Font = FONT
		priceLabel.TextSize = 11
		priceLabel.TextColor3 = COLORS.gold
		priceLabel.TextXAlignment = Enum.TextXAlignment.Left
		priceLabel.Text = tostring(itemDef.price) .. " credits"
		priceLabel.Parent = card

		-- Action button
		local actionBtn = Instance.new("TextButton")
		actionBtn.Name = "ActionBtn"
		actionBtn.Size = UDim2.new(1, -12, 0, 26)
		actionBtn.Position = UDim2.new(0, 6, 1, -32)
		actionBtn.BorderSizePixel = 0
		actionBtn.Font = FONT
		actionBtn.TextSize = 12
		actionBtn.AutoButtonColor = false
		actionBtn.Parent = card
		applyCorner(actionBtn)

		if equipped then
			-- Equipped state
			actionBtn.Text = "EQUIPPED"
			actionBtn.BackgroundColor3 = COLORS.gold
			actionBtn.BackgroundTransparency = 0.2
			actionBtn.TextColor3 = COLORS.bg
			applyStroke(actionBtn, COLORS.gold, 1)
		elseif owned then
			-- Owned but not equipped
			actionBtn.Text = "EQUIP"
			actionBtn.BackgroundColor3 = COLORS.green
			actionBtn.BackgroundTransparency = 0.3
			actionBtn.TextColor3 = COLORS.white
			applyStroke(actionBtn, COLORS.green, 1)
		else
			-- Not owned — show BUY
			actionBtn.Text = "BUY"
			actionBtn.BackgroundColor3 = COLORS.bgLight
			actionBtn.BackgroundTransparency = BG_TRANSPARENCY
			actionBtn.TextColor3 = COLORS.cyan
			applyStroke(actionBtn, COLORS.cyan, 1)
		end

		-- Hover feedback
		local defaultBg = actionBtn.BackgroundColor3
		local defaultTransparency = actionBtn.BackgroundTransparency
		actionBtn.MouseEnter:Connect(function()
			actionBtn.BackgroundTransparency = math.max(defaultTransparency - 0.15, 0)
		end)
		actionBtn.MouseLeave:Connect(function()
			actionBtn.BackgroundColor3 = defaultBg
			actionBtn.BackgroundTransparency = defaultTransparency
		end)

		-- Click handler
		local capturedCategory = activeCategory
		local capturedItemId = itemId
		actionBtn.MouseButton1Click:Connect(function()
			if isEquipped(capturedCategory, capturedItemId) then
				-- Already equipped, toggle unequip by re-equipping (server toggles)
				ClientNetwork.fireServer(EventNames.CosmeticEquipRequest, {
					category = capturedCategory,
					itemId = capturedItemId,
				})
			elseif isOwned(capturedCategory, capturedItemId) then
				-- Owned — equip it
				ClientNetwork.fireServer(EventNames.CosmeticEquipRequest, {
					category = capturedCategory,
					itemId = capturedItemId,
				})
			else
				-- Not owned — purchase
				ClientNetwork.fireServer(EventNames.CosmeticPurchaseRequest, {
					category = capturedCategory,
					itemId = capturedItemId,
				})
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Build the shop UI (created once in init)
---------------------------------------------------------------------------

local function buildShopUI()
	-- ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CosmeticsShopUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 15 -- above HUD and other modals
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
	local panelWidth = CARDS_PER_ROW * CARD_WIDTH + (CARDS_PER_ROW - 1) * CARD_GAP + 48
	local panelHeight = 480

	local mainPanel = Instance.new("Frame")
	mainPanel.Name = "MainPanel"
	mainPanel.Size = UDim2.new(0, panelWidth, 0, panelHeight)
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
	title.Text = "COSMETICS SHOP"
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
		Shop.hide()
	end)

	-- Category tabs
	local tabContainer = Instance.new("Frame")
	tabContainer.Name = "Tabs"
	tabContainer.Size = UDim2.new(1, -32, 0, 30)
	tabContainer.Position = UDim2.new(0, 16, 0, 48)
	tabContainer.BackgroundTransparency = 1
	tabContainer.BorderSizePixel = 0
	tabContainer.ZIndex = 3
	tabContainer.Parent = mainPanel

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabContainer

	for i, cat in CATEGORIES do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. cat.key
		tabBtn.Size = UDim2.new(0, 130, 0, 28)
		tabBtn.BackgroundColor3 = COLORS.bgLight
		tabBtn.BackgroundTransparency = BG_TRANSPARENCY
		tabBtn.BorderSizePixel = 0
		tabBtn.Font = FONT
		tabBtn.TextSize = 13
		tabBtn.TextColor3 = COLORS.cyan
		tabBtn.Text = cat.display
		tabBtn.AutoButtonColor = false
		tabBtn.LayoutOrder = i
		tabBtn.ZIndex = 4
		tabBtn.Parent = tabContainer
		applyCorner(tabBtn)
		applyStroke(tabBtn, COLORS.cyan, 1)

		tabButtons[cat.key] = tabBtn

		tabBtn.MouseEnter:Connect(function()
			if activeCategory ~= cat.key then
				tabBtn.BackgroundTransparency = 0.15
			end
		end)
		tabBtn.MouseLeave:Connect(function()
			if activeCategory ~= cat.key then
				tabBtn.BackgroundTransparency = BG_TRANSPARENCY
			end
		end)
		tabBtn.MouseButton1Click:Connect(function()
			activeCategory = cat.key
			buildItemGrid()
		end)
	end

	-- Content area (below tabs)
	contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, -32, 1, -92)
	contentFrame.Position = UDim2.new(0, 16, 0, 84)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.ClipsDescendants = true
	contentFrame.ZIndex = 3
	contentFrame.Parent = mainPanel
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function Shop.show()
	if isVisible then
		return
	end
	isVisible = true

	-- Request fresh data from server
	ClientNetwork.fireServer(EventNames.ShopDataSync)

	if screenGui then
		screenGui.Enabled = true
	end

	buildItemGrid()
end

function Shop.hide()
	if not isVisible then
		return
	end
	isVisible = false

	if screenGui then
		screenGui.Enabled = false
	end
end

function Shop.toggle()
	if isVisible then
		Shop.hide()
	else
		Shop.show()
	end
end

function Shop.isVisible(): boolean
	return isVisible
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function Shop.init()
	-- Build the shop shell
	buildShopUI()

	-- B key to toggle the shop
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.B then
			Shop.toggle()
		end
	end)

	-- Listen for purchase confirmation from server
	ClientNetwork.onServerEvent(EventNames.CosmeticPurchased, function(data: any)
		if type(data) ~= "table" then
			return
		end
		local category = data.category
		local itemId = data.itemId

		-- Update local owned state
		if not ownedItems[category] then
			ownedItems[category] = {}
		end
		ownedItems[category][itemId] = true

		-- Refresh grid if the shop is open and showing this category
		if isVisible and activeCategory == category then
			buildItemGrid()
		end
	end)

	-- Listen for equip confirmation from server
	ClientNetwork.onServerEvent(EventNames.CosmeticEquipped, function(data: any)
		if type(data) ~= "table" then
			return
		end

		-- Update local equipped state from server's authoritative copy
		if data.equipped then
			equippedItems.weaponSkin = data.equipped.weaponSkin
			equippedItems.killEffect = data.equipped.killEffect
		end

		-- Refresh grid if the shop is open
		if isVisible then
			buildItemGrid()
		end
	end)

	-- Listen for full shop data sync from server
	ClientNetwork.onServerEvent(EventNames.ShopDataSync, function(data: any)
		if type(data) ~= "table" then
			return
		end

		if data.ownedItems then
			ownedItems = data.ownedItems
		end

		if data.equipped then
			equippedItems.weaponSkin = data.equipped.weaponSkin
			equippedItems.killEffect = data.equipped.killEffect
		end

		-- Refresh grid if the shop is open
		if isVisible then
			buildItemGrid()
		end
	end)

	print("[Shop] Initialised")
end

return Shop

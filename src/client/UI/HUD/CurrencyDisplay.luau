--[[
	CurrencyDisplay — Small HUD element showing the player's credit balance.

	Positioned on the left side below the chatbox area.
	Shows a coin icon + amount. Flashes green/red on changes.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventNames = require(Shared:WaitForChild("Network"):WaitForChild("EventNames"))
local ClientNetwork = require(script.Parent.Parent.Parent:WaitForChild("Network"))

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------------
-- Style constants
---------------------------------------------------------------------------

local COLORS = {
	bg = Color3.fromRGB(10, 10, 20),
	purple = Color3.fromRGB(180, 80, 255),
	white = Color3.fromRGB(255, 255, 255),
	green = Color3.fromRGB(0, 230, 100),
	red = Color3.fromRGB(230, 40, 40),
}

local FONT = Enum.Font.GothamBold
local BG_TRANSPARENCY = 0.4

-- TODO: Upload your coin.png to Roblox and replace this ID
local COIN_IMAGE = "rbxassetid://6031091005"

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------

local CurrencyDisplay = {}

local amountLabel: TextLabel? = nil
local lastCredits: number? = nil

---------------------------------------------------------------------------
-- Flash animation
---------------------------------------------------------------------------

local function flashColor(label: TextLabel, color: Color3)
	label.TextColor3 = color
	local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, tweenInfo, { TextColor3 = COLORS.white }):Play()
end

---------------------------------------------------------------------------
-- Update handler
---------------------------------------------------------------------------

local function onCurrencyUpdate(newBalance: number)
	if not amountLabel then
		return
	end

	amountLabel.Text = tostring(newBalance)

	if lastCredits ~= nil then
		if newBalance > lastCredits then
			flashColor(amountLabel, COLORS.green)
		elseif newBalance < lastCredits then
			flashColor(amountLabel, COLORS.red)
		end
	end

	lastCredits = newBalance
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function CurrencyDisplay.init()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("MemoryHeistHUD")

	-- Container: left side, below chat area (~top-left)
	local frame = Instance.new("Frame")
	frame.Name = "CurrencyDisplay"
	frame.Size = UDim2.new(0, 130, 0, 36)
	frame.Position = UDim2.new(0, 10, 0.35, 0)
	frame.BackgroundColor3 = COLORS.bg
	frame.BackgroundTransparency = BG_TRANSPARENCY
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.purple
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	-- Coin icon (left side)
	local coinIcon = Instance.new("ImageLabel")
	coinIcon.Name = "CoinIcon"
	coinIcon.Size = UDim2.new(0, 28, 0, 28)
	coinIcon.Position = UDim2.new(0, 4, 0.5, 0)
	coinIcon.AnchorPoint = Vector2.new(0, 0.5)
	coinIcon.BackgroundTransparency = 1
	coinIcon.Image = COIN_IMAGE
	coinIcon.ScaleType = Enum.ScaleType.Fit
	coinIcon.Parent = frame

	-- Amount label (right of icon)
	local label = Instance.new("TextLabel")
	label.Name = "AmountLabel"
	label.Size = UDim2.new(1, -38, 1, 0)
	label.Position = UDim2.new(0, 36, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = 16
	label.TextColor3 = COLORS.white
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "---"
	label.Parent = frame

	amountLabel = label

	-- Shop button — same size as currency bar, green glitching cart
	local shopBtn = Instance.new("TextButton")
	shopBtn.Name = "ShopButton"
	shopBtn.Size = UDim2.new(0, 130, 0, 36)
	shopBtn.Position = UDim2.new(0, 10, 0.35, 44)
	shopBtn.BackgroundColor3 = COLORS.bg
	shopBtn.BackgroundTransparency = BG_TRANSPARENCY
	shopBtn.BorderSizePixel = 0
	shopBtn.Text = ""
	shopBtn.AutoButtonColor = false
	shopBtn.Parent = screenGui

	local shopCorner = Instance.new("UICorner")
	shopCorner.CornerRadius = UDim.new(0, 6)
	shopCorner.Parent = shopBtn

	local shopStroke = Instance.new("UIStroke")
	shopStroke.Color = Color3.fromRGB(0, 220, 80)
	shopStroke.Thickness = 1
	shopStroke.Transparency = 0.3
	shopStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	shopStroke.Parent = shopBtn

	-- Cart icon (text-based shopping cart)
	local cartLabel = Instance.new("TextLabel")
	cartLabel.Name = "CartIcon"
	cartLabel.Size = UDim2.new(0, 30, 0, 30)
	cartLabel.Position = UDim2.new(0, 6, 0.5, 0)
	cartLabel.AnchorPoint = Vector2.new(0, 0.5)
	cartLabel.BackgroundTransparency = 1
	cartLabel.Font = Enum.Font.GothamBold
	cartLabel.TextSize = 20
	cartLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
	cartLabel.Text = "\u{1F6D2}"
	cartLabel.Parent = shopBtn

	-- "SHOP" label
	local shopLabel = Instance.new("TextLabel")
	shopLabel.Name = "ShopLabel"
	shopLabel.Size = UDim2.new(1, -40, 1, 0)
	shopLabel.Position = UDim2.new(0, 38, 0, 0)
	shopLabel.BackgroundTransparency = 1
	shopLabel.Font = FONT
	shopLabel.TextSize = 15
	shopLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
	shopLabel.TextXAlignment = Enum.TextXAlignment.Left
	shopLabel.Text = "SHOP"
	shopLabel.Parent = shopBtn

	-- Glitch effect: randomly offset the cart icon
	local glitchActive = true
	task.spawn(function()
		while glitchActive do
			-- Quick glitch frame
			local offsetX = math.random(-2, 2)
			local offsetY = math.random(-1, 1)
			cartLabel.Position = UDim2.new(0, 6 + offsetX, 0.5, offsetY)
			cartLabel.TextColor3 = Color3.fromRGB(
				math.random(0, 40),
				math.random(200, 255),
				math.random(60, 130)
			)
			task.wait(0.08)

			-- Settle back
			cartLabel.Position = UDim2.new(0, 6, 0.5, 0)
			cartLabel.TextColor3 = Color3.fromRGB(0, 255, 100)

			-- Wait before next glitch (random interval)
			task.wait(math.random() * 1.5 + 0.5)
		end
	end)

	shopBtn.MouseEnter:Connect(function()
		shopBtn.BackgroundTransparency = 0.1
		shopStroke.Transparency = 0
		shopStroke.Color = Color3.fromRGB(0, 255, 120)
		shopLabel.TextColor3 = COLORS.white
	end)
	shopBtn.MouseLeave:Connect(function()
		shopBtn.BackgroundTransparency = BG_TRANSPARENCY
		shopStroke.Transparency = 0.3
		shopStroke.Color = Color3.fromRGB(0, 220, 80)
		shopLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
	end)

	shopBtn.MouseButton1Click:Connect(function()
		local ok, err = pcall(function()
			local ShopUI = require(script.Parent.Parent.Shop)
			ShopUI.toggle()
		end)
		if not ok then
			warn("[CurrencyDisplay] Shop button error:", err)
		end
	end)

	ClientNetwork.onServerEvent(EventNames.CurrencyUpdate, onCurrencyUpdate)
end

return CurrencyDisplay

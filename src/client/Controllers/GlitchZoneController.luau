--[[
	GlitchZoneController — Client-side Glitch Zone notifications.

	Listens for GlitchZoneEnter / GlitchZoneExit events from the server
	and displays brief notification text at the top of the screen with
	the zone name and color.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventNames = require(Shared:WaitForChild("Network"):WaitForChild("EventNames"))
local ClientNetwork = require(script.Parent.Parent:WaitForChild("Network"))

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------------
-- Style
---------------------------------------------------------------------------

local FONT = Enum.Font.GothamBold
local TEXT_SIZE = 22
local DISPLAY_DURATION = 2 -- seconds the notification is visible
local FADE_IN_TIME = 0.2
local FADE_OUT_TIME = 0.5

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local screenGui: ScreenGui? = nil
local activeLabel: TextLabel? = nil
local activeTween: Tween? = nil

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local GlitchZoneController = {}

---------------------------------------------------------------------------
-- UI creation
---------------------------------------------------------------------------

local function ensureScreenGui(): ScreenGui
	if screenGui and screenGui.Parent then
		return screenGui
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "GlitchZoneNotifications"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	screenGui = gui
	return gui
end

--- Show a notification at the top of the screen.
--- @param text string  The text to display (e.g. "ENTERED SPEED ZONE")
--- @param color Color3 The color for the text
local function showNotification(text: string, color: Color3)
	local gui = ensureScreenGui()

	-- Cancel any existing notification
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	if activeLabel and activeLabel.Parent then
		activeLabel:Destroy()
	end

	-- Create the label
	local label = Instance.new("TextLabel")
	label.Name = "ZoneNotification"
	label.Size = UDim2.new(1, 0, 0, 50)
	label.Position = UDim2.new(0, 0, 0, 40)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = TEXT_SIZE
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.TextTransparency = 1 -- start invisible for fade-in
	label.ZIndex = 10
	label.Parent = gui

	activeLabel = label

	-- Fade in
	local fadeInInfo = TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeIn = TweenService:Create(label, fadeInInfo, { TextTransparency = 0 })
	fadeIn:Play()

	-- After display duration, fade out and destroy
	task.delay(DISPLAY_DURATION, function()
		if not label or not label.Parent then
			return
		end

		local fadeOutInfo = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeOut = TweenService:Create(label, fadeOutInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		activeTween = fadeOut
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if label and label.Parent then
				label:Destroy()
			end
			if activeLabel == label then
				activeLabel = nil
			end
			if activeTween == fadeOut then
				activeTween = nil
			end
		end)
	end)
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------

local function onZoneEnter(data: { zoneType: string, name: string, color: { number } })
	local color = Color3.new(data.color[1], data.color[2], data.color[3])
	local text = "ENTERED " .. string.upper(data.name)
	showNotification(text, color)
end

local function onZoneExit(data: { zoneType: string, name: string, color: { number } })
	local color = Color3.new(data.color[1], data.color[2], data.color[3])
	local text = "LEFT " .. string.upper(data.name)
	showNotification(text, color)
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function GlitchZoneController.init()
	ClientNetwork.onServerEvent(EventNames.GlitchZoneEnter, onZoneEnter)
	ClientNetwork.onServerEvent(EventNames.GlitchZoneExit, onZoneExit)

	print("[GlitchZoneController] Initialised")
end

return GlitchZoneController

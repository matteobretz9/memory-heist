--[[
	OverloadController — Client-side visual effects for memory overload.

	Listens for OverloadUpdate from the server and applies escalating
	screen distortion effects based on the player's current overload tier:
	  - ColorCorrectionEffect (desaturation + purple/red tint)
	  - BlurEffect
	  - Static/noise overlay (flickering semi-transparent Frame)
	  - Camera shake (small random CFrame offsets each render frame)
	  - Brief red flash when an ability is locked

	All effects scale with screenGlitchIntensity from OverloadData.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local OverloadData = require(Shared.Data.OverloadData)
local EventNames = require(Shared.Network.EventNames)
local ClientNetwork = require(script.Parent.Parent.Network)

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local currentTier: number = 0
local currentIntensity: number = 0 -- screenGlitchIntensity for the active tier

-- Effect instances (created lazily, destroyed on cleanup)
local colorCorrection: ColorCorrectionEffect? = nil
local blurEffect: BlurEffect? = nil
local screenGui: ScreenGui? = nil
local staticFrame: Frame? = nil
local flashFrame: Frame? = nil

-- Connections
local heartbeatConn: RBXScriptConnection? = nil -- static flicker
local renderStepConn: RBXScriptConnection? = nil -- camera shake

-- Camera shake bookkeeping: we apply an offset and undo it next frame
local lastShakeOffset: CFrame = CFrame.new()

-- Frame counter for static flicker (we don't need to change every frame)
local flickerCounter: number = 0

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Find the tier data entry for a given tier number.
local function getTierData(tier: number): { [string]: any }?
	for _, entry in OverloadData.tiers do
		if entry.tier == tier then
			return entry
		end
	end
	return nil
end

local camera = workspace.CurrentCamera

---------------------------------------------------------------------------
-- Effect creation / destruction
---------------------------------------------------------------------------

--- Create all Lighting and GUI effect instances (idempotent).
local function ensureEffectsCreated()
	-- ColorCorrectionEffect
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "OverloadColorCorrection"
		colorCorrection.Parent = Lighting
	end

	-- BlurEffect
	if not blurEffect then
		blurEffect = Instance.new("BlurEffect")
		blurEffect.Name = "OverloadBlur"
		blurEffect.Size = 0
		blurEffect.Parent = Lighting
	end

	-- ScreenGui for static overlay and flash
	if not screenGui then
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui")

		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "OverloadEffects"
		screenGui.IgnoreGuiInset = true
		screenGui.DisplayOrder = 100 -- render above most UI
		screenGui.ResetOnSpawn = true
		screenGui.Parent = playerGui
	end

	-- Static noise overlay: a full-screen Frame with dark background
	-- that flickers in transparency to simulate digital static
	if not staticFrame then
		staticFrame = Instance.new("Frame")
		staticFrame.Name = "StaticOverlay"
		staticFrame.Size = UDim2.new(1, 0, 1, 0)
		staticFrame.Position = UDim2.new(0, 0, 0, 0)
		staticFrame.BackgroundColor3 = Color3.fromRGB(40, 10, 50) -- dark purple
		staticFrame.BackgroundTransparency = 0.95
		staticFrame.BorderSizePixel = 0
		staticFrame.ZIndex = 10
		staticFrame.Parent = screenGui
	end

	-- Flash overlay for ability-locked events (brief red flash)
	if not flashFrame then
		flashFrame = Instance.new("Frame")
		flashFrame.Name = "LockFlash"
		flashFrame.Size = UDim2.new(1, 0, 1, 0)
		flashFrame.Position = UDim2.new(0, 0, 0, 0)
		flashFrame.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
		flashFrame.BackgroundTransparency = 1 -- invisible by default
		flashFrame.BorderSizePixel = 0
		flashFrame.ZIndex = 11
		flashFrame.Parent = screenGui
	end
end

--- Remove all effect instances and disconnect loops.
local function destroyEffects()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end

	if renderStepConn then
		renderStepConn:Disconnect()
		renderStepConn = nil
	end

	-- Undo any lingering camera offset
	if camera then
		camera.CFrame = camera.CFrame * lastShakeOffset:Inverse()
	end
	lastShakeOffset = CFrame.new()

	if colorCorrection then
		colorCorrection:Destroy()
		colorCorrection = nil
	end

	if blurEffect then
		blurEffect:Destroy()
		blurEffect = nil
	end

	if screenGui then
		screenGui:Destroy()
		screenGui = nil
		staticFrame = nil -- children destroyed with parent
		flashFrame = nil
	end
end

---------------------------------------------------------------------------
-- Effect application
---------------------------------------------------------------------------

--- Start or update the per-frame loops that drive dynamic effects.
local function startEffectLoops(intensity: number, tier: number)
	-- Disconnect old connections so we don't stack them
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	if renderStepConn then
		renderStepConn:Disconnect()
		renderStepConn = nil
	end

	-- Reset shake offset before starting fresh
	lastShakeOffset = CFrame.new()
	flickerCounter = 0

	-- Static flicker: toggle the overlay transparency every few frames
	heartbeatConn = RunService.Heartbeat:Connect(function()
		flickerCounter += 1

		-- Only update every 3 frames to create a stuttery static look
		if flickerCounter % 3 == 0 and staticFrame then
			-- Flicker between 0.85 and 0.95 transparency, scaled by intensity
			-- Higher intensity = more visible (lower transparency)
			local baseMin = 0.85
			local baseMax = 0.95
			-- Shift the range downward (more opaque) as intensity increases
			local minT = baseMin - (0.15 * intensity)
			local maxT = baseMax - (0.10 * intensity)
			staticFrame.BackgroundTransparency = minT + math.random() * (maxT - minT)
		end
	end)

	-- Camera shake: apply small random CFrame offsets each render frame
	renderStepConn = RunService.RenderStepped:Connect(function()
		camera = workspace.CurrentCamera
		if not camera then
			return
		end

		-- Undo the previous frame's offset first
		camera.CFrame = camera.CFrame * lastShakeOffset:Inverse()

		-- Calculate new shake magnitude scaled by intensity and tier
		local shakeMagnitude = 0.05 * intensity * tier
		local rx = (math.random() - 0.5) * 2 * shakeMagnitude
		local ry = (math.random() - 0.5) * 2 * shakeMagnitude
		local rz = (math.random() - 0.5) * 2 * shakeMagnitude * 0.5 -- less Z shake

		lastShakeOffset = CFrame.new(rx, ry, rz)
		camera.CFrame = camera.CFrame * lastShakeOffset
	end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

local OverloadController = {}

--- Apply (or remove) overload visual effects for the given tier.
function OverloadController.setOverloadTier(tier: number)
	-- Early out if nothing changed
	if tier == currentTier then
		return
	end

	currentTier = tier

	if tier <= 0 then
		-- Remove all effects
		OverloadController.cleanup()
		return
	end

	-- Look up intensity from tier data
	local tierData = getTierData(tier)
	if not tierData then
		-- Unknown tier, treat as max intensity
		currentIntensity = 1.0
	else
		currentIntensity = tierData.screenGlitchIntensity
	end

	-- Make sure all effect instances exist
	ensureEffectsCreated()

	-- Color correction: desaturate and tint toward purple/red
	if colorCorrection then
		-- Saturation goes negative (desaturated) — -0.2 per tier
		colorCorrection.Saturation = -0.2 * tier
		-- Tint toward a purple-red hue, intensity-scaled
		local tintR = 1.0
		local tintG = 1.0 - (0.08 * currentIntensity)
		local tintB = 1.0 - (0.04 * currentIntensity)
		colorCorrection.TintColor = Color3.new(tintR, tintG, tintB)
	end

	-- Blur: increases with tier
	if blurEffect then
		blurEffect.Size = 2 * tier
	end

	-- Start/restart the dynamic effect loops
	startEffectLoops(currentIntensity, tier)
end

--- Remove all overload effects and reset state.
function OverloadController.cleanup()
	currentTier = 0
	currentIntensity = 0
	destroyEffects()
end

--- Flash the screen briefly red when an ability gets locked.
local function flashAbilityLocked()
	if not flashFrame then
		return
	end

	-- Quick flash: fade in then fade out over ~0.3 seconds
	flashFrame.BackgroundTransparency = 0.6
	task.spawn(function()
		-- Simple linear fade-out over 6 steps
		for i = 1, 6 do
			task.wait(0.05)
			if flashFrame then
				flashFrame.BackgroundTransparency = 0.6 + (0.4 * (i / 6))
			end
		end
		-- Ensure fully invisible
		if flashFrame then
			flashFrame.BackgroundTransparency = 1
		end
	end)
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function OverloadController.init()
	-- Listen for overload tier updates from the server
	ClientNetwork.onServerEvent(EventNames.OverloadUpdate, function(tier: number)
		OverloadController.setOverloadTier(tier)
	end)

	-- Listen for ability lock/unlock events
	ClientNetwork.onServerEvent(EventNames.AbilityLocked, function(
		slotIndex: number,
		locked: boolean,
		_duration: number
	)
		-- Flash the screen when an ability is locked
		if locked then
			-- Ensure effects GUI exists so we can flash
			if currentTier > 0 then
				ensureEffectsCreated()
			end
			flashAbilityLocked()
		end
	end)

	-- Clean up effects when the character dies or respawns
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function()
		-- New character = new life, server will send a fresh OverloadUpdate
		OverloadController.cleanup()
	end)

	print("[OverloadController] Initialised")
end

return OverloadController

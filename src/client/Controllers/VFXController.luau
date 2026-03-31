--[[
	VFXController — Client-side visual effects polish for Memory Heist.

	Provides hit markers, floating damage numbers, muzzle flash,
	kill screen flash, low-health vignette, and ability activation flash.

	All effects are temporary and self-cleaning (Destroy after duration).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local EventNames = require(Shared.Network.EventNames)
local ClientNetwork = require(script.Parent.Parent.Network)
local WeaponData = require(Shared.Data.WeaponData)
local AbilityData = require(Shared.Data.AbilityData)
local RarityData = require(Shared.Data.RarityData)

local LocalPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local VFXController = {}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

-- Hit marker ScreenGui (persistent, reused)
local vfxScreenGui: ScreenGui? = nil

-- Hit marker elements (4 lines forming an X)
local hitMarkerLines: { Frame } = {}

-- Low health vignette state
local vignetteFrame: Frame? = nil
local vignetteEdges: { Frame } = {}
local vignetteTween: Tween? = nil
local vignetteActive: boolean = false
local healthConnection: RBXScriptConnection? = nil

-- Kill flash frame
local killFlashFrame: Frame? = nil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function getPlayerGui(): PlayerGui?
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function ensureScreenGui(): ScreenGui?
	if vfxScreenGui and vfxScreenGui.Parent then
		return vfxScreenGui
	end

	local playerGui = getPlayerGui()
	if not playerGui then
		return nil
	end

	vfxScreenGui = Instance.new("ScreenGui")
	vfxScreenGui.Name = "VFXEffects"
	vfxScreenGui.IgnoreGuiInset = true
	vfxScreenGui.DisplayOrder = 90
	vfxScreenGui.ResetOnSpawn = true
	vfxScreenGui.Parent = playerGui

	return vfxScreenGui
end

---------------------------------------------------------------------------
-- 1. Hit Markers
---------------------------------------------------------------------------

local HIT_MARKER_SIZE = 16 -- length of each line in pixels
local HIT_MARKER_THICKNESS = 2
local HIT_MARKER_OFFSET = 6 -- gap from center

local function createHitMarkerLines(parent: ScreenGui)
	-- Remove old lines
	for _, line in hitMarkerLines do
		if line and line.Parent then
			line:Destroy()
		end
	end
	hitMarkerLines = {}

	-- 4 lines forming an X pattern at screen center
	-- Each line is a thin Frame rotated 45 or -45 degrees, offset from center
	local configs = {
		-- top-left arm of X
		{ rotation = 45, offsetX = -HIT_MARKER_OFFSET, offsetY = -HIT_MARKER_OFFSET },
		-- top-right arm of X
		{ rotation = -45, offsetX = HIT_MARKER_OFFSET, offsetY = -HIT_MARKER_OFFSET },
		-- bottom-left arm of X
		{ rotation = -45, offsetX = -HIT_MARKER_OFFSET, offsetY = HIT_MARKER_OFFSET },
		-- bottom-right arm of X
		{ rotation = 45, offsetX = HIT_MARKER_OFFSET, offsetY = HIT_MARKER_OFFSET },
	}

	for _, cfg in configs do
		local line = Instance.new("Frame")
		line.Name = "HitMarkerLine"
		line.Size = UDim2.new(0, HIT_MARKER_SIZE, 0, HIT_MARKER_THICKNESS)
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.new(0.5, cfg.offsetX, 0.5, cfg.offsetY)
		line.Rotation = cfg.rotation
		line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		line.BackgroundTransparency = 1 -- hidden by default
		line.BorderSizePixel = 0
		line.ZIndex = 20
		line.Parent = parent

		table.insert(hitMarkerLines, line)
	end
end

local function showHitMarker()
	local gui = ensureScreenGui()
	if not gui then
		return
	end

	-- Ensure lines exist
	if #hitMarkerLines == 0 then
		createHitMarkerLines(gui)
	end

	-- Show instantly, then fade out over 0.3s
	for _, line in hitMarkerLines do
		-- Cancel any existing tweens on this line
		line.BackgroundTransparency = 0

		local fadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(line, fadeInfo, {
			BackgroundTransparency = 1,
		})
		tween:Play()
	end
end

---------------------------------------------------------------------------
-- 2. Damage Numbers
---------------------------------------------------------------------------

local function showDamageNumber(damage: number, worldPosition: Vector3, isCritical: boolean?)
	-- Determine color based on damage amount and crit status
	local color: Color3
	if isCritical then
		color = Color3.fromRGB(255, 60, 60) -- red for critical
	elseif damage > 30 then
		color = Color3.fromRGB(255, 220, 50) -- yellow for high damage
	else
		color = Color3.fromRGB(255, 255, 255) -- white for normal
	end

	-- Create a Part at the hit position to attach a BillboardGui
	local part = Instance.new("Part")
	part.Name = "DamageNumberAnchor"
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = worldPosition
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumber"
	billboard.Size = UDim2.new(0, 80, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 0, 0)
	billboard.Adornee = part
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "DamageText"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Text = tostring(math.ceil(damage))
	label.Parent = billboard

	-- Animate: float upward and fade out over 1 second
	local floatInfo = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local floatTween = TweenService:Create(billboard, floatInfo, {
		StudsOffset = Vector3.new(0, 3, 0),
	})
	floatTween:Play()

	local fadeTween = TweenService:Create(label, floatInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	fadeTween:Play()

	-- Destroy after animation completes
	task.delay(1.1, function()
		if part and part.Parent then
			part:Destroy()
		end
	end)
end

---------------------------------------------------------------------------
-- 3. Muzzle Flash
---------------------------------------------------------------------------

--[[
	Creates a brief bright neon sphere at the weapon barrel position.
	@param barrelPosition -- world position of the weapon barrel
	@param weaponType -- "hitscan" or "projectile" to determine color
]]
function VFXController.playMuzzleFlash(barrelPosition: Vector3, weaponType: string?)
	local color: Color3
	if weaponType == "projectile" then
		color = Color3.fromRGB(255, 150, 30) -- orange for projectile
	else
		color = Color3.fromRGB(0, 220, 255) -- cyan for hitscan
	end

	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.5, 0.5, 0.5)
	flash.Position = barrelPosition
	flash.Anchored = true
	flash.CanCollide = false
	flash.Color = color
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0
	flash.CastShadow = false
	flash.Parent = workspace

	-- Destroy after 0.1 seconds
	task.delay(0.1, function()
		if flash and flash.Parent then
			flash:Destroy()
		end
	end)
end

---------------------------------------------------------------------------
-- 4. Kill Screen Flash
---------------------------------------------------------------------------

local function createKillFlashFrame(parent: ScreenGui)
	if killFlashFrame and killFlashFrame.Parent then
		return
	end

	killFlashFrame = Instance.new("Frame")
	killFlashFrame.Name = "KillFlash"
	killFlashFrame.Size = UDim2.new(1, 0, 1, 0)
	killFlashFrame.Position = UDim2.new(0, 0, 0, 0)
	killFlashFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	killFlashFrame.BackgroundTransparency = 1 -- invisible by default
	killFlashFrame.BorderSizePixel = 0
	killFlashFrame.ZIndex = 15
	killFlashFrame.Parent = parent
end

local function showKillFlash()
	local gui = ensureScreenGui()
	if not gui then
		return
	end

	createKillFlashFrame(gui)

	if not killFlashFrame then
		return
	end

	-- Start at 0.7 transparency, tween to 1.0 (invisible) over 0.3s
	killFlashFrame.BackgroundTransparency = 0.7

	local fadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(killFlashFrame, fadeInfo, {
		BackgroundTransparency = 1,
	})
	tween:Play()
end

---------------------------------------------------------------------------
-- 5. Low Health Vignette
---------------------------------------------------------------------------

local function createVignetteOverlay(parent: ScreenGui)
	if vignetteFrame and vignetteFrame.Parent then
		return
	end

	-- Container frame (full screen, no background)
	vignetteFrame = Instance.new("Frame")
	vignetteFrame.Name = "LowHealthVignette"
	vignetteFrame.Size = UDim2.new(1, 0, 1, 0)
	vignetteFrame.Position = UDim2.new(0, 0, 0, 0)
	vignetteFrame.BackgroundTransparency = 1
	vignetteFrame.BorderSizePixel = 0
	vignetteFrame.ZIndex = 12
	vignetteFrame.Visible = false
	vignetteFrame.Parent = parent

	vignetteEdges = {}

	-- 4 edge frames with red gradient fading toward center
	local edgeConfigs = {
		-- Top edge
		{
			size = UDim2.new(1, 0, 0.15, 0),
			position = UDim2.new(0, 0, 0, 0),
			gradientRotation = 180, -- red at top, transparent toward center
		},
		-- Bottom edge
		{
			size = UDim2.new(1, 0, 0.15, 0),
			position = UDim2.new(0, 0, 0.85, 0),
			gradientRotation = 0, -- red at bottom, transparent toward center
		},
		-- Left edge
		{
			size = UDim2.new(0.15, 0, 1, 0),
			position = UDim2.new(0, 0, 0, 0),
			gradientRotation = 90, -- red at left, transparent toward center
		},
		-- Right edge
		{
			size = UDim2.new(0.15, 0, 1, 0),
			position = UDim2.new(0.85, 0, 0, 0),
			gradientRotation = 270, -- red at right, transparent toward center
		},
	}

	for i, cfg in edgeConfigs do
		local edge = Instance.new("Frame")
		edge.Name = "VignetteEdge" .. i
		edge.Size = cfg.size
		edge.Position = cfg.position
		edge.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
		edge.BackgroundTransparency = 0.3
		edge.BorderSizePixel = 0
		edge.ZIndex = 12
		edge.Parent = vignetteFrame

		-- UIGradient: red (opaque) at the screen edge, transparent toward center
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(Color3.fromRGB(200, 20, 20))
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Rotation = cfg.gradientRotation
		gradient.Parent = edge

		table.insert(vignetteEdges, edge)
	end
end

local function startVignettePulse(intensity: number)
	-- intensity: 0..1, where 1 = very low health
	if vignetteActive then
		return
	end
	vignetteActive = true

	if not vignetteFrame then
		return
	end
	vignetteFrame.Visible = true

	-- Set base transparency based on intensity (lower health = more visible)
	local baseTransparency = 0.3 + (1 - intensity) * 0.4 -- range: 0.3 (very visible) to 0.7 (barely visible)

	for _, edge in vignetteEdges do
		edge.BackgroundTransparency = baseTransparency
	end

	-- Pulse: tween transparency back and forth
	local function doPulse()
		if not vignetteActive or not vignetteFrame or not vignetteFrame.Parent then
			return
		end

		local pulseHigh = math.clamp(baseTransparency + 0.2, 0, 1)

		-- Fade out slightly
		local fadeOutInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		for _, edge in vignetteEdges do
			local tw = TweenService:Create(edge, fadeOutInfo, {
				BackgroundTransparency = pulseHigh,
			})
			tw:Play()
		end

		task.delay(0.8, function()
			if not vignetteActive or not vignetteFrame or not vignetteFrame.Parent then
				return
			end

			-- Fade back in
			local fadeInInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			for _, edge in vignetteEdges do
				local tw = TweenService:Create(edge, fadeInInfo, {
					BackgroundTransparency = baseTransparency,
				})
				tw:Play()
			end

			task.delay(0.8, doPulse)
		end)
	end

	doPulse()
end

local function stopVignette()
	vignetteActive = false
	if vignetteFrame then
		vignetteFrame.Visible = false
	end
end

local function updateVignetteForHealth(currentHealth: number, maxHealth: number)
	local fraction = if maxHealth > 0 then math.clamp(currentHealth / maxHealth, 0, 1) else 1

	if fraction < 0.3 then
		local gui = ensureScreenGui()
		if gui then
			createVignetteOverlay(gui)
		end

		-- Intensity: 1.0 at 0 health, 0.0 at 30% health
		local intensity = math.clamp(1 - (fraction / 0.3), 0, 1)

		if vignetteActive then
			-- Update edge transparency while pulse is running
			local baseTransparency = 0.3 + (1 - intensity) * 0.4
			for _, edge in vignetteEdges do
				edge.BackgroundTransparency = baseTransparency
			end
		else
			startVignettePulse(intensity)
		end
	else
		stopVignette()
	end
end

---------------------------------------------------------------------------
-- 6. Ability Activation Flash
---------------------------------------------------------------------------

local function showAbilityActivationFlash(slotIndex: number)
	-- Find the ability slot frame in the HUD
	local playerGui = getPlayerGui()
	if not playerGui then
		return
	end

	local hudGui = playerGui:FindFirstChild("MemoryHeistHUD")
	if not hudGui then
		return
	end

	local hudFrame = hudGui:FindFirstChild("HUDFrame")
	if not hudFrame then
		return
	end

	local slotsContainer = hudFrame:FindFirstChild("AbilitySlots")
	if not slotsContainer then
		return
	end

	local slotFrame = slotsContainer:FindFirstChild("Slot" .. slotIndex)
	if not slotFrame then
		return
	end

	-- Brief cyan flash overlay on the slot
	local flash = Instance.new("Frame")
	flash.Name = "AbilityFlash"
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = Color3.fromRGB(0, 255, 255)
	flash.BackgroundTransparency = 0.3
	flash.BorderSizePixel = 0
	flash.ZIndex = 5
	flash.Parent = slotFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = flash

	-- Fade out the flash
	local fadeInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTween = TweenService:Create(flash, fadeInfo, {
		BackgroundTransparency = 1,
	})
	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		if flash and flash.Parent then
			flash:Destroy()
		end
	end)

	-- Scale pop: 1.0 -> 1.1 -> 1.0 over 0.2s
	-- Save original size so we can restore it
	local originalSize = slotFrame.Size

	local popUpInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local popUpTween = TweenService:Create(slotFrame, popUpInfo, {
		Size = UDim2.new(
			originalSize.X.Scale * 1.1,
			math.floor(originalSize.X.Offset * 1.1),
			originalSize.Y.Scale * 1.1,
			math.floor(originalSize.Y.Offset * 1.1)
		),
	})
	popUpTween:Play()

	popUpTween.Completed:Connect(function()
		local popDownInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local popDownTween = TweenService:Create(slotFrame, popDownInfo, {
			Size = originalSize,
		})
		popDownTween:Play()
	end)
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

local function cleanup()
	-- Stop vignette
	stopVignette()

	-- Disconnect health listener
	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end

	-- Clear hit marker lines reference (GUI is ResetOnSpawn so it auto-destroys)
	hitMarkerLines = {}
	vignetteFrame = nil
	vignetteEdges = {}
	killFlashFrame = nil
	vfxScreenGui = nil
end

---------------------------------------------------------------------------
-- Health connection
---------------------------------------------------------------------------

local function connectToCharacterHealth()
	-- Disconnect previous
	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end

	local character = LocalPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	end
	if not humanoid then
		return
	end

	-- Initial check
	updateVignetteForHealth(humanoid.Health, humanoid.MaxHealth)

	healthConnection = humanoid.HealthChanged:Connect(function(newHealth: number)
		updateVignetteForHealth(newHealth, humanoid.MaxHealth)
	end)
end

---------------------------------------------------------------------------
-- 7. Ability World VFX
---------------------------------------------------------------------------

-- Color mapping for ability useTypes
local USE_TYPE_COLORS: { [string]: Color3 } = {
	Movement = Color3.fromRGB(0, 200, 255),
	Attack = Color3.fromRGB(255, 60, 60),
	Defense = Color3.fromRGB(0, 180, 255),
	Support = Color3.fromRGB(0, 255, 120),
	Control = Color3.fromRGB(180, 0, 255),
	Stealth = Color3.fromRGB(100, 100, 120),
	Trick = Color3.fromRGB(255, 200, 0),
	Projectile = Color3.fromRGB(255, 100, 30),
	Beam = Color3.fromRGB(0, 255, 255),
	Summon = Color3.fromRGB(255, 50, 50),
	Ultimate = Color3.fromRGB(255, 50, 50),
	Heavy = Color3.fromRGB(255, 80, 0),
	Area = Color3.fromRGB(100, 255, 100),
	Melee = Color3.fromRGB(255, 50, 200),
	Buff = Color3.fromRGB(255, 220, 50),
	AOE = Color3.fromRGB(255, 150, 0),
}

local function getColorForUseType(useType: string): Color3
	if USE_TYPE_COLORS[useType] then
		return USE_TYPE_COLORS[useType]
	end
	for keyword, color in USE_TYPE_COLORS do
		if string.find(useType, keyword) then
			return color
		end
	end
	return Color3.fromRGB(0, 255, 255)
end

--- Create expanding ring effect at a position
local function spawnRingEffect(position: Vector3, color: Color3, radius: number, duration: number)
	local ring = Instance.new("Part")
	ring.Name = "AbilityRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.3
	ring.CastShadow = false
	ring.Parent = workspace

	-- Expand outward and fade
	local expandInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local targetSize = Vector3.new(0.2, radius * 2, radius * 2)
	TweenService:Create(ring, expandInfo, { Size = targetSize, Transparency = 1 }):Play()

	task.delay(duration + 0.1, function()
		if ring and ring.Parent then ring:Destroy() end
	end)
end

--- Create burst of neon particles (small spheres flying outward)
local function spawnBurstEffect(position: Vector3, color: Color3, count: number, speed: number, lifetime: number)
	for _ = 1, count do
		local particle = Instance.new("Part")
		particle.Name = "AbilityParticle"
		particle.Shape = Enum.PartType.Ball
		particle.Size = Vector3.new(0.3, 0.3, 0.3)
		particle.Position = position
		particle.Anchored = false
		particle.CanCollide = false
		particle.Color = color
		particle.Material = Enum.Material.Neon
		particle.Transparency = 0
		particle.CastShadow = false
		particle.Parent = workspace

		-- Random outward direction
		local dir = Vector3.new(
			(math.random() - 0.5) * 2,
			math.random() * 1.5,
			(math.random() - 0.5) * 2
		).Unit
		particle.AssemblyLinearVelocity = dir * speed

		-- Fade out
		local fadeInfo = TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(particle, fadeInfo, { Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05) }):Play()

		task.delay(lifetime + 0.1, function()
			if particle and particle.Parent then particle:Destroy() end
		end)
	end
end

--- Create a beam/column effect shooting upward
local function spawnColumnEffect(position: Vector3, color: Color3, height: number, duration: number)
	local column = Instance.new("Part")
	column.Name = "AbilityColumn"
	column.Size = Vector3.new(1.5, 0.1, 1.5)
	column.CFrame = CFrame.new(position)
	column.Anchored = true
	column.CanCollide = false
	column.Color = color
	column.Material = Enum.Material.Neon
	column.Transparency = 0.2
	column.CastShadow = false
	column.Parent = workspace

	-- Grow upward
	local growInfo = TweenInfo.new(duration * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(column, growInfo, {
		Size = Vector3.new(1.5, height, 1.5),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)),
	}):Play()

	-- Then fade
	task.delay(duration * 0.4, function()
		if not column or not column.Parent then return end
		local fadeInfo = TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(column, fadeInfo, { Transparency = 1 }):Play()
	end)

	task.delay(duration + 0.1, function()
		if column and column.Parent then column:Destroy() end
	end)
end

--- Create a ground shockwave (flat disc expanding outward)
local function spawnGroundWave(position: Vector3, color: Color3, radius: number, duration: number)
	local disc = Instance.new("Part")
	disc.Name = "AbilityGroundWave"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.1, 2, 2)
	disc.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	disc.Anchored = true
	disc.CanCollide = false
	disc.Color = color
	disc.Material = Enum.Material.Neon
	disc.Transparency = 0.4
	disc.CastShadow = false
	disc.Parent = workspace

	local expandInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(disc, expandInfo, {
		Size = Vector3.new(0.1, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()

	task.delay(duration + 0.1, function()
		if disc and disc.Parent then disc:Destroy() end
	end)
end

--- Create a flash sphere (expands and fades quickly)
local function spawnFlashSphere(position: Vector3, color: Color3, size: number, duration: number)
	local sphere = Instance.new("Part")
	sphere.Name = "AbilityFlash"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(1, 1, 1)
	sphere.Position = position
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.Color = color
	sphere.Material = Enum.Material.Neon
	sphere.Transparency = 0.1
	sphere.CastShadow = false
	sphere.Parent = workspace

	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(sphere, info, {
		Size = Vector3.new(size, size, size),
		Transparency = 1,
	}):Play()

	task.delay(duration + 0.1, function()
		if sphere and sphere.Parent then sphere:Destroy() end
	end)
end

--- Play ability VFX based on the ability's useType and rarity
local function playAbilityVFX(data: { abilityId: string, playerName: string, position: Vector3, direction: Vector3 })
	local abilityDef = AbilityData[data.abilityId]
	if not abilityDef then return end

	local rarityInfo = RarityData[abilityDef.rarity]
	local rarityColor = if rarityInfo then rarityInfo.color else Color3.fromRGB(180, 180, 180)
	local typeColor = getColorForUseType(abilityDef.useType)
	local pos = data.position
	local dir = data.direction

	-- Scale effects based on rarity
	local rarityScale = 1.0
	if abilityDef.rarity == "Rare" then
		rarityScale = 1.2
	elseif abilityDef.rarity == "Epic" then
		rarityScale = 1.4
	elseif abilityDef.rarity == "Legendary" then
		rarityScale = 1.6
	elseif abilityDef.rarity == "Mythic" then
		rarityScale = 2.0
	end

	local useType = abilityDef.useType

	-- Movement abilities: speed lines + ring burst
	if string.find(useType, "Movement") then
		spawnRingEffect(pos, typeColor, 6 * rarityScale, 0.4)
		spawnBurstEffect(pos, typeColor, 6, 15 * rarityScale, 0.5)
		return
	end

	-- Attack/AOE abilities: ground shockwave + upward burst
	if string.find(useType, "AOE") or string.find(useType, "Attack") then
		spawnGroundWave(pos, typeColor, 10 * rarityScale, 0.6)
		spawnFlashSphere(pos, typeColor, 4 * rarityScale, 0.3)
		spawnBurstEffect(pos, rarityColor, 8, 12 * rarityScale, 0.6)
		return
	end

	-- Defense abilities: shield sphere
	if string.find(useType, "Defense") then
		spawnFlashSphere(pos, typeColor, 8 * rarityScale, 0.8)
		spawnRingEffect(pos, typeColor, 5 * rarityScale, 0.6)
		return
	end

	-- Support/Heal abilities: upward column + gentle particles
	if string.find(useType, "Support") or string.find(useType, "Heal") then
		spawnColumnEffect(pos, typeColor, 12 * rarityScale, 1.0)
		spawnBurstEffect(pos, typeColor, 5, 8, 0.8)
		return
	end

	-- Control abilities: expanding rings + flash
	if string.find(useType, "Control") then
		spawnRingEffect(pos, typeColor, 8 * rarityScale, 0.5)
		spawnRingEffect(pos + Vector3.new(0, 1, 0), rarityColor, 6 * rarityScale, 0.7)
		spawnFlashSphere(pos, typeColor, 3 * rarityScale, 0.3)
		return
	end

	-- Stealth abilities: dark imploding particles
	if string.find(useType, "Stealth") then
		spawnFlashSphere(pos, typeColor, 5 * rarityScale, 0.5)
		return
	end

	-- Trick abilities: burst of sparks
	if string.find(useType, "Trick") then
		spawnBurstEffect(pos, typeColor, 10, 18 * rarityScale, 0.5)
		spawnFlashSphere(pos, rarityColor, 3 * rarityScale, 0.25)
		return
	end

	-- Projectile abilities: forward flash + directional burst
	if string.find(useType, "Projectile") or string.find(useType, "Beam") or string.find(useType, "Heavy") then
		local forwardPos = pos + dir * 3
		spawnFlashSphere(forwardPos, typeColor, 3 * rarityScale, 0.3)
		spawnBurstEffect(pos, typeColor, 6, 14 * rarityScale, 0.4)
		return
	end

	-- Ultimate abilities: big column + rings + burst
	if string.find(useType, "Ultimate") then
		spawnColumnEffect(pos, rarityColor, 20 * rarityScale, 1.2)
		spawnGroundWave(pos, rarityColor, 12 * rarityScale, 0.8)
		spawnRingEffect(pos + Vector3.new(0, 3, 0), rarityColor, 8 * rarityScale, 0.6)
		spawnBurstEffect(pos, rarityColor, 12, 20 * rarityScale, 0.8)
		return
	end

	-- Default: simple ring + burst
	spawnRingEffect(pos, typeColor, 5 * rarityScale, 0.4)
	spawnBurstEffect(pos, typeColor, 6, 12 * rarityScale, 0.5)
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function VFXController.init()
	-- 1. Hit Markers — listen for weapon hit confirmation
	ClientNetwork.onServerEvent(EventNames.WeaponHitConfirm, function(_data: any)
		showHitMarker()
	end)

	-- 2. Damage Numbers — listen for damage dealt
	ClientNetwork.onServerEvent(EventNames.DamageDealt, function(data: any)
		local damage = data.damage or 0
		local isCritical = data.isCritical or false

		-- Use the target's position if available, otherwise fall back to camera
		local worldPos: Vector3
		if data.position then
			worldPos = data.position
		elseif data.targetName then
			-- Try to find the target character in the workspace
			local targetPlayer = Players:FindFirstChild(data.targetName)
			if targetPlayer and (targetPlayer :: Player).Character then
				local rootPart = (targetPlayer :: Player).Character:FindFirstChild("HumanoidRootPart")
				if rootPart then
					worldPos = rootPart.Position + Vector3.new(
						(math.random() - 0.5) * 2,
						2,
						(math.random() - 0.5) * 2
					)
				end
			end
		end

		-- Fallback: place it in front of the camera
		if not worldPos then
			camera = workspace.CurrentCamera
			if camera then
				worldPos = camera.CFrame.Position + camera.CFrame.LookVector * 10
			else
				return
			end
		end

		showDamageNumber(damage, worldPos, isCritical)
	end)

	-- 4. Kill Screen Flash — listen for kills where we are the killer
	ClientNetwork.onServerEvent(EventNames.KillOccurred, function(killerName: string, _victimName: string)
		if killerName == LocalPlayer.Name then
			showKillFlash()
		end
	end)

	-- 6. Ability Activation Flash — listen for cooldown updates (fired on ability use)
	ClientNetwork.onServerEvent(EventNames.AbilityCooldownUpdate, function(slotIndex: number, _cooldownDuration: number)
		showAbilityActivationFlash(slotIndex)
	end)

	-- 7. Ability World VFX — listen for ability VFX broadcasts
	ClientNetwork.onServerEvent(EventNames.AbilityVFX, function(data: any)
		if data and data.abilityId and data.position then
			playAbilityVFX(data)
		end
	end)

	-- 5. Low Health Vignette — connect to character health
	task.spawn(connectToCharacterHealth)

	-- Reconnect on respawn and clean up old effects
	LocalPlayer.CharacterAdded:Connect(function()
		cleanup()
		-- Small delay to let the character fully load
		task.wait(0.2)
		connectToCharacterHealth()
	end)

	print("[VFXController] Initialized")
end

return VFXController

--[[
	CrouchController — Crouch + Directional Slide system (Roblox Rivals style).

	- Hold Left Control while standing still: crouch (lower stance, reduced speed)
	- Press Left Control while moving in ANY direction: slide that direction
	  Uses Humanoid.MoveDirection so WASD determines slide direction relative
	  to camera — forward, backward, sideways, diagonal all work instantly.
	- Slide decelerates naturally over time (not constant speed)
	- Press Space during a slide to jump-cancel with momentum boost
	- Camera tilts during slide for juicy feedback
	- Works in both first and third person.
]]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CrouchController = {}

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local isCrouching: boolean = false
local isSliding: boolean = false
local slideCooldownActive: boolean = false
local controlHeld: boolean = false

-- Original values (captured before crouch/slide modifies them)
local originalHipHeight: number? = nil
local originalWalkSpeed: number? = nil

-- Slide runtime
local slideDirection: Vector3 = Vector3.zero
local slideSpeed: number = 0
local slideElapsed: number = 0
local slideConnection: RBXScriptConnection? = nil

---------------------------------------------------------------------------
-- Slide configuration (Roblox Rivals style)
---------------------------------------------------------------------------
local SLIDE_INITIAL_SPEED = 38       -- fast initial burst
local SLIDE_MIN_SPEED_CUTOFF = 6     -- speed at which slide ends naturally
local SLIDE_DECELERATION = 45        -- studs/sec² — how fast slide slows down
local SLIDE_MAX_DURATION = 1.0       -- hard cap seconds
local SLIDE_COOLDOWN = 0.35          -- short cooldown between slides
local SLIDE_HIP_OFFSET = -1.8        -- HipHeight drop during slide
local SLIDE_CAMERA_TILT = 4          -- degrees of camera roll during slide

local JUMP_CANCEL_UPWARD_BOOST = 30
local JUMP_CANCEL_HORIZONTAL_KEEP = 0.75

---------------------------------------------------------------------------
-- Crouch configuration
---------------------------------------------------------------------------
local CROUCH_SPEED_MULTIPLIER = 0.45
local CROUCH_HIP_OFFSET = -1.2
local CROUCH_CAMERA_Y = -0.8

---------------------------------------------------------------------------
-- Tween presets
---------------------------------------------------------------------------
local TWEEN_SNAP = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SMOOTH = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_STAND = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function getHumanoid(): Humanoid?
	local character = localPlayer.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(): BasePart?
	local character = localPlayer.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function captureOriginals(humanoid: Humanoid)
	if originalHipHeight == nil then
		originalHipHeight = humanoid.HipHeight
	end
	if originalWalkSpeed == nil then
		originalWalkSpeed = humanoid.WalkSpeed
	end
end

local function restoreToStanding(humanoid: Humanoid, tweenInfo: TweenInfo?)
	local info = tweenInfo or TWEEN_STAND
	if originalWalkSpeed then
		humanoid.WalkSpeed = originalWalkSpeed
	end
	if originalHipHeight then
		TweenService:Create(humanoid, info, {
			HipHeight = originalHipHeight,
			CameraOffset = Vector3.new(0, 0, 0),
		}):Play()
	end
	originalHipHeight = nil
	originalWalkSpeed = nil
end

---------------------------------------------------------------------------
-- Camera tilt (roll during slide for juicy feel)
---------------------------------------------------------------------------

local baseCameraCFrame: CFrame? = nil
local tiltConnection: RBXScriptConnection? = nil

local function startCameraTilt(direction: Vector3)
	-- Determine tilt direction based on slide direction relative to camera
	local camRight = camera.CFrame.RightVector
	local dot = direction:Dot(camRight)
	local tiltAngle = math.rad(SLIDE_CAMERA_TILT)

	-- Tilt slightly toward the slide direction
	if math.abs(dot) > 0.3 then
		tiltAngle = tiltAngle * (dot > 0 and 1 or -1)
	else
		-- Forward/backward slide: slight forward tilt feel (no roll)
		tiltAngle = 0
	end

	if tiltConnection then
		tiltConnection:Disconnect()
		tiltConnection = nil
	end

	tiltConnection = RunService.RenderStepped:Connect(function()
		if not isSliding then
			if tiltConnection then
				tiltConnection:Disconnect()
				tiltConnection = nil
			end
			return
		end
		-- Apply subtle roll to camera
		local currentCF = camera.CFrame
		camera.CFrame = currentCF * CFrame.Angles(0, 0, tiltAngle * 0.1) -- smooth blend
	end)
end

local function stopCameraTilt()
	if tiltConnection then
		tiltConnection:Disconnect()
		tiltConnection = nil
	end
end

---------------------------------------------------------------------------
-- Slide cooldown
---------------------------------------------------------------------------

local function startSlideCooldown()
	slideCooldownActive = true
	task.delay(SLIDE_COOLDOWN, function()
		slideCooldownActive = false
	end)
end

---------------------------------------------------------------------------
-- Slide tick — runs every frame during a slide, applies deceleration
---------------------------------------------------------------------------

local function cleanupSlide()
	if slideConnection then
		slideConnection:Disconnect()
		slideConnection = nil
	end
	stopCameraTilt()
end

local function endSlide()
	if not isSliding then return end
	isSliding = false
	cleanupSlide()

	local humanoid = getHumanoid()
	if not humanoid then
		originalHipHeight = nil
		originalWalkSpeed = nil
		startSlideCooldown()
		return
	end

	if controlHeld then
		-- Transition to crouch since key is still held
		isCrouching = true
		humanoid.WalkSpeed = (originalWalkSpeed or 24) * CROUCH_SPEED_MULTIPLIER

		local targetHip = (originalHipHeight or humanoid.HipHeight) + CROUCH_HIP_OFFSET
		TweenService:Create(humanoid, TWEEN_SMOOTH, {
			HipHeight = targetHip,
			CameraOffset = Vector3.new(0, CROUCH_CAMERA_Y, 0),
		}):Play()
	else
		restoreToStanding(humanoid, TWEEN_STAND)
	end

	startSlideCooldown()
end

---------------------------------------------------------------------------
-- Start slide — Roblox Rivals style
---------------------------------------------------------------------------

local function startSlide()
	if isSliding or slideCooldownActive then return false end

	local humanoid = getHumanoid()
	local rootPart = getRootPart()
	if not humanoid or not rootPart then return false end

	-- Get movement direction from WASD input (relative to camera)
	local moveDir = humanoid.MoveDirection
	local horizontalMoveDir = Vector3.new(moveDir.X, 0, moveDir.Z)

	if horizontalMoveDir.Magnitude < 0.1 then
		-- No movement input — can't slide (Rivals requires movement)
		return false
	end

	-- Stop any active crouch
	isCrouching = false

	captureOriginals(humanoid)
	isSliding = true

	-- Slide direction = normalized movement input direction
	slideDirection = horizontalMoveDir.Unit

	-- Initial speed: use SLIDE_INITIAL_SPEED or current speed, whichever is higher
	local currentVel = rootPart.AssemblyLinearVelocity
	local currentHorizSpeed = Vector3.new(currentVel.X, 0, currentVel.Z).Magnitude
	slideSpeed = math.max(SLIDE_INITIAL_SPEED, currentHorizSpeed * 1.2)
	slideElapsed = 0

	-- Lock WalkSpeed to 0 during slide so WASD doesn't fight
	humanoid.WalkSpeed = 0

	-- Drop HipHeight and camera for slide pose
	local targetHip = (originalHipHeight :: number) + SLIDE_HIP_OFFSET
	TweenService:Create(humanoid, TWEEN_SNAP, {
		HipHeight = targetHip,
		CameraOffset = Vector3.new(0, -1.2, 0),
	}):Play()

	-- Start camera tilt
	startCameraTilt(slideDirection)

	-- Apply initial velocity burst
	rootPart.AssemblyLinearVelocity = Vector3.new(
		slideDirection.X * slideSpeed,
		rootPart.AssemblyLinearVelocity.Y, -- preserve vertical velocity
		slideDirection.Z * slideSpeed
	)

	-- Slide tick: decelerate every frame using AssemblyLinearVelocity directly
	-- This feels more grounded than BodyVelocity (Rivals style)
	cleanupSlide() -- safety
	slideConnection = RunService.Heartbeat:Connect(function(dt)
		if not isSliding then
			cleanupSlide()
			return
		end

		slideElapsed += dt
		slideSpeed = math.max(0, slideSpeed - SLIDE_DECELERATION * dt)

		local rp = getRootPart()
		if not rp then
			endSlide()
			return
		end

		-- Apply slide velocity (override horizontal, keep vertical)
		local currentVelY = rp.AssemblyLinearVelocity.Y
		rp.AssemblyLinearVelocity = Vector3.new(
			slideDirection.X * slideSpeed,
			currentVelY,
			slideDirection.Z * slideSpeed
		)

		-- End slide if too slow or max duration reached
		if slideSpeed <= SLIDE_MIN_SPEED_CUTOFF or slideElapsed >= SLIDE_MAX_DURATION then
			endSlide()
		end
	end)

	return true
end

---------------------------------------------------------------------------
-- Jump cancel (press Space during slide)
---------------------------------------------------------------------------

local function jumpCancelSlide()
	if not isSliding then return end

	local humanoid = getHumanoid()
	local rootPart = getRootPart()

	-- Capture current slide velocity before ending
	local currentSlideVel = slideDirection * slideSpeed

	isSliding = false
	cleanupSlide()

	if humanoid and rootPart then
		-- Restore movement
		if originalWalkSpeed then
			humanoid.WalkSpeed = originalWalkSpeed
		end
		if originalHipHeight then
			TweenService:Create(humanoid, TWEEN_SNAP, {
				HipHeight = originalHipHeight,
				CameraOffset = Vector3.new(0, 0, 0),
			}):Play()
		end

		-- Apply momentum: upward boost + preserved horizontal velocity
		local horizontalKeep = Vector3.new(currentSlideVel.X, 0, currentSlideVel.Z) * JUMP_CANCEL_HORIZONTAL_KEEP
		rootPart.AssemblyLinearVelocity = horizontalKeep + Vector3.new(0, JUMP_CANCEL_UPWARD_BOOST, 0)
	end

	originalHipHeight = nil
	originalWalkSpeed = nil
	startSlideCooldown()
end

---------------------------------------------------------------------------
-- Crouch (hold-based, for standing still)
---------------------------------------------------------------------------

local function startCrouch()
	if isCrouching or isSliding then return end

	local humanoid = getHumanoid()
	if not humanoid then return end

	isCrouching = true
	captureOriginals(humanoid)

	humanoid.WalkSpeed = (originalWalkSpeed :: number) * CROUCH_SPEED_MULTIPLIER

	local targetHip = (originalHipHeight :: number) + CROUCH_HIP_OFFSET
	TweenService:Create(humanoid, TWEEN_SMOOTH, {
		HipHeight = targetHip,
		CameraOffset = Vector3.new(0, CROUCH_CAMERA_Y, 0),
	}):Play()
end

local function stopCrouch()
	if not isCrouching then return end

	local humanoid = getHumanoid()
	isCrouching = false

	if humanoid then
		restoreToStanding(humanoid, TWEEN_STAND)
	else
		originalHipHeight = nil
		originalWalkSpeed = nil
	end
end

---------------------------------------------------------------------------
-- Input handling
---------------------------------------------------------------------------

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
		controlHeld = true

		-- Check if player is pressing any movement key
		local humanoid = getHumanoid()
		if humanoid then
			local moveDir = humanoid.MoveDirection
			local hasMoveInput = Vector3.new(moveDir.X, 0, moveDir.Z).Magnitude > 0.1

			if hasMoveInput then
				local started = startSlide()
				if not started then
					startCrouch()
				end
			else
				startCrouch()
			end
		else
			startCrouch()
		end
	end

	-- Jump cancel: Space while sliding
	if input.KeyCode == Enum.KeyCode.Space then
		if isSliding then
			jumpCancelSlide()
		end
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
		controlHeld = false

		if isCrouching and not isSliding then
			stopCrouch()
		end
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function CrouchController.isCrouching(): boolean
	return isCrouching
end

function CrouchController.isSliding(): boolean
	return isSliding
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------

function CrouchController.init()
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)

	-- Reset all state on respawn
	localPlayer.CharacterAdded:Connect(function(character)
		cleanupSlide()

		isCrouching = false
		isSliding = false
		slideCooldownActive = false
		controlHeld = false
		originalHipHeight = nil
		originalWalkSpeed = nil
		slideDirection = Vector3.zero
		slideSpeed = 0
		slideElapsed = 0

		-- Ensure camera offset is reset
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.CameraOffset = Vector3.new(0, 0, 0)
		end
	end)

	print("[CrouchController] Initialized (Rivals-style Slide + Crouch)")
end

return CrouchController

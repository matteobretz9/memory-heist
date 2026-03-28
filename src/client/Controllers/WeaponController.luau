--[[
	Client-side weapon handling.
	Reads player input, enforces local cooldowns for responsive feel,
	communicates fire/reload requests to the server, and manages
	placeholder weapon models attached to the character's hand.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ClientNetwork = require(script.Parent.Parent.Network)
local HUD = require(script.Parent.Parent.UI.HUD)
local EventNames = require(ReplicatedStorage.Shared.Network.EventNames)
local WeaponData = require(ReplicatedStorage.Shared.Data.WeaponData)

local WeaponController = {}

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

--------------------------------------------------------------------------------
-- Local weapon state (mirrors server for responsiveness)
--------------------------------------------------------------------------------

local currentWeaponId: string = "PulseBlaster"
local currentAmmo: number = 0
local isReloading: boolean = false
local lastFireTime: number = 0

-- Reference to the currently equipped weapon model
local currentWeaponModel: Model? = nil

--------------------------------------------------------------------------------
-- Placeholder weapon model definitions
--------------------------------------------------------------------------------

-- Each weapon gets a simple geometric shape with a color.
-- Sizes are in studs. Melee weapons attach differently from guns.
local WEAPON_VISUALS = {
	EnergySword = {
		shape = "blade",
		color = Color3.fromRGB(0, 200, 255),
		material = Enum.Material.Neon,
		size = Vector3.new(0.3, 0.3, 4),
		grip = CFrame.new(0, 0, -2) * CFrame.Angles(math.rad(90), 0, 0),
	},
	PulseBlaster = {
		shape = "gun",
		color = Color3.fromRGB(80, 80, 120),
		material = Enum.Material.SmoothPlastic,
		size = Vector3.new(0.4, 0.5, 1.6),
		grip = CFrame.new(0, -0.2, -0.6),
		barrel = { size = Vector3.new(0.2, 0.2, 0.8), offset = CFrame.new(0, 0.1, -1.0), color = Color3.fromRGB(0, 180, 255), material = Enum.Material.Neon },
	},
	RailRifle = {
		shape = "gun",
		color = Color3.fromRGB(60, 60, 80),
		material = Enum.Material.SmoothPlastic,
		size = Vector3.new(0.35, 0.45, 2.4),
		grip = CFrame.new(0, -0.2, -0.8),
		barrel = { size = Vector3.new(0.15, 0.15, 1.2), offset = CFrame.new(0, 0.1, -1.5), color = Color3.fromRGB(255, 60, 60), material = Enum.Material.Neon },
	},
	MemorySMG = {
		shape = "gun",
		color = Color3.fromRGB(70, 70, 90),
		material = Enum.Material.SmoothPlastic,
		size = Vector3.new(0.35, 0.4, 1.2),
		grip = CFrame.new(0, -0.2, -0.4),
		barrel = { size = Vector3.new(0.15, 0.15, 0.6), offset = CFrame.new(0, 0.05, -0.7), color = Color3.fromRGB(0, 255, 150), material = Enum.Material.Neon },
	},
	GlitchShotgun = {
		shape = "gun",
		color = Color3.fromRGB(90, 70, 60),
		material = Enum.Material.SmoothPlastic,
		size = Vector3.new(0.45, 0.5, 1.8),
		grip = CFrame.new(0, -0.2, -0.6),
		barrel = { size = Vector3.new(0.35, 0.35, 0.4), offset = CFrame.new(0, 0.05, -0.9), color = Color3.fromRGB(255, 100, 0), material = Enum.Material.Neon },
	},
	PhaseKnife = {
		shape = "blade",
		color = Color3.fromRGB(200, 0, 255),
		material = Enum.Material.Neon,
		size = Vector3.new(0.15, 0.15, 1.8),
		grip = CFrame.new(0, 0, -0.9) * CFrame.Angles(math.rad(90), 0, 0),
	},
	ShockLauncher = {
		shape = "gun",
		color = Color3.fromRGB(80, 80, 80),
		material = Enum.Material.SmoothPlastic,
		size = Vector3.new(0.5, 0.55, 2.0),
		grip = CFrame.new(0, -0.2, -0.7),
		barrel = { size = Vector3.new(0.4, 0.4, 0.5), offset = CFrame.new(0, 0.1, -1.1), color = Color3.fromRGB(255, 255, 0), material = Enum.Material.Neon },
	},
}

--------------------------------------------------------------------------------
-- Weapon model creation / destruction
--------------------------------------------------------------------------------

local function destroyWeaponModel()
	if currentWeaponModel then
		currentWeaponModel:Destroy()
		currentWeaponModel = nil
	end
end

local function createWeaponModel(weaponId: string)
	destroyWeaponModel()

	local character = localPlayer.Character
	if not character then
		return
	end

	local rightHand = character:FindFirstChild("RightHand") -- R15
		or character:FindFirstChild("Right Arm") -- R6

	if not rightHand then
		return
	end

	local visual = WEAPON_VISUALS[weaponId]
	if not visual then
		-- Fallback: small grey box
		visual = {
			shape = "gun",
			color = Color3.fromRGB(100, 100, 100),
			material = Enum.Material.SmoothPlastic,
			size = Vector3.new(0.3, 0.3, 1.0),
			grip = CFrame.new(0, -0.2, -0.4),
		}
	end

	local model = Instance.new("Model")
	model.Name = "WeaponModel"

	-- Main body part
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = visual.size
	body.Color = visual.color
	body.Material = visual.material
	body.CanCollide = false
	body.Massless = true
	body.Anchored = false
	body.Parent = model

	-- Weld body to the hand
	local weld = Instance.new("Motor6D")
	weld.Name = "GripWeld"
	weld.Part0 = rightHand
	weld.Part1 = body
	weld.C0 = visual.grip
	weld.Parent = body

	-- Add a barrel/accent piece for guns
	if visual.barrel then
		local barrel = Instance.new("Part")
		barrel.Name = "Barrel"
		barrel.Size = visual.barrel.size
		barrel.Color = visual.barrel.color
		barrel.Material = visual.barrel.material
		barrel.CanCollide = false
		barrel.Massless = true
		barrel.Anchored = false
		barrel.Parent = model

		local barrelWeld = Instance.new("Motor6D")
		barrelWeld.Name = "BarrelWeld"
		barrelWeld.Part0 = body
		barrelWeld.Part1 = barrel
		barrelWeld.C0 = visual.barrel.offset
		barrelWeld.Parent = barrel
	end

	-- Add a handle wrap for blades
	if visual.shape == "blade" then
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.25, 0.25, 0.6)
		handle.Color = Color3.fromRGB(50, 50, 50)
		handle.Material = Enum.Material.SmoothPlastic
		handle.CanCollide = false
		handle.Massless = true
		handle.Anchored = false
		handle.Parent = model

		local handleWeld = Instance.new("Motor6D")
		handleWeld.Name = "HandleWeld"
		handleWeld.Part0 = body
		handleWeld.Part1 = handle
		-- Place handle at the base of the blade
		handleWeld.C0 = CFrame.new(0, 0, visual.size.Z / 2 + 0.15)
		handleWeld.Parent = handle
	end

	model.PrimaryPart = body
	model.Parent = character
	currentWeaponModel = model
end

--------------------------------------------------------------------------------
-- HUD helper
--------------------------------------------------------------------------------

local function pushWeaponHud()
	local weaponDef = WeaponData[currentWeaponId]
	if not weaponDef then
		return
	end
	HUD.updateWeaponInfo(weaponDef.name, currentAmmo, weaponDef.magazineSize, isReloading)
end

local function refreshWeaponState()
	local weaponDef = WeaponData[currentWeaponId]
	if not weaponDef then
		return
	end
	currentAmmo = weaponDef.magazineSize
	isReloading = false
	lastFireTime = 0
	pushWeaponHud()
end

--------------------------------------------------------------------------------
-- Fire logic
--------------------------------------------------------------------------------

local function tryFire()
	local weaponDef = WeaponData[currentWeaponId]
	if not weaponDef then
		return
	end

	if isReloading then
		return
	end

	if weaponDef.magazineSize > 0 and currentAmmo <= 0 then
		return
	end

	local now = tick()
	local fireCooldown = 1.0 / weaponDef.fireRate
	if (now - lastFireTime) < fireCooldown then
		return
	end
	lastFireTime = now

	if weaponDef.magazineSize > 0 then
		currentAmmo -= 1
	end

	pushWeaponHud()

	local camCF = camera.CFrame
	ClientNetwork.fireServer(EventNames.WeaponFire, {
		origin = camCF.Position,
		direction = camCF.LookVector,
	})
end

--------------------------------------------------------------------------------
-- Reload logic
--------------------------------------------------------------------------------

local function tryReload()
	local weaponDef = WeaponData[currentWeaponId]
	if not weaponDef then
		return
	end

	if weaponDef.magazineSize <= 0 then
		return
	end

	if isReloading then
		return
	end
	if currentAmmo >= weaponDef.magazineSize then
		return
	end

	isReloading = true
	ClientNetwork.fireServer(EventNames.WeaponReload)
	pushWeaponHud()

	task.delay(weaponDef.reloadTime, function()
		currentAmmo = weaponDef.magazineSize
		isReloading = false
		pushWeaponHud()
	end)
end

--------------------------------------------------------------------------------
-- Input handling
--------------------------------------------------------------------------------

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		tryFire()
	elseif input.KeyCode == Enum.KeyCode.R then
		tryReload()
	end
end

--------------------------------------------------------------------------------
-- Network listeners
--------------------------------------------------------------------------------

local function onWeaponHitConfirm(_data: any)
	print("[WeaponController] Hit confirmed on", _data.targetName)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function WeaponController.setWeapon(weaponId: string)
	currentWeaponId = weaponId
	refreshWeaponState()
	createWeaponModel(weaponId)
end

function WeaponController.getAmmo(): number
	return currentAmmo
end

function WeaponController.getIsReloading(): boolean
	return isReloading
end

function WeaponController.init()
	refreshWeaponState()

	-- Input
	UserInputService.InputBegan:Connect(onInputBegan)

	-- Network events from server
	ClientNetwork.onServerEvent(EventNames.WeaponEquip, function(weaponState)
		WeaponController.setWeapon(weaponState.weaponId)
	end)
	ClientNetwork.onServerEvent(EventNames.WeaponHitConfirm, onWeaponHitConfirm)

	-- Re-create weapon model on respawn
	localPlayer.CharacterAdded:Connect(function()
		-- Small delay to let the character fully load
		task.wait(0.2)
		if currentWeaponId then
			createWeaponModel(currentWeaponId)
		end
	end)

	-- If character already exists, equip now
	if localPlayer.Character then
		createWeaponModel(currentWeaponId)
	end

	print("[WeaponController] Initialized")
end

return WeaponController

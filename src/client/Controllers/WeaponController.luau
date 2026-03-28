--[[
	Client-side weapon handling.
	Reads player input, enforces local cooldowns for responsive feel,
	and communicates fire/reload requests to the server.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ClientNetwork = require(script.Parent.Parent.Network)
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

--[[
	Refresh local state from the weapon definition.
	Called when the weapon changes.
]]
local function refreshWeaponState()
	local weaponDef = WeaponData[currentWeaponId]
	if not weaponDef then
		return
	end
	currentAmmo = weaponDef.magazineSize
	isReloading = false
	lastFireTime = 0
end

--------------------------------------------------------------------------------
-- Fire logic
--------------------------------------------------------------------------------

--[[
	Attempt to fire the current weapon.
	Checks local cooldown and ammo, then sends the request to the server.
]]
local function tryFire()
	local weaponDef = WeaponData[currentWeaponId]
	if not weaponDef then
		return
	end

	-- Cannot fire while reloading
	if isReloading then
		return
	end

	-- Ammo check (melee = magazineSize 0 = unlimited)
	if weaponDef.magazineSize > 0 and currentAmmo <= 0 then
		return
	end

	-- Local fire rate cooldown
	local now = tick()
	local fireCooldown = 1.0 / weaponDef.fireRate
	if (now - lastFireTime) < fireCooldown then
		return
	end
	lastFireTime = now

	-- Consume ammo locally for instant feedback
	if weaponDef.magazineSize > 0 then
		currentAmmo -= 1
	end

	-- Send fire request to server with camera origin and direction
	local camCF = camera.CFrame
	ClientNetwork.fireServer(EventNames.WeaponFire, {
		origin = camCF.Position,
		direction = camCF.LookVector,
	})
end

--------------------------------------------------------------------------------
-- Reload logic
--------------------------------------------------------------------------------

--[[
	Attempt to start a reload.
	Sends the request to the server and begins a local timer for UI feedback.
]]
local function tryReload()
	local weaponDef = WeaponData[currentWeaponId]
	if not weaponDef then
		return
	end

	-- Melee weapons don't reload
	if weaponDef.magazineSize <= 0 then
		return
	end

	-- Already reloading or magazine is full
	if isReloading then
		return
	end
	if currentAmmo >= weaponDef.magazineSize then
		return
	end

	isReloading = true
	ClientNetwork.fireServer(EventNames.WeaponReload)

	-- Optimistic local reload timer (server is authoritative)
	task.delay(weaponDef.reloadTime, function()
		currentAmmo = weaponDef.magazineSize
		isReloading = false
	end)
end

--------------------------------------------------------------------------------
-- Input handling
--------------------------------------------------------------------------------

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	-- Ignore input when the player is typing in chat, etc.
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
	-- Visual hit marker will be driven by UI later.
	-- For now, log for debugging.
	print("[WeaponController] Hit confirmed on", _data.targetName)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
	Set the locally tracked weapon. Called when the server tells us
	our weapon changed (equip, upgrade, etc.).
]]
function WeaponController.setWeapon(weaponId: string)
	currentWeaponId = weaponId
	refreshWeaponState()
end

--[[
	Get the current local ammo count (for UI).
]]
function WeaponController.getAmmo(): number
	return currentAmmo
end

--[[
	Get whether the player is currently reloading (for UI).
]]
function WeaponController.getIsReloading(): boolean
	return isReloading
end

function WeaponController.init()
	-- Set up initial weapon state
	refreshWeaponState()

	-- Input
	UserInputService.InputBegan:Connect(onInputBegan)

	-- Network events from server
	ClientNetwork.onServerEvent(EventNames.WeaponHitConfirm, onWeaponHitConfirm)

	print("[WeaponController] Initialized")
end

return WeaponController

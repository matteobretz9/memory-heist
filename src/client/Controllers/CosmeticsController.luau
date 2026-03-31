--[[
	CosmeticsController — Client-side visual application of equipped cosmetics.

	Handles two cosmetic categories:
	  - WeaponSkins: tints the equipped weapon model parts and adds a PointLight
	  - KillEffects: spawns particle effects at victim position on kill

	Listens for CosmeticEquipped, ShopDataSync, WeaponEquip, and KillOccurred
	events. Re-applies visuals on respawn and weapon changes.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local CosmeticsData = require(Shared.Data.CosmeticsData)
local EventNames = require(Shared.Network.EventNames)
local ClientNetwork = require(script.Parent.Parent.Network)

local CosmeticsController = {}

local localPlayer = Players.LocalPlayer

---------------------------------------------------------------------------
-- Local state
---------------------------------------------------------------------------

local equippedWeaponSkin: string? = nil
local equippedKillEffect: string? = nil

-- Stores original Body/Barrel colors so we can restore on unequip
local originalWeaponColors: { bodyColor: Color3?, barrelColor: Color3? }? = nil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Returns a brighter version of a Color3 by lerping toward white.
local function brighten(color: Color3, amount: number?): Color3
	local t = amount or 0.4
	return color:Lerp(Color3.new(1, 1, 1), t)
end

--- Find the WeaponModel inside the local player's character.
local function getWeaponModel(): Model?
	local character = localPlayer.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("WeaponModel") :: Model?
end

---------------------------------------------------------------------------
-- Weapon Skins
---------------------------------------------------------------------------

local function storeOriginalColors()
	local weaponModel = getWeaponModel()
	if not weaponModel then
		return
	end

	local body = weaponModel:FindFirstChild("Body") :: BasePart?
	local barrel = weaponModel:FindFirstChild("Barrel") :: BasePart?

	originalWeaponColors = {
		bodyColor = body and body.Color or nil,
		barrelColor = barrel and barrel.Color or nil,
	}
end

local function applyWeaponSkin(skinId: string)
	local skinData = CosmeticsData.WeaponSkins[skinId]
	if not skinData or not skinData.color then
		return
	end

	local weaponModel = getWeaponModel()
	if not weaponModel then
		return
	end

	-- Store originals before first application
	if not originalWeaponColors then
		storeOriginalColors()
	end

	local body = weaponModel:FindFirstChild("Body") :: BasePart?
	local barrel = weaponModel:FindFirstChild("Barrel") :: BasePart?

	if body then
		body.Color = skinData.color

		-- Add or update PointLight
		local light = body:FindFirstChildOfClass("PointLight")
		if not light then
			light = Instance.new("PointLight")
			light.Range = 6
			light.Brightness = 0.8
			light.Parent = body
		end
		light.Color = skinData.color
	end

	if barrel then
		barrel.Color = brighten(skinData.color)
	end
end

local function removeWeaponSkin()
	local weaponModel = getWeaponModel()
	if not weaponModel then
		originalWeaponColors = nil
		return
	end

	local body = weaponModel:FindFirstChild("Body") :: BasePart?
	local barrel = weaponModel:FindFirstChild("Barrel") :: BasePart?

	if originalWeaponColors then
		if body and originalWeaponColors.bodyColor then
			body.Color = originalWeaponColors.bodyColor
		end
		if barrel and originalWeaponColors.barrelColor then
			barrel.Color = originalWeaponColors.barrelColor
		end
	end

	-- Remove the PointLight we added
	if body then
		local light = body:FindFirstChildOfClass("PointLight")
		if light then
			light:Destroy()
		end
	end

	originalWeaponColors = nil
end

local function refreshWeaponSkin()
	-- Reset stored originals so we re-capture from the new weapon model
	originalWeaponColors = nil
	if equippedWeaponSkin then
		storeOriginalColors()
		applyWeaponSkin(equippedWeaponSkin)
	end
end

---------------------------------------------------------------------------
-- Kill Effects
---------------------------------------------------------------------------

--- Spawn a quick debris part in workspace and auto-destroy.
local function spawnEffectPart(position: Vector3, size: Vector3, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	return part
end

local function playGlitchEffect(position: Vector3)
	for _ = 1, 10 do
		local color = Color3.fromRGB(math.random(0, 255), math.random(0, 255), math.random(0, 255))
		local size = Vector3.new(
			math.random(2, 5) / 10,
			math.random(2, 5) / 10,
			math.random(2, 5) / 10
		)
		local part = spawnEffectPart(position, size, color, Enum.Material.Neon)

		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.Velocity = Vector3.new(
			math.random(-20, 20),
			math.random(5, 25),
			math.random(-20, 20)
		)
		bodyVelocity.MaxForce = Vector3.new(1e4, 1e4, 1e4)
		bodyVelocity.Parent = part

		task.delay(1, function()
			part:Destroy()
		end)
	end
end

local function playDissolveEffect(position: Vector3)
	for _ = 1, 15 do
		local size = Vector3.new(
			math.random(2, 4) / 10,
			math.random(2, 4) / 10,
			math.random(2, 4) / 10
		)
		local offset = Vector3.new(
			math.random(-10, 10) / 10,
			math.random(0, 5) / 10,
			math.random(-10, 10) / 10
		)
		local part = spawnEffectPart(position + offset, size, Color3.fromRGB(200, 200, 255), Enum.Material.Neon)

		-- Slow upward drift
		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.Velocity = Vector3.new(
			math.random(-3, 3),
			math.random(3, 8),
			math.random(-3, 3)
		)
		bodyVelocity.MaxForce = Vector3.new(1e4, 1e4, 1e4)
		bodyVelocity.Parent = part

		-- Fade out over 1.5 seconds
		local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Linear)
		local tween = TweenService:Create(part, tweenInfo, { Transparency = 1 })
		tween:Play()

		task.delay(1.5, function()
			part:Destroy()
		end)
	end
end

local function playLightningEffect(position: Vector3)
	for _ = 1, 3 do
		local bolt = Instance.new("Part")
		bolt.Shape = Enum.PartType.Cylinder
		bolt.Size = Vector3.new(8, 0.3, 0.3) -- tall and thin (X is height for cylinders)
		bolt.Color = Color3.fromRGB(255, 255, 50)
		bolt.Material = Enum.Material.Neon
		bolt.Anchored = true
		bolt.CanCollide = false
		-- Rotate cylinder upright; offset randomly around the position
		local offsetX = math.random(-15, 15) / 10
		local offsetZ = math.random(-15, 15) / 10
		bolt.CFrame = CFrame.new(position + Vector3.new(offsetX, 4, offsetZ))
			* CFrame.Angles(0, 0, math.rad(90))
		bolt.Parent = workspace

		task.delay(0.5, function()
			bolt:Destroy()
		end)
	end
end

local function playKillEffect(effectId: string, victimName: string)
	-- Try to find victim character to get their position
	local victimPlayer = Players:FindFirstChild(victimName)
	local position: Vector3? = nil

	if victimPlayer and (victimPlayer :: Player).Character then
		local rootPart = (victimPlayer :: Player).Character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			position = (rootPart :: BasePart).Position
		end
	end

	-- If character is already gone, try to use any remaining model in workspace
	if not position then
		local victimModel = workspace:FindFirstChild(victimName)
		if victimModel then
			local rootPart = victimModel:FindFirstChild("HumanoidRootPart")
			if rootPart then
				position = (rootPart :: BasePart).Position
			end
		end
	end

	if not position then
		return
	end

	if effectId == "Glitch" then
		playGlitchEffect(position)
	elseif effectId == "Dissolve" then
		playDissolveEffect(position)
	elseif effectId == "Lightning" then
		playLightningEffect(position)
	end
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------

local function onCosmeticEquipped(data: any)
	if type(data) ~= "table" or not data.equipped then
		return
	end

	local equipped = data.equipped
	local category = data.category

	-- Update local state from the full equipped table
	equippedWeaponSkin = equipped.weaponSkin
	equippedKillEffect = equipped.killEffect

	-- Apply visual for the category that just changed
	if category == "WeaponSkins" then
		if equippedWeaponSkin then
			-- Reset originals so we capture fresh colors from the current model
			originalWeaponColors = nil
			storeOriginalColors()
			applyWeaponSkin(equippedWeaponSkin)
		else
			removeWeaponSkin()
		end
	end
	-- KillEffects don't need immediate visual application
end

local function onShopDataSync(data: any)
	if type(data) ~= "table" or not data.equipped then
		return
	end

	local equipped = data.equipped
	equippedWeaponSkin = equipped.weaponSkin
	equippedKillEffect = equipped.killEffect

	-- Apply all visuals with initial state
	refreshWeaponSkin()
end

local function onWeaponEquip(_weaponState: any)
	-- Weapon model is being recreated by WeaponController; wait briefly
	-- for the new model to be parented, then re-apply the skin.
	if equippedWeaponSkin then
		task.delay(0.1, function()
			refreshWeaponSkin()
		end)
	end
end

local function onKillOccurred(data: any)
	if type(data) ~= "table" then
		return
	end

	if data.killerName ~= localPlayer.Name then
		return
	end

	if equippedKillEffect and data.victimName then
		playKillEffect(equippedKillEffect, data.victimName)
	end
end

local function onCharacterAdded()
	-- Wait for the character to fully load
	task.wait(0.3)

	-- Re-apply weapon skin after weapon model is created
	if equippedWeaponSkin then
		task.delay(0.3, function()
			refreshWeaponSkin()
		end)
	end
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function CosmeticsController.init()
	-- Cosmetic equip/unequip events from server
	ClientNetwork.onServerEvent(EventNames.CosmeticEquipped, onCosmeticEquipped)

	-- Initial state sync when shop data arrives
	ClientNetwork.onServerEvent(EventNames.ShopDataSync, onShopDataSync)

	-- Re-apply weapon skin when weapon changes
	ClientNetwork.onServerEvent(EventNames.WeaponEquip, onWeaponEquip)

	-- Kill effects
	ClientNetwork.onServerEvent(EventNames.KillOccurred, onKillOccurred)

	-- Re-apply on respawn
	localPlayer.CharacterAdded:Connect(onCharacterAdded)

	-- If character already exists, apply now
	if localPlayer.Character then
		task.spawn(onCharacterAdded)
	end

	print("[CosmeticsController] Initialized")
end

return CosmeticsController

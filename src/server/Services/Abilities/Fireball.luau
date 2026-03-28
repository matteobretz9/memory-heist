--[[
	Fireball — Projectile attack ability.
	Creates a neon sphere that travels forward and damages the first
	enemy player it contacts. Auto-destroys after 3 seconds.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local Fireball = {}

function Fireball.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector

	-- Create the fireball projectile
	local fireball = Instance.new("Part")
	fireball.Name = "Fireball"
	fireball.Shape = Enum.PartType.Ball
	fireball.Size = Vector3.new(2, 2, 2)
	fireball.BrickColor = BrickColor.new("Bright orange")
	fireball.Material = Enum.Material.Neon
	fireball.Anchored = false
	fireball.CanCollide = false
	fireball.CFrame = rootPart.CFrame + lookVector * 3
	fireball.Parent = workspace

	-- Give it velocity in the look direction
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bodyVelocity.Velocity = lookVector * 100
	bodyVelocity.Parent = fireball

	-- Track whether the fireball has already hit something
	local hasHit = false

	-- Detect collisions with other player characters
	fireball.Touched:Connect(function(hitPart: BasePart)
		if hasHit then
			return
		end

		-- Find the character model that owns the hit part
		local hitCharacter = hitPart:FindFirstAncestorOfClass("Model")
		if not hitCharacter then
			return
		end

		-- Ignore the caster's own character
		if hitCharacter == character then
			return
		end

		-- Check if this model belongs to a player
		local targetPlayer = Players:GetPlayerFromCharacter(hitCharacter)
		if not targetPlayer then
			return
		end

		-- Confirm the target has a humanoid that is alive
		local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		hasHit = true
		DamageService.processDamage(player, targetPlayer, abilityDef.damage, "Fireball")
		fireball:Destroy()
	end)

	-- Auto-destroy after 3 seconds if nothing was hit
	task.delay(3, function()
		if fireball and fireball.Parent then
			fireball:Destroy()
		end
	end)
end

return Fireball

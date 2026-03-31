--[[
	FreezeBlast — Projectile attack ability.
	Fires a slower projectile that damages and freezes (slows) the
	first enemy hit, reducing their WalkSpeed for 3 seconds.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local FreezeBlast = {}

function FreezeBlast.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector

	-- Create the freeze projectile
	local projectile = Instance.new("Part")
	projectile.Name = "FreezeBlast"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(2.5, 2.5, 2.5)
	projectile.BrickColor = BrickColor.new("Cyan")
	projectile.Material = Enum.Material.Neon
	projectile.Anchored = false
	projectile.CanCollide = false
	projectile.CFrame = rootPart.CFrame + lookVector * 3
	projectile.Parent = workspace

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bodyVelocity.Velocity = lookVector * 60
	bodyVelocity.Parent = projectile

	local hasHit = false

	projectile.Touched:Connect(function(hitPart: BasePart)
		if hasHit then
			return
		end

		local hitCharacter = hitPart:FindFirstAncestorOfClass("Model")
		if not hitCharacter then
			return
		end

		if hitCharacter == character then
			return
		end

		local targetPlayer = Players:GetPlayerFromCharacter(hitCharacter)
		if not targetPlayer then
			return
		end

		local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		hasHit = true
		DamageService.processDamage(player, targetPlayer, abilityDef.damage, "FreezeBlast")

		-- Freeze (slow) the target
		local originalSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 4

		task.delay(3, function()
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = originalSpeed
			end
		end)

		projectile:Destroy()
	end)

	-- Auto-destroy after 4 seconds
	task.delay(4, function()
		if projectile and projectile.Parent then
			projectile:Destroy()
		end
	end)
end

return FreezeBlast

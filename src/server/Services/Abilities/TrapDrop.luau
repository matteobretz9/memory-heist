--[[
	TrapDrop — Places an anchored trap at the player's feet.
	When an enemy touches it, they take damage and are slowed for 3 seconds.
	Trap auto-destroys after 15 seconds.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local TrapDrop = {}

function TrapDrop.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	-- Create the trap part at the player's feet
	local trap = Instance.new("Part")
	trap.Name = "Trap"
	trap.Size = Vector3.new(4, 0.5, 4)
	trap.BrickColor = BrickColor.new("Bright red")
	trap.Material = Enum.Material.Neon
	trap.Transparency = 0.3
	trap.Anchored = true
	trap.CanCollide = false
	trap.CFrame = CFrame.new(rootPart.Position - Vector3.new(0, 3, 0))
	trap.Parent = workspace

	local triggered = false

	trap.Touched:Connect(function(hitPart: BasePart)
		if triggered then
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

		triggered = true
		DamageService.processDamage(player, targetPlayer, abilityDef.damage, "TrapDrop")

		-- Slow the target
		local originalSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 8

		task.delay(3, function()
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = originalSpeed
			end
		end)

		trap:Destroy()
	end)

	-- Auto-destroy after 15 seconds if not triggered
	task.delay(15, function()
		if trap and trap.Parent then
			trap:Destroy()
		end
	end)
end

return TrapDrop

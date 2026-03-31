--[[
	MagnetPull — Pull enemies toward the caster.
	Pulls all enemies within 20 studs toward the player using BodyVelocity
	(speed 60) for 0.5s. Damages each pulled enemy.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local MagnetPull = {}

function MagnetPull.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local casterPos = rootPart.Position

	for _, target in Players:GetPlayers() do
		if target == player then
			continue
		end

		local targetChar = target.Character
		if not targetChar then
			continue
		end

		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart
		local humanoid = targetChar:FindFirstChildOfClass("Humanoid")
		if not targetRoot or not humanoid or humanoid.Health <= 0 then
			continue
		end

		local dist = (targetRoot.Position - casterPos).Magnitude
		if dist > 20 then
			continue
		end

		-- Deal damage
		DamageService.processDamage(player, target, abilityDef.damage, "MagnetPull")

		-- Apply pull velocity toward caster
		local pullDir = (casterPos - targetRoot.Position).Unit
		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bodyVelocity.Velocity = pullDir * 60
		bodyVelocity.Parent = targetRoot

		-- Remove after 0.5s
		task.delay(0.5, function()
			if bodyVelocity and bodyVelocity.Parent then
				bodyVelocity:Destroy()
			end
		end)
	end
end

return MagnetPull

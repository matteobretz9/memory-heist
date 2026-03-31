--[[
	KnockbackBlast — Single-target knockback ability.
	Damages the closest enemy within 15 studs and applies
	a strong knockback pushing them away from the caster.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local KnockbackBlast = {}

function KnockbackBlast.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local origin = rootPart.Position

	local closestTarget: Player? = nil
	local closestDist = 15

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player then
			continue
		end

		local otherChar = otherPlayer.Character
		if not otherChar then
			continue
		end

		local otherRoot = otherChar:FindFirstChild("HumanoidRootPart") :: BasePart
		local otherHumanoid = otherChar:FindFirstChildOfClass("Humanoid")
		if not otherRoot or not otherHumanoid or otherHumanoid.Health <= 0 then
			continue
		end

		local dist = (otherRoot.Position - origin).Magnitude
		if dist < closestDist then
			closestDist = dist
			closestTarget = otherPlayer
		end
	end

	if not closestTarget then
		return
	end

	local targetChar = closestTarget.Character
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart

	DamageService.processDamage(player, closestTarget, abilityDef.damage, "KnockbackBlast")

	-- Strong knockback away from caster
	local knockDir = (targetRoot.Position - origin).Unit
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(100000, 100000, 100000)
	bv.Velocity = knockDir * 120
	bv.Parent = targetRoot

	task.delay(0.3, function()
		if bv and bv.Parent then
			bv:Destroy()
		end
	end)
end

return KnockbackBlast

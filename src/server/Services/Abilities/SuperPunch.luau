--[[
	SuperPunch — Melee attack ability.
	Damages the closest enemy within 8 studs in front of the player
	and applies a small knockback.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local SuperPunch = {}

function SuperPunch.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector
	local origin = rootPart.Position

	local closestTarget: Player? = nil
	local closestDist = 8

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

		local offset = (otherRoot.Position - origin)
		local dist = offset.Magnitude
		if dist > closestDist then
			continue
		end

		local dot = lookVector:Dot(offset.Unit)
		if dot > 0.5 then
			closestDist = dist
			closestTarget = otherPlayer
		end
	end

	if not closestTarget then
		return
	end

	local targetChar = closestTarget.Character
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart

	DamageService.processDamage(player, closestTarget, abilityDef.damage, "SuperPunch")

	-- Apply small knockback
	local knockDir = (targetRoot.Position - origin).Unit
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(100000, 100000, 100000)
	bv.Velocity = knockDir * 50
	bv.Parent = targetRoot

	task.delay(0.2, function()
		if bv and bv.Parent then
			bv:Destroy()
		end
	end)
end

return SuperPunch

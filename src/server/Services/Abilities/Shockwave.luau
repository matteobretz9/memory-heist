--[[
	Shockwave — Directional AOE attack ability.
	Damages enemies within 12 studs in front of the caster
	and applies knockback pushing them away.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local Shockwave = {}

function Shockwave.execute(player: Player, abilityDef: any)
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

		local offset = otherRoot.Position - origin
		local dist = offset.Magnitude
		if dist > 12 then
			continue
		end

		local dot = lookVector:Dot(offset.Unit)
		if dot <= 0.3 then
			continue
		end

		DamageService.processDamage(player, otherPlayer, abilityDef.damage, "Shockwave")

		-- Knockback away from caster
		local knockDir = offset.Unit
		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(100000, 100000, 100000)
		bv.Velocity = knockDir * 80
		bv.Parent = otherRoot

		task.delay(0.25, function()
			if bv and bv.Parent then
				bv:Destroy()
			end
		end)
	end
end

return Shockwave

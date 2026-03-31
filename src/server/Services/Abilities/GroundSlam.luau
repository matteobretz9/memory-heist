--[[
	GroundSlam — AOE attack ability.
	Slams the caster downward, then damages all enemies within 15 studs.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local GroundSlam = {}

function GroundSlam.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	-- Slam downward for animation feel
	local slamVelocity = Instance.new("BodyVelocity")
	slamVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
	slamVelocity.Velocity = Vector3.new(0, -80, 0)
	slamVelocity.Parent = rootPart

	task.delay(0.2, function()
		if slamVelocity and slamVelocity.Parent then
			slamVelocity:Destroy()
		end

		-- After landing, damage all nearby enemies
		if not rootPart or not rootPart.Parent then
			return
		end

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

			local dist = (otherRoot.Position - origin).Magnitude
			if dist <= 15 then
				DamageService.processDamage(player, otherPlayer, abilityDef.damage, "GroundSlam")
			end
		end
	end)
end

return GroundSlam

--[[
	SpinAttack — AOE attack ability.
	Damages all enemy players within 10 studs radius.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local SpinAttack = {}

function SpinAttack.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
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
		if dist <= 10 then
			DamageService.processDamage(player, otherPlayer, abilityDef.damage, "SpinAttack")
		end
	end
end

return SpinAttack

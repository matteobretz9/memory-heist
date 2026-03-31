--[[
	EMPBlast — AOE damage + disruption ability (Legendary).
	Damages all enemies within 18 studs and sets their WalkSpeed to 10
	for 3 seconds (represents electronic disruption).
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local EMPBlast = {}

function EMPBlast.execute(player: Player, abilityDef: any)
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
		if dist > 18 then
			continue
		end

		-- Deal damage
		DamageService.processDamage(player, target, abilityDef.damage, "EMPBlast")

		-- Apply speed disruption
		local originalSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 10

		task.delay(3, function()
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = originalSpeed
			end
		end)
	end
end

return EMPBlast

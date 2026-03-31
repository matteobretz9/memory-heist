--[[
	SpeedBoost — Temporarily increases the player's WalkSpeed for 5 seconds.
]]

local SpeedBoost = {}

function SpeedBoost.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 28

	task.delay(5, function()
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = originalSpeed
		end
	end)
end

return SpeedBoost

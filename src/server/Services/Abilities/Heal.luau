--[[
	Heal — Support ability.
	Immediately restores 30 HP to the player, capped at max health.
]]

local Heal = {}

function Heal.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	humanoid.Health = math.min(humanoid.Health + 30, humanoid.MaxHealth)
end

return Heal

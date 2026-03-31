--[[
	RageMode — Mythic self-buff ability.
	Increases WalkSpeed by 6, sets a 1.5x DamageBoost attribute, and
	grants +30 MaxHealth (with immediate heal) for 10 seconds.
	All bonuses are removed when the duration ends or the player dies.
]]

local RageMode = {}

function RageMode.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Speed boost
	local originalWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed += 6

	-- Damage boost
	character:SetAttribute("DamageBoost", 1.5)

	-- Health boost
	local originalMaxHealth = humanoid.MaxHealth
	humanoid.MaxHealth += 30
	humanoid.Health += 30

	local restored = false

	local function restore()
		if restored then
			return
		end
		restored = true

		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = originalWalkSpeed
			humanoid.MaxHealth = originalMaxHealth
			-- Clamp current health to new max if needed
			if humanoid.Health > originalMaxHealth then
				humanoid.Health = originalMaxHealth
			end
		end

		if character and character.Parent then
			character:SetAttribute("DamageBoost", nil)
		end
	end

	local diedConnection: RBXScriptConnection
	diedConnection = humanoid.Died:Connect(function()
		diedConnection:Disconnect()
		restore()
	end)

	task.delay(10, function()
		if diedConnection.Connected then
			diedConnection:Disconnect()
		end
		restore()
	end)
end

return RageMode

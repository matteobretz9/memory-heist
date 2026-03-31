--[[
	OverloadMode — Mythic self-buff ability.
	Increases WalkSpeed by 10 and sets a 1.3x DamageBoost attribute
	for 8 seconds. Stores an OverloadActive BoolValue on the character
	for other systems to query.
]]

local OverloadMode = {}

function OverloadMode.execute(player: Player, abilityDef: any)
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
	humanoid.WalkSpeed += 10

	-- Damage boost attribute
	character:SetAttribute("DamageBoost", 1.3)

	-- Active flag
	local flag = Instance.new("BoolValue")
	flag.Name = "OverloadActive"
	flag.Value = true
	flag.Parent = character

	local restored = false

	local function restore()
		if restored then
			return
		end
		restored = true

		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = originalWalkSpeed
		end

		if character and character.Parent then
			character:SetAttribute("DamageBoost", nil)
		end

		if flag and flag.Parent then
			flag:Destroy()
		end
	end

	local diedConnection: RBXScriptConnection
	diedConnection = humanoid.Died:Connect(function()
		diedConnection:Disconnect()
		restore()
	end)

	task.delay(8, function()
		if diedConnection.Connected then
			diedConnection:Disconnect()
		end
		restore()
	end)
end

return OverloadMode

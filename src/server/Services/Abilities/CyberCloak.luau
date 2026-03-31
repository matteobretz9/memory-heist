--[[
	CyberCloak — Mythic stealth ability.
	Semi-invisible (Transparency 0.8) and speed boost (+8 WalkSpeed)
	for 6 seconds. Superior version of Invisibility.
]]

local CyberCloak = {}

function CyberCloak.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Store originals
	local originalTransparencies: { [BasePart]: number } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			originalTransparencies[descendant] = descendant.Transparency
			descendant.Transparency = 0.8
		end
	end

	local originalNameDistance = humanoid.NameDisplayDistance
	local originalHealthDistance = humanoid.HealthDisplayDistance
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0

	local originalWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed += 8

	local restored = false

	local function restore()
		if restored then
			return
		end
		restored = true

		for part, originalValue in originalTransparencies do
			if part and part.Parent then
				part.Transparency = originalValue
			end
		end

		if humanoid and humanoid.Parent then
			humanoid.NameDisplayDistance = originalNameDistance
			humanoid.HealthDisplayDistance = originalHealthDistance
			humanoid.WalkSpeed = originalWalkSpeed
		end
	end

	local diedConnection: RBXScriptConnection
	diedConnection = humanoid.Died:Connect(function()
		diedConnection:Disconnect()
		restore()
	end)

	task.delay(6, function()
		if diedConnection.Connected then
			diedConnection:Disconnect()
		end
		restore()
	end)
end

return CyberCloak

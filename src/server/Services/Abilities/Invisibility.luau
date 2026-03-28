--[[
	Invisibility — Stealth ability.
	Makes the player invisible for 5 seconds by setting all parts to
	full transparency and hiding name/health display. Restores original
	values when the effect ends or if the character dies early.
]]

local Invisibility = {}

function Invisibility.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Store original transparency values so we can restore them
	local originalTransparencies: { [BasePart]: number } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			originalTransparencies[descendant] = descendant.Transparency
			descendant.Transparency = 1
		end
	end

	-- Hide name and health bar
	local originalNameDistance = humanoid.NameDisplayDistance
	local originalHealthDistance = humanoid.HealthDisplayDistance
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0

	-- Track whether we have already restored (prevent double-restore)
	local restored = false

	local function restore()
		if restored then
			return
		end
		restored = true

		-- Restore part transparencies
		for part, originalValue in originalTransparencies do
			if part and part.Parent then
				part.Transparency = originalValue
			end
		end

		-- Restore display distances
		if humanoid and humanoid.Parent then
			humanoid.NameDisplayDistance = originalNameDistance
			humanoid.HealthDisplayDistance = originalHealthDistance
		end
	end

	-- If the character dies while invisible, clean up immediately
	local diedConnection: RBXScriptConnection
	diedConnection = humanoid.Died:Connect(function()
		diedConnection:Disconnect()
		restore()
	end)

	-- End invisibility after 5 seconds
	task.delay(5, function()
		if diedConnection.Connected then
			diedConnection:Disconnect()
		end
		restore()
	end)
end

return Invisibility

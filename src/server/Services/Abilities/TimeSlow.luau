--[[
	TimeSlow — Crowd control ability (Legendary).
	Slows all enemies within 25 studs by setting WalkSpeed to 6
	for 4 seconds, then restores original speed. No damage.
]]

local Players = game:GetService("Players")

local TimeSlow = {}

function TimeSlow.execute(player: Player, abilityDef: any)
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
		if dist > 25 then
			continue
		end

		local originalSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 6

		task.delay(4, function()
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = originalSpeed
			end
		end)
	end
end

return TimeSlow

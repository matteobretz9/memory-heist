--[[
	TornadoSpin — Movement + AOE damage ability (Legendary).
	Player gets BodyVelocity forward (lookVector * 40) for 2 seconds.
	Every 0.3s, damages enemies within 10 studs. Can hit same enemy
	multiple times.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local TornadoSpin = {}

function TornadoSpin.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector

	-- Propel player forward
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bodyVelocity.Velocity = lookVector * 40
	bodyVelocity.Parent = rootPart

	-- Damage loop every 0.3s for 2 seconds
	task.spawn(function()
		local elapsed = 0
		while elapsed < 2 do
			task.wait(0.3)
			elapsed += 0.3

			if not rootPart or not rootPart.Parent then
				break
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
				if dist <= 10 then
					DamageService.processDamage(player, target, abilityDef.damage, "TornadoSpin")
				end
			end
		end
	end)

	-- Remove BodyVelocity after 2 seconds
	task.delay(2, function()
		if bodyVelocity and bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
	end)
end

return TornadoSpin

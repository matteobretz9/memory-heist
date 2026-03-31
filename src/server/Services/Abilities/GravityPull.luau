--[[
	GravityPull — Displacement + damage ability (Legendary).
	Picks a point 20 studs in front of the player. All enemies within
	15 studs of that point get pulled toward it via BodyVelocity for 1.5s.
	Damages each enemy on pull start.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local GravityPull = {}

function GravityPull.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector
	local pullCenter = rootPart.Position + lookVector * 20

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

		local dist = (targetRoot.Position - pullCenter).Magnitude
		if dist > 15 then
			continue
		end

		-- Deal damage on pull start
		DamageService.processDamage(player, target, abilityDef.damage, "GravityPull")

		-- Apply pull velocity toward the gravity center
		local pullDir = (pullCenter - targetRoot.Position).Unit
		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bodyVelocity.Velocity = pullDir * 50
		bodyVelocity.Parent = targetRoot

		-- Remove after 1.5s
		task.delay(1.5, function()
			if bodyVelocity and bodyVelocity.Parent then
				bodyVelocity:Destroy()
			end
		end)
	end
end

return GravityPull

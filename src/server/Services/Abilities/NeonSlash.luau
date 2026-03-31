--[[
	NeonSlash — Mythic melee ability.
	Instantly damages the closest enemy within 10 studs in front of the
	player (dot product > 0.4) and creates a brief cyan neon arc visual.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local NeonSlash = {}

function NeonSlash.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector
	local origin = rootPart.Position

	-- Find closest enemy in front
	local closestPlayer: Player? = nil
	local closestDist = 10

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player then
			continue
		end
		local otherChar = otherPlayer.Character
		if not otherChar then
			continue
		end
		local otherRoot = otherChar:FindFirstChild("HumanoidRootPart") :: BasePart
		local otherHumanoid = otherChar:FindFirstChildOfClass("Humanoid")
		if not otherRoot or not otherHumanoid or otherHumanoid.Health <= 0 then
			continue
		end
		local offset = (otherRoot.Position - origin)
		local dist = offset.Magnitude
		if dist > closestDist then
			continue
		end
		-- Dot product check: must be in front
		local dot = lookVector:Dot(offset.Unit)
		if dot > 0.4 and dist < closestDist then
			closestDist = dist
			closestPlayer = otherPlayer
		end
	end

	if closestPlayer then
		DamageService.processDamage(player, closestPlayer, abilityDef.damage, "NeonSlash")
	end

	-- Create neon arc visual
	local arc = Instance.new("Part")
	arc.Name = "NeonSlashArc"
	arc.Size = Vector3.new(6, 0.3, 1)
	arc.Color = Color3.fromRGB(0, 255, 255)
	arc.Material = Enum.Material.Neon
	arc.Anchored = true
	arc.CanCollide = false
	arc.CFrame = rootPart.CFrame + lookVector * 4
	arc.Parent = workspace

	task.delay(0.3, function()
		if arc and arc.Parent then
			arc:Destroy()
		end
	end)
end

return NeonSlash

--[[
	LaserBeam — Raycast forward ability.
	Raycasts 80 studs forward, damages the first enemy hit,
	and creates a thin neon visual beam for 0.5s.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local LaserBeam = {}

function LaserBeam.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local origin = rootPart.Position
	local direction = rootPart.CFrame.LookVector * 80

	-- Raycast ignoring the caster's character
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(origin, direction, rayParams)

	local endPos = origin + direction
	if result then
		endPos = result.Position
	end

	-- Create visual beam
	local beamLength = (endPos - origin).Magnitude
	local beamCF = CFrame.lookAt(origin, endPos) * CFrame.new(0, 0, -beamLength / 2)

	local beam = Instance.new("Part")
	beam.Name = "LaserBeam"
	beam.Size = Vector3.new(0.3, 0.3, beamLength)
	beam.BrickColor = BrickColor.new("Bright red")
	beam.Material = Enum.Material.Neon
	beam.Anchored = true
	beam.CanCollide = false
	beam.CFrame = beamCF
	beam.Parent = workspace

	-- Check if we hit an enemy
	if result then
		local hitCharacter = result.Instance:FindFirstAncestorOfClass("Model")
		if hitCharacter then
			local targetPlayer = Players:GetPlayerFromCharacter(hitCharacter)
			if targetPlayer and targetPlayer ~= player then
				local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					DamageService.processDamage(player, targetPlayer, abilityDef.damage, "LaserBeam")
				end
			end
		end
	end

	-- Destroy beam after 0.5s
	task.delay(0.5, function()
		if beam and beam.Parent then
			beam:Destroy()
		end
	end)
end

return LaserBeam

--[[
	LightningStrike — AOE damage ability.
	Raycasts from where the player is looking to find an impact point.
	Spawns a bright yellow beam from sky to ground at that point.
	After a 0.5s delay, damages all enemies within 12 studs.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local DamageService = require(script.Parent.Parent.DamageService)

local LightningStrike = {}

local MAX_RANGE = 200

function LightningStrike.execute(player: Player, abilityDef: any, aimData: any?)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	-- Determine impact position from where the player is aiming
	local impactPos = rootPart.Position

	if aimData and aimData.origin and aimData.direction then
		local origin = aimData.origin
		local direction = aimData.direction.Unit * MAX_RANGE

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { character }

		local result = Workspace:Raycast(origin, direction, rayParams)
		if result then
			impactPos = result.Position
		else
			-- No hit — use the end of the ray projected down to ground level
			local endPoint = origin + direction
			-- Raycast straight down from the end point to find ground
			local downResult = Workspace:Raycast(endPoint, Vector3.new(0, -500, 0), rayParams)
			if downResult then
				impactPos = downResult.Position
			else
				impactPos = endPoint
			end
		end
	end

	-- Create beam visual from sky to impact point
	local beam = Instance.new("Part")
	beam.Name = "LightningStrike"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(80, 3, 3)
	beam.BrickColor = BrickColor.new("Bright yellow")
	beam.Material = Enum.Material.Neon
	beam.Anchored = true
	beam.CanCollide = false
	beam.CFrame = CFrame.new(impactPos + Vector3.new(0, 40, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Parent = Workspace

	-- Delay damage by 0.5s
	task.delay(0.5, function()
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

			local dist = (targetRoot.Position - impactPos).Magnitude
			if dist <= 12 then
				DamageService.processDamage(player, target, abilityDef.damage, "LightningStrike")
			end
		end
	end)

	-- Destroy visual after 1s
	task.delay(1, function()
		if beam and beam.Parent then
			beam:Destroy()
		end
	end)
end

return LightningStrike

--[[
	PlasmaCannon — Mythic projectile ability.
	Fires a large neon projectile (3,3,3) at speed 70. On contact with an
	enemy or after 3 seconds, it explodes dealing AoE damage to all enemies
	within 12 studs and creates a brief large sphere visual.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local PlasmaCannon = {}

local function explode(player: Player, position: Vector3, damage: number)
	-- Damage all enemies within 12 studs
	local RADIUS = 12
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
		if (otherRoot.Position - position).Magnitude <= RADIUS then
			DamageService.processDamage(player, otherPlayer, damage, "PlasmaCannon")
		end
	end

	-- Explosion visual
	local sphere = Instance.new("Part")
	sphere.Name = "PlasmaExplosion"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(20, 20, 20)
	sphere.Color = Color3.fromRGB(170, 0, 255)
	sphere.Material = Enum.Material.Neon
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.Transparency = 0.4
	sphere.CFrame = CFrame.new(position)
	sphere.Parent = workspace

	task.delay(0.5, function()
		if sphere and sphere.Parent then
			sphere:Destroy()
		end
	end)
end

function PlasmaCannon.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector

	-- Create the plasma projectile
	local projectile = Instance.new("Part")
	projectile.Name = "PlasmaProjectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(3, 3, 3)
	projectile.Color = Color3.fromRGB(170, 0, 255)
	projectile.Material = Enum.Material.Neon
	projectile.Anchored = false
	projectile.CanCollide = false
	projectile.CFrame = rootPart.CFrame + lookVector * 4
	projectile.Parent = workspace

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bodyVelocity.Velocity = lookVector * 70
	bodyVelocity.Parent = projectile

	local hasExploded = false

	-- Detect enemy contact
	projectile.Touched:Connect(function(hitPart: BasePart)
		if hasExploded then
			return
		end
		local hitCharacter = hitPart:FindFirstAncestorOfClass("Model")
		if not hitCharacter or hitCharacter == character then
			return
		end
		local targetPlayer = Players:GetPlayerFromCharacter(hitCharacter)
		if not targetPlayer then
			return
		end
		local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		hasExploded = true
		local pos = projectile.Position
		projectile:Destroy()
		explode(player, pos, abilityDef.damage)
	end)

	-- Auto-explode after 3 seconds
	task.delay(3, function()
		if hasExploded then
			return
		end
		hasExploded = true
		local pos = projectile.Position
		if projectile and projectile.Parent then
			projectile:Destroy()
		end
		explode(player, pos, abilityDef.damage)
	end)
end

return PlasmaCannon

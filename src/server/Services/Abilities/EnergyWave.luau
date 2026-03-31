--[[
	EnergyWave — Wide projectile ability.
	Spawns a wide thin neon Part (10,3,1) that travels forward at speed 80
	for 2 seconds. Damages enemies it touches (Fireball pattern but wider).
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local EnergyWave = {}

function EnergyWave.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector

	-- Create wide wave projectile
	local wave = Instance.new("Part")
	wave.Name = "EnergyWave"
	wave.Size = Vector3.new(10, 3, 1)
	wave.BrickColor = BrickColor.new("Cyan")
	wave.Material = Enum.Material.Neon
	wave.Anchored = false
	wave.CanCollide = false
	wave.CFrame = rootPart.CFrame + lookVector * 4
	wave.Parent = workspace

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bodyVelocity.Velocity = lookVector * 80
	bodyVelocity.Parent = wave

	-- Track which players have been hit to prevent double damage
	local hitPlayers: { [Player]: boolean } = {}

	wave.Touched:Connect(function(hitPart: BasePart)
		local hitCharacter = hitPart:FindFirstAncestorOfClass("Model")
		if not hitCharacter then
			return
		end

		if hitCharacter == character then
			return
		end

		local targetPlayer = Players:GetPlayerFromCharacter(hitCharacter)
		if not targetPlayer then
			return
		end

		if hitPlayers[targetPlayer] then
			return
		end

		local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		hitPlayers[targetPlayer] = true
		DamageService.processDamage(player, targetPlayer, abilityDef.damage, "EnergyWave")
	end)

	-- Auto-destroy after 2 seconds
	task.delay(2, function()
		if wave and wave.Parent then
			wave:Destroy()
		end
	end)
end

return EnergyWave

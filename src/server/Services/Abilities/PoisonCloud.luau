--[[
	PoisonCloud — DOT area ability.
	Spawns a green semi-transparent sphere at the player's position.
	Every 1 second for 5 seconds, damages all enemies inside the radius.
	Destroys the cloud after the effect ends.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local PoisonCloud = {}

function PoisonCloud.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local cloudPos = rootPart.Position

	-- Create cloud visual
	local cloud = Instance.new("Part")
	cloud.Name = "PoisonCloud"
	cloud.Shape = Enum.PartType.Ball
	cloud.Size = Vector3.new(18, 18, 18)
	cloud.BrickColor = BrickColor.new("Bright green")
	cloud.Material = Enum.Material.Neon
	cloud.Transparency = 0.5
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CFrame = CFrame.new(cloudPos)
	cloud.Parent = workspace

	local radius = 9 -- half the sphere diameter

	-- Tick damage every 1s for 5 ticks
	task.spawn(function()
		for i = 1, 5 do
			task.wait(1)

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

				local dist = (targetRoot.Position - cloudPos).Magnitude
				if dist <= radius then
					DamageService.processDamage(player, target, abilityDef.damage, "PoisonCloud")
				end
			end
		end

		-- Destroy cloud after all ticks
		if cloud and cloud.Parent then
			cloud:Destroy()
		end
	end)
end

return PoisonCloud

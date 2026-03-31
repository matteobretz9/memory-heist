--[[
	DroneStrike — Mythic offensive ability.
	Spawns a dark drone Part above the player that follows them for 6 seconds.
	Every 1s the drone raycasts downward and damages the closest enemy within
	15 studs beneath it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DamageService = require(script.Parent.Parent.DamageService)

local DroneStrike = {}

function DroneStrike.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	-- Create the drone
	local drone = Instance.new("Part")
	drone.Name = "DroneStrike"
	drone.Size = Vector3.new(2, 1, 3)
	drone.BrickColor = BrickColor.new("Really black")
	drone.Material = Enum.Material.SmoothPlastic
	drone.Anchored = true
	drone.CanCollide = false
	drone.CFrame = rootPart.CFrame + Vector3.new(0, 20, 0)
	drone.Parent = workspace

	local DURATION = 6
	local TICK_INTERVAL = 1
	local RANGE = 15
	local elapsed = 0
	local tickTimer = 0

	-- Follow player and scan for enemies
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= DURATION or not rootPart or not rootPart.Parent then
			connection:Disconnect()
			if drone and drone.Parent then
				drone:Destroy()
			end
			return
		end

		-- Follow player position
		drone.CFrame = CFrame.new(rootPart.Position + Vector3.new(0, 20, 0))

		-- Damage tick
		tickTimer += dt
		if tickTimer < TICK_INTERVAL then
			return
		end
		tickTimer -= TICK_INTERVAL

		-- Find closest enemy below drone
		local dronePos = drone.Position
		local closestPlayer: Player? = nil
		local closestDist = RANGE

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
			local offset = otherRoot.Position - dronePos
			-- Must be below the drone
			if offset.Y > 0 then
				continue
			end
			local dist = offset.Magnitude
			if dist < closestDist then
				closestDist = dist
				closestPlayer = otherPlayer
			end
		end

		if closestPlayer then
			DamageService.processDamage(player, closestPlayer, abilityDef.damage, "DroneStrike")
		end
	end)

	-- Safety cleanup
	task.delay(DURATION + 1, function()
		if connection.Connected then
			connection:Disconnect()
		end
		if drone and drone.Parent then
			drone:Destroy()
		end
	end)
end

return DroneStrike

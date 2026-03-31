--[[
	PulseDash — Mythic movement/attack ability.
	Dashes forward at high speed (BodyVelocity lookVector*120 for 0.4s)
	and damages all enemies within 6 studs along the path. Each enemy
	can only be hit once per dash.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DamageService = require(script.Parent.Parent.DamageService)

local PulseDash = {}

function PulseDash.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector

	-- Create the dash velocity
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
	bodyVelocity.Velocity = lookVector * 120
	bodyVelocity.P = 10000
	bodyVelocity.Parent = rootPart

	-- Track hit enemies to prevent double damage
	local hitPlayers: { [Player]: boolean } = {}
	local RANGE = 6
	local elapsed = 0
	local DURATION = 0.4

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= DURATION or not rootPart or not rootPart.Parent then
			connection:Disconnect()
			return
		end

		local origin = rootPart.Position
		for _, otherPlayer in Players:GetPlayers() do
			if otherPlayer == player or hitPlayers[otherPlayer] then
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
			local dist = (otherRoot.Position - origin).Magnitude
			if dist <= RANGE then
				hitPlayers[otherPlayer] = true
				DamageService.processDamage(player, otherPlayer, abilityDef.damage, "PulseDash")
			end
		end
	end)

	-- Remove BodyVelocity after dash duration
	task.delay(DURATION, function()
		if connection.Connected then
			connection:Disconnect()
		end
		if bodyVelocity and bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
	end)
end

return PulseDash

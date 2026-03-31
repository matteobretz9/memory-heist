--[[
	DataHack — Mythic debuff ability.
	Targets the closest enemy within 20 studs, deals minor damage, and
	reduces their WalkSpeed to 8 and JumpPower to 20 for 4 seconds.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local DataHack = {}

function DataHack.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local origin = rootPart.Position

	-- Find closest enemy within 20 studs
	local closestPlayer: Player? = nil
	local closestDist = 20

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
		local dist = (otherRoot.Position - origin).Magnitude
		if dist < closestDist then
			closestDist = dist
			closestPlayer = otherPlayer
		end
	end

	if not closestPlayer then
		return
	end

	-- Deal damage
	DamageService.processDamage(player, closestPlayer, abilityDef.damage, "DataHack")

	-- Apply debuff
	local targetChar = closestPlayer.Character
	if not targetChar then
		return
	end
	local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return
	end

	local originalWalkSpeed = targetHumanoid.WalkSpeed
	local originalJumpPower = targetHumanoid.JumpPower
	targetHumanoid.WalkSpeed = 8
	targetHumanoid.JumpPower = 20

	local restored = false

	local function restore()
		if restored then
			return
		end
		restored = true
		if targetHumanoid and targetHumanoid.Parent then
			targetHumanoid.WalkSpeed = originalWalkSpeed
			targetHumanoid.JumpPower = originalJumpPower
		end
	end

	local diedConnection: RBXScriptConnection
	diedConnection = targetHumanoid.Died:Connect(function()
		diedConnection:Disconnect()
		restore()
	end)

	task.delay(4, function()
		if diedConnection.Connected then
			diedConnection:Disconnect()
		end
		restore()
	end)
end

return DataHack

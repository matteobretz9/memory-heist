--[[
	RocketJump — Movement ability.
	Launches the player upward and slightly forward for a powerful
	rocket-jump effect. No damage dealt.
]]

local RocketJump = {}

function RocketJump.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
	bodyVelocity.Velocity = Vector3.new(0, 120, 0) + lookVector * 30
	bodyVelocity.P = 10000
	bodyVelocity.Parent = rootPart

	task.delay(0.3, function()
		if bodyVelocity and bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
	end)
end

return RocketJump

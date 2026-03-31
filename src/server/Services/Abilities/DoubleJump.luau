--[[
	DoubleJump — Movement ability.
	Allows one extra jump while airborne. Resets when the player lands.
	Uses a BoolValue flag on the character to track whether the
	double jump has been used this airborne cycle.
]]

local RunService = game:GetService("RunService")

local DoubleJump = {}

-- Track per-player landing connections so we don't leak them
local landingConnections: { [number]: RBXScriptConnection } = {}

function DoubleJump.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Must be in the air (Freefall or Jumping state)
	local state = humanoid:GetState()
	if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then
		return
	end

	-- Check if already used this airborne cycle
	local usedFlag = character:FindFirstChild("DoubleJumpUsed")
	if usedFlag and usedFlag.Value == true then
		return
	end

	-- Mark as used
	if not usedFlag then
		usedFlag = Instance.new("BoolValue")
		usedFlag.Name = "DoubleJumpUsed"
		usedFlag.Parent = character
	end
	usedFlag.Value = true

	-- Apply upward boost equal to a normal jump, added on top of current
	-- vertical velocity. This means if used right after the first jump
	-- the player goes roughly twice as high.
	local jumpVelocity = humanoid.JumpPower -- default is 50
	if not humanoid.UseJumpPower then
		jumpVelocity = math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)
	end

	local currentVel = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(
		currentVel.X,
		currentVel.Y + jumpVelocity,
		currentVel.Z
	)

	-- Set up landing detection to reset the flag (only once per character)
	if not landingConnections[player.UserId] then
		landingConnections[player.UserId] = humanoid.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Running then
				local flag = character:FindFirstChild("DoubleJumpUsed")
				if flag then
					flag.Value = false
				end
			end
		end)

		-- Clean up when character is removed
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(workspace) then
				local conn = landingConnections[player.UserId]
				if conn then
					conn:Disconnect()
					landingConnections[player.UserId] = nil
				end
			end
		end)
	end
end

return DoubleJump

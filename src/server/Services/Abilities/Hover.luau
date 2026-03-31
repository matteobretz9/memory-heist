--[[
	Hover — Movement ability.
	Holds the player at their current height for 4 seconds using a
	BodyPosition, then releases them. Does not push upward continuously.
]]

local Hover = {}

function Hover.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	-- Lock the player at their current Y position (allow X/Z movement)
	local hoverPos = rootPart.Position
	local bodyPosition = Instance.new("BodyPosition")
	bodyPosition.MaxForce = Vector3.new(0, 100000, 0) -- only control Y axis
	bodyPosition.Position = Vector3.new(hoverPos.X, hoverPos.Y, hoverPos.Z)
	bodyPosition.P = 5000
	bodyPosition.D = 500
	bodyPosition.Parent = rootPart

	-- Update the X/Z to follow the player while keeping Y locked
	local conn
	conn = game:GetService("RunService").Heartbeat:Connect(function()
		if not bodyPosition or not bodyPosition.Parent then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local currentPos = rootPart.Position
		bodyPosition.Position = Vector3.new(currentPos.X, hoverPos.Y, currentPos.Z)
	end)

	task.delay(4, function()
		if conn then
			conn:Disconnect()
		end
		if bodyPosition and bodyPosition.Parent then
			bodyPosition:Destroy()
		end
	end)
end

return Hover

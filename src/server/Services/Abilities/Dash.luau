--[[
	Dash — Movement ability.
	Propels the player ~30 studs forward over ~0.2 seconds using a BodyVelocity.
]]

local Dash = {}

function Dash.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	-- Calculate dash direction from the character's facing direction
	local lookVector = rootPart.CFrame.LookVector

	-- Create a BodyVelocity to propel the player forward
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
	bodyVelocity.Velocity = lookVector * 150
	bodyVelocity.P = 10000
	bodyVelocity.Parent = rootPart

	-- Remove after 0.2 seconds so the player travels roughly 30 studs
	task.delay(0.2, function()
		if bodyVelocity and bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
	end)
end

return Dash

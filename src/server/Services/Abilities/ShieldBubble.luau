--[[
	ShieldBubble — Defense ability.
	Creates a semi-transparent sphere around the player and grants a
	ForceField for damage immunity. Lasts 4 seconds.
]]

local RunService = game:GetService("RunService")

local ShieldBubble = {}

function ShieldBubble.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	-- Grant damage immunity via Roblox's built-in ForceField
	local forceField = Instance.new("ForceField")
	forceField.Visible = false -- we supply our own visual
	forceField.Parent = character

	-- Create a visual bubble sphere
	local bubble = Instance.new("Part")
	bubble.Name = "ShieldBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.new(10, 10, 10)
	bubble.BrickColor = BrickColor.new("Cyan")
	bubble.Material = Enum.Material.Neon
	bubble.Transparency = 0.7
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CFrame = rootPart.CFrame
	bubble.Parent = workspace

	-- Track the bubble to the player's position each frame
	local trackConnection: RBXScriptConnection
	trackConnection = RunService.Heartbeat:Connect(function()
		if not rootPart or not rootPart.Parent then
			trackConnection:Disconnect()
			return
		end
		if bubble and bubble.Parent then
			bubble.CFrame = rootPart.CFrame
		end
	end)

	-- Clean up everything after 4 seconds
	task.delay(4, function()
		trackConnection:Disconnect()

		if bubble and bubble.Parent then
			bubble:Destroy()
		end

		if forceField and forceField.Parent then
			forceField:Destroy()
		end
	end)
end

return ShieldBubble

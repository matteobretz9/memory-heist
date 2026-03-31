--[[
	HologramDecoy — Distraction ability (Legendary).
	Spawns a neon Part (2,5,1) at player position with transparency 0.4.
	The decoy moves forward slowly (BodyVelocity at speed 8) for 8 seconds.
	No damage, purely a distraction. Destroyed after duration.
]]

local HologramDecoy = {}

function HologramDecoy.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector

	-- Create decoy
	local decoy = Instance.new("Part")
	decoy.Name = "HologramDecoy"
	decoy.Size = Vector3.new(2, 5, 1)
	decoy.Material = Enum.Material.Neon
	decoy.BrickColor = BrickColor.new("Bright blue")
	decoy.Transparency = 0.4
	decoy.Anchored = false
	decoy.CanCollide = false
	decoy.CFrame = rootPart.CFrame
	decoy.Parent = workspace

	-- Move forward slowly
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bodyVelocity.Velocity = lookVector * 8
	bodyVelocity.Parent = decoy

	-- Destroy after 8 seconds
	task.delay(8, function()
		if decoy and decoy.Parent then
			decoy:Destroy()
		end
	end)
end

return HologramDecoy

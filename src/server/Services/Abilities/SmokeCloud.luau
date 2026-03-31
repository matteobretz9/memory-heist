--[[
	SmokeCloud — Visual obstruction ability.
	Spawns a large semi-transparent dark sphere at the player's position
	that lasts for 6 seconds.
]]

local SmokeCloud = {}

function SmokeCloud.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local cloud = Instance.new("Part")
	cloud.Name = "SmokeCloud"
	cloud.Shape = Enum.PartType.Ball
	cloud.Size = Vector3.new(20, 20, 20)
	cloud.BrickColor = BrickColor.new("Black")
	cloud.Material = Enum.Material.SmoothPlastic
	cloud.Transparency = 0.6
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CFrame = CFrame.new(rootPart.Position)
	cloud.Parent = workspace

	task.delay(6, function()
		if cloud and cloud.Parent then
			cloud:Destroy()
		end
	end)
end

return SmokeCloud

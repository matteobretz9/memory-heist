--[[
	IceWall — Defensive barrier ability.
	Spawns 5 anchored ice-blue Parts in a line perpendicular to the
	player's look direction, 8 studs in front. CanCollide=true.
	Destroyed after 6 seconds.
]]

local IceWall = {}

function IceWall.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector
	local rightVector = rootPart.CFrame.RightVector
	local spawnCenter = rootPart.Position + lookVector * 8

	local wallParts: { Part } = {}

	for i = -2, 2 do
		local wallPart = Instance.new("Part")
		wallPart.Name = "IceWall"
		wallPart.Size = Vector3.new(4, 8, 2)
		wallPart.BrickColor = BrickColor.new("Pastel Blue")
		wallPart.Material = Enum.Material.Ice
		wallPart.Transparency = 0.2
		wallPart.Anchored = true
		wallPart.CanCollide = true
		wallPart.CFrame = CFrame.new(spawnCenter + rightVector * (i * 4) + Vector3.new(0, 4, 0))
		wallPart.Parent = workspace
		table.insert(wallParts, wallPart)
	end

	-- Destroy after 6 seconds
	task.delay(6, function()
		for _, part in wallParts do
			if part and part.Parent then
				part:Destroy()
			end
		end
	end)
end

return IceWall

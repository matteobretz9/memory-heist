--[[
	Teleport — Movement ability.
	Instantly moves the player 40 studs forward in their look direction.
	Uses a raycast to avoid teleporting into walls; if obstructed, the
	player is placed just in front of the hit surface.
]]

local Teleport = {}

local TELEPORT_DISTANCE = 40
-- How far in front of a wall to place the player when obstructed
local WALL_OFFSET = 3

function Teleport.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local lookVector = rootPart.CFrame.LookVector
	local origin = rootPart.Position

	-- Raycast forward to check for obstructions
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }

	local rayResult = workspace:Raycast(origin, lookVector * TELEPORT_DISTANCE, raycastParams)

	if rayResult then
		-- Something is in the way; teleport to just before the hit point
		local safePosition = rayResult.Position - lookVector * WALL_OFFSET
		rootPart.CFrame = CFrame.new(safePosition, safePosition + lookVector)
	else
		-- Clear path; teleport the full distance
		rootPart.CFrame = rootPart.CFrame + lookVector * TELEPORT_DISTANCE
	end
end

return Teleport

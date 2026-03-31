--[[
	CloneSpawn — Decoy ability (Legendary).
	Creates 2 dummy clones near the player (offset left/right by 5 studs).
	Each clone is a full visual copy of the player's character.
	Clones stand still and are destroyed after 6 seconds. If an enemy
	touches a clone, deal damage and destroy it.
]]

local Players = game:GetService("Players")
local DamageService = require(script.Parent.Parent.DamageService)

local CloneSpawn = {}

--- Create a visual-only copy of the player's character.
--- Copies body parts, clothing, accessories, and body colors but strips
--- scripts, tools, and gameplay objects. The resulting model is anchored.
local function cloneCharacterAppearance(character: Model): Model?
	local clone = character:Clone()

	-- Remove things that shouldn't be on a decoy
	for _, child in clone:GetDescendants() do
		if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") then
			child:Destroy()
		end
	end

	-- Remove tools and weapon models
	for _, child in clone:GetChildren() do
		if child:IsA("Tool") or child:IsA("BackpackItem") then
			child:Destroy()
		end
	end

	-- Anchor all parts so the clone stands still
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	-- Disable the humanoid so it doesn't animate or respond to damage
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.NameDisplayDistance = 0
		humanoid.HealthDisplayDistance = 0
	end

	clone.Name = "Clone"
	return clone
end

function CloneSpawn.execute(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not rootPart then
		return
	end

	local rightVector = rootPart.CFrame.RightVector
	local offsets = { -5, 5 }

	for _, offset in offsets do
		local cloneModel = cloneCharacterAppearance(character)
		if not cloneModel then
			continue
		end

		-- Position the clone offset from the player
		local cloneRoot = cloneModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not cloneRoot then
			cloneModel:Destroy()
			continue
		end

		local targetPos = rootPart.Position + rightVector * offset
		local offsetCF = CFrame.new(targetPos) * CFrame.Angles(0, rootPart.CFrame:ToEulerAnglesYXZ())
		cloneModel:PivotTo(offsetCF)

		cloneModel.Parent = workspace

		local destroyed = false

		-- Set up touch detection on all parts of the clone
		for _, part in cloneModel:GetDescendants() do
			if not part:IsA("BasePart") then
				continue
			end

			part.Touched:Connect(function(hitPart: BasePart)
				if destroyed then
					return
				end

				local hitCharacter = hitPart:FindFirstAncestorOfClass("Model")
				if not hitCharacter or hitCharacter == character then
					return
				end

				local targetPlayer = Players:GetPlayerFromCharacter(hitCharacter)
				if not targetPlayer then
					return
				end

				local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
				if not humanoid or humanoid.Health <= 0 then
					return
				end

				destroyed = true
				DamageService.processDamage(player, targetPlayer, abilityDef.damage, "CloneSpawn")
				cloneModel:Destroy()
			end)
		end

		task.delay(6, function()
			if not destroyed and cloneModel and cloneModel.Parent then
				cloneModel:Destroy()
			end
		end)
	end
end

return CloneSpawn

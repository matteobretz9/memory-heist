--[[
	MapService — Server-side map management.

	Responsibilities:
	  - Scan Workspace for a "SpawnPoints" folder on init; create one with
	    8 default spawn points in a circle if none exists.
	  - Provide helpers to query spawn point CFrames.
	  - Teleport each player's character to a random spawn point on
	    CharacterAdded so spawns are distributed across the map.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MapData = require(Shared.Data.MapData)

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local MapService = {}

-- Cached list of spawn‐point CFrames (rebuilt once during init)
local spawnCFrames: { CFrame } = {}

-- Connections we need to clean up per-player
local playerConnections: { [number]: RBXScriptConnection } = {}

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

--- Gather CFrames from every Part child inside the given folder.
local function collectSpawnCFrames(folder: Folder)
	spawnCFrames = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(spawnCFrames, child.CFrame)
		end
	end
end

--- Create a small, invisible, anchored Part to act as a spawn marker.
local function createSpawnPart(name: string, position: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(2, 1, 2)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = parent
	return part
end

--- Generate default spawn points arranged in a circle.
local function generateDefaultSpawnPoints(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "SpawnPoints"

	local count = 8
	local radius = MapData.spawnRadius
	local y = 5

	for i = 1, count do
		local angle = (2 * math.pi / count) * (i - 1)
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		createSpawnPart("Spawn" .. i, Vector3.new(x, y, z), folder)
	end

	folder.Parent = Workspace
	return folder
end

---------------------------------------------------------------------------
-- Character spawn integration
---------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	-- Small yield to let the character fully load (HumanoidRootPart, etc.)
	task.wait(0.1)

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart and #spawnCFrames > 0 then
		rootPart.CFrame = MapService.getRandomSpawnPoint()
	end
end

local function onPlayerAdded(player: Player)
	local conn = player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	playerConnections[player.UserId] = conn

	-- Handle an already-existing character (studio quick-start)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local conn = playerConnections[player.UserId]
	if conn then
		conn:Disconnect()
	end
	playerConnections[player.UserId] = nil
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Returns a random CFrame chosen from the available spawn points.
function MapService.getRandomSpawnPoint(): CFrame
	if #spawnCFrames == 0 then
		-- Fallback: origin at Y=5
		return CFrame.new(0, 5, 0)
	end
	return spawnCFrames[math.random(1, #spawnCFrames)]
end

--- Returns a copy of all spawn point CFrames.
function MapService.getSpawnPoints(): { CFrame }
	return table.clone(spawnCFrames)
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function MapService.init()
	-- Look for an existing SpawnPoints folder in Workspace
	local folder = Workspace:FindFirstChild("SpawnPoints")

	if not folder then
		folder = generateDefaultSpawnPoints()
		print("[MapService] No SpawnPoints folder found — generated 8 default spawn points")
	end

	collectSpawnCFrames(folder)
	print("[MapService] Loaded", #spawnCFrames, "spawn points for map:", MapData.mapName)

	-- Hook player lifecycle for spawn teleportation
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players already in the game (studio)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	print("[MapService] Initialised")
end

return MapService

--[[
	Server-side networking module.
	Creates all RemoteEvents/RemoteFunctions on startup and provides
	typed wrappers for firing to clients.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventNames = require(ReplicatedStorage.Shared.Network.EventNames)

local ServerNetwork = {}
ServerNetwork._remotes = {} :: { [string]: RemoteEvent | RemoteFunction }

-- Create a folder to hold all remotes
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

function ServerNetwork.init()
	-- Create a RemoteEvent for every entry in EventNames
	for name, _ in EventNames do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotesFolder
		ServerNetwork._remotes[name] = remote
	end
end

-- Fire a remote event to a specific player
function ServerNetwork.fireClient(eventName: string, player: Player, ...: any)
	local remote = ServerNetwork._remotes[eventName]
	if remote then
		(remote :: RemoteEvent):FireClient(player, ...)
	else
		warn("[ServerNetwork] Unknown event:", eventName)
	end
end

-- Fire a remote event to all players
function ServerNetwork.fireAllClients(eventName: string, ...: any)
	local remote = ServerNetwork._remotes[eventName]
	if remote then
		(remote :: RemoteEvent):FireAllClients(...)
	else
		warn("[ServerNetwork] Unknown event:", eventName)
	end
end

-- Listen for a remote event from clients
function ServerNetwork.onClientEvent(eventName: string, callback: (Player, ...any) -> ())
	local remote = ServerNetwork._remotes[eventName]
	if remote then
		(remote :: RemoteEvent).OnServerEvent:Connect(callback)
	else
		warn("[ServerNetwork] Unknown event:", eventName)
	end
end

-- Get the raw RemoteEvent if needed
function ServerNetwork.getRemote(eventName: string): RemoteEvent?
	return ServerNetwork._remotes[eventName] :: RemoteEvent?
end

return ServerNetwork

--[[
	Client-side networking module.
	Provides typed wrappers for sending events to the server
	and listening for events from the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientNetwork = {}

-- Wait for the Remotes folder to be created by the server
local remotesFolder: Folder = nil

function ClientNetwork.init()
	remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		warn("[ClientNetwork] Remotes folder not found! Server may not have initialized.")
	end
end

-- Get a remote event by name (waits for it if needed)
local function getRemote(eventName: string): RemoteEvent?
	if not remotesFolder then
		return nil
	end
	local remote = remotesFolder:FindFirstChild(eventName)
	if not remote then
		remote = remotesFolder:WaitForChild(eventName, 5)
	end
	return remote :: RemoteEvent?
end

-- Fire a remote event to the server
function ClientNetwork.fireServer(eventName: string, ...: any)
	local remote = getRemote(eventName)
	if remote then
		(remote :: RemoteEvent):FireServer(...)
	else
		warn("[ClientNetwork] Unknown event:", eventName)
	end
end

-- Listen for a remote event from the server
function ClientNetwork.onServerEvent(eventName: string, callback: (...any) -> ())
	local remote = getRemote(eventName)
	if remote then
		(remote :: RemoteEvent).OnClientEvent:Connect(callback)
	else
		warn("[ClientNetwork] Unknown event:", eventName)
	end
end

-- Get the raw RemoteEvent if needed
function ClientNetwork.getRemote(eventName: string): RemoteEvent?
	return getRemote(eventName)
end

return ClientNetwork

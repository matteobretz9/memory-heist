--[[
	MapData — Static configuration for the current map.
]]

local MapData = {
	mapName = "CyberArena",
	roundTime = 180,
	minPlayers = 2,
	maxPlayers = 12,
	spawnRadius = 50,
}

table.freeze(MapData)
return MapData

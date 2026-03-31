--[[
	GameModeData — Configuration for all supported game modes.

	Each entry defines the rules, player limits, scoring thresholds,
	and team settings for a game mode.
]]

local GameModeData = {
	FFA = {
		name = "Free For All",
		minPlayers = 2,
		maxPlayers = 12,
		roundTime = 180,
		killsToWin = 10,
		teamBased = false,
	},

	TDM = {
		name = "Team Deathmatch",
		minPlayers = 4,
		maxPlayers = 12,
		roundTime = 240,
		killsToWin = 30,
		teamBased = true,
		teams = { "Red", "Blue" },
		teamColors = {
			Red = Color3.fromRGB(255, 60, 60),
			Blue = Color3.fromRGB(60, 60, 255),
		},
	},

	Duel = {
		name = "1v1 Duel",
		minPlayers = 2,
		maxPlayers = 2,
		roundTime = 120,
		killsToWin = 3,
		teamBased = false,
	},
}

table.freeze(GameModeData.FFA)
table.freeze(GameModeData.TDM.teamColors)
table.freeze(GameModeData.TDM.teams)
table.freeze(GameModeData.TDM)
table.freeze(GameModeData.Duel)
table.freeze(GameModeData)

return GameModeData

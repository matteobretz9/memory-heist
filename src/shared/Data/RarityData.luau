--[[
	Rarity definitions: colors, steal chances, and spawn weights.
]]

local RarityData = {
	Common = {
		order = 1,
		color = Color3.fromRGB(180, 180, 180),
		stealChance = 1.0,
		spawnWeight = 40,
	},
	Rare = {
		order = 2,
		color = Color3.fromRGB(0, 150, 255),
		stealChance = 0.70,
		spawnWeight = 25,
	},
	Epic = {
		order = 3,
		color = Color3.fromRGB(180, 0, 255),
		stealChance = 0.45,
		spawnWeight = 18,
	},
	Legendary = {
		order = 4,
		color = Color3.fromRGB(255, 200, 0),
		stealChance = 0.25,
		spawnWeight = 12,
	},
	Mythic = {
		order = 5,
		color = Color3.fromRGB(255, 50, 50),
		stealChance = 0.10,
		spawnWeight = 5,
	},
}

table.freeze(RarityData)
return RarityData

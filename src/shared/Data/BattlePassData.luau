--[[
	BattlePassData — Defines the season structure and tier rewards for the
	Battle Pass progression system.

	Each tier alternates between credit rewards and cosmetic unlocks
	(weapon skins, kill effects). Other modules read this table
	to validate claims and render the UI.
]]

local BattlePassData = {
	seasonName = "Season 1: Neural Breach",
	maxTier = 20,
	xpPerTier = 100, -- XP needed to advance one tier

	tiers = {
		{ tier = 1,  reward = "50 Credits",        rewardType = "credits",  amount = 50 },
		{ tier = 2,  reward = "Neon Pink Skin",     rewardType = "cosmetic", category = "WeaponSkins", itemId = "NeonPink" },
		{ tier = 3,  reward = "75 Credits",         rewardType = "credits",  amount = 75 },
		{ tier = 4,  reward = "100 Credits",        rewardType = "credits",  amount = 100 },
		{ tier = 5,  reward = "Dissolve Effect",    rewardType = "cosmetic", category = "KillEffects", itemId = "Dissolve" },
		{ tier = 6,  reward = "75 Credits",         rewardType = "credits",  amount = 75 },
		{ tier = 7,  reward = "100 Credits",        rewardType = "credits",  amount = 100 },
		{ tier = 8,  reward = "Cyan Edge Skin",     rewardType = "cosmetic", category = "WeaponSkins", itemId = "CyanEdge" },
		{ tier = 9,  reward = "125 Credits",        rewardType = "credits",  amount = 125 },
		{ tier = 10, reward = "100 Credits",        rewardType = "credits",  amount = 100 },
		{ tier = 11, reward = "Glitch Effect",      rewardType = "cosmetic", category = "KillEffects", itemId = "Glitch" },
		{ tier = 12, reward = "150 Credits",        rewardType = "credits",  amount = 150 },
		{ tier = 13, reward = "Inferno Glow Skin",  rewardType = "cosmetic", category = "WeaponSkins", itemId = "InfernoGlow" },
		{ tier = 14, reward = "125 Credits",        rewardType = "credits",  amount = 125 },
		{ tier = 15, reward = "Lightning Effect",   rewardType = "cosmetic", category = "KillEffects", itemId = "Lightning" },
		{ tier = 16, reward = "200 Credits",        rewardType = "credits",  amount = 200 },
		{ tier = 17, reward = "150 Credits",        rewardType = "credits",  amount = 150 },
		{ tier = 18, reward = "175 Credits",        rewardType = "credits",  amount = 175 },
		{ tier = 19, reward = "200 Credits",        rewardType = "credits",  amount = 200 },
		{ tier = 20, reward = "Void Black Skin",    rewardType = "cosmetic", category = "WeaponSkins", itemId = "VoidBlack" },
	},
}

table.freeze(BattlePassData.tiers)
table.freeze(BattlePassData)
return BattlePassData

--[[
	CosmeticsData — Defines all purchasable cosmetic items.

	Categories: WeaponSkins, KillEffects.
	Each item has a name, description, price (in credits), rarity, and
	optionally a color for visual effects.
]]

local CosmeticsData = {
	WeaponSkins = {
		CyanEdge = {
			name = "Cyan Edge",
			description = "Glowing cyan weapon trail",
			price = 200,
			rarity = "Rare",
			color = Color3.fromRGB(0, 255, 255),
		},
		InfernoGlow = {
			name = "Inferno Glow",
			description = "Fiery orange weapon aura",
			price = 350,
			rarity = "Epic",
			color = Color3.fromRGB(255, 100, 0),
		},
		VoidBlack = {
			name = "Void Black",
			description = "Dark matter weapon effect",
			price = 500,
			rarity = "Legendary",
			color = Color3.fromRGB(30, 0, 50),
		},
		NeonPink = {
			name = "Neon Pink",
			description = "Bright pink neon weapon glow",
			price = 150,
			rarity = "Common",
			color = Color3.fromRGB(255, 50, 200),
		},
	},

	KillEffects = {
		Glitch = {
			name = "Glitch Effect",
			description = "Target glitches on elimination",
			price = 400,
			rarity = "Epic",
		},
		Dissolve = {
			name = "Dissolve",
			description = "Target dissolves into particles",
			price = 300,
			rarity = "Rare",
		},
		Lightning = {
			name = "Lightning Strike",
			description = "Lightning hits on elimination",
			price = 600,
			rarity = "Legendary",
		},
	},

}

table.freeze(CosmeticsData.WeaponSkins)
table.freeze(CosmeticsData.KillEffects)
table.freeze(CosmeticsData)

return CosmeticsData

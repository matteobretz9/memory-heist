--[[
	GlitchZoneData — Definitions for all Glitch Zone types.

	Each zone has visual properties (name, color, size) and gameplay
	modifiers that the server applies while a player is inside.
]]

local GlitchZoneData = {
	SpeedZone = {
		name = "Speed Zone",
		color = Color3.fromRGB(0, 255, 100),
		speedMultiplier = 1.5,
		damageMultiplier = 1.0,
		size = Vector3.new(30, 10, 30),
	},

	DamageZone = {
		name = "Damage Zone",
		color = Color3.fromRGB(255, 50, 50),
		speedMultiplier = 1.0,
		damageMultiplier = 1.5,
		size = Vector3.new(25, 10, 25),
	},

	LowGravZone = {
		name = "Low Gravity",
		color = Color3.fromRGB(150, 50, 255),
		speedMultiplier = 1.0,
		damageMultiplier = 1.0,
		gravityMultiplier = 0.3,
		size = Vector3.new(35, 15, 35),
	},

	GlitchStorm = {
		name = "Glitch Storm",
		color = Color3.fromRGB(255, 0, 255),
		speedMultiplier = 0.8,
		damageMultiplier = 1.3,
		size = Vector3.new(40, 12, 40),
	},
}

table.freeze(GlitchZoneData)
return GlitchZoneData

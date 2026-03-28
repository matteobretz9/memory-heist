--[[
	Memory Overload tier definitions.
	Overload kicks in when a player holds more than 3 abilities.
]]

local OverloadData = {
	-- No overload at 0-3 abilities
	{
		tier = 1,
		minAbilities = 4,
		speedReduction = 0.10,
		damageReduction = 0.00,
		abilityLockChance = 0.15, -- 15% chance per check cycle
		abilityLockDuration = 3.0,
		screenGlitchIntensity = 0.3,
	},
	{
		tier = 2,
		minAbilities = 5,
		speedReduction = 0.20,
		damageReduction = 0.10,
		abilityLockChance = 0.30,
		abilityLockDuration = 4.0,
		screenGlitchIntensity = 0.6,
	},
	-- Tier 3 is theoretical (if max slots ever increase beyond 5)
	{
		tier = 3,
		minAbilities = 6,
		speedReduction = 0.30,
		damageReduction = 0.20,
		abilityLockChance = 0.50,
		abilityLockDuration = 5.0,
		screenGlitchIntensity = 1.0,
	},
}

-- How often the server checks for random ability lockouts (seconds)
local OVERLOAD_CHECK_INTERVAL = 5.0

-- Max number of ability slots a player can hold
local MAX_ABILITY_SLOTS = 5

-- Number of abilities before overload starts
local OVERLOAD_THRESHOLD = 3

table.freeze(OverloadData)

return {
	tiers = OverloadData,
	checkInterval = OVERLOAD_CHECK_INTERVAL,
	maxSlots = MAX_ABILITY_SLOTS,
	threshold = OVERLOAD_THRESHOLD,
}

--[[
	ChallengeData — Template definitions for daily and weekly challenges.

	Each challenge template has:
	  - id: unique identifier
	  - description: human-readable text shown in the UI
	  - goal: target value to complete the challenge
	  - stat: which player stat to track ("kills", "abilitiesUsed", etc.)
	  - rewardCredits: credits awarded on claim
	  - rewardXP: XP awarded on claim
]]

local ChallengeData = {
	Daily = {
		{ id = "daily_kills_5", description = "Get 5 kills", goal = 5, stat = "kills", rewardCredits = 50, rewardXP = 30 },
		{ id = "daily_kills_10", description = "Get 10 kills", goal = 10, stat = "kills", rewardCredits = 100, rewardXP = 60 },
		{ id = "daily_abilities_3", description = "Use abilities 3 times", goal = 3, stat = "abilitiesUsed", rewardCredits = 40, rewardXP = 25 },
		{ id = "daily_abilities_10", description = "Use abilities 10 times", goal = 10, stat = "abilitiesUsed", rewardCredits = 75, rewardXP = 45 },
		{ id = "daily_rounds_2", description = "Complete 2 rounds", goal = 2, stat = "roundsCompleted", rewardCredits = 60, rewardXP = 35 },
		{ id = "daily_rounds_5", description = "Complete 5 rounds", goal = 5, stat = "roundsCompleted", rewardCredits = 120, rewardXP = 70 },
		{ id = "daily_wins_1", description = "Win 1 round", goal = 1, stat = "wins", rewardCredits = 80, rewardXP = 50 },
		{ id = "daily_steals_2", description = "Steal 2 abilities", goal = 2, stat = "steals", rewardCredits = 70, rewardXP = 40 },
	},
	Weekly = {
		{ id = "weekly_kills_50", description = "Get 50 kills", goal = 50, stat = "kills", rewardCredits = 300, rewardXP = 150 },
		{ id = "weekly_wins_5", description = "Win 5 rounds", goal = 5, stat = "wins", rewardCredits = 400, rewardXP = 200 },
		{ id = "weekly_rounds_15", description = "Complete 15 rounds", goal = 15, stat = "roundsCompleted", rewardCredits = 350, rewardXP = 175 },
		{ id = "weekly_abilities_50", description = "Use abilities 50 times", goal = 50, stat = "abilitiesUsed", rewardCredits = 250, rewardXP = 125 },
	},
}

table.freeze(ChallengeData.Daily)
table.freeze(ChallengeData.Weekly)
table.freeze(ChallengeData)

return ChallengeData

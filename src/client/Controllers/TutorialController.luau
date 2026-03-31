--[[
	TutorialController -- Client-side controller for the first-join tutorial.

	Responsibilities:
	  - Wait for the player to spawn, then check if the tutorial has been seen.
	  - If not, show the guided onboarding walkthrough.
	  - Expose showTutorial() so it can be re-triggered from a settings menu.
]]

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------------
-- Module table
---------------------------------------------------------------------------
local TutorialController = {}

-- Lazy-loaded reference to the Tutorial UI module
local Tutorial = nil

local COMPLETED_FLAG_NAME = "TutorialCompleted"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function getTutorialModule()
	if not Tutorial then
		Tutorial = require(script.Parent.Parent.UI.Tutorial)
	end
	return Tutorial
end

local function hasCompletedTutorial(): boolean
	return LocalPlayer:FindFirstChild(COMPLETED_FLAG_NAME) ~= nil
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--[[
	Force-show the tutorial regardless of completion state.
	Can be called from a settings menu or debug console.
]]
function TutorialController.showTutorial()
	getTutorialModule().show()
end

---------------------------------------------------------------------------
-- Initialisation
---------------------------------------------------------------------------

function TutorialController.init()
	-- Wait for the character to spawn so the HUD has time to load
	if not LocalPlayer.Character then
		LocalPlayer.CharacterAdded:Wait()
	end
	task.wait(2)

	-- Only show automatically if the player hasn't seen it this session
	if not hasCompletedTutorial() then
		getTutorialModule().init()
	end

	print("[TutorialController] Initialised")
end

return TutorialController

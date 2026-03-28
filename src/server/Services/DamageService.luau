--[[
	Central damage pipeline.
	All damage in the game flows through processDamage() so that
	modifiers (overload penalties, buffs, etc.) are applied consistently.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ServerNetwork = require(script.Parent.Parent.Network)
local EventNames = require(ReplicatedStorage.Shared.Network.EventNames)

local DamageService = {}

-- Ordered list of damage modifiers. Each entry is { name, callback }.
-- callback signature: (attacker: Player, target: Player, amount: number, source: string) -> number
local modifiers: { { name: string, callback: (Player, Player, number, string) -> number } } = {}

--[[
	Register a damage modifier that will be applied every time processDamage is called.
	Modifiers run in the order they were registered.
	The callback receives the current damage amount and must return the (possibly modified) amount.
]]
function DamageService.registerModifier(
	name: string,
	callback: (attacker: Player, target: Player, amount: number, source: string) -> number
)
	table.insert(modifiers, { name = name, callback = callback })
end

--[[
	The single function all damage goes through.
	Applies every registered modifier, reduces the target's Humanoid health,
	and handles kill attribution + networking.
]]
function DamageService.processDamage(
	attacker: Player,
	target: Player,
	amount: number,
	source: string
)
	-- Sanity: both players must still be in the game
	if not attacker or not target then
		return
	end

	local targetChar = target.Character
	if not targetChar then
		return
	end

	local humanoid = targetChar:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Run through all registered modifiers
	local finalAmount = amount
	for _, mod in modifiers do
		finalAmount = mod.callback(attacker, target, finalAmount, source)
	end

	-- Clamp to zero minimum so modifiers can't heal via negative damage
	finalAmount = math.max(0, finalAmount)

	if finalAmount == 0 then
		return
	end

	-- Apply the damage
	humanoid.Health -= finalAmount

	-- Notify the attacker about the damage they dealt
	ServerNetwork.fireClient(EventNames.DamageDealt, attacker, {
		targetName = target.Name,
		amount = finalAmount,
		source = source,
	})

	-- Check for kill
	if humanoid.Health <= 0 then
		-- Set creator tag so Roblox's built-in KO tracking picks it up
		local creatorTag = targetChar:FindFirstChild("creator")
		if not creatorTag then
			creatorTag = Instance.new("ObjectValue")
			creatorTag.Name = "creator"
			creatorTag.Parent = humanoid
		end
		(creatorTag :: ObjectValue).Value = attacker

		-- Broadcast the kill to all players (for kill feed, score, etc.)
		ServerNetwork.fireAllClients(EventNames.KillOccurred, {
			killerName = attacker.Name,
			victimName = target.Name,
			source = source,
		})
	end
end

function DamageService.init()
	-- Nothing to initialize right now; modifiers are registered externally.
	-- This hook exists so the overload system (or other systems) can call
	-- DamageService.registerModifier() after init.
	print("[DamageService] Initialized")
end

return DamageService

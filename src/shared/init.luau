--[[
	Shared module entry point.
	Provides easy access to all shared modules.
]]

local Shared = {
	Data = require(script.Data),
	Network = require(script.Network),
	Types = require(script.Types),
}

return Shared

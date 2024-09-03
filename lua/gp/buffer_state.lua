local logger = require("gp.logger")

local M = {}

local state = {}

---@param buf number # buffer number
M.clear = function(buf)
	logger.debug("buffer state[" .. buf .. "] clear: current state: " .. vim.inspect(state[buf]))
	state[buf] = nil
end

---@param buf number # buffer number
---@return table # buffer state
M.get = function(buf)
	logger.debug("buffer state[" .. buf .. "]: get: " .. vim.inspect(state[buf]))
	return state[buf] or {}
end

---@param buf number # buffer number
---@param key string # key to get
---@return any # value of the key
M.get_key = function(buf, key)
	local value = state[buf] and state[buf][key] or nil
	logger.debug("buffer state[" .. buf .. "] get_key: key '" .. key .. "' value: " .. vim.inspect(value))
	return value
end

---@param buf number # buffer number
---@param key string # key to set
---@param value any # value to set
M.set = function(buf, key, value)
	logger.debug("buffer state[" .. buf .. "]: set: key '" .. key .. "' to value: " .. vim.inspect(value))
	state[buf] = state[buf] or {}
	state[buf][key] = value
	logger.debug("buffer state[" .. buf .. "]: set: updated state: " .. vim.inspect(state[buf]))
end

return M

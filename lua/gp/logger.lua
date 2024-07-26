--------------------------------------------------------------------------------
-- Logger module
--------------------------------------------------------------------------------

local M = {}

local file = "/dev/null"
local uuid = ""

M._log_history = {}

---@param path string # path to log file
M.set_log_file = function(path)
	uuid = string.format("%x", math.random(0, 0xFFFF)) .. string.format("%x", os.time() % 0xFFFF)
	M.debug("New neovim instance [" .. uuid .. "] started, setting log file to " .. path)
	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	file = path

	local log_file = io.open(file, "a")
	if log_file then
		for _, line in ipairs(M._log_history) do
			log_file:write(line .. "\n")
		end
		log_file:close()
	end
end

---@param msg string # message to log
---@param level integer # log level
---@param slevel string # log level as string
---@param sensitive boolean | nil # sensitive log
local log = function(msg, level, slevel, sensitive)
	local raw = string.format("[%s] [%s] %s: %s", os.date("%Y-%m-%d %H:%M:%S"), uuid, slevel, msg)

	if not sensitive then
		M._log_history[#M._log_history + 1] = raw
	end
	if #M._log_history > 100 then
		table.remove(M._log_history, 1)
	end

	local log_file = io.open(file, "a")
	if log_file then
		log_file:write(raw .. "\n")
		log_file:close()
	end

	if level <= vim.log.levels.DEBUG then
		return
	end

	vim.schedule(function()
		vim.notify("Gp.nvim: " .. msg, level, { title = "Gp.nvim" })
	end)
end

---@param msg string # error message
---@param sensitive boolean | nil # sensitive log
M.error = function(msg, sensitive)
	log(msg, vim.log.levels.ERROR, "ERROR", sensitive)
end

---@param msg string # warning message
---@param sensitive boolean | nil # sensitive log
M.warning = function(msg, sensitive)
	log(msg, vim.log.levels.WARN, "WARNING", sensitive)
end

---@param msg string # plain message
---@param sensitive boolean | nil # sensitive log
M.info = function(msg, sensitive)
	log(msg, vim.log.levels.INFO, "INFO", sensitive)
end

---@param msg string # debug message
---@param sensitive boolean | nil # sensitive log
M.debug = function(msg, sensitive)
	log(msg, vim.log.levels.DEBUG, "DEBUG", sensitive)
end

---@param msg string # trace message
---@param sensitive boolean | nil # sensitive log
M.trace = function(msg, sensitive)
	log(msg, vim.log.levels.TRACE, "TRACE", sensitive)
end

return M

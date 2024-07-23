local M = {}

local file = "/dev/null"

M._log_history = {}

---@param path string # path to log file
M.set_log_file = function(path)
	M.debug("New neovim instance started, setting log file to " .. path)
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
local log = function(msg, level, slevel)
	local raw = string.format("[%s] %s: %s", os.date("%Y-%m-%d %H:%M:%S"), slevel, msg)

	M._log_history[#M._log_history + 1] = raw
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
		vim.notify(msg, level, { title = "gp.nvim" })
	end)
end

---@param msg string # error message
M.error = function(msg)
	log(msg, vim.log.levels.ERROR, "ERROR")
end

---@param msg string # warning message
M.warning = function(msg)
	log(msg, vim.log.levels.WARN, "WARNING")
end

---@param msg string # plain message
M.info = function(msg)
	log(msg, vim.log.levels.INFO, "INFO")
end

---@param msg string # debug message
M.debug = function(msg)
	log(msg, vim.log.levels.DEBUG, "DEBUG")
end

---@param msg string # trace message
M.trace = function(msg)
	log(msg, vim.log.levels.TRACE, "TRACE")
end

return M

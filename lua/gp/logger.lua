--------------------------------------------------------------------------------
-- Logger module
--------------------------------------------------------------------------------

local uv = vim.uv or vim.loop

local M = {}

local file = "/dev/null"
local log_level = vim.log.levels.DEBUG
local uuid = ""
local store_sensitive = false

M._log_history = {}

---@return string # formatted time with milliseconds
M.now = function()
	local time = os.date("%Y-%m-%d.%H-%M-%S")
	local stamp = tostring(math.floor(uv.hrtime() / 1000000) % 1000)
	-- make sure stamp is 3 digits
	while #stamp < 3 do
		stamp = stamp .. "0"
	end
	return time .. "." .. stamp
end

---@param path string # path to log file
---@param sensitive boolean | nil # whether to store sensitive data in logs
---@param level number
M.setup = function(path, sensitive, level)
	store_sensitive = sensitive or false
	uuid = string.format("%x", math.random(0, 0xFFFF)) .. string.format("%x", os.time() % 0xFFFF)
	log_level = level
	M.debug("New neovim instance [" .. uuid .. "] started, setting log file to " .. path)
	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	file = path

	-- truncate log file if it's too big
	if uv.fs_stat(file) then
		local content = {}
		for line in io.lines(file) do
			table.insert(content, line)
		end

		if #content > 20000 then
			local truncated_file = io.open(file, "w")
			if truncated_file then
				for i, line in ipairs(content) do
					if #content - i < 10000 then
						truncated_file:write(line .. "\n")
					end
				end
				truncated_file:close()
				M.debug("Log file " .. file .. " truncated to last 10K lines")
			end
		end
	end

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
	if level <= log_level then
		return
	end

	local raw = msg
	if sensitive then
		if not store_sensitive then
			raw = "REDACTED"
		end
		raw = raw:gsub("([^\n]+)", "[SENSITIVE DATA] %1")
	end
	raw = string.format("[%s] [%s] %s: %s", M.now(), uuid, slevel, raw)

	if not sensitive then
		M._log_history[#M._log_history + 1] = raw
	end
	if #M._log_history > 20 then
		table.remove(M._log_history, 1)
	end

	local log_file = io.open(file, "a")
	if log_file then
		log_file:write(raw .. "\n")
		log_file:close()
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

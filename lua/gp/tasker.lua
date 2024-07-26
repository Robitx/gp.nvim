--------------------------------------------------------------------------------
-- Task managmenet module
--------------------------------------------------------------------------------

local logger = require("gp.logger")

local uv = vim.uv or vim.loop

local M = {}
M._handles = {}
M._queries = {} -- table of latest queries

---@param fn function # function to wrap so it only gets called once
M.once = function(fn)
	local once = false
	return function(...)
		if once then
			return
		end
		once = true
		fn(...)
	end
end

---@param N number # number of queries to keep
---@param age number # age of queries to keep in seconds
M.cleanup_old_queries = function(N, age)
	local current_time = os.time()

	local query_count = 0
	for _ in pairs(M._queries) do
		query_count = query_count + 1
	end

	if query_count <= N then
		return
	end

	for qid, query_data in pairs(M._queries) do
		if current_time - query_data.timestamp > age then
			M._queries[qid] = nil
		end
	end
end

---@param qid string # query id
---@return table | nil # query data
M.get_query = function(qid)
	if not M._queries[qid] then
		M.logger.error("query with ID " .. tostring(qid) .. " not found.")
		return nil
	end
	return M._queries[qid]
end

---@param qid string # query id
---@param payload table # query payload
M.set_query = function(qid, payload)
	M._queries[qid] = payload
	M.cleanup_old_queries(10, 60)
end

-- add a process handle and its corresponding pid to the _handles table
---@param handle userdata | nil # the Lua uv handle
---@param pid number | string # the process id
---@param buf number | nil # buffer number
M.add_handle = function(handle, pid, buf)
	table.insert(M._handles, { handle = handle, pid = pid, buf = buf })
end

-- remove a process handle from the _handles table using its pid
---@param pid number | string # the process id to find the corresponding handle
M.remove_handle = function(pid)
	for i, h in ipairs(M._handles) do
		if h.pid == pid then
			table.remove(M._handles, i)
			return
		end
	end
end

--- check if there is some pid running for the given buffer
---@param buf number | nil # buffer number
---@return boolean
M.is_busy = function(buf)
	if buf == nil then
		return false
	end
	for _, h in ipairs(M._handles) do
		if h.buf == buf then
			logger.warning("Another Gp process [" .. h.pid .. "] is already running for buffer " .. buf)
			return true
		end
	end
	return false
end

-- stop receiving gpt responses for all processes and clean the handles
---@param signal number | nil # signal to send to the process
M.stop = function(signal)
	if M._handles == {} then
		return
	end

	for _, h in ipairs(M._handles) do
		if h.handle ~= nil and not h.handle:is_closing() then
			uv.kill(h.pid, signal or 15)
		end
	end

	M._handles = {}
end

---@param buf number | nil # buffer number
---@param cmd string # command to execute
---@param args table # arguments for command
---@param callback function | nil # exit callback function(code, signal, stdout_data, stderr_data)
---@param out_reader function | nil # stdout reader function(err, data)
---@param err_reader function | nil # stderr reader function(err, data)
M.run = function(buf, cmd, args, callback, out_reader, err_reader)
	logger.debug("run command: " .. cmd .. " " .. table.concat(args, " "), true)

	local handle, pid
	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)
	local stdout_data = ""
	local stderr_data = ""

	if M.is_busy(buf) then
		return
	end

	local on_exit = M.once(vim.schedule_wrap(function(code, signal)
		stdout:read_stop()
		stderr:read_stop()
		stdout:close()
		stderr:close()
		if handle and not handle:is_closing() then
			handle:close()
		end
		if callback then
			callback(code, signal, stdout_data, stderr_data)
		end
		M.remove_handle(pid)
	end))

	handle, pid = uv.spawn(cmd, {
		args = args,
		stdio = { nil, stdout, stderr },
		hide = true,
		detach = true,
	}, on_exit)

	logger.debug(cmd .. " command started with pid: " .. pid, true)

	M.add_handle(handle, pid, buf)

	uv.read_start(stdout, function(err, data)
		if err then
			logger.error("Error reading stdout: " .. vim.inspect(err))
		end
		if data then
			stdout_data = stdout_data .. data
		end
		if out_reader then
			out_reader(err, data)
		end
	end)

	uv.read_start(stderr, function(err, data)
		if err then
			logger.error("Error reading stderr: " .. vim.inspect(err))
		end
		if data then
			stderr_data = stderr_data .. data
		end
		if err_reader then
			err_reader(err, data)
		end
	end)
end

---@param buf number | nil # buffer number
---@param directory string # directory to search in
---@param pattern string # pattern to search for
---@param callback function # callback function(results, regex)
-- results: table of elements with file, lnum and line
-- regex: string - final regex used for search
M.grep_directory = function(buf, directory, pattern, callback)
	pattern = pattern or ""
	-- replace spaces with wildcards
	pattern = pattern:gsub("%s+", ".*")
	-- strip leading and trailing non alphanumeric characters
	local re = pattern:gsub("^%W*(.-)%W*$", "%1")

	M.run(buf, "grep", { "-irEn", "--null", pattern, directory }, function(c, _, stdout, _)
		local results = {}
		if c ~= 0 then
			callback(results, re)
			return
		end
		for _, line in ipairs(vim.split(stdout, "\n")) do
			line = line:gsub("^%s*(.-)%s*$", "%1")
			-- line contains non whitespace characters
			if line:match("%S") then
				-- extract file path (until zero byte)
				local file = line:match("^(.-)%z")
				-- substract dir from file
				local filename = vim.fn.fnamemodify(file, ":t")
				local line_number = line:match("%z(%d+):")
				local line_text = line:match("%z%d+:(.*)")
				table.insert(results, {
					file = filename,
					lnum = line_number,
					line = line_text,
				})
			end
		end
		table.sort(results, function(a, b)
			if a.file == b.file then
				return a.lnum < b.lnum
			else
				return a.file > b.file
			end
		end)
		callback(results, re)
	end)
end

return M

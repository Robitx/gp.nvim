-- Gp (GPT prompt) lua plugin for Neovim
-- https://github.com/Robitx/gp.nvim/

-- Define module structure
local _H = {}
M = {
	_Name = "Gp (GPT prompt)", -- plugin name
	_H = _H, -- helper functions
	_payload = {}, -- payload for openai api
	_response = "", -- response from openai api
	config = {}, -- config variables
	cmd = {}, -- default command functions
	cmd_hooks = {}, -- user defined command functions
}

-- nicer error messages
M.error = function(msg)
	error(string.format("\n\n%s error:\n%s\n", M._Name, msg))
end

-- default config also serving as documentation example
local config = {
	-- required openai api key
	openai_api_key = os.getenv("OPENAI_API_KEY"),
	-- default prefix for all commands
	cmd_prefix = "G",
	-- example hook functions
	hooks = {
		InspectPlugin = function(plugin)
			print(string.format("%s plugin structure:\n%s", M._Name, vim.inspect(plugin)))
		end,
	},
	chat_dir = os.getenv("HOME") .. "/.local/share/nvim/gp/chats",
}

-- setup function
M.setup = function(opts)
	-- make sure opts is a table
	opts = opts or {}
	if type(opts) ~= "table" then
		M.error(string.format("setup() expects table, but got %s:\n%s", type(opts), vim.inspect(opts)))
		opts = {}
	end

	-- reset M.config
	M.config = vim.deepcopy(config)

	-- mv default M.config.hooks to M.cmd_hooks
	for k, v in pairs(M.config.hooks) do
		M.cmd_hooks[k] = v
	end
	M.config.hooks = nil

	-- merge user hooks to M.cmd_hooks
	if opts.hooks then
		for k, v in pairs(opts.hooks) do
			M.cmd_hooks[k] = v
		end
		opts.hooks = nil
	end

	-- merge user opts to M.config
	for k, v in pairs(opts) do
		M.config[k] = v
	end

	-- make sure _dirs exists
	for k, v in pairs(M.config) do
		if k:match("_dir$") and vim.fn.isdirectory(v) == 0 then
			print(M._Name .. ": creating directory " .. v)
			vim.fn.mkdir(v, "p")
		end
	end

	-- register user commands
	for hook, _ in pairs(M.cmd_hooks) do
		vim.api.nvim_create_user_command(M.config.cmd_prefix .. hook, function()
			M.call_hook(hook)
		end, { nargs = "?", range = (hook:match("^Visual") ~= nil), desc = "GPT Prompt plugin" })
	end

	-- register default commands
	for cmd, _ in pairs(M.cmd) do
		if M.cmd_hooks[cmd] == nil then
			vim.api.nvim_create_user_command(M.config.cmd_prefix .. cmd, function()
				M.cmd[cmd]()
			end, { nargs = "?", range = (cmd:match("^Visual") ~= nil), desc = "GPT Prompt plugin" })
		end
	end

	-- make sure curl is installed
	if vim.fn.executable("curl") == 0 then
		M.error("curl is not installed")
		return
	end

	-- make sure openai_api_key is set
	if M.config.openai_api_key == nil then
		M.error("openai_api_key is not set")
		return
	end
end

M.call_hook = function(name)
	if M.cmd_hooks[name] ~= nil then
		return M.cmd_hooks[name](M)
	end
	M.error("The hook '" .. name .. "' does not exist.")
end

M.query = function(payload, handler, on_exit)
	-- make sure handler is a function
	if type(handler) ~= "function" then
		M.error(string.format("query() expects handler function, but got %s:\n%s", type(handler), vim.inspect(handler)))
		return
	end

	-- store payload for debugging
	M._payload = payload

	-- prepare pipes
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)

	-- spawn curl process
	vim.loop.spawn("curl", {
		args = {
			"--no-buffer",
			"-s",
			"https://api.openai.com/v1/chat/completions",
			"-H",
			"Content-Type: application/json",
			"-H",
			"Authorization: Bearer " .. M.config.openai_api_key,
			"-d",
			vim.json.encode(payload),
			--[[ "--doesnt_exist" ]]
		},
		stdio = { nil, stdout, stderr },
	}, function(code, signal)
		-- process cleanup
		if code ~= 0 then
			M.error(string.format("OpenAI query exited: %d, %d", code, signal))
		end
		vim.loop.read_stop(stdout)
		vim.loop.read_stop(stderr)
		vim.loop.close(stdout)
		vim.loop.close(stderr)

		-- optional on_exit handler
		if type(on_exit) == "function" then
			on_exit()
		end
	end)

	-- read stdout
	vim.loop.read_start(stdout, function(err, chunk)
		if err then
			M.error("OpenAI query stdout error: " .. vim.inspect(err))
		end

		if chunk then
			-- iterate over lines
			local lines = vim.split(chunk, "\n")
			for _, line in ipairs(lines) do
				-- parse out content for handler
				line = line:gsub("^data: ", "")
				if line:match("chat%.completion%.chunk") then
					line = vim.json.decode(line)
					local content = line.choices[1].delta.content
					if content ~= nil then
						-- store response for debugging
						M._response = M._response .. content
						-- call response handler
						handler(content)
					end
				end
			end
		end
	end)

	-- read stderr
	vim.loop.read_start(stderr, function(err, chunk)
		if err then
			M.error("OpenAI query stderr error: " .. vim.inspect(err))
		end

		if chunk then
			print("stderr data: " .. vim.inspect(chunk))
		end
	end)
end

M.create_handler = function(buf, line, first_undojoin)
	buf = buf or vim.api.nvim_get_current_buf()
	local first_line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
	local skip_first_undojoin = not first_undojoin

	local response = ""
	return vim.schedule_wrap(function(chunk)
		-- undojoin takes previous change into account, so skip it for the first chunk
		if skip_first_undojoin then
			skip_first_undojoin = false
		else
			vim.cmd("undojoin")
		end

		-- clean previous response
		local line_count = #vim.split(response, "\n")
		vim.api.nvim_buf_set_lines(buf, first_line, first_line + line_count, false, {})

		-- append new response
		response = response .. chunk
		vim.cmd("undojoin")
		vim.api.nvim_buf_set_lines(buf, first_line, first_line, false, vim.split(response, "\n"))
	end)
end

M.cmd.Run = function()
	local handler = M.create_handler()
	M.query({
		model = "gpt-3.5-turbo",
		stream = true,
		messages = { { role = "user", content = "Hi. Please tell me few short jokes." } },
	}, handler)
end

--[[ M.setup() ]]
--[[ print("gp.lua loaded\n\n") ]]

--[[ M.setup({chat_dir = "/tmp/gp/chats"}) ]]
--[[ M.setup("") ]]
--[[ M.call_hook("InsectPlugin") ]]
--[[ M.call_hook("InspectPlugin") ]]

return M

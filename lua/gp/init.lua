-- Gp (GPT prompt) lua plugin for Neovim
-- https://github.com/Robitx/gp.nvim/

--------------------------------------------------------------------------------
-- Default config
--------------------------------------------------------------------------------

local config = {
	-- required openai api key
	openai_api_key = os.getenv("OPENAI_API_KEY"),
	-- api endpoint (you can change this to azure endpoint)
	openai_api_endpoint = "https://api.openai.com/v1/chat/completions",
	-- openai_api_endpoint = "https://$URL.openai.azure.com/openai/deployments/{{model}}/chat/completions?api-version=2023-03-15-preview",
	-- prefix for all commands
	cmd_prefix = "Gp",

	-- directory for storing chat files
	chat_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/gp/chats",
	-- chat model (string with model name or table with model name and parameters)
	chat_model = { model = "gpt-3.5-turbo-16k", temperature = 1.1, top_p = 1 },
	-- chat model system prompt (use this to specify the persona/role of the AI)
	chat_system_prompt = "You are a general AI assistant.",
	-- chat custom instructions (not visible in the chat but prepended to model prompt)
	chat_custom_instructions = "The user provided the additional info about how they would like you to respond:\n\n"
		.. "- If you're unsure don't guess and say you don't know instead.\n"
		.. "- Ask question if you need clarification to provide better answer.\n"
		.. "- Think deeply and carefully from first principles step by step.\n"
		.. "- Zoom out first to see the big picture and then zoom in to details.\n"
		.. "- Use Socratic method to improve your thinking and coding skills.\n"
		.. "- Don't elide any code from your output if the answer requires coding.\n"
		.. "- Take a deep breath; You've got this!\n",
	-- chat user prompt prefix
	chat_user_prefix = "🗨:",
	-- chat assistant prompt prefix
	chat_assistant_prefix = "🤖:",
	-- chat topic generation prompt
	chat_topic_gen_prompt = "Summarize the topic of our conversation above"
		.. " in two or three words. Respond only with those words.",
	-- chat topic model (string with model name or table with model name and parameters)
	chat_topic_gen_model = "gpt-3.5-turbo-16k",
	-- explicitly confirm deletion of a chat file
	chat_confirm_delete = true,
	-- conceal model parameters in chat
	chat_conceal_model_params = true,
	-- local shortcuts bound to the chat buffer
	-- (be careful to choose something which will work across specified modes)
	chat_shortcut_respond = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g><C-g>" },
	chat_shortcut_delete = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>d" },
	chat_shortcut_new = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>n" },

	-- command config and templates bellow are used by commands like GpRewrite, GpEnew, etc.
	-- command prompt prefix for asking user for input
	command_prompt_prefix = "🤖 ~ ",
	-- command model (string with model name or table with model name and parameters)
	command_model = { model = "gpt-3.5-turbo-16k", temperature = 1.1, top_p = 1 },
	-- command system prompt
	command_system_prompt = "You are an AI that strictly generates just the formated final code.",

	-- templates
	template_selection = "I have the following code from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}",
	template_rewrite = "I have the following code from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond just with the snippet of code that should be inserted.",
	template_command = "{{command}}",

	-- https://platform.openai.com/docs/guides/speech-to-text/quickstart
	-- Whisper costs $0.006 / minute (rounded to the nearest second)
	-- by eliminating silence and speeding up the tempo of the recording
	-- we can reduce the cost by 50% or more and get the results faster
	-- directory for storing whisper files
	whisper_dir = "/tmp/gp_whisper",
	-- multiplier of RMS level dB for threshold used by sox to detect silence vs speech
	whisper_silence = "1.75",
	-- whisper max recording time (mm:ss)
	whisper_max_time = "05:00",
	-- whisper tempo (1.0 is normal speed)
	whisper_tempo = "1.75",

	-- example hook functions (see Extend functionality section in the README)
	hooks = {
		InspectPlugin = function(plugin, params)
			print(string.format("Plugin structure:\n%s", vim.inspect(plugin)))
			print(string.format("Command params:\n%s", vim.inspect(params)))
		end,

		-- GpImplement rewrites the provided selection/range based on comments in the code
		Implement = function(gp, params)
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please rewrite this code according to the comment instructions."
				.. "\n\nRespond only with the snippet of finalized code:"

			gp.Prompt(
				params,
				gp.Target.rewrite,
				nil, -- command will run directly without any prompting for user input
				gp.config.command_model,
				template,
				gp.config.command_system_prompt
			)
		end,

		-- your own functions can go here, see README for more examples like
		-- :GpExplain, :GpUnitTests.., :GpBetterChatNew, ..

		-- -- example of making :%GpChatNew a dedicated command which
		-- -- opens new chat with the entire current buffer as a context
		-- BufferChatNew = function(gp, _)
		--     -- call GpChatNew command in range mode on whole buffer
		--     vim.api.nvim_command("%" .. gp.config.cmd_prefix .. "ChatNew")
		-- end,

		-- -- example of adding a custom chat command with non-default parameters
		-- -- (configured default might be gpt-3 and sometimes you might want to use gpt-4)
		-- BetterChatNew = function(gp, params)
		-- 	local chat_model = { model = "gpt-4", temperature = 0.7, top_p = 1 }
		-- 	local chat_system_prompt = "You are a general AI assistant."
		-- 	gp.cmd.ChatNew(params, chat_model, chat_system_prompt)
		-- end,

		-- -- example of adding command which writes unit tests for the selected code
		-- UnitTests = function(gp, params)
		-- 	local template = "I have the following code from {{filename}}:\n\n"
		-- 		.. "```{{filetype}}\n{{selection}}\n```\n\n"
		-- 		.. "Please respond by writing table driven unit tests for the code above."
		-- 	gp.Prompt(params, gp.Target.enew, nil, gp.config.command_model,
		--         template, gp.config.command_system_prompt)
		-- end,

		-- -- example of adding command which explains the selected code
		-- Explain = function(gp, params)
		-- 	local template = "I have the following code from {{filename}}:\n\n"
		-- 		.. "```{{filetype}}\n{{selection}}\n```\n\n"
		-- 		.. "Please respond by explaining the code above."
		-- 	gp.Prompt(params, gp.Target.popup, nil, gp.config.command_model,
		--         template, gp.config.chat_system_prompt)
		-- end,
	},
}

--------------------------------------------------------------------------------
-- Module structure
--------------------------------------------------------------------------------

local _H = {}
local M = {
	_Name = "Gp (GPT prompt)", -- plugin name
	_H = _H, -- helper functions
	_payload = {}, -- payload for openai api
	_response = "", -- response from openai api
	config = {}, -- config variables
	cmd = {}, -- default command functions
	cmd_hooks = {}, -- user defined command functions
}

--------------------------------------------------------------------------------
-- Generic helper functions
--------------------------------------------------------------------------------

---@param fn function # function to wrap so it only gets called once
_H.once = function(fn)
	local once = false
	return function(...)
		if once then
			return
		end
		once = true
		fn(...)
	end
end

---@param keys string # string of keystrokes
---@param mode string # string of vim mode ('n', 'i', 'c', etc.), default is 'n'
_H.feedkeys = function(keys, mode)
	mode = mode or "n"
	keys = vim.api.nvim_replace_termcodes(keys, true, false, true)
	vim.api.nvim_feedkeys(keys, mode, true)
end

---@param buffers table # table of buffers
---@param mode table | string # mode(s) to set keymap for
---@param key string # shortcut key
---@param callback function | string # callback or string to set keymap
---@param desc string | nil # optional description for keymap
_H.set_keymap = function(buffers, mode, key, callback, desc)
	for _, buf in ipairs(buffers) do
		vim.keymap.set(mode, key, callback, {
			noremap = true,
			silent = true,
			nowait = true,
			buffer = buf,
			desc = desc,
		})
	end
end

---@param events string | table # events to listen to
---@param buffers table | nil # buffers to listen to (nil for all buffers)
---@param callback function # callback to call
---@param gid number # augroup id
_H.autocmd = function(events, buffers, callback, gid)
	if buffers then
		for _, buf in ipairs(buffers) do
			vim.api.nvim_create_autocmd(events, {
				group = gid,
				buffer = buf,
				callback = vim.schedule_wrap(callback),
			})
		end
	else
		vim.api.nvim_create_autocmd(events, {
			group = gid,
			callback = vim.schedule_wrap(callback),
		})
	end
end

---@param file_name string # name of the file for which to delete buffers
_H.delete_buffer = function(file_name)
	-- iterate over buffer list and close all buffers with the same name
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == file_name then
			vim.api.nvim_buf_delete(b, { force = true })
		end
	end
end

---@param file_name string # name of the file for which to get buffer
---@return number | nil # buffer number
_H.get_buffer = function(file_name)
	-- iterate over buffer list and return first buffer with the same name
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == file_name then
			return b
		end
	end
	return nil
end

---@param cmd string # command to execute
---@param args table # arguments for command
---@param callback function | nil # exit callback function(code, signal, stdout_data, stderr_data)
---@param out_reader function | nil # stdout reader function(err, data)
---@param err_reader function | nil # stderr reader function(err, data)
_H.process = function(cmd, args, callback, out_reader, err_reader)
	local handle, pid
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)
	local stdout_data = ""
	local stderr_data = ""

	local on_exit = _H.once(vim.schedule_wrap(function(code, signal)
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
		M._handle = nil
		M._pid = nil
	end))

	handle, pid = vim.loop.spawn(cmd, {
		args = args,
		stdio = { nil, stdout, stderr },
		hide = true,
		detach = true,
	}, on_exit)

	M._handle = handle
	M._pid = pid

	vim.loop.read_start(stdout, function(err, data)
		if err then
			M.error("Error reading stdout: " .. vim.inspect(err))
		end
		if data then
			stdout_data = stdout_data .. data
		end
		if out_reader then
			out_reader(err, data)
		end
	end)

	vim.loop.read_start(stderr, function(err, data)
		if err then
			M.error("Error reading stderr: " .. vim.inspect(err))
		end
		if data then
			stderr_data = stderr_data .. data
		end
		if err_reader then
			err_reader(err, data)
		end
	end)
end

---@param directory string # directory to search in
---@param pattern string # pattern to search for
---@param callback function # callback function(results, regex)
-- results: table of elements with file, lnum and line
-- regex: string - final regex used for search
_H.grep_directory = function(directory, pattern, callback)
	pattern = pattern or ""
	-- replace spaces with wildcards
	pattern = pattern:gsub("%s+", ".*")
	-- strip leading and trailing non alphanumeric characters
	local re = pattern:gsub("^%W*(.-)%W*$", "%1")

	_H.process("grep", { "-irEn", "--null", pattern, directory }, function(c, _, stdout, _)
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
				local filename = file:gsub(directory .. "/", "")
				local line_number = line:match("%z(%d+):")
				local line_text = line:match("%z%d+:(.*)")
				table.insert(results, {
					file = filename,
					lnum = line_number,
					line = line_text,
				})
				-- extract line number
			end
		end
		callback(results, re)
	end)
end

---@param buf number | nil # buffer number
---@param title string # title of the popup
---@param size_func function # size_func(editor_width, editor_height) -> width, height, row, col
---@param opts table # options - gid=nul, on_leave=false, keep_buf=false
---returns table with buffer, window, close function, resize function
_H.create_popup = function(buf, title, size_func, opts)
	opts = opts or {}

	-- create buffer
	buf = buf or vim.api.nvim_create_buf(not not opts.persist, not opts.persist)

	-- setting to the middle of the editor
	local options = {
		relative = "editor",
		-- dummy values gets resized later
		width = 10,
		height = 10,
		row = 10,
		col = 10,
		style = "minimal",
		border = "single",
		title = title,
		title_pos = "center",
	}

	-- open the window and return the buffer
	local win = vim.api.nvim_open_win(buf, true, options)

	local resize = function()
		-- get editor dimensions
		local ew = vim.api.nvim_get_option("columns")
		local eh = vim.api.nvim_get_option("lines")

		local w, h, r, c = size_func(ew, eh)

		-- setting to the middle of the editor
		local o = {
			relative = "editor",
			-- half of the editor width
			width = math.floor(w),
			-- half of the editor height
			height = math.floor(h),
			-- center of the editor
			row = math.floor(r),
			-- center of the editor
			col = math.floor(c),
		}
		vim.api.nvim_win_set_config(win, o)
	end

	-- prepare unique group name and register augroup
	local gname = title:gsub("[^%w]", "_")
		.. os.date("_%Y_%m_%d_%H_%M_%S_")
		.. tostring(math.floor(vim.loop.hrtime() / 1000000) % 1000)
	-- use user defined group id or create new one
	local pgid = opts.gid or vim.api.nvim_create_augroup(gname, { clear = true })

	-- cleanup on exit
	local close = _H.once(function()
		vim.schedule(function()
			-- delete only internal augroups
			if not opts.gid then
				vim.api.nvim_del_augroup_by_id(pgid)
			end
			if win and vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
			if opts.keep_buf then
				return
			end
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end)
	end)

	-- resize on vim resize
	_H.autocmd("VimResized", { buf }, resize, pgid)

	-- cleanup on buffer exit
	_H.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { buf }, close, pgid)

	-- optional cleanup on buffer leave
	if opts.on_leave then
		-- close when entering non-popup buffer
		_H.autocmd({ "BufEnter" }, nil, function(event)
			local b = event.buf
			if b ~= buf then
				close()
				-- make sure to set current buffer after close
				vim.schedule(vim.schedule_wrap(function()
					vim.api.nvim_set_current_buf(b)
				end))
			end
		end, pgid)
	end

	-- cleanup on escape exit
	if opts.escape then
		_H.set_keymap({ buf }, "n", "<esc>", close, title .. " close on escape")
	end

	resize()
	return buf, win, close, resize
end

---@param buf number # buffer number
---@return number # returns the first line with content of specified buffer
_H.last_content_line = function(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	-- go from end and return number of last nonwhitespace line
	local line = vim.api.nvim_buf_line_count(buf)
	while line > 0 do
		local content = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
		if content:match("%S") then
			return line
		end
		line = line - 1
	end
	return 0
end

---@param buf number # buffer number
---@return string # returns filetype of specified buffer
_H.get_filetype = function(buf)
	return vim.api.nvim_buf_get_option(buf, "filetype")
end

-- returns rendered template with specified key replaced by value
_H.template_replace = function(template, key, value)
	if template == nil then
		return nil
	end

	if value == nil then
		return template:gsub(key, "")
	end

	if type(value) == "table" then
		value = table.concat(value, "\n")
	end

	value = value:gsub("%%", "%%%%")
	template = template:gsub(key, value)
	template = template:gsub("%%%%", "%%")
	return template
end

---@param template string | nil # template string
---@param key_value_pairs table # table with key value pairs
---@return string | nil # returns rendered template with keys replaced by values from key_value_pairs
_H.template_render = function(template, key_value_pairs)
	if template == nil then
		return nil
	end

	for key, value in pairs(key_value_pairs) do
		template = _H.template_replace(template, key, value)
	end

	return template
end

---@param line number # line number
---@param buf number # buffer number
---@param win number | nil # window number
_H.cursor_to_line = function(line, buf, win)
	-- don't manipulate cursor if user is elsewhere
	if buf ~= vim.api.nvim_get_current_buf() then
		return
	end

	-- check if win is valid
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end

	-- move cursor to the line
	vim.api.nvim_win_set_cursor(win, { line, 0 })
end

--------------------------------------------------------------------------------
-- Module helper functions and variables
--------------------------------------------------------------------------------

-- tries to find an .gp.md file in the root of current git repo
---@return string # returns instructions from the .gp.md file
M.repo_instructions = function()
	-- folder of the current buffer
	local cwd = vim.fn.expand("%:p:h")

	local git_dir = vim.fn.finddir(".git", cwd .. ";")

	if git_dir == "" then
		return ""
	end

	local instruct_file = git_dir:gsub(".git$", ".gp.md")

	if vim.fn.filereadable(instruct_file) == 0 then
		return ""
	end

	local lines = vim.fn.readfile(instruct_file)
	return table.concat(lines, "\n")
end

M.template_render = function(template, command, selection, filetype, filename)
	local key_value_pairs = {
		["{{command}}"] = command,
		["{{selection}}"] = selection,
		["{{filetype}}"] = filetype,
		["{{filename}}"] = filename,
	}
	return _H.template_render(template, key_value_pairs)
end

-- nicer error messages
M.error = function(msg)
	error(string.format("\n\n%s error:\n%s\n", M._Name, msg))
end

-- setup function
M._setup_called = false
---@param opts table | nil # table with options
M.setup = function(opts)
	M._setup_called = true

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
		-- strip trailing slash
		if k:match("_dir$") and type(v) == "string" then
			M.config[k] = v:gsub("/$", "")
		end
		if k:match("_dir$") and vim.fn.isdirectory(v) == 0 then
			print(M._Name .. ": creating directory " .. v)
			vim.fn.mkdir(v, "p")
		end
	end

	M.prepare_commands()

	-- register user commands
	for hook, _ in pairs(M.cmd_hooks) do
		vim.api.nvim_create_user_command(M.config.cmd_prefix .. hook, function(params)
			M.call_hook(hook, params)
		end, { nargs = "?", range = true, desc = "GPT Prompt plugin" })
	end

	-- register default commands
	for cmd, _ in pairs(M.cmd) do
		if M.cmd_hooks[cmd] == nil then
			vim.api.nvim_create_user_command(M.config.cmd_prefix .. cmd, function(params)
				M.cmd[cmd](params)
			end, { nargs = "?", range = true, desc = "GPT Prompt plugin" })
		end
	end

	-- make sure curl is installed
	if vim.fn.executable("curl") == 0 then
		M.error("curl is not installed, run :checkhealth gp")
	end

	-- make sure openai_api_key is set
	if M.config.openai_api_key == nil then
		print("gp.nvim config.openai_api_key is not set, run :checkhealth gp")
	end
end

M.Target = {
	rewrite = 0, -- for replacing the selection, range or the current line
	append = 1, -- for appending after the selection, range or the current line
	prepend = 2, -- for prepending before the selection, range or the current line
	popup = 3, -- for writing into the popup window

	-- for writing into a new buffer
	---@param filetype nil | string # nil = same as the original buffer
	---@return table # a table with type=4 and filetype=filetype
	enew = function(filetype)
		return { type = 4, filetype = filetype }
	end,
}

-- creates prompt commands for each target
M.prepare_commands = function()
	for name, target in pairs(M.Target) do
		-- uppercase first letter
		local command = name:gsub("^%l", string.upper)

		local prefix = M.config.command_prompt_prefix
		local system_prompt = M.config.command_system_prompt

		-- model to use
		local model = M.config.command_model
		-- popup is like ephemeral one off chat
		if target == M.Target.popup then
			model = M.config.chat_model
			system_prompt = M.config.chat_system_prompt
		end

		local cmd = function(params, whisper)
			-- template is chosen dynamically based on mode in which the command is called
			local template = M.config.template_command
			if params.range == 2 then
				template = M.config.template_selection
				-- rewrite needs custom template
				if target == M.Target.rewrite then
					template = M.config.template_rewrite
				end
			end
			M.Prompt(params, target, prefix, model, template, system_prompt, whisper)
		end

		M.cmd[command] = function(params)
			cmd(params)
		end

		M.cmd["Whisper" .. command] = function(params)
			M.Whisper(function(text)
				vim.schedule(function()
					cmd(params, text)
				end)
			end)
		end
	end
end

-- hook caller
M.call_hook = function(name, params)
	if M.cmd_hooks[name] ~= nil then
		return M.cmd_hooks[name](M, params)
	end
	M.error("The hook '" .. name .. "' does not exist.")
end

M.prepare_payload = function(model, default_model, messages)
	model = model or default_model

	-- if model is a string
	if type(model) == "string" then
		return {
			model = model,
			stream = true,
			messages = messages,
		}
	end

	-- if model is a table
	return {
		model = model.model,
		stream = true,
		messages = messages,
		temperature = math.max(0, math.min(2, model.temperature or 1)),
		top_p = math.max(0, math.min(1, model.top_p or 1)),
	}
end

-- gpt query
M.query = function(payload, handler, on_exit)
	-- make sure handler is a function
	if type(handler) ~= "function" then
		M.error(string.format("query() expects handler function, but got %s:\n%s", type(handler), vim.inspect(handler)))
		return
	end

	-- make sure openai_api_key is set
	if M.config.openai_api_key == nil then
		M.error("config.openai_api_key is not set, run :checkhealth gp")
		return
	end

	-- store payload for debugging
	M._payload = payload

	-- clear response
	M._raw_response = ""
	M._response = ""
	M._first_line = -1
	M._last_line = -1

	local out_reader = function()
		local buffer = ""

		---@param lines_chunk string
		local function process_lines(lines_chunk)
			local lines = vim.split(lines_chunk, "\n")
			for _, line in ipairs(lines) do
				if line ~= "" and line ~= nil then
					M._raw_response = M._raw_response .. line .. "\n"
				end
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

		-- closure for vim.loop.read_start(stdout, fn)
		return function(err, chunk)
			if err then
				M.error("OpenAI query stdout error: " .. vim.inspect(err))
			elseif chunk then
				-- add the incoming chunk to the buffer
				buffer = buffer .. chunk
				local last_newline_pos = buffer:find("\n[^\n]*$")
				if last_newline_pos then
					local complete_lines = buffer:sub(1, last_newline_pos - 1)
					-- save the rest of the buffer for the next chunk
					buffer = buffer:sub(last_newline_pos + 1)

					process_lines(complete_lines)
				end
			-- chunk is nil when EOF is reached
			else
				-- if there's remaining data in the buffer, process it
				if #buffer > 0 then
					process_lines(buffer)
				end

				if M._response == ""  then
					M.error("OpenAI query response is empty: \n" .. vim.inspect(M._raw_response))
				end

				-- optional on_exit handler
				if type(on_exit) == "function" then
					on_exit()
				end
			end
		end
	end

	-- try to replace model in endpoint (for azure)
	local endpoint = M._H.template_replace(M.config.openai_api_endpoint, "{{model}}", payload.model)

	M._H.process("curl", {
		"--no-buffer",
		"-s",
		endpoint,
		"-H",
		"Content-Type: application/json",
		-- api-key is for azure, authorization is for openai
		"-H",
		"Authorization: Bearer " .. M.config.openai_api_key,
		"-H",
		"api-key: " .. M.config.openai_api_key,
		"-d",
		vim.json.encode(payload),
		--[[ "--doesnt_exist" ]]
	}, nil, out_reader(), nil)
end

-- stop recieving gpt response
---@param signal number | nil # signal to send to the process
M.cmd.Stop = function(signal)
	if M._handle ~= nil and not M._handle:is_closing() then
		vim.loop.kill(M._pid, signal or 15)
	end
end

-- response handler
---@param buf number | nil # buffer to insert response into
---@param win number | nil # window to insert response into
---@param line number | nil # line to insert response into
---@param first_undojoin boolean | nil # whether to skip first undojoin
M.create_handler = function(buf, win, line, first_undojoin)
	buf = buf or vim.api.nvim_get_current_buf()
	local first_line = line or vim.api.nvim_win_get_cursor(win)[1] - 1
	local skip_first_undojoin = not first_undojoin

	local response = ""
	return vim.schedule_wrap(function(chunk)
		-- if buf is not valid, stop
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		-- undojoin takes previous change into account, so skip it for the first chunk
		if skip_first_undojoin then
			skip_first_undojoin = false
		else
			vim.cmd("undojoin")
		end

		-- make sure buffer still exists
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		-- clean previous response
		local line_count = #vim.split(response, "\n")
		vim.api.nvim_buf_set_lines(buf, first_line, first_line + line_count, false, {})

		-- append new response
		response = response .. chunk
		vim.cmd("undojoin")
		vim.api.nvim_buf_set_lines(buf, first_line, first_line, false, vim.split(response, "\n"))

		-- move cursor to the end of the response
		local end_line = first_line + #vim.split(response, "\n")
		M._H.cursor_to_line(end_line, buf, win)

		M._first_line = first_line
		M._last_line = end_line - 1
	end)
end

--------------------
-- Chat logic
--------------------

M.chat_template = [[
# topic: ?

- model: %s
- file: %s
- role: %s

Write your queries after %s. Use `%s` or :%sChatRespond to generate a response.
Chats are saved automatically. To delete this chat, use `%s` or :%sChatDelete.
Be cautious of very long chats. Start a fresh chat by using `%s` or :%sChatNew.

---

%s]]

M._chat_popup = { win = nil, buf = nil, close = nil }

---@return boolean # true if popup was closed
M._chat_popup_close = function()
	if M._chat_popup and M._chat_popup.win and vim.api.nvim_win_is_valid(M._chat_popup.win) then
		M._chat_popup.close()
		M._chat_popup = nil
		return true
	end
	return false
end

---@param file_name string
---@param popup boolean
M.open_chat = function(file_name, popup)
	if popup ~= nil then
		local old_buf = M._H.get_buffer(file_name)

		-- close previous popup if it exists
		M._chat_popup_close()

		-- create popup
		local b, win, close, _ = M._H.create_popup(old_buf, M._Name .. " Chat Popup", function(w, h)
			return w * 0.8, h * 0.8, h * 0.1, w * 0.1
		end, { on_leave = false, escape = false, persist = true, keep_buf = true })

		M._chat_popup = { win = win, buf = b, close = close }

		if old_buf == nil then
			-- read file into buffer and force write it
			vim.api.nvim_command("silent 0read " .. file_name)
			vim.api.nvim_command("silent file " .. file_name)
			vim.api.nvim_command("silent write! " .. file_name)
		else
			-- move cursor to the beginning of the file and scroll to the end
			M._H.feedkeys("ggG", "x")
		end

		-- delete whitespace lines at the end of the file
		local last_content_line = M._H.last_content_line(b)
		vim.api.nvim_buf_set_lines(b, last_content_line, -1, false, {})
		-- insert a new line at the end of the file
		vim.api.nvim_buf_set_lines(b, -1, -1, false, { "" })
	else
		-- is it already open in a buffer?
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_name(buf) == file_name then
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_get_buf(win) == buf then
						vim.api.nvim_set_current_win(win)
						return
					end
				end
			end
		end

		-- open in new buffer
		vim.api.nvim_command("edit " .. file_name)
	end

	-- make last.md a symlink to the last opened chat file
	local last = M.config.chat_dir .. "/last.md"
	if file_name ~= last then
		os.execute("ln -sf " .. file_name .. " " .. last)
	end

	-- disable swapping for this buffer and set filetype to markdown
	vim.api.nvim_command("setlocal filetype=markdown noswapfile")
	-- better text wrapping
	vim.api.nvim_command("setlocal wrap linebreak")
	-- auto save on TextChanged, TextChangedI
	vim.api.nvim_command("autocmd TextChanged,TextChangedI <buffer> silent! write")
	-- register shortcuts local to this buffer
	local buf = vim.api.nvim_get_current_buf()
	-- respond shortcut
	local rs = M.config.chat_shortcut_respond
	_H.set_keymap({ buf }, rs.modes, rs.shortcut, M.cmd.ChatRespond, "GPT prompt Chat Respond")
	-- delete shortcut
	local ds = M.config.chat_shortcut_delete
	_H.set_keymap({ buf }, ds.modes, ds.shortcut, M.cmd.ChatDelete, "GPT prompt Chat Delete")
	-- new shortcut
	local ns = M.config.chat_shortcut_new
	local cmd = M.config.cmd_prefix .. "ChatNew<cr>"
	for _, mode in ipairs(ns.modes) do
		if mode == "n" or mode == "i" then
			_H.set_keymap({ buf }, mode, ns.shortcut, ":" .. cmd, "GPT prompt Chat New")
		else
			_H.set_keymap({ buf }, mode, ns.shortcut, ":<C-u>'<,'>" .. cmd, "GPT prompt Chat New")
		end
	end

	-- conceal parameters in model header so it's not distracting
	if not M.config.chat_conceal_model_params then
		return
	end
	vim.opt_local.conceallevel = 2
	vim.opt_local.concealcursor = ""
	vim.fn.matchadd("Conceal", [[^- model: .*model.:.[^"]*\zs".*\ze]], 10, -1, { conceal = "…" })
	vim.fn.matchadd("Conceal", [[^- model: \zs.*model.:.\ze.*]], 10, -1, { conceal = "…" })
	vim.fn.matchadd("Conceal", [[^- role: .\{64,64\}\zs.*\ze]], 10, -1, { conceal = "…" })
	vim.fn.matchadd("Conceal", [[^- role: .[^\\]*\zs\\.*\ze]], 10, -1, { conceal = "…" })

	-- move cursor to a new line at the end of the file
	M._H.feedkeys("G", "x")
end

M.cmd.ChatNew = function(params, model, system_prompt, popup)
	-- if popup chat is open, close it and start a new one
	if M._chat_popup_close() then
		M.cmd.ChatNew(params, model, system_prompt, true)
		return
	end

	-- prepare filename
	local time = os.date("%Y-%m-%d.%H-%M-%S")
	local stamp = tostring(math.floor(vim.loop.hrtime() / 1000000) % 1000)
	-- make sure stamp is 3 digits
	while #stamp < 3 do
		stamp = "0" .. stamp
	end
	time = time .. "." .. stamp
	local filename = M.config.chat_dir .. "/" .. time .. ".md"

	-- encode as json if model is a table
	model = model or M.config.chat_model
	if type(model) == "table" then
		model = vim.json.encode(model)
	end

	-- display system prompt as single line with escaped newlines
	system_prompt = system_prompt or M.config.chat_system_prompt
	system_prompt = system_prompt:gsub("\n", "\\n")

	local template = string.format(
		M.chat_template,
		model,
		string.match(filename, "([^/]+)$"),
		system_prompt,
		M.config.chat_user_prefix,
		M.config.chat_shortcut_respond.shortcut,
		M.config.cmd_prefix,
		M.config.chat_shortcut_delete.shortcut,
		M.config.cmd_prefix,
		M.config.chat_shortcut_new.shortcut,
		M.config.cmd_prefix,
		M.config.chat_user_prefix
	)
	-- escape underscores (for markdown)
	template = template:gsub("_", "\\_")

	if params.range == 2 then
		-- get current buffer
		local buf = vim.api.nvim_get_current_buf()

		-- get range lines
		local lines = vim.api.nvim_buf_get_lines(buf, params.line1 - 1, params.line2, false)
		local selection = table.concat(lines, "\n")

		if selection ~= "" then
			local filetype = M._H.get_filetype(buf)
			local fname = vim.api.nvim_buf_get_name(buf)
			local rendered = M.template_render(M.config.template_selection, "", selection, filetype, fname)
			template = template .. "\n" .. rendered
		end
	end

	-- strip leading and trailing newlines
	template = template:gsub("^%s*(.-)%s*$", "%1") .. "\n"

	-- create chat file
	vim.fn.writefile(vim.split(template, "\n"), filename)

	-- open and configure chat file
	M.open_chat(filename, popup)
end

M.cmd.ChatToggle = function(params, model, system_prompt)
	-- close popup if it's open
	if M._chat_popup_close() then
		return
	end

	-- if the range is 2, we want to create a new chat file with the selection
	if params.range ~= 2 then
		-- check if last.md chat file exists and open it
		local last = M.config.chat_dir .. "/last.md"
		if vim.fn.filereadable(last) == 1 then
			-- resolve symlink
			last = vim.fn.resolve(last)
			M.open_chat(last, true)
			return
		end
	end

	-- create new chat file otherwise
	M.cmd.ChatNew(params, model, system_prompt, true)
end

M.delete_chat = function(file)
	-- iterate over buffer list and close all buffers with the same name
	M._H.delete_buffer(file)
	os.remove(file)
end

M.cmd.ChatDelete = function()
	-- get buffer and file
	local buf = vim.api.nvim_get_current_buf()
	local file_name = vim.api.nvim_buf_get_name(buf)

	-- check if file is in the chat dir
	if not string.match(file_name, M.config.chat_dir) then
		print("File " .. file_name .. " is not in chat dir")
		return
	end

	-- delete without confirmation
	if not M.config.chat_confirm_delete then
		M.delete_chat(file_name)
		return
	end

	-- ask for confirmation
	vim.ui.input({ prompt = "Delete " .. file_name .. "? [y/N] " }, function(input)
		if input and input:lower() == "y" then
			M.delete_chat(file_name)
		end
	end)
end

M.cmd.ChatRespond = function()
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	-- go to normal mode
	vim.cmd("stopinsert")

	-- get all lines
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

	-- check if file looks like a chat file
	local file_name = vim.api.nvim_buf_get_name(buf)
	if not (lines[1]:match("^# topic: ") and lines[3]:match("^- model: ")) then
		print("File " .. file_name .. " does not look like a chat file")
		return
	end

	-- headers are fields before first ---
	local headers = {}
	local headers_done = false
	-- message needs role and content
	local messages = {}
	local role = ""
	local content = ""

	for _, line in ipairs(lines) do
		if headers_done then
			if line:sub(1, #M.config.chat_user_prefix) == M.config.chat_user_prefix then
				table.insert(messages, { role = role, content = content })
				role = "user"
				content = line:sub(#M.config.chat_user_prefix + 1)
			elseif line:sub(1, #M.config.chat_assistant_prefix) == M.config.chat_assistant_prefix then
				table.insert(messages, { role = role, content = content })
				role = "assistant"
				content = line:sub(#M.config.chat_assistant_prefix + 1)
			elseif role ~= "" then
				content = content .. "\n" .. line
			end
		else
			-- first line starts with ---
			if line:sub(1, 3) == "---" then
				headers_done = true
			else
				-- parse header fields
				local key, value = line:match("^[-#] (%w+): (.*)")
				if key ~= nil then
					headers[key] = value
				end
			end
		end
	end
	-- insert last message not handled in loop
	table.insert(messages, { role = role, content = content })

	-- replace first empty message with system prompt
	content = ""
	if headers.role and headers.role:match("%S") then
		content = headers.role
	else
		content = M.config.chat_system_prompt
	end
	if content:match("%S") then
		-- make it multiline again if it contains escaped newlines
		content = content:gsub("\\n", "\n")
		messages[1] = { role = "system", content = content }
	end

	-- add custom instructions if they exist and contains some text
	if M.config.chat_custom_instructions and M.config.chat_custom_instructions:match("%S") then
		table.insert(messages, 2, { role = "system", content = M.config.chat_custom_instructions })
	end

	-- strip whitespace from ends of content
	for _, message in ipairs(messages) do
		message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
	end

	-- write assistant prompt
	local last_content_line = M._H.last_content_line(buf)
	vim.api.nvim_buf_set_lines(
		buf,
		last_content_line,
		last_content_line,
		false,
		{ "", M.config.chat_assistant_prefix, "" }
	)

	-- if model contains { } then it is a json string otherwise it is a model name
	if headers.model and headers.model:match("{.*}") then
		-- unescape underscores before decoding json
		headers.model = headers.model:gsub("\\_", "_")
		headers.model = vim.json.decode(headers.model)
	end

	-- call the model and write response
	M.query(
		M.prepare_payload(headers.model, M.config.chat_model, messages),
		M.create_handler(buf, win, M._H.last_content_line(buf), true),
		vim.schedule_wrap(function()
			-- write user prompt
			last_content_line = M._H.last_content_line(buf)
			vim.cmd("undojoin")
			vim.api.nvim_buf_set_lines(
				buf,
				last_content_line,
				last_content_line,
				false,
				{ "", "", M.config.chat_user_prefix, "" }
			)

			-- delete whitespace lines at the end of the file
			last_content_line = M._H.last_content_line(buf)
			vim.cmd("undojoin")
			vim.api.nvim_buf_set_lines(buf, last_content_line, -1, false, {})
			-- insert a new line at the end of the file
			vim.cmd("undojoin")
			vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })

			-- if topic is ?, then generate it
			if headers.topic == "?" then
				-- insert last model response
				table.insert(messages, { role = "assistant", content = M._response })

				-- ignore custom instructions for topic generation
				if M.config.chat_custom_instructions and M.config.chat_custom_instructions:match("%S") then
					table.remove(messages, 2)
				end

				-- ask model to generate topic/title for the chat
				table.insert(messages, { role = "user", content = M.config.chat_topic_gen_prompt })

				-- prepare invisible buffer for the model to write to
				local topic_buf = vim.api.nvim_create_buf(false, true)
				local topic_handler = M.create_handler(topic_buf, nil, 0, false)

				-- call the model
				M.query(
					M.prepare_payload(nil, M.config.chat_topic_gen_model, messages),
					topic_handler,
					vim.schedule_wrap(function()
						-- get topic from invisible buffer
						local topic = vim.api.nvim_buf_get_lines(topic_buf, 0, -1, false)[1]
						-- close invisible buffer
						vim.api.nvim_buf_delete(topic_buf, { force = true })
						-- strip whitespace from ends of topic
						topic = topic:gsub("^%s*(.-)%s*$", "%1")
						-- strip dot from end of topic
						topic = topic:gsub("%.$", "")

						-- if topic is empty do not replace it
						if topic == "" then
							return
						end

						-- replace topic in current buffer
						vim.cmd("undojoin")
						vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "# topic: " .. topic })

						-- move cursor to a new line at the end of the file
						local line = vim.api.nvim_buf_line_count(buf)
						M._H.cursor_to_line(line, buf, win)
					end)
				)
			end

			-- move cursor to a new line at the end of the file
			local line = vim.api.nvim_buf_line_count(buf)
			M._H.cursor_to_line(line, buf, win)
		end)
	)

	--[[ print("headers:\n" .. vim.inspect(headers)) ]]
	--[[ print("messages:\n" .. vim.inspect(messages)) ]]
end

M.cmd.ChatFinder = function()
	local dir = M.config.chat_dir

	-- prepare unique group name and register augroup
	local gname = "GpExplorer"
		.. os.date("_%Y_%m_%d_%H_%M_%S_")
		.. tostring(math.floor(vim.loop.hrtime() / 1000000) % 1000)
	local gid = vim.api.nvim_create_augroup(gname, { clear = true })

	-- prepare three popup buffers and windows
	local wfactor = 0.9
	local hfactor = 0.7
	local preview_ratio = 0.6
	local picker_buf, picker_win, picker_close, picker_resize = M._H.create_popup(
		nil,
		"Picker: j/k <Esc> <Enter> <Alt+Enter>|Pop dd|Del i|Srch",
		function(w, h)
			local wh = math.ceil(h * hfactor - 5)
			local ww = math.ceil(w * wfactor)
			local r = math.ceil((h - wh) / 4 - 1)
			local c = math.ceil((w - ww) / 2)
			return ww * (1 - preview_ratio), wh, r, c
		end,
		{ gid = gid }
	)
	--[[ vim.api.nvim_buf_set_option(picker_buf, "filetype", "bash") ]]
	vim.api.nvim_win_set_option(picker_win, "cursorline", true)

	local preview_buf, preview_win, preview_close, preview_resize = M._H.create_popup(
		nil,
		"Preview (edits are ephemeral)",
		function(w, h)
			local wh = math.ceil(h * hfactor - 5)
			local ww = math.ceil(w * wfactor)
			local r = math.ceil((h - wh) / 4 - 1)
			local c = math.ceil((w - ww) / 2)
			return ww * preview_ratio, wh, r, c + math.ceil(ww * (1 - preview_ratio)) + 2
		end,
		{ gid = gid }
	)

	vim.api.nvim_buf_set_option(preview_buf, "filetype", "markdown")

	local command_buf, command_win, command_close, command_resize = M._H.create_popup(
		nil,
		"Search: <Tab>/<Shift+Tab>|Navigate <Esc>/<Enter>|Picker 2x<Esc>|Exit 2x<Enter>|Open 2x<Alt+Enter>|Popup",
		function(w, h)
			local wh = math.ceil(h * hfactor - 5)
			local ww = math.ceil(w * wfactor)
			local r = math.ceil((h - wh) / 4 - 1)
			local c = math.ceil((w - ww) / 2)
			return ww + 2, 1, r + wh + 2, c
		end,
		{ gid = gid }
	)
	-- set initial content of command buffer
	vim.api.nvim_buf_set_lines(command_buf, 0, -1, false, { "topic " })

	-- make highlight group for search by linking to existing Search group
	local hl_group = "GpExplorerSearch"
	vim.cmd("highlight default link " .. hl_group .. " Search")
	local picker_match_id = 0
	local preview_match_id = 0
	local regex = ""

	-- clean up augroup and popup buffers/windows
	local close = _H.once(function()
		vim.api.nvim_del_augroup_by_id(gid)
		picker_close()
		preview_close()
		command_close()
	end)

	local resize = function()
		picker_resize()
		preview_resize()
		command_resize()
		vim.api.nvim_win_set_option(picker_win, "cursorline", true)
	end

	-- logic for updating picker and preview
	local picker_files = {}
	local preview_lines = {}

	local refresh_preview = function()
		if not vim.api.nvim_buf_is_valid(picker_buf) then
			return
		end

		-- empty preview buffer
		vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, {})
		vim.api.nvim_win_set_cursor(preview_win, { 1, 0 })

		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local file = picker_files[index]
		if not file then
			return
		end

		local lines = {}
		for l in io.lines(file) do
			table.insert(lines, l)
		end
		vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)

		local preview_line = preview_lines[index]
		if preview_line then
			vim.api.nvim_win_set_cursor(preview_win, { preview_line, 0 })
		end

		-- highlight preview
		if preview_match_id ~= 0 then
			vim.fn.matchdelete(preview_match_id, preview_win)
		end
		if regex == "" then
			preview_match_id = 0
			return
		end
		preview_match_id = vim.fn.matchadd(hl_group, regex, 0, -1, { window = preview_win })
	end

	local refresh_picker = function()
		-- get last line of command buffer
		local cmd = vim.api.nvim_buf_get_lines(command_buf, -2, -1, false)[1]

		_H.grep_directory(dir, cmd, function(results, re)
			if not vim.api.nvim_buf_is_valid(picker_buf) then
				return
			end

			picker_files = {}
			preview_lines = {}
			local picker_lines = {}
			for _, f in ipairs(results) do
				table.insert(picker_files, dir .. "/" .. f.file)
				table.insert(picker_lines, string.format("%s:%s %s", f.file, f.lnum, f.line))
				table.insert(preview_lines, tonumber(f.lnum))
			end

			vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, picker_lines)

			-- prepare regex for highlighting
			regex = re
			if regex ~= "" then
				-- case insensitive
				regex = "\\c" .. regex
			end

			refresh_preview()

			-- highlight picker
			if picker_match_id ~= 0 then
				vim.fn.matchdelete(picker_match_id, picker_win)
			end

			picker_match_id = 0
			if regex == "" then
				return
			end
			picker_match_id = vim.fn.matchadd(hl_group, regex, 0, -1, { window = picker_win })
		end)
	end

	refresh_picker()
	vim.api.nvim_set_current_win(command_win)
	vim.api.nvim_command("startinsert!")

	-- resize on VimResized
	_H.autocmd({ "VimResized" }, nil, resize, gid)

	-- moving cursor on picker window will update preview window
	_H.autocmd({ "CursorMoved", "CursorMovedI" }, { picker_buf }, function()
		vim.api.nvim_command("stopinsert")
		refresh_preview()
	end, gid)

	-- InsertEnter on picker or preview window will go to command window
	_H.autocmd({ "InsertEnter" }, { picker_buf, preview_buf }, function()
		vim.api.nvim_set_current_win(command_win)
		vim.api.nvim_command("startinsert!")
	end, gid)

	-- InsertLeave on command window will go to picker window
	_H.autocmd({ "InsertLeave" }, { command_buf }, function()
		vim.api.nvim_set_current_win(picker_win)
		vim.api.nvim_command("stopinsert")
	end, gid)

	-- when preview becomes active call some function
	_H.autocmd({ "WinEnter" }, { preview_buf }, function()
		-- go to normal mode
		vim.api.nvim_command("stopinsert")
	end, gid)

	-- when command buffer is written, execute it
	_H.autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT" }, { command_buf }, function()
		refresh_picker()
	end, gid)

	-- close on buffer delete
	_H.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { picker_buf, preview_buf, command_buf }, close, gid)

	-- close by escape key on any window
	_H.set_keymap({ picker_buf, preview_buf, command_buf }, "n", "<esc>", close)

	local open_chat = function(popup)
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local file = picker_files[index]
		close()
		-- delay so explorer can close before opening file
		vim.defer_fn(function()
			if not file then
				return
			end
			M.open_chat(file, popup)
		end, 200)
	end

	-- enter on picker window will open file
	_H.set_keymap({ picker_buf }, "n", "<cr>", open_chat)
	_H.set_keymap({ picker_buf }, "n", "<a-cr>", function()
		open_chat(true)
	end)

	-- enter on preview window will go to picker window
	_H.set_keymap({ command_buf }, "i", "<cr>", function()
		vim.api.nvim_set_current_win(picker_win)
		vim.api.nvim_command("stopinsert")
	end)

	-- tab in command window will cycle through lines in picker window
	_H.set_keymap({ command_buf, picker_buf }, { "i", "n" }, "<tab>", function()
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local next_index = index + 1
		if next_index > #picker_files then
			next_index = 1
		end
		vim.api.nvim_win_set_cursor(picker_win, { next_index, 0 })
		refresh_preview()
	end)

	-- shift-tab in command window will cycle through lines in picker window
	_H.set_keymap({ command_buf, picker_buf }, { "i", "n" }, "<s-tab>", function()
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local next_index = index - 1
		if next_index < 1 then
			next_index = #picker_files
		end
		vim.api.nvim_win_set_cursor(picker_win, { next_index, 0 })
		refresh_preview()
	end)

	-- dd on picker or preview window will delete file
	_H.set_keymap({ picker_buf, preview_buf }, "n", "dd", function()
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local file = picker_files[index]

		-- delete without confirmation
		if not M.config.chat_confirm_delete then
			M.delete_chat(file)
			refresh_picker()
			return
		end

		-- ask for confirmation
		vim.ui.input({ prompt = "Delete " .. file .. "? [y/N] " }, function(input)
			if input and input:lower() == "y" then
				M.delete_chat(file)
				refresh_picker()
			end
		end)
	end)
end

--------------------
-- Prompt logic
--------------------

M.Prompt = function(params, target, prompt, model, template, system_template, whisper)
	-- backwards compatibility for old usage of enew
	if type(target) == "function" then
		target = M.Target.enew()
	end

	target = target or M.Target.enew()

	-- get current buffer
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	-- defaults to normal mode
	local selection = nil
	local start_line = vim.api.nvim_win_get_cursor(0)[1]
	local end_line = start_line

	-- handle range
	if params.range == 2 then
		start_line = params.line1
		end_line = params.line2
		local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
		selection = table.concat(lines, "\n")

		if selection == "" then
			print("Please select some text to rewrite")
			return
		end
	end

	local callback = function(command)
		-- dummy handler
		local handler = function() end
		-- default on_exit strips trailing backticks if response was markdown snippet
		local on_exit = function()
			-- if buf is not valid, return
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end

			-- get content of M._first_line and M._last_line
			local fl = vim.api.nvim_buf_get_lines(buf, M._first_line, M._first_line + 1, false)[1]
			local ll = vim.api.nvim_buf_get_lines(buf, M._last_line, M._last_line + 1, false)[1]
			-- if fl and ll starts with triple backticks, remove these lines
			if fl and ll and fl:match("^```") and ll:match("^```") then
				-- remove first line with undojoin
				vim.cmd("undojoin")
				vim.api.nvim_buf_set_lines(buf, M._first_line, M._first_line + 1, false, {})
				-- remove last line
				vim.cmd("undojoin")
				vim.api.nvim_buf_set_lines(buf, M._last_line - 1, M._last_line, false, {})
			end
		end

		-- prepare messages
		local messages = {}
		local filetype = M._H.get_filetype(buf)
		local filename = vim.api.nvim_buf_get_name(buf)

		local sys_prompt = M.template_render(system_template, command, selection, filetype, filename)
		table.insert(messages, { role = "system", content = sys_prompt })

		local repo_instructions = M.repo_instructions()
		if repo_instructions ~= "" then
			table.insert(messages, { role = "system", content = repo_instructions })
		end

		local user_prompt = M.template_render(template, command, selection, filetype, filename)
		table.insert(messages, { role = "user", content = user_prompt })

		-- cancel possible visual mode before calling the model
		M._H.feedkeys("<esc>", "x")

		-- mode specific logic
		if target == M.Target.rewrite then
			-- delete selection
			vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line - 1, false, {})
			-- prepare handler
			handler = M.create_handler(buf, win, start_line - 1, true)
		elseif target == M.Target.append then
			-- move cursor to the end of the selection
			vim.api.nvim_win_set_cursor(0, { end_line, 0 })
			-- put newline after selection
			vim.api.nvim_put({ "", "" }, "l", true, true)
			-- prepare handler
			handler = M.create_handler(buf, win, end_line + 1, true)
		elseif target == M.Target.prepend then
			-- move cursor to the start of the selection
			vim.api.nvim_win_set_cursor(0, { start_line, 0 })
			-- put newline before selection
			vim.api.nvim_put({ "", "" }, "l", false, true)
			-- prepare handler
			handler = M.create_handler(buf, win, start_line - 1, true)
		elseif target == M.Target.popup then
			-- create a new buffer
			buf, win, _, _ = M._H.create_popup(nil, M._Name .. " popup (close with <esc>)", function(w, h)
				return w / 2, h / 2, h / 4, w / 4
			end, { on_leave = true, escape = true })
			-- set the created buffer as the current buffer
			vim.api.nvim_set_current_buf(buf)
			-- set the filetype to markdown
			vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
			-- better text wrapping
			vim.api.nvim_command("setlocal wrap linebreak")
			-- prepare handler
			handler = M.create_handler(buf, win, 0, false)
		elseif type(target) == "table" and target.type == M.Target.enew().type then
			-- create a new buffer
			buf = vim.api.nvim_create_buf(true, false)
			-- set the created buffer as the current buffer
			vim.api.nvim_set_current_buf(buf)
			-- set the filetype
			local ft = target.filetype or filetype
			vim.api.nvim_buf_set_option(buf, "filetype", ft)
			-- prepare handler
			handler = M.create_handler(buf, win, 0, false)
		end

		-- call the model and write the response
		M.query(
			M.prepare_payload(model, M.config.command_model, messages),
			handler,
			vim.schedule_wrap(function()
				on_exit()
			end)
		)
	end

	vim.schedule(function()
		-- if prompt is not provided, run the command directly
		if not prompt or prompt == "" then
			callback(nil)
			return
		end

		-- if prompt is provided, ask the user to enter the command
		vim.ui.input({ prompt = prompt, default = whisper }, function(input)
			if not input or input == "" then
				return
			end
			callback(input)
		end)
	end)
end

---@param callback function # callback function(text)
M.Whisper = function(callback)
	-- make sure sox is installed
	if vim.fn.executable("sox") == 0 then
		M.error("sox is not installed")
		return
	end

	-- make sure openai_api_key is set
	if M.config.openai_api_key == nil then
		M.error("config.openai_api_key is not set, run :checkhealth gp")
		return
	end

	-- prepare unique group name and register augroup
	local gname = "GpWhisper"
		.. os.date("_%Y_%m_%d_%H_%M_%S_")
		.. tostring(math.floor(vim.loop.hrtime() / 1000000) % 1000)
	local gid = vim.api.nvim_create_augroup(gname, { clear = true })

	-- create popup
	local buf, _, close_popup, _ = M._H.create_popup(nil, M._Name .. " Whisper", function(w, h)
		return 60, 12, (h - 12) * 0.4, (w - 60) * 0.5
	end, { gid = gid, on_leave = false, escape = false, persist = false })

	-- animated instructions in the popup
	local counter = 0
	local timer = vim.loop.new_timer()
	timer:start(
		0,
		200,
		vim.schedule_wrap(function()
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
					"    ",
					"    Speak 👄 loudly 📣 into the microphone 🎤: ",
					"    " .. string.rep("👂", counter),
					"    ",
					"    Pressing <Enter> starts the transcription.",
					"    ",
					"    Cancel the recording with <esc> or :GpStop.",
					"    ",
					"    The last recording is in /tmp/gp_whisper/.",
				})
			end
			counter = counter + 1
			if counter % 22 == 0 then
				counter = 0
			end
		end)
	)

	local close = _H.once(function()
		if timer then
			timer:stop()
			timer:close()
		end
		close_popup()
		vim.api.nvim_del_augroup_by_id(gid)
		M.cmd.Stop()
	end)

	_H.set_keymap({ buf }, { "n", "i", "v" }, "<esc>", function()
		M.cmd.Stop()
	end)

	local continue = false
	_H.set_keymap({ buf }, { "n", "i", "v" }, "<cr>", function()
		continue = true
		vim.defer_fn(function()
			M.cmd.Stop()
		end, 300)
	end)

	-- cleanup on buffer exit
	_H.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { buf }, close, gid)

	-- transcribe the recording
	local transcribe = function()
		local cmd = "cd "
			.. M.config.whisper_dir
			.. " && "
			-- normalize volume to -3dB
			.. "sox --norm=-3 rec.wav norm.wav && "
			-- get RMS level dB * silence threshold
			.. "t=$(sox 'norm.wav' -n channels 1 stats 2>&1 | grep 'RMS lev dB' "
			.. " | sed -e 's/.* //' | awk '{print $1*"
			.. M.config.whisper_silence
			.. "}') && "
			-- remove silence, speed up, pad and convert to mp3
			.. "sox -q norm.wav -C 196.5 final.mp3 silence -l 1 0.05 $t'dB' -1 1.0 $t'dB'"
			.. " pad 0.1 0.1 tempo "
			.. M.config.whisper_tempo
			.. " && "
			-- call openai
			.. "curl --max-time 20 https://api.openai.com/v1/audio/transcriptions -s "
			.. '-H "Authorization: Bearer '
			.. M.config.openai_api_key
			.. '" -H "Content-Type: multipart/form-data" '
			.. '-F model="whisper-1" -F language="en" -F file="@final.mp3" '
			.. '-F response_format="json"'

		M._H.process("bash", { "-c", cmd }, function(code, signal, stdout, _)
			if code ~= 0 then
				M.error(string.format("Whisper query exited: %d, %d", code, signal))
				return
			end

			local text = vim.json.decode(stdout).text
			if not text then
				M.error("Whisper query no text: " .. vim.inspect(stdout))
				return
			end

			text = table.concat(vim.split(text, "\n"), " ")
			text = text:gsub("%s+$", "")

			if callback and stdout then
				callback(text)
			end
		end)
	end

	M._H.process("sox", {
		--[[ "-q", ]]
		-- single channel
		"-c",
		"1",
		-- output file
		"-d",
		M.config.whisper_dir .. "/rec.wav",
		-- max recording time
		"trim",
		"0",
		M.config.whisper_max_time,
	}, function(code, signal, _, _)
		close()

		if code and code ~= 0 then
			M.error("Sox exited with code and signal: " .. code .. " " .. signal)
			return
		end

		if not continue then
			return
		end

		vim.schedule(function()
			transcribe()
		end)
	end)
end

M.cmd.Whisper = function(params)
	local buf = vim.api.nvim_get_current_buf()
	local start_line = vim.api.nvim_win_get_cursor(0)[1]
	local end_line = start_line

	-- handle range
	if params.range == 2 then
		start_line = params.line1
		end_line = params.line2
	end

	M.Whisper(function(text)
		-- if buf is not valid, stop
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		if text then
			vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line, false, { text })
		end
	end)
end

--[[ M.setup() ]]
--[[ print("gp.lua loaded\n\n") ]]

return M

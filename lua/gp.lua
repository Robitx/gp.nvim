-- Gp (GPT prompt) lua plugin for Neovim
-- https://github.com/Robitx/gp.nvim/

-- default config also serving as documentation example
local config = {
	-- required openai api key
	openai_api_key = os.getenv("OPENAI_API_KEY"),
	-- prefix for all commands
	cmd_prefix = "G",
	-- example hook functions
	hooks = {
		InspectPlugin = function(plugin)
			print(string.format("%s plugin structure:\n%s", M._Name, vim.inspect(plugin)))
		end,
	},

	-- directory for storing chat files
	chat_dir = os.getenv("HOME") .. "/.local/share/nvim/gp/chats",
	-- chat model
	chat_model = "gpt-3.5-turbo-16k",
	-- chat temperature
	chat_temperature = 0.7,
	-- chat model system prompt
	chat_sysem_prompt = "You are a general AI assistant.",
	-- chat user prompt prefix
	chat_user_prefix = "🗨:",
	-- chat assistant prompt prefix
	chat_assistant_prefix = "🤖:",
	-- chat topic generation prompt
	chat_topic_gen_prompt = "Summarize the topic of our conversation above"
		.. " in two or three words. Respond only with those words.",
	-- chat topic model
	chat_topic_gen_model = "gpt-3.5-turbo-16k",

	-- prompt for rewrite command
	rewrite_prompt = "🤖 ~ ",
	-- rewrite model
	rewrite_model = "gpt-3.5-turbo-16k",
}

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

_H.get_selection = function(buf)
	local start_line = vim.api.nvim_buf_get_mark(buf, "<")[1]
	local end_line = vim.api.nvim_buf_get_mark(buf, ">")[1]

	local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
	local selection = table.concat(lines, "\n")

	return selection, start_line, end_line
end

_H.feedkeys = function(keys, mode)
	mode = mode or "n"
	keys = vim.api.nvim_replace_termcodes(keys, true, false, true)
	vim.api.nvim_feedkeys(keys, mode, true)
end

-- nicer error messages
M.error = function(msg)
	error(string.format("\n\n%s error:\n%s\n", M._Name, msg))
end

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

	-- clear response
	M._response = ""

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
	end)

	-- read stdout
	vim.loop.read_start(stdout, function(err, chunk)
		if err then
			M.error("OpenAI query stdout error: " .. vim.inspect(err))
		elseif chunk then
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
		-- chunk is nil when EOF is reached
		else
			-- optional on_exit handler
			if type(on_exit) == "function" then
				on_exit()
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

--------------------
-- Chat logic
--------------------

M.chat_template = [[
# topic: ?

- model: %s
- file: %s
- role: %s

Write your queries after %s. Run :%sChatRespond to generate response.

---

%s]]

M.open_chat = function(file_name)
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
	-- disable swapping for this buffer and set filetype to markdown
	vim.api.nvim_command("setlocal filetype=markdown noswapfile")
	-- better text wrapping
	vim.api.nvim_command("setlocal wrap linebreak")
	-- auto save on TextChanged, TextChangedI
	vim.api.nvim_command("autocmd TextChanged,TextChangedI <buffer> silent! write")
end

M.cmd.ChatNew = function()
	-- prepare filename
	local time = os.date("%Y-%m-%d_%H-%M-%S")
	time = time .. "." .. tostring(math.floor(vim.loop.hrtime() / 1000000) % 1000)
	local filename = M.config.chat_dir .. "/" .. time .. ".md"

	-- create chat file
	os.execute("touch " .. filename)

	-- open and configure chat file
	M.open_chat(filename)

	-- write chat template
	vim.api.nvim_buf_set_lines(
		0,
		0,
		-1,
		false,
		vim.split(
			string.format(
				M.chat_template,
				M.config.chat_model,
				string.match(filename, "([^/]+)$"),
				M.config.chat_sysem_prompt,
				M.config.chat_user_prefix,
				M.config.cmd_prefix,
				M.config.chat_user_prefix
			),
			"\n"
		)
	)

	-- move cursor to a new line at the end of the file
	vim.cmd("normal Go")
end

M.cmd.ChatRespond = function()
	local buf = vim.api.nvim_get_current_buf()
	-- get all lines
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

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
		content = M.config.chat_sysem_prompt
	end
	if content:match("%S") then
		messages[1] = { role = "system", content = content }
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

	-- call the model and write response
	M.query(
		{
			model = headers.model or M.config.chat_model,
			stream = true,
			messages = messages,
		},
		M.create_handler(buf, M._H.last_content_line(buf), true),
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

			-- move cursor to a new line at the end of the file
			vim.cmd("normal Go")

			-- if topic is ?, then generate it
			if headers.topic == "?" then
				-- insert last model response
				table.insert(messages, { role = "assistant", content = M._response })

				-- ask model to generate topic/title for the chat
				table.insert(messages, { role = "user", content = M.config.chat_topic_gen_prompt })

				-- prepare invisible buffer for the model to write to
				local topic_buf = vim.api.nvim_create_buf(false, true)
				local topic_handler = M.create_handler(topic_buf, 0, false)

				-- call the model
				M.query(
					{
						model = M.config.chat_topic_gen_model,
						stream = true,
						messages = messages,
					},
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
						vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "# topic: " .. topic })
					end)
				)
			end
		end)
	)

	--[[ print("headers:\n" .. vim.inspect(headers)) ]]
	--[[ print("messages:\n" .. vim.inspect(messages)) ]]
end

M.cmd.ChatPicker = function()
	local telescope = require("telescope.builtin")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	telescope.grep_string({
		prompt_title = "Chat Picker",
		default_text = "^# 'topic: ",
		shorten_path = true,
		search_dirs = { M.config.chat_dir },
		path_display = { "hidden" },
		only_sort_text = true,
		word_match = "-w",
		search = "",
		-- custom open function
		attach_mappings = function(prompt_bufnr, _)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)
				M.open_chat(selection.filename)

				-- move cursor to a new line at the end of the file
				vim.cmd("normal Go")
			end)
			return true
		end,
	})
end

--------------------
-- Rewrite logic
--------------------

M.rewrite = function(prompt, model, template, system_template)
	-- make sure the user has selected some text
	local buf = vim.api.nvim_get_current_buf()
	local selection, line_start, line_end = M._H.get_selection(buf)

	if selection == "" then
		print("Please select some text to rewrite")
		return
	end

	-- user should see the selection before writing the command
	local mode = vim.api.nvim_get_mode().mode
	if mode ~= "v" and mode ~= "V" then
		M._H.feedkeys("gv", "x")
	end

	local callback = function(command)
		-- delete selection
		vim.api.nvim_buf_set_lines(buf, line_start - 1, line_end - 1, false, {})
		M._H.feedkeys("<esc>", "x")

		-- call the model and write response
		local messages = {}
		table.insert(messages, { role = "user", content = command })
		M.query(
			{
				model = model or M.config.rewrite_model,
				stream = true,
				messages = messages,
			},
			M.create_handler(buf, line_start - 1, true),
			vim.schedule_wrap(function()
				-- on exit
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
		vim.ui.input({ prompt = prompt }, function(input)
			if not input or input == "" then
				return
			end
			callback(input)
		end)
	end)
end

M.cmd.VisualRewrite = function()
	M.rewrite(M.config.rewrite_prompt, nil, nil, nil)
end

--[[ M.setup() ]]
--[[ print("gp.lua loaded\n\n") ]]

--[[ M.setup({chat_dir = "/tmp/gp/chats"}) ]]
--[[ M.setup("") ]]
--[[ M.call_hook("InsectPlugin") ]]
--[[ M.call_hook("InspectPlugin") ]]

return M

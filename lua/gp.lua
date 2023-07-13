-- Gp (GPT prompt) lua plugin for Neovim
-- https://github.com/Robitx/gp.nvim/

--------------------------------------------------------------------------------
-- Default config
--------------------------------------------------------------------------------

local config = {
	-- required openai api key
	openai_api_key = os.getenv("OPENAI_API_KEY"),
	-- prefix for all commands
	cmd_prefix = "Gp",
	-- example hook functions
	hooks = {
		InspectPlugin = function(plugin)
			print(string.format("Plugin structure:\n%s", vim.inspect(plugin)))
		end,
	},

	-- directory for storing chat files
	chat_dir = os.getenv("HOME") .. "/.local/share/nvim/gp/chats",
	-- chat model
	chat_model = "gpt-3.5-turbo-16k",
	-- chat temperature
	chat_temperature = 0.7,
	-- chat model system prompt
	chat_system_prompt = "You are a general AI assistant.",
	-- chat user prompt prefix
	chat_user_prefix = "🗨:",
	-- chat assistant prompt prefix
	chat_assistant_prefix = "🤖:",
	-- chat topic generation prompt
	chat_topic_gen_prompt = "Summarize the topic of our conversation above"
		.. " in two or three words. Respond only with those words.",
	-- chat topic model
	chat_topic_gen_model = "gpt-3.5-turbo-16k",

	-- command prompt prefix for asking user for input
	command_prompt_prefix = "🤖 ~ ",
	-- command model
	command_model = "gpt-3.5-turbo-16k",
	-- command system prompt
	command_system_prompt = "You are an AI that strictly generates pure formated final code, without providing any comments or explanations.",

	-- templates
	template_selection = "I have the following code from {{filename}}:\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}",
	template_rewrite = "I have the following code from {{filename}}:\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond just with the pure formated final code. !!And please: No ``` code ``` blocks.",
	template_command = "{{command}}",
}

--------------------------------------------------------------------------------
-- Module structure
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Generic helper functions
--------------------------------------------------------------------------------

_H.create_popup = function(title, size_func)
	-- create scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)

	-- setting to the middle of the editor
	local options = {
		relative = "editor",
		width = 10,
		height = 10,
		row = 10,
		col = 10,
		style = "minimal",
		border = "single",
		title = title,
		title_pos = "center",
	}

	-- make it close on escape
	vim.api.nvim_buf_set_keymap(buf, "n", "<esc>", ":q<cr>", { noremap = true, silent = true })

	-- open the window and return the buffer
	local win = vim.api.nvim_open_win(buf, true, options)

	local resize = function()
		-- get editor dimensions
		local ew = vim.api.nvim_get_option("columns")
		local eh = vim.api.nvim_get_option("lines")

		local w, h, r, c = size_func(ew, eh)

		-- setting to the middle of the editor
		local opts = {
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
		vim.api.nvim_win_set_config(win, opts)
	end

	-- register command group
	local gid = vim.api.nvim_create_augroup(title, { clear = true })

	-- resize on window resize
	vim.api.nvim_create_autocmd("VimResized", {
		group = gid,
		callback = resize,
	})
	resize()
	return buf, win
end

_H.feedkeys = function(keys, mode)
	mode = mode or "n"
	keys = vim.api.nvim_replace_termcodes(keys, true, false, true)
	vim.api.nvim_feedkeys(keys, mode, true)
end

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
	-- call esc to get to normal mode, so < and > marks are set properly
	M._H.feedkeys("<esc>", "x")
	local start_line = vim.api.nvim_buf_get_mark(buf, "<")[1]
	local end_line = vim.api.nvim_buf_get_mark(buf, ">")[1]

	local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
	local selection = table.concat(lines, "\n")

	-- user should see the selection
	if string.lower(vim.api.nvim_get_mode().mode) ~= "v" then
		M._H.feedkeys("gv", "x")
	end
	return selection, start_line, end_line
end

_H.get_filetype = function(buf)
	return vim.api.nvim_buf_get_option(buf, "filetype")
end

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

_H.template_render = function(template, key_value_pairs)
	if template == nil then
		return nil
	end

	for key, value in pairs(key_value_pairs) do
		template = _H.template_replace(template, key, value)
	end

	return template
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

--------------------------------------------------------------------------------
-- Module helper functions and variables
--------------------------------------------------------------------------------

M.target = {
	replace = 0, -- for replacing the selection or the current line
	append = 1, -- for appending after the selection or the current line
	prepend = 2, -- for prepending before the selection or the current line
	enew = 3, -- for writing into the new buffer
	popup = 4, -- for writing into the popup window
}

M.mode = {
	normal = 0, -- based just on the command
	visual = 1, -- uses the current or the last visual selection
}

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

-- hook caller
M.call_hook = function(name)
	if M.cmd_hooks[name] ~= nil then
		return M.cmd_hooks[name](M)
	end
	M.error("The hook '" .. name .. "' does not exist.")
end

-- gpt query
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

-- response handler
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

		-- move cursor to end of response
		local end_line = first_line + #vim.split(response, "\n")
		vim.api.nvim_win_set_cursor(0, { end_line, 0 })
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
- temperature: %s

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

M.new_chat = function(mode)
	-- prepare filename
	local time = os.date("%Y-%m-%d_%H-%M-%S")
	time = time .. "." .. tostring(math.floor(vim.loop.hrtime() / 1000000) % 1000)
	local filename = M.config.chat_dir .. "/" .. time .. ".md"

	local template = string.format(
		M.chat_template,
		M.config.chat_model,
		string.match(filename, "([^/]+)$"),
		M.config.chat_system_prompt,
		M.config.chat_temperature,
		M.config.chat_user_prefix,
		M.config.cmd_prefix,
		M.config.chat_user_prefix
	)

	if mode == M.mode.visual then
		-- get current buffer
		local buf = vim.api.nvim_get_current_buf()

		-- make sure the user has selected some text
		local selection, _, _ = M._H.get_selection(buf)

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
	os.execute("touch " .. filename)

	-- open and configure chat file
	M.open_chat(filename)

	-- write chat template
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(template, "\n"))

	-- move cursor to a new line at the end of the file
	M._H.feedkeys("G", "x")
end

M.cmd.ChatNew = function()
	M.new_chat(M.mode.normal)
end

M.cmd.VisualChatNew = function()
	M.new_chat(M.mode.visual)
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

	-- ask for confirmation
	vim.ui.input({ prompt = "Delete " .. file_name .. "? [y/N] " }, function(input)
		if input and input:lower() == "y" then
			-- delete buffer and file
			vim.api.nvim_buf_delete(buf, { force = true })
			os.remove(file_name)
		end
	end)
end

M.cmd.ChatRespond = function()
	local buf = vim.api.nvim_get_current_buf()

	-- check if file is in the chat dir
	local file_name = vim.api.nvim_buf_get_name(buf)
	if not string.match(file_name, M.config.chat_dir) then
		print("File " .. file_name .. " is not in chat dir")
		return
	end

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
		content = M.config.chat_system_prompt
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

	-- validate temperature
	local temperature = tonumber(headers.temperature) or M.config.chat_temperature
	if temperature == nil then
		temperature = 0.7
	elseif temperature < 0 then
		temperature = 0
	elseif temperature > 2 then
		temperature = 2
	end

	-- call the model and write response
	M.query(
		{
			model = headers.model or M.config.chat_model,
			stream = true,
			messages = messages,
			temperature = temperature,
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
			-- insert a new line at the end of the file
			vim.cmd("undojoin")
			vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })

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
						vim.api.nvim_set_current_buf(buf)
						vim.cmd("undojoin")
						vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "# topic: " .. topic })

						-- move cursor to a new line at the end of the file
						M._H.feedkeys("G", "x")
					end)
				)
			end

			-- move cursor to a new line at the end of the file
			M._H.feedkeys("G", "x")
		end)
	)

	--[[ print("headers:\n" .. vim.inspect(headers)) ]]
	--[[ print("messages:\n" .. vim.inspect(messages)) ]]
end

M.cmd.ChatFinder = function()
	local status_ok, _ = pcall(require, "telescope")
	if not status_ok then
		M.error("telescope.nvim is not installed")
		return
	end

	local builtin = require("telescope.builtin")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	builtin.grep_string({
		prompt_title = M._Name .. " Chat Finder",
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
				M._H.feedkeys("G", "x")
			end)
			return true
		end,
	})
end

--------------------
-- Prompt logic
--------------------

M.prompt = function(mode, target, prompt, model, template, system_template)
	mode = mode or M.mode.normal
	target = target or M.target.enew
	model = model or M.config.command_model

	-- validate temperature
	local temperature = tonumber(M.config.chat_temperature)
	if temperature == nil then
		temperature = 0.7
	elseif temperature < 0 then
		temperature = 0
	elseif temperature > 2 then
		temperature = 2
	end

	-- get current buffer
	local buf = vim.api.nvim_get_current_buf()

	-- defaults to normal mode
	local selection = nil
	local start_line = vim.api.nvim_win_get_cursor(0)[1]
	local end_line = start_line

	if mode == M.mode.visual then
		-- make sure the user has selected some text
		selection, start_line, end_line = M._H.get_selection(buf)

		if selection == "" then
			print("Please select some text to rewrite")
			return
		end
	end

	local callback = function(command)
		-- dummy handler and on_exit
		local handler = function() end
		local on_exit = function() end

		-- prepare messages
		local messages = {}
		local filetype = M._H.get_filetype(buf)
		local filename = vim.api.nvim_buf_get_name(buf)
		local sys_prompt = M.template_render(system_template, command, selection, filetype, filename)
		table.insert(messages, { role = "system", content = sys_prompt })
		local user_prompt = M.template_render(template, command, selection, filetype, filename)
		table.insert(messages, { role = "user", content = user_prompt })

		-- cancel possible visual mode before calling the model
		M._H.feedkeys("<esc>", "x")

		-- mode specific logic
		if target == M.target.replace then
			-- delete selection
			vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line - 1, false, {})
			-- prepare handler
			handler = M.create_handler(buf, start_line - 1, true)
		elseif target == M.target.append then
			-- move cursor to the end of the selection
			vim.api.nvim_win_set_cursor(0, { end_line, 0 })
			-- put newline after selection
			vim.api.nvim_put({ "", "" }, "l", true, true)
			-- prepare handler
			handler = M.create_handler(buf, end_line + 1, true)
		elseif target == M.target.prepend then
			-- move cursor to the start of the selection
			vim.api.nvim_win_set_cursor(0, { start_line, 0 })
			-- put newline before selection
			vim.api.nvim_put({ "", "" }, "l", false, true)
			-- prepare handler
			handler = M.create_handler(buf, start_line - 1, true)
		elseif target == M.target.enew then
			-- create a new buffer
			buf = vim.api.nvim_create_buf(true, false)
			-- set the created buffer as the current buffer
			vim.api.nvim_set_current_buf(buf)
			-- set the filetype
			vim.api.nvim_buf_set_option(buf, "filetype", filetype)
			-- prepare handler
			handler = M.create_handler(buf, 0, false)
		elseif target == M.target.popup then
			-- create a new buffer
			buf, _ = M._H.create_popup(M._Name .. " popup (close with <esc>)", function(w, h)
				return w / 2, h / 2, h / 4, w / 4
			end)
			-- set the created buffer as the current buffer
			vim.api.nvim_set_current_buf(buf)
			-- set the filetype to markdown
			vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
			-- better text wrapping
			vim.api.nvim_command("setlocal wrap linebreak")
			-- prepare handler
			handler = M.create_handler(buf, 0, false)
		end

		-- call the model and write the response
		M.query(
			{
				model = model,
				stream = true,
				messages = messages,
				temperature = temperature,
			},
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
		vim.ui.input({ prompt = prompt }, function(input)
			if not input or input == "" then
				return
			end
			callback(input)
		end)
	end)
end

M.cmd.VisualRewrite = function()
	M.prompt(
		M.mode.visual,
		M.target.replace,
		M.config.command_prompt_prefix,
		M.config.command_model,
		M.config.template_rewrite,
		M.config.command_system_prompt
	)
end

M.cmd.VisualAppend = function()
	M.prompt(
		M.mode.visual,
		M.target.append,
		M.config.command_prompt_prefix,
		M.config.command_model,
		M.config.template_selection,
		M.config.command_system_prompt
	)
end

M.cmd.VisualPrepend = function()
	M.prompt(
		M.mode.visual,
		M.target.prepend,
		M.config.command_prompt_prefix,
		M.config.command_model,
		M.config.template_selection,
		M.config.command_system_prompt
	)
end

M.cmd.VisualEnew = function()
	M.prompt(
		M.mode.visual,
		M.target.enew,
		M.config.command_prompt_prefix,
		M.config.command_model,
		M.config.template_selection,
		M.config.command_system_prompt
	)
end

M.cmd.VisualPopup = function()
	M.prompt(
		M.mode.visual,
		M.target.popup,
		M.config.command_prompt_prefix,
		M.config.chat_model,
		M.config.template_selection,
		M.config.chat_system_prompt
	)
end

M.cmd.Inline = function()
	M.prompt(
		M.mode.normal,
		M.target.replace,
		M.config.command_prompt_prefix,
		M.config.command_model,
		M.config.template_command,
		M.config.command_system_prompt
	)
end

M.cmd.Append = function()
	M.prompt(
		M.mode.normal,
		M.target.append,
		M.config.command_prompt_prefix,
		M.config.command_model,
		M.config.template_command,
		M.config.command_system_prompt
	)
end

M.cmd.Prepend = function()
	M.prompt(
		M.mode.normal,
		M.target.prepend,
		M.config.command_prompt_prefix,
		M.config.command_model,
		M.config.template_command,
		M.config.command_system_prompt
	)
end

M.cmd.Enew = function()
	M.prompt(
		M.mode.normal,
		M.target.enew,
		M.config.command_prompt_prefix,
		M.config.command_model,
		M.config.template_command,
		M.config.command_system_prompt
	)
end

M.cmd.Popup = function()
	M.prompt(
		M.mode.normal,
		M.target.popup,
		M.config.command_prompt_prefix,
		M.config.chat_model,
		M.config.template_command,
		M.config.chat_system_prompt
	)
end

--[[ M.setup() ]]
--[[ print("gp.lua loaded\n\n") ]]

return M

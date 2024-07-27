-- Gp (GPT prompt) lua plugin for Neovim
-- https://github.com/Robitx/gp.nvim/

--------------------------------------------------------------------------------
-- Module structure
--------------------------------------------------------------------------------
local uv = vim.uv or vim.loop

local config = require("gp.config")

local M = {
	_Name = "Gp", -- plugin name
	_state = {}, -- table of state variables
	agents = {}, -- table of agents
	cmd = {}, -- default command functions
	config = {}, -- config variables
	hooks = {}, -- user defined command functions
	defaults = require("gp.defaults"), -- some useful defaults
	logger = require("gp.logger"), -- logger module
	spinner = require("gp.spinner"), -- spinner module
	tasker = require("gp.tasker"), -- tasker module
	helpers = require("gp.helper"), -- helper functions
	deprecator = require("gp.deprecator"), -- handle deprecated options
	render = require("gp.render"), -- render module
	imager = require("gp.imager"), -- imager module
	vault = require("gp.vault"), -- vault module
}

--------------------------------------------------------------------------------
-- Module helper functions and variables
--------------------------------------------------------------------------------

-- setup function
M._setup_called = false
---@param opts table | nil # table with options
M.setup = function(opts)
	M._setup_called = true

	math.randomseed(os.time())

	-- make sure opts is a table
	opts = opts or {}
	if type(opts) ~= "table" then
		M.logger.error(string.format("setup() expects table, but got %s:\n%s", type(opts), vim.inspect(opts)))
		opts = {}
	end

	-- reset M.config
	M.config = vim.deepcopy(config)

	M.logger.setup(opts.log_file or M.config.log_file, opts.log_sensitive)

	local image_opts = opts.image or {}
	image_opts.state_dir = opts.state_dir or M.config.state_dir
	image_opts.cmd_prefix = opts.cmd_prefix or M.config.cmd_prefix
	M.imager.setup(image_opts)

	-- merge nested tables
	local mergeTables = { "hooks", "agents", "providers" }
	for _, tbl in ipairs(mergeTables) do
		M[tbl] = M[tbl] or {}
		---@diagnostic disable-next-line: param-type-mismatch
		for k, v in pairs(M.config[tbl]) do
			if tbl == "hooks" or tbl == "providers" then
				M[tbl][k] = v
			elseif tbl == "agents" then
				M[tbl][v.name] = v
			end
		end
		M.config[tbl] = nil

		opts[tbl] = opts[tbl] or {}
		for k, v in pairs(opts[tbl]) do
			if tbl == "hooks" then
				M[tbl][k] = v
			elseif tbl == "providers" then
				M[tbl][k] = M[tbl][k] or {}
				M[tbl][k].disable = false
				for pk, pv in pairs(v) do
					M[tbl][k][pk] = pv
				end
				if next(v) == nil then
					M[tbl][k] = nil
				end
			elseif tbl == "agents" then
				M[tbl][v.name] = v
			end
		end
		opts[tbl] = nil
	end

	for k, v in pairs(opts) do
		if M.deprecator.is_valid(k, v) then
			M.config[k] = v
		end
	end
	M.deprecator.report()

	-- make sure _dirs exists
	for k, v in pairs(M.config) do
		if k:match("_dir$") and type(v) == "string" then
			M.config[k] = M.helpers.prepare_dir(v, k)
		end
	end

	-- remove invalid agents
	for name, agent in pairs(M.agents) do
		if type(agent) ~= "table" or agent.disable then
			M.agents[name] = nil
		elseif not agent.model or not agent.system_prompt then
			M.logger.warning(
				"Agent "
					.. name
					.. " is missing model or system_prompt\n"
					.. "If you want to disable an agent, use: { name = '"
					.. name
					.. "', disable = true },"
			)
			M.agents[name] = nil
		end
	end

	-- remove invalid providers
	for name, provider in pairs(M.providers) do
		if type(provider) ~= "table" or provider.disable then
			M.providers[name] = nil
		elseif not provider.endpoint then
			M.logger.warning("Provider " .. name .. " is missing endpoint")
			M.providers[name] = nil
		end
	end

	-- prepare agent completions
	M._chat_agents = {}
	M._command_agents = {}
	for name, agent in pairs(M.agents) do
		if not M.agents[name].provider then
			M.agents[name].provider = "openai"
		end

		if M.providers[M.agents[name].provider] then
			if agent.command then
				table.insert(M._command_agents, name)
			end
			if agent.chat then
				table.insert(M._chat_agents, name)
			end
		else
			M.agents[name] = nil
		end
	end
	table.sort(M._chat_agents)
	table.sort(M._command_agents)

	M.refresh_state()

	-- register user commands
	for hook, _ in pairs(M.hooks) do
		vim.api.nvim_create_user_command(M.config.cmd_prefix .. hook, function(params)
			M.call_hook(hook, params)
		end, { nargs = "?", range = true, desc = "GPT Prompt plugin" })
	end

	local completions = {
		ChatNew = { "popup", "split", "vsplit", "tabnew" },
		ChatPaste = { "popup", "split", "vsplit", "tabnew" },
		ChatToggle = { "popup", "split", "vsplit", "tabnew" },
		Context = { "popup", "split", "vsplit", "tabnew" },
	}

	-- register default commands
	for cmd, _ in pairs(M.cmd) do
		if M.hooks[cmd] == nil then
			vim.api.nvim_create_user_command(M.config.cmd_prefix .. cmd, function(params)
				M.cmd[cmd](params)
			end, {
				nargs = "?",
				range = true,
				desc = "GPT Prompt plugin",
				complete = function()
					if completions[cmd] then
						return completions[cmd]
					end

					if cmd == "Agent" then
						local buf = vim.api.nvim_get_current_buf()
						local file_name = vim.api.nvim_buf_get_name(buf)
						if M.not_chat(buf, file_name) == nil then
							return M._chat_agents
						end
						return M._command_agents
					end

					return {}
				end,
			})
		end
	end

	M.buf_handler()

	if vim.fn.executable("curl") == 0 then
		M.logger.error("curl is not installed, run :checkhealth gp")
	end

	M.vault.setup({
		state_dir = M.config.state_dir,
		curl_params = M.config.curl_params,
	})

	for name, provider in pairs(M.providers) do
		if name == "copilot" then
			M.vault.resolve_secret(name, provider.secret, M.vault.refresh_copilot_bearer)
		else
			M.vault.resolve_secret(name, provider.secret)
		end
		provider.secret = nil
	end
	M.vault.resolve_secret("openai_api_key", M.config.openai_api_key)
	M.vault.resolve_secret("openai_api_key", image_opts.openai_api_key)
end

M.refresh_state = function()
	local state_file = M.config.state_dir .. "/state.json"

	local state = {}
	if vim.fn.filereadable(state_file) ~= 0 then
		state = M.helpers.file_to_table(state_file) or {}
	end

	M.logger.debug("loaded state: " .. vim.inspect(state))

	M._state.chat_agent = M._state.chat_agent or state.chat_agent or nil
	if M._state.chat_agent == nil or not M.agents[M._state.chat_agent] then
		M._state.chat_agent = M._chat_agents[1]
	end

	M._state.command_agent = M._state.command_agent or state.command_agent or nil
	if not M._state.command_agent == nil or not M.agents[M._state.command_agent] then
		M._state.command_agent = M._command_agents[1]
	end

	M.helpers.table_to_file(M._state, state_file)

	M.prepare_commands()

	local buf = vim.api.nvim_get_current_buf()
	local file_name = vim.api.nvim_buf_get_name(buf)
	M.display_chat_agent(buf, file_name)
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

	--- for creating a new horizontal split
	---@param filetype nil | string # nil = same as the original buffer
	---@return table # a table with type=5 and filetype=filetype
	new = function(filetype)
		return { type = 5, filetype = filetype }
	end,

	--- for creating a new vertical split
	---@param filetype nil | string # nil = same as the original buffer
	---@return table # a table with type=6 and filetype=filetype
	vnew = function(filetype)
		return { type = 6, filetype = filetype }
	end,

	--- for creating a new tab
	---@param filetype nil | string # nil = same as the original buffer
	---@return table # a table with type=7 and filetype=filetype
	tabnew = function(filetype)
		return { type = 7, filetype = filetype }
	end,
}

-- creates prompt commands for each target
M.prepare_commands = function()
	for name, target in pairs(M.Target) do
		-- uppercase first letter
		local command = name:gsub("^%l", string.upper)

		local agent = M.get_command_agent()
		-- popup is like ephemeral one off chat
		if target == M.Target.popup then
			agent = M.get_chat_agent()
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
				if target == M.Target.append then
					template = M.config.template_append
				end
				if target == M.Target.prepend then
					template = M.config.template_prepend
				end
			end
			if agent then
				M.Prompt(params, target, agent, template, agent.cmd_prefix, whisper)
			end
		end

		M.cmd[command] = function(params)
			cmd(params)
		end

		M.cmd["Whisper" .. command] = function(params)
			M.Whisper(M.config.whisper_language, function(text)
				vim.schedule(function()
					cmd(params, text)
				end)
			end)
		end
	end
end

-- hook caller
M.call_hook = function(name, params)
	if M.hooks[name] ~= nil then
		return M.hooks[name](M, params)
	end
	M.logger.error("The hook '" .. name .. "' does not exist.")
end

---@param messages table
---@param model string | table
---@param provider string | nil
M.prepare_payload = function(messages, model, provider)
	if type(model) == "string" then
		return {
			model = model,
			stream = true,
			messages = messages,
		}
	end

	if provider == "googleai" then
		for i, message in ipairs(messages) do
			if message.role == "system" then
				messages[i].role = "user"
			end
			if message.role == "assistant" then
				messages[i].role = "model"
			end
			if message.content then
				messages[i].parts = {
					{
						text = message.content,
					},
				}
				messages[i].content = nil
			end
		end
		local i = 1
		while i < #messages do
			if messages[i].role == messages[i + 1].role then
				table.insert(messages[i].parts, {
					text = messages[i + 1].parts[1].text,
				})
				table.remove(messages, i + 1)
			else
				i = i + 1
			end
		end
		local payload = {
			contents = messages,
			safetySettings = {
				{
					category = "HARM_CATEGORY_HARASSMENT",
					threshold = "BLOCK_NONE",
				},
				{
					category = "HARM_CATEGORY_HATE_SPEECH",
					threshold = "BLOCK_NONE",
				},
				{
					category = "HARM_CATEGORY_SEXUALLY_EXPLICIT",
					threshold = "BLOCK_NONE",
				},
				{
					category = "HARM_CATEGORY_DANGEROUS_CONTENT",
					threshold = "BLOCK_NONE",
				},
			},
			generationConfig = {
				temperature = math.max(0, math.min(2, model.temperature or 1)),
				maxOutputTokens = model.max_tokens or 8192,
				topP = math.max(0, math.min(1, model.top_p or 1)),
				topK = model.top_k or 100,
			},
			model = model.model,
		}
		return payload
	end

	if provider == "anthropic" then
		local system = ""
		local i = 1
		while i < #messages do
			if messages[i].role == "system" then
				system = system .. messages[i].content .. "\n"
				table.remove(messages, i)
			else
				i = i + 1
			end
		end

		local payload = {
			model = model.model,
			stream = true,
			messages = messages,
			system = system,
			max_tokens = model.max_tokens or 4096,
			temperature = math.max(0, math.min(2, model.temperature or 1)),
			top_p = math.max(0, math.min(1, model.top_p or 1)),
		}
		return payload
	end

	return {
		model = model.model,
		stream = true,
		messages = messages,
		temperature = math.max(0, math.min(2, model.temperature or 1)),
		top_p = math.max(0, math.min(1, model.top_p or 1)),
	}
end

-- gpt query
---@param buf number | nil # buffer number
---@param provider string # provider name
---@param payload table # payload for api
---@param handler function # response handler
---@param on_exit function | nil # optional on_exit handler
---@param callback function | nil # optional callback handler
M.query = function(buf, provider, payload, handler, on_exit, callback)
	-- make sure handler is a function
	if type(handler) ~= "function" then
		M.logger.error(
			string.format("query() expects a handler function, but got %s:\n%s", type(handler), vim.inspect(handler))
		)
		return
	end

	local qid = M.helpers.uuid()
	M.tasker.set_query(qid, {
		timestamp = os.time(),
		buf = buf,
		provider = provider,
		payload = payload,
		handler = handler,
		on_exit = on_exit,
		raw_response = "",
		response = "",
		first_line = -1,
		last_line = -1,
		ns_id = nil,
		ex_id = nil,
	})

	local out_reader = function()
		local buffer = ""

		---@param lines_chunk string
		local function process_lines(lines_chunk)
			local qt = M.tasker.get_query(qid)
			if not qt then
				return
			end

			local lines = vim.split(lines_chunk, "\n")
			for _, line in ipairs(lines) do
				if line ~= "" and line ~= nil then
					qt.raw_response = qt.raw_response .. line .. "\n"
				end
				line = line:gsub("^data: ", "")
				local content = ""
				if line:match("choices") and line:match("delta") and line:match("content") then
					line = vim.json.decode(line)
					if line.choices[1] and line.choices[1].delta and line.choices[1].delta.content then
						content = line.choices[1].delta.content
					end
				end

				if qt.provider == "anthropic" and line:match('"text":') then
					if line:match("content_block_start") or line:match("content_block_delta") then
						line = vim.json.decode(line)
						if line.delta and line.delta.text then
							content = line.delta.text
						end
						if line.content_block and line.content_block.text then
							content = line.content_block.text
						end
					end
				end

				if qt.provider == "googleai" then
					if line:match('"text":') then
						content = vim.json.decode("{" .. line .. "}").text
					end
				end

				if content and type(content) == "string" then
					qt.response = qt.response .. content
					handler(qid, content)
				end
			end
		end

		-- closure for uv.read_start(stdout, fn)
		return function(err, chunk)
			local qt = M.tasker.get_query(qid)
			if not qt then
				return
			end

			if err then
				M.logger.error(qt.provider .. " query stdout error: " .. vim.inspect(err))
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

				if qt.response == "" then
					M.logger.error(qt.provider .. " response is empty: \n" .. vim.inspect(qt.raw_response))
				end

				-- optional on_exit handler
				if type(on_exit) == "function" then
					on_exit(qid)
					if qt.ns_id and qt.buf then
						vim.schedule(function()
							vim.api.nvim_buf_clear_namespace(qt.buf, qt.ns_id, 0, -1)
						end)
					end
				end

				-- optional callback handler
				if type(callback) == "function" then
					vim.schedule(function()
						callback(qt.response)
					end)
				end
			end
		end
	end

	---TODO: this could be moved to a separate function returning endpoint and headers
	local endpoint = M.providers[provider].endpoint
	local headers = {}
	local bearer = M.vault.get_secret(provider)
	if not bearer then
		return
	end

	if provider == "copilot" then
		M.refresh_copilot_bearer()
		bearer = M.vault.get_secret("copilot_bearer")
		if not bearer then
			return
		end
		headers = {
			"-H",
			"editor-version: vscode/1.85.1",
			"-H",
			"Authorization: Bearer " .. bearer,
		}
	elseif provider == "openai" then
		headers = {
			"-H",
			"Authorization: Bearer " .. bearer,
			-- backwards compatibility
			"-H",
			"api-key: " .. bearer,
		}
	elseif provider == "googleai" then
		headers = {}
		endpoint = M.render.template_replace(endpoint, "{{secret}}", bearer)
		endpoint = M.render.template_replace(endpoint, "{{model}}", payload.model)
		payload.model = nil
	elseif provider == "anthropic" then
		headers = {
			"-H",
			"x-api-key: " .. bearer,
			"-H",
			"anthropic-version: 2023-06-01",
			"-H",
			"anthropic-beta: messages-2023-12-15",
		}
	elseif provider == "azure" then
		headers = {
			"-H",
			"api-key: " .. bearer,
		}
		endpoint = M.render.template_replace(endpoint, "{{model}}", payload.model)
	else -- default to openai compatible headers
		headers = {
			"-H",
			"Authorization: Bearer " .. bearer,
		}
	end

	local curl_params = vim.deepcopy(M.config.curl_params or {})
	local args = {
		"--no-buffer",
		"-s",
		endpoint,
		"-H",
		"Content-Type: application/json",
		"-d",
		vim.json.encode(payload),
		--[[ "--doesnt_exist" ]]
	}

	for _, arg in ipairs(args) do
		table.insert(curl_params, arg)
	end

	for _, header in ipairs(headers) do
		table.insert(curl_params, header)
	end

	M.tasker.run(buf, "curl", curl_params, nil, out_reader(), nil)
end

-- response handler
---@param buf number | nil # buffer to insert response into
---@param win number | nil # window to insert response into
---@param line number | nil # line to insert response into
---@param first_undojoin boolean | nil # whether to skip first undojoin
---@param prefix string | nil # prefix to insert before each response line
---@param cursor boolean # whether to move cursor to the end of the response
M.create_handler = function(buf, win, line, first_undojoin, prefix, cursor)
	buf = buf or vim.api.nvim_get_current_buf()
	prefix = prefix or ""
	local first_line = line or vim.api.nvim_win_get_cursor(win or 0)[1] - 1
	local finished_lines = 0
	local skip_first_undojoin = not first_undojoin

	local hl_handler_group = "GpHandlerStandout"
	vim.cmd("highlight default link " .. hl_handler_group .. " CursorLine")

	local ns_id = vim.api.nvim_create_namespace("GpHandler_" .. M.helpers.uuid())

	local ex_id = vim.api.nvim_buf_set_extmark(buf, ns_id, first_line, 0, {
		strict = false,
		right_gravity = false,
	})

	local response = ""
	return vim.schedule_wrap(function(qid, chunk)
		local qt = M.tasker.get_query(qid)
		if not qt then
			return
		end
		-- if buf is not valid, stop
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		-- undojoin takes previous change into account, so skip it for the first chunk
		if skip_first_undojoin then
			skip_first_undojoin = false
		else
			M.helpers.undojoin(buf)
		end

		if not qt.ns_id then
			qt.ns_id = ns_id
		end

		if not qt.ex_id then
			qt.ex_id = ex_id
		end

		first_line = vim.api.nvim_buf_get_extmark_by_id(buf, ns_id, ex_id, {})[1]

		-- clean previous response
		local line_count = #vim.split(response, "\n")
		vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + line_count, false, {})

		-- append new response
		response = response .. chunk
		M.helpers.undojoin(buf)

		-- prepend prefix to each line
		local lines = vim.split(response, "\n")
		for i, l in ipairs(lines) do
			lines[i] = prefix .. l
		end

		local unfinished_lines = {}
		for i = finished_lines + 1, #lines do
			table.insert(unfinished_lines, lines[i])
		end

		vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + finished_lines, false, unfinished_lines)

		local new_finished_lines = math.max(0, #lines - 1)
		for i = finished_lines, new_finished_lines do
			vim.api.nvim_buf_add_highlight(buf, qt.ns_id, hl_handler_group, first_line + i, 0, -1)
		end
		finished_lines = new_finished_lines

		local end_line = first_line + #vim.split(response, "\n")
		qt.first_line = first_line
		qt.last_line = end_line - 1

		-- move cursor to the end of the response
		if cursor then
			M.helpers.cursor_to_line(end_line, buf, win)
		end
	end)
end

-- stop receiving gpt responses for all processes and clean the handles
---@param signal number | nil # signal to send to the process
M.cmd.Stop = function(signal)
	M.tasker.stop(signal)
end

--------------------
-- Chat logic
--------------------

M._toggle = {}

M._toggle_kind = {
	unknown = 0, -- unknown toggle
	chat = 1, -- chat toggle
	popup = 2, -- popup toggle
	context = 3, -- context toggle
}

---@param kind number # kind of toggle
---@return boolean # true if toggle was closed
M._toggle_close = function(kind)
	if
		M._toggle[kind]
		and M._toggle[kind].win
		and M._toggle[kind].buf
		and M._toggle[kind].close
		and vim.api.nvim_win_is_valid(M._toggle[kind].win)
		and vim.api.nvim_buf_is_valid(M._toggle[kind].buf)
		and vim.api.nvim_win_get_buf(M._toggle[kind].win) == M._toggle[kind].buf
	then
		if #vim.api.nvim_list_wins() == 1 then
			M.logger.warning("Can't close the last window.")
		else
			M._toggle[kind].close()
			M._toggle[kind] = nil
		end
		return true
	end
	M._toggle[kind] = nil
	return false
end

---@param kind number # kind of toggle
---@param toggle table # table containing `win`, `buf`, and `close` information
M._toggle_add = function(kind, toggle)
	M._toggle[kind] = toggle
end

---@param kind string # string representation of the toggle kind
---@return number # numeric kind of the toggle
M._toggle_resolve = function(kind)
	kind = kind:lower()
	if kind == "chat" then
		return M._toggle_kind.chat
	elseif kind == "popup" then
		return M._toggle_kind.popup
	elseif kind == "context" then
		return M._toggle_kind.context
	end
	M.logger.warning("Unknown toggle kind: " .. kind)
	return M._toggle_kind.unknown
end

---@param buf number | nil # buffer number
M.prep_md = function(buf)
	-- disable swapping for this buffer and set filetype to markdown
	vim.api.nvim_command("setlocal noswapfile")
	-- better text wrapping
	vim.api.nvim_command("setlocal wrap linebreak")
	-- auto save on TextChanged, InsertLeave
	vim.api.nvim_command("autocmd TextChanged,InsertLeave <buffer=" .. buf .. "> silent! write")

	-- register shortcuts local to this buffer
	buf = buf or vim.api.nvim_get_current_buf()

	-- ensure normal mode
	vim.api.nvim_command("stopinsert")
	M.helpers.feedkeys("<esc>", "xn")
end

---@param buf number # buffer number
---@param file_name string # file name
---@return string | nil # reason for not being a chat or nil if it is a chat
M.not_chat = function(buf, file_name)
	file_name = vim.fn.resolve(file_name)
	local chat_dir = vim.fn.resolve(M.config.chat_dir)
	if not M.helpers.starts_with(file_name, chat_dir) then
		return "resolved file (" .. file_name .. ") not in chat dir (" .. chat_dir .. ")"
	end

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	if #lines < 5 then
		return "file too short"
	end

	if not lines[1]:match("^# ") then
		return "missing topic header"
	end

	local header_found = nil
	for i = 1, 10 do
		if i < #lines and lines[i]:match("^- file: ") then
			header_found = true
			break
		end
	end
	if not header_found then
		return "missing file header"
	end

	return nil
end

M.display_chat_agent = function(buf, file_name)
	if M.not_chat(buf, file_name) then
		return
	end

	if buf ~= vim.api.nvim_get_current_buf() then
		return
	end

	local ns_id = vim.api.nvim_create_namespace("GpChatExt_" .. file_name)
	vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

	vim.api.nvim_buf_set_extmark(buf, ns_id, 0, 0, {
		strict = false,
		right_gravity = true,
		virt_text_pos = "right_align",
		virt_text = {
			{ "Current Agent: [" .. M._state.chat_agent .. "]", "DiagnosticHint" },
		},
		hl_mode = "combine",
	})
end

M.prep_chat = function(buf, file_name)
	if M.not_chat(buf, file_name) then
		return
	end

	if buf ~= vim.api.nvim_get_current_buf() then
		return
	end

	M.prep_md(buf)

	if M.config.chat_prompt_buf_type then
		vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
		vim.fn.prompt_setprompt(buf, "")
		vim.fn.prompt_setcallback(buf, function()
			M.cmd.ChatRespond({ args = "" })
		end)
	end

	-- setup chat specific commands
	local range_commands = {
		{
			command = "ChatRespond",
			modes = M.config.chat_shortcut_respond.modes,
			shortcut = M.config.chat_shortcut_respond.shortcut,
			comment = "GPT prompt Chat Respond",
		},
		{
			command = "ChatNew",
			modes = M.config.chat_shortcut_new.modes,
			shortcut = M.config.chat_shortcut_new.shortcut,
			comment = "GPT prompt Chat New",
		},
	}
	for _, rc in ipairs(range_commands) do
		local cmd = M.config.cmd_prefix .. rc.command .. "<cr>"
		for _, mode in ipairs(rc.modes) do
			if mode == "n" or mode == "i" then
				M.helpers.set_keymap({ buf }, mode, rc.shortcut, function()
					vim.api.nvim_command(M.config.cmd_prefix .. rc.command)
					-- go to normal mode
					vim.api.nvim_command("stopinsert")
					M.helpers.feedkeys("<esc>", "xn")
				end, rc.comment)
			else
				M.helpers.set_keymap({ buf }, mode, rc.shortcut, ":<C-u>'<,'>" .. cmd, rc.comment)
			end
		end
	end

	local ds = M.config.chat_shortcut_delete
	M.helpers.set_keymap({ buf }, ds.modes, ds.shortcut, M.cmd.ChatDelete, "GPT prompt Chat Delete")

	local ss = M.config.chat_shortcut_stop
	M.helpers.set_keymap({ buf }, ss.modes, ss.shortcut, M.cmd.Stop, "GPT prompt Chat Stop")

	-- conceal parameters in model header so it's not distracting
	if M.config.chat_conceal_model_params then
		vim.opt_local.conceallevel = 2
		vim.opt_local.concealcursor = ""
		vim.fn.matchadd("Conceal", [[^- model: .*model.:.[^"]*\zs".*\ze]], 10, -1, { conceal = "…" })
		vim.fn.matchadd("Conceal", [[^- model: \zs.*model.:.\ze.*]], 10, -1, { conceal = "…" })
		vim.fn.matchadd("Conceal", [[^- role: .\{64,64\}\zs.*\ze]], 10, -1, { conceal = "…" })
		vim.fn.matchadd("Conceal", [[^- role: .[^\\]*\zs\\.*\ze]], 10, -1, { conceal = "…" })
	end

	-- make last.md a symlink to the last opened chat file
	local last = M.config.chat_dir .. "/last.md"
	if file_name ~= last then
		os.execute("ln -sf " .. file_name .. " " .. last)
	end
end

M.buf_handler = function()
	local gid = M.helpers.create_augroup("GpBufHandler", { clear = true })

	M.helpers.autocmd({ "BufEnter" }, nil, function(event)
		local buf = event.buf

		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		local file_name = vim.api.nvim_buf_get_name(buf)

		M.prep_chat(buf, file_name)
		M.display_chat_agent(buf, file_name)
		M.prep_context(buf, file_name)
	end, gid)

	M.helpers.autocmd({ "WinEnter" }, nil, function(event)
		local buf = event.buf

		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		local file_name = vim.api.nvim_buf_get_name(buf)

		M.display_chat_agent(buf, file_name)
	end, gid)
end

M.BufTarget = {
	current = 0, -- current window
	popup = 1, -- popup window
	split = 2, -- split window
	vsplit = 3, -- vsplit window
	tabnew = 4, -- new tab
}

---@param params table | string # table with args or string args
---@return number # buf target
M.resolve_buf_target = function(params)
	local args = ""
	if type(params) == "table" then
		args = params.args or ""
	else
		args = params
	end

	args = args:match("^%s*(.-)%s*$")

	if args == "popup" then
		return M.BufTarget.popup
	elseif args == "split" then
		return M.BufTarget.split
	elseif args == "vsplit" then
		return M.BufTarget.vsplit
	elseif args == "tabnew" then
		return M.BufTarget.tabnew
	else
		return M.BufTarget.current
	end
end

---@param file_name string
---@param target number | nil # buf target
---@param kind number # nil or a toggle kind
---@param toggle boolean # whether to toggle
---@return number # buffer number
M.open_buf = function(file_name, target, kind, toggle)
	target = target or M.BufTarget.current

	-- close previous popup if it exists
	M._toggle_close(M._toggle_kind.popup)

	if toggle then
		M._toggle_close(kind)
	end

	local close, buf, win

	if target == M.BufTarget.popup then
		local old_buf = M.helpers.get_buffer(file_name)

		buf, win, close, _ = M.render.popup(old_buf, M._Name .. " Popup", function(w, h)
			local top = M.config.style_popup_margin_top or 2
			local bottom = M.config.style_popup_margin_bottom or 8
			local left = M.config.style_popup_margin_left or 1
			local right = M.config.style_popup_margin_right or 1
			local max_width = M.config.style_popup_max_width or 160
			local ww = math.min(w - (left + right), max_width)
			local wh = h - (top + bottom)
			return ww, wh, top, (w - ww) / 2
		end, { on_leave = false, escape = false, persist = true }, {
			border = M.config.style_popup_border or "single",
		})

		if not toggle then
			M._toggle_add(M._toggle_kind.popup, { win = win, buf = buf, close = close })
		end

		if old_buf == nil then
			-- read file into buffer and force write it
			vim.api.nvim_command("silent 0read " .. file_name)
			vim.api.nvim_command("silent file " .. file_name)
			-- set the filetype to markdown
			vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
		else
			-- move cursor to the beginning of the file and scroll to the end
			M.helpers.feedkeys("ggG", "xn")
		end

		-- delete whitespace lines at the end of the file
		local last_content_line = M.helpers.last_content_line(buf)
		vim.api.nvim_buf_set_lines(buf, last_content_line, -1, false, {})
		-- insert a new line at the end of the file
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
		vim.api.nvim_command("silent write! " .. file_name)
	elseif target == M.BufTarget.split then
		vim.api.nvim_command("split " .. file_name)
	elseif target == M.BufTarget.vsplit then
		vim.api.nvim_command("vsplit " .. file_name)
	elseif target == M.BufTarget.tabnew then
		vim.api.nvim_command("tabnew " .. file_name)
	else
		-- is it already open in a buffer?
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_name(b) == file_name then
				for _, w in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_get_buf(w) == b then
						vim.api.nvim_set_current_win(w)
						return b
					end
				end
			end
		end

		-- open in new buffer
		vim.api.nvim_command("edit " .. file_name)
	end

	buf = vim.api.nvim_get_current_buf()
	win = vim.api.nvim_get_current_win()
	close = close or function() end

	if not toggle then
		return buf
	end

	vim.api.nvim_set_option_value("buflisted", false, { buf = buf })

	if target == M.BufTarget.split or target == M.BufTarget.vsplit then
		close = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
	end

	if target == M.BufTarget.tabnew then
		close = function()
			if vim.api.nvim_win_is_valid(win) then
				local tab = vim.api.nvim_win_get_tabpage(win)
				vim.api.nvim_set_current_tabpage(tab)
				vim.api.nvim_command("tabclose")
			end
		end
	end

	M._toggle_add(kind, { win = win, buf = buf, close = close })

	return buf
end

---@param params table  # vim command parameters such as range, args, etc.
---@param toggle boolean # whether chat is toggled
---@param system_prompt string | nil # system prompt to use
---@param agent table | nil # obtained from get_command_agent or get_chat_agent
---@return number # buffer number
M.new_chat = function(params, toggle, system_prompt, agent)
	M._toggle_close(M._toggle_kind.popup)

	-- prepare filename
	local time = os.date("%Y-%m-%d.%H-%M-%S")
	local stamp = tostring(math.floor(uv.hrtime() / 1000000) % 1000)
	-- make sure stamp is 3 digits
	while #stamp < 3 do
		stamp = "0" .. stamp
	end
	time = time .. "." .. stamp
	local filename = M.config.chat_dir .. "/" .. time .. ".md"

	-- encode as json if model is a table
	local model = ""
	local provider = ""
	if agent and agent.model and agent.provider then
		model = agent.model
		provider = agent.provider
		if type(model) == "table" then
			model = "- model: " .. vim.json.encode(model) .. "\n"
		else
			model = "- model: " .. model .. "\n"
		end

		provider = "- provider: " .. provider:gsub("\n", "\\n") .. "\n"
	end

	-- display system prompt as single line with escaped newlines
	if system_prompt then
		system_prompt = "- role: " .. system_prompt:gsub("\n", "\\n") .. "\n"
	else
		system_prompt = ""
	end

	local template = M.render.template(M.config.chat_template or require("gp.defaults").chat_template, {
		["{{filename}}"] = string.match(filename, "([^/]+)$"),
		["{{optional_headers}}"] = model .. provider .. system_prompt,
		["{{user_prefix}}"] = M.config.chat_user_prefix,
		["{{respond_shortcut}}"] = M.config.chat_shortcut_respond.shortcut,
		["{{cmd_prefix}}"] = M.config.cmd_prefix,
		["{{stop_shortcut}}"] = M.config.chat_shortcut_stop.shortcut,
		["{{delete_shortcut}}"] = M.config.chat_shortcut_delete.shortcut,
		["{{new_shortcut}}"] = M.config.chat_shortcut_new.shortcut,
	})

	-- escape underscores (for markdown)
	template = template:gsub("_", "\\_")

	local cbuf = vim.api.nvim_get_current_buf()

	-- strip leading and trailing newlines
	template = template:gsub("^%s*(.-)%s*$", "%1") .. "\n"

	-- create chat file
	vim.fn.writefile(vim.split(template, "\n"), filename)
	local target = M.resolve_buf_target(params)
	local buf = M.open_buf(filename, target, M._toggle_kind.chat, toggle)

	if params.range == 2 then
		M.render.append_selection(params, cbuf, buf, M.config.template_selection)
	end
	M.helpers.feedkeys("G", "xn")
	return buf
end

local exampleChatHook = [[
Translator = function(gp, params)
    local chat_system_prompt = "You are a Translator, please translate between English and Chinese."
    gp.cmd.ChatNew(params, chat_system_prompt)

    -- -- you can also create a chat with a specific fixed agent like this:
    -- local agent = gp.get_chat_agent("ChatGPT4o")
    -- gp.cmd.ChatNew(params, chat_system_prompt, agent)
end,
]]

---@param params table
---@param system_prompt string | nil
---@param agent table | nil # obtained from get_command_agent or get_chat_agent
---@return number # buffer number
M.cmd.ChatNew = function(params, system_prompt, agent)
	if agent then
		if not type(agent) == "table" or not agent.provider then
			M.logger.warning(
				"The `gp.cmd.ChatNew` method signature has changed.\n"
					.. "Please update your hook functions as demonstrated in the example below:\n\n"
					.. exampleChatHook
					.. "\nFor more information, refer to the 'Extend Functionality' section in the documentation."
			)
			return -1
		end
	end
	-- if chat toggle is open, close it and start a new one
	if M._toggle_close(M._toggle_kind.chat) then
		params.args = params.args or ""
		if params.args == "" then
			params.args = M.config.toggle_target
		end
		return M.new_chat(params, true, system_prompt, agent)
	end

	return M.new_chat(params, false, system_prompt, agent)
end

---@param params table
---@param system_prompt string | nil
---@param agent table | nil # obtained from get_command_agent or get_chat_agent
M.cmd.ChatToggle = function(params, system_prompt, agent)
	if M._toggle_close(M._toggle_kind.popup) then
		return
	end
	if M._toggle_close(M._toggle_kind.chat) and params.range ~= 2 then
		return
	end

	-- create new chat file otherwise
	params.args = params.args or ""
	if params.args == "" then
		params.args = M.config.toggle_target
	end

	-- if the range is 2, we want to create a new chat file with the selection
	if params.range ~= 2 then
		-- check if last.md chat file exists and open it
		local last = M.config.chat_dir .. "/last.md"
		if vim.fn.filereadable(last) == 1 then
			-- resolve symlink
			last = vim.fn.resolve(last)
			M.open_buf(last, M.resolve_buf_target(params), M._toggle_kind.chat, true)
			return
		end
	end

	M.new_chat(params, true, system_prompt, agent)
end

M.cmd.ChatPaste = function(params)
	-- if there is no selection, do nothing
	if params.range ~= 2 then
		M.logger.warning("Please select some text to paste into the chat.")
		return
	end

	-- get current buffer
	local cbuf = vim.api.nvim_get_current_buf()

	local last = M.config.chat_dir .. "/last.md"

	-- make new chat if last doesn't exist
	if vim.fn.filereadable(last) ~= 1 then
		-- skip rest since new chat will handle snippet on it's own
		M.cmd.ChatNew(params, nil, nil)
		return
	end

	params.args = params.args or ""
	if params.args == "" then
		params.args = M.config.toggle_target
	end
	local target = M.resolve_buf_target(params)

	last = vim.fn.resolve(last)
	local buf = M.helpers.get_buffer(last)
	local win_found = false
	if buf then
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(w) == buf then
				vim.api.nvim_set_current_win(w)
				vim.api.nvim_set_current_buf(buf)
				win_found = true
				break
			end
		end
	end
	buf = win_found and buf or M.open_buf(last, target, M._toggle_kind.chat, true)

	M.render.append_selection(params, cbuf, buf, M.config.template_selection)
	M.helpers.feedkeys("G", "xn")
end

M.cmd.ChatDelete = function()
	-- get buffer and file
	local buf = vim.api.nvim_get_current_buf()
	local file_name = vim.api.nvim_buf_get_name(buf)

	-- check if file is in the chat dir
	if not M.helpers.starts_with(file_name, vim.fn.resolve(M.config.chat_dir)) then
		M.logger.warning("File " .. vim.inspect(file_name) .. " is not in chat dir")
		return
	end

	-- delete without confirmation
	if not M.config.chat_confirm_delete then
		M.helpers.delete_file(file_name)
		return
	end

	-- ask for confirmation
	vim.ui.input({ prompt = "Delete " .. file_name .. "? [y/N] " }, function(input)
		if input and input:lower() == "y" then
			M.helpers.delete_file(file_name)
		end
	end)
end

M.chat_respond = function(params)
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	if M.tasker.is_busy(buf) then
		return
	end

	-- go to normal mode
	vim.cmd("stopinsert")

	-- get all lines
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

	-- check if file looks like a chat file
	local file_name = vim.api.nvim_buf_get_name(buf)
	local reason = M.not_chat(buf, file_name)
	if reason then
		M.logger.warning("File " .. vim.inspect(file_name) .. " does not look like a chat file: " .. vim.inspect(reason))
		return
	end

	-- headers are fields before first ---
	local headers = {}
	local header_end = nil
	local line_idx = 0
	---parse headers
	for _, line in ipairs(lines) do
		-- first line starts with ---
		if line:sub(1, 3) == "---" then
			header_end = line_idx
			break
		end
		-- parse header fields
		local key, value = line:match("^[-#] (%w+): (.*)")
		if key ~= nil then
			headers[key] = value
		end

		line_idx = line_idx + 1
	end

	if header_end == nil then
		M.logger.error("Error while parsing headers: --- not found. Check your chat template.")
		return
	end

	-- message needs role and content
	local messages = {}
	local role = ""
	local content = ""

	-- iterate over lines
	local start_index = header_end + 1
	local end_index = #lines
	if params.range == 2 then
		start_index = math.max(start_index, params.line1)
		end_index = math.min(end_index, params.line2)
	end

	local agent = M.get_chat_agent()
	local agent_name = agent.name

	-- if model contains { } then it is a json string otherwise it is a model name
	if headers.model and headers.model:match("{.*}") then
		-- unescape underscores before decoding json
		headers.model = headers.model:gsub("\\_", "_")
		headers.model = vim.json.decode(headers.model)
	end

	if headers.model and type(headers.model) == "table" then
		agent_name = headers.model.model
	elseif headers.model and headers.model:match("%S") then
		agent_name = headers.model
	end

	if headers.role and headers.role:match("%S") then
		---@diagnostic disable-next-line: cast-local-type
		agent_name = agent_name .. " & custom role"
	end

	if headers.model and not headers.provider then
		headers.provider = "openai"
	end

	local agent_prefix = config.chat_assistant_prefix[1]
	local agent_suffix = config.chat_assistant_prefix[2]
	if type(M.config.chat_assistant_prefix) == "string" then
		---@diagnostic disable-next-line: cast-local-type
		agent_prefix = M.config.chat_assistant_prefix
	elseif type(M.config.chat_assistant_prefix) == "table" then
		agent_prefix = M.config.chat_assistant_prefix[1]
		agent_suffix = M.config.chat_assistant_prefix[2] or ""
	end
	---@diagnostic disable-next-line: cast-local-type
	agent_suffix = M.render.template(agent_suffix, { ["{{agent}}"] = agent_name })

	local old_default_user_prefix = "🗨:"
	for index = start_index, end_index do
		local line = lines[index]
		if line:sub(1, #M.config.chat_user_prefix) == M.config.chat_user_prefix then
			table.insert(messages, { role = role, content = content })
			role = "user"
			content = line:sub(#M.config.chat_user_prefix + 1)
		elseif line:sub(1, #old_default_user_prefix) == old_default_user_prefix then
			table.insert(messages, { role = role, content = content })
			role = "user"
			content = line:sub(#old_default_user_prefix + 1)
		elseif line:sub(1, #agent_prefix) == agent_prefix then
			table.insert(messages, { role = role, content = content })
			role = "assistant"
			content = ""
		elseif role ~= "" then
			content = content .. "\n" .. line
		end
	end
	-- insert last message not handled in loop
	table.insert(messages, { role = role, content = content })

	-- replace first empty message with system prompt
	content = ""
	if headers.role and headers.role:match("%S") then
		content = headers.role
	else
		content = agent.system_prompt
	end
	if content:match("%S") then
		-- make it multiline again if it contains escaped newlines
		content = content:gsub("\\n", "\n")
		messages[1] = { role = "system", content = content }
	end

	-- strip whitespace from ends of content
	for _, message in ipairs(messages) do
		message.content = message.content:gsub("^%s*(.-)%s*$", "%1")
	end

	-- write assistant prompt
	local last_content_line = M.helpers.last_content_line(buf)
	vim.api.nvim_buf_set_lines(buf, last_content_line, last_content_line, false, { "", agent_prefix .. agent_suffix, "" })

	-- call the model and write response
	M.query(
		buf,
		headers.provider or agent.provider,
		M.prepare_payload(messages, headers.model or agent.model, headers.provider or agent.provider),
		M.create_handler(buf, win, M.helpers.last_content_line(buf), true, "", not M.config.chat_free_cursor),
		vim.schedule_wrap(function(qid)
			local qt = M.tasker.get_query(qid)
			if not qt then
				return
			end

			-- write user prompt
			last_content_line = M.helpers.last_content_line(buf)
			M.helpers.undojoin(buf)
			vim.api.nvim_buf_set_lines(
				buf,
				last_content_line,
				last_content_line,
				false,
				{ "", "", M.config.chat_user_prefix, "" }
			)

			-- delete whitespace lines at the end of the file
			last_content_line = M.helpers.last_content_line(buf)
			M.helpers.undojoin(buf)
			vim.api.nvim_buf_set_lines(buf, last_content_line, -1, false, {})
			-- insert a new line at the end of the file
			M.helpers.undojoin(buf)
			vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })

			-- if topic is ?, then generate it
			if headers.topic == "?" then
				-- insert last model response
				table.insert(messages, { role = "assistant", content = qt.response })

				-- ask model to generate topic/title for the chat
				table.insert(messages, { role = "user", content = M.config.chat_topic_gen_prompt })

				-- prepare invisible buffer for the model to write to
				local topic_buf = vim.api.nvim_create_buf(false, true)
				local topic_handler = M.create_handler(topic_buf, nil, 0, false, "", false)

				-- call the model
				M.query(
					nil,
					headers.provider or agent.provider,
					M.prepare_payload(messages, headers.model or agent.model, headers.provider or agent.provider),
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
						M.helpers.undojoin(buf)
						vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "# topic: " .. topic })
					end)
				)
			end
			if not M.config.chat_free_cursor then
				local line = vim.api.nvim_buf_line_count(buf)
				M.helpers.cursor_to_line(line, buf, win)
			end
			vim.cmd("doautocmd User GpDone")
		end)
	)
end

M.cmd.ChatRespond = function(params)
	if params.args == "" and vim.v.count == 0 then
		M.chat_respond(params)
		return
	elseif params.args == "" and vim.v.count ~= 0 then
		params.args = tostring(vim.v.count)
	end

	-- ensure args is a single positive number
	local n_requests = tonumber(params.args)
	if n_requests == nil or math.floor(n_requests) ~= n_requests or n_requests <= 0 then
		M.logger.warning("args for ChatRespond should be a single positive number, not: " .. params.args)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local cur_index = #lines
	while cur_index > 0 and n_requests > 0 do
		if lines[cur_index]:sub(1, #M.config.chat_user_prefix) == M.config.chat_user_prefix then
			n_requests = n_requests - 1
		end
		cur_index = cur_index - 1
	end

	params.range = 2
	params.line1 = cur_index + 1
	params.line2 = #lines
	M.chat_respond(params)
end

M._chat_finder_opened = false
M.cmd.ChatFinder = function()
	if M._chat_finder_opened then
		M.logger.warning("Chat finder is already open")
		return
	end
	M._chat_finder_opened = true

	local dir = M.config.chat_dir

	-- prepare unique group name and register augroup
	local gid = M.helpers.create_augroup("GpChatFinder", { clear = true })

	-- prepare three popup buffers and windows
	local ratio = M.config.style_chat_finder_preview_ratio or 0.5
	local top = M.config.style_chat_finder_margin_top or 2
	local bottom = M.config.style_chat_finder_margin_bottom or 8
	local left = M.config.style_chat_finder_margin_left or 1
	local right = M.config.style_chat_finder_margin_right or 2
	local picker_buf, picker_win, picker_close, picker_resize = M.render.popup(
		nil,
		"Picker: j/k <Esc>|exit <Enter>|open dd|del i|srch",
		function(w, h)
			local wh = h - top - bottom - 2
			local ww = w - left - right - 2
			return math.floor(ww * (1 - ratio)), wh, top, left
		end,
		{ gid = gid },
		{ border = M.config.style_chat_finder_border or "single" }
	)

	local preview_buf, preview_win, preview_close, preview_resize = M.render.popup(
		nil,
		"Preview (edits are ephemeral)",
		function(w, h)
			local wh = h - top - bottom - 2
			local ww = w - left - right - 1
			return ww * ratio, wh, top, left + math.ceil(ww * (1 - ratio)) + 2
		end,
		{ gid = gid },
		{ border = M.config.style_chat_finder_border or "single" }
	)

	vim.api.nvim_set_option_value("filetype", "markdown", { buf = preview_buf })

	local command_buf, command_win, command_close, command_resize = M.render.popup(
		nil,
		"Search: <Tab>/<Shift+Tab>|navigate <Esc>|picker <C-c>|exit "
			.. "<Enter>/<C-f>/<C-x>/<C-v>/<C-t>/<C-g>|open/float/split/vsplit/tab/toggle",
		function(w, h)
			return w - left - right, 1, h - bottom, left
		end,
		{ gid = gid },
		{ border = M.config.style_chat_finder_border or "single" }
	)
	-- set initial content of command buffer
	vim.api.nvim_buf_set_lines(command_buf, 0, -1, false, { M.config.chat_finder_pattern })

	local hl_search_group = "GpExplorerSearch"
	vim.cmd("highlight default link " .. hl_search_group .. " Search ")
	local hl_cursorline_group = "GpExplorerCursorLine"
	vim.cmd("highlight default " .. hl_cursorline_group .. " gui=standout cterm=standout")

	local picker_pos_id = 0
	local picker_match_id = 0
	local preview_match_id = 0
	local regex = ""

	-- clean up augroup and popup buffers/windows
	local close = M.tasker.once(function()
		vim.api.nvim_del_augroup_by_id(gid)
		picker_close()
		preview_close()
		command_close()
		M._chat_finder_opened = false
	end)

	local resize = function()
		picker_resize()
		preview_resize()
		command_resize()
	end

	-- logic for updating picker and preview
	local picker_files = {}
	local preview_lines = {}

	local refresh = function()
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

		-- highlight grep results and current line
		if picker_pos_id ~= 0 then
			vim.fn.matchdelete(picker_pos_id, picker_win)
		end
		if picker_match_id ~= 0 then
			vim.fn.matchdelete(picker_match_id, picker_win)
		end
		if preview_match_id ~= 0 then
			vim.fn.matchdelete(preview_match_id, preview_win)
		end

		if regex == "" then
			picker_pos_id = 0
			picker_match_id = 0
			preview_match_id = 0
			return
		end

		picker_match_id = vim.fn.matchadd(hl_search_group, regex, 0, -1, { window = picker_win })
		preview_match_id = vim.fn.matchadd(hl_search_group, regex, 0, -1, { window = preview_win })
		picker_pos_id = vim.fn.matchaddpos(hl_cursorline_group, { { index } }, 0, -1, { window = picker_win })
	end

	local refresh_picker = function()
		-- get last line of command buffer
		local cmd = vim.api.nvim_buf_get_lines(command_buf, -2, -1, false)[1]

		M.tasker.grep_directory(nil, dir, cmd, function(results, re)
			if not vim.api.nvim_buf_is_valid(picker_buf) then
				return
			end

			picker_files = {}
			preview_lines = {}
			local picker_lines = {}
			for _, f in ipairs(results) do
				if f.line:len() > 0 then
					table.insert(picker_files, dir .. "/" .. f.file)
					local fline = string.format("%s:%s %s", f.file:sub(3, -11), f.lnum, f.line)
					table.insert(picker_lines, fline)
					table.insert(preview_lines, tonumber(f.lnum))
				end
			end

			vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, picker_lines)

			-- prepare regex for highlighting
			regex = re
			if regex ~= "" then
				-- case insensitive
				regex = "\\c" .. regex
			end

			refresh()
		end)
	end

	refresh_picker()
	vim.api.nvim_set_current_win(command_win)
	vim.api.nvim_command("startinsert!")

	-- resize on VimResized
	M.helpers.autocmd({ "VimResized" }, nil, resize, gid)

	-- moving cursor on picker window will update preview window
	M.helpers.autocmd({ "CursorMoved", "CursorMovedI" }, { picker_buf }, function()
		vim.api.nvim_command("stopinsert")
		refresh()
	end, gid)

	-- InsertEnter on picker or preview window will go to command window
	M.helpers.autocmd({ "InsertEnter" }, { picker_buf, preview_buf }, function()
		vim.api.nvim_set_current_win(command_win)
		vim.api.nvim_command("startinsert!")
	end, gid)

	-- InsertLeave on command window will go to picker window
	M.helpers.autocmd({ "InsertLeave" }, { command_buf }, function()
		vim.api.nvim_set_current_win(picker_win)
		vim.api.nvim_command("stopinsert")
	end, gid)

	-- when preview becomes active call some function
	M.helpers.autocmd({ "WinEnter" }, { preview_buf }, function()
		-- go to normal mode
		vim.api.nvim_command("stopinsert")
	end, gid)

	-- when command buffer is written, execute it
	M.helpers.autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT" }, { command_buf }, function()
		vim.api.nvim_win_set_cursor(picker_win, { 1, 0 })
		refresh_picker()
	end, gid)

	-- close on buffer delete
	M.helpers.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { picker_buf, preview_buf, command_buf }, close, gid)

	-- close by escape key on any window
	M.helpers.set_keymap({ picker_buf, preview_buf, command_buf }, "n", "<esc>", close)
	M.helpers.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n" }, "<C-c>", close)

	---@param target number
	---@param toggle boolean
	local open_chat = function(target, toggle)
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local file = picker_files[index]
		close()
		-- delay so explorer can close before opening file
		vim.defer_fn(function()
			if not file then
				return
			end
			M.open_buf(file, target, M._toggle_kind.chat, toggle)
		end, 200)
	end

	-- enter on picker window will open file
	M.helpers.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<cr>", open_chat)
	M.helpers.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<C-f>", function()
		open_chat(M.BufTarget.popup, false)
	end)
	M.helpers.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<C-x>", function()
		open_chat(M.BufTarget.split, false)
	end)
	M.helpers.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<C-v>", function()
		open_chat(M.BufTarget.vsplit, false)
	end)
	M.helpers.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<C-t>", function()
		open_chat(M.BufTarget.tabnew, false)
	end)
	M.helpers.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<C-g>", function()
		local target = M.resolve_buf_target(M.config.toggle_target)
		open_chat(target, true)
	end)

	-- tab in command window will cycle through lines in picker window
	M.helpers.set_keymap({ command_buf, picker_buf }, { "i", "n" }, "<tab>", function()
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local next_index = index + 1
		if next_index > #picker_files then
			next_index = 1
		end
		vim.api.nvim_win_set_cursor(picker_win, { next_index, 0 })
		refresh()
	end)

	-- shift-tab in command window will cycle through lines in picker window
	M.helpers.set_keymap({ command_buf, picker_buf }, { "i", "n" }, "<s-tab>", function()
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local next_index = index - 1
		if next_index < 1 then
			next_index = #picker_files
		end
		vim.api.nvim_win_set_cursor(picker_win, { next_index, 0 })
		refresh()
	end)

	-- dd on picker or preview window will delete file
	M.helpers.set_keymap({ picker_buf, preview_buf }, "n", "dd", function()
		local index = vim.api.nvim_win_get_cursor(picker_win)[1]
		local file = picker_files[index]

		-- delete without confirmation
		if not M.config.chat_confirm_delete then
			M.helpers.delete_file(file)
			refresh_picker()
			return
		end

		-- ask for confirmation
		vim.ui.input({ prompt = "Delete " .. file .. "? [y/N] " }, function(input)
			if input and input:lower() == "y" then
				M.helpers.delete_file(file)
				refresh_picker()
			end
		end)
	end)
end

--------------------
-- Prompt logic
--------------------

M.cmd.Agent = function(params)
	local agent_name = string.gsub(params.args, "^%s*(.-)%s*$", "%1")
	if agent_name == "" then
		M.logger.info(" Chat agent: " .. M._state.chat_agent .. "  |  Command agent: " .. M._state.command_agent)
		return
	end

	if not M.agents[agent_name] then
		M.logger.warning("Unknown agent: " .. agent_name)
		return
	end

	local buf = vim.api.nvim_get_current_buf()
	local file_name = vim.api.nvim_buf_get_name(buf)
	local is_chat = M.not_chat(buf, file_name) == nil
	if is_chat and M.agents[agent_name].chat then
		M._state.chat_agent = agent_name
		M.logger.info("Chat agent: " .. M._state.chat_agent)
	elseif is_chat then
		M.logger.warning(agent_name .. " is not a Chat agent")
	elseif M.agents[agent_name].command then
		M._state.command_agent = agent_name
		M.logger.info("Command agent: " .. M._state.command_agent)
	else
		M.logger.warning(agent_name .. " is not a Command agent")
	end

	M.refresh_state()
end

M.cmd.NextAgent = function()
	local buf = vim.api.nvim_get_current_buf()
	local file_name = vim.api.nvim_buf_get_name(buf)
	local is_chat = M.not_chat(buf, file_name) == nil
	local current_agent, agent_list

	if is_chat then
		current_agent = M._state.chat_agent
		agent_list = M._chat_agents
	else
		current_agent = M._state.command_agent
		agent_list = M._command_agents
	end

	local set_agent = function(agent_name)
		if is_chat then
			M._state.chat_agent = agent_name
			M.logger.info("Chat agent: " .. agent_name)
		else
			M._state.command_agent = agent_name
			M.logger.info("Command agent: " .. agent_name)
		end
		M.refresh_state()
	end

	for i, agent_name in ipairs(agent_list) do
		if agent_name == current_agent then
			set_agent(agent_list[i % #agent_list + 1])
			return
		end
	end
	set_agent(agent_list[1])
end

---@param name string | nil
---@return table | nil # { cmd_prefix, name, model, system_prompt, provider}
M.get_command_agent = function(name)
	name = name or M._state.command_agent
	if M.agents[name] == nil then
		M.logger.warning("Command Agent " .. name .. " not found, using " .. M._state.command_agent)
		name = M._state.command_agent
	end
	local template = M.config.command_prompt_prefix_template
	local cmd_prefix = M.render.template(template, { ["{{agent}}"] = name })
	local model = M.agents[name].model
	local system_prompt = M.agents[name].system_prompt
	local provider = M.agents[name].provider
	return {
		cmd_prefix = cmd_prefix,
		name = name,
		model = model,
		system_prompt = system_prompt,
		provider = provider,
	}
end

---@param name string | nil
---@return table # { cmd_prefix, name, model, system_prompt, provider }
M.get_chat_agent = function(name)
	name = name or M._state.chat_agent
	if M.agents[name] == nil then
		M.logger.warning("Chat Agent " .. name .. " not found, using " .. M._state.chat_agent)
		name = M._state.chat_agent
	end
	local template = M.config.command_prompt_prefix_template
	local cmd_prefix = M.render.template(template, { ["{{agent}}"] = name })
	local model = M.agents[name].model
	local system_prompt = M.agents[name].system_prompt
	local provider = M.agents[name].provider
	return {
		cmd_prefix = cmd_prefix,
		name = name,
		model = model,
		system_prompt = system_prompt,
		provider = provider,
	}
end

-- tries to find an .gp.md file in the root of current git repo
---@return string # returns instructions from the .gp.md file
M.repo_instructions = function()
	local git_root = M.helpers.find_git_root()

	if git_root == "" then
		return ""
	end

	local instruct_file = git_root .. "/.gp.md"

	if vim.fn.filereadable(instruct_file) == 0 then
		return ""
	end

	local lines = vim.fn.readfile(instruct_file)
	return table.concat(lines, "\n")
end

M.prep_context = function(buf, file_name)
	if not M.helpers.ends_with(file_name, ".gp.md") then
		return
	end

	if buf ~= vim.api.nvim_get_current_buf() then
		return
	end

	M.prep_md(buf)
end

M.cmd.Context = function(params)
	M._toggle_close(M._toggle_kind.popup)
	-- if there is no selection, try to close context toggle
	if params.range ~= 2 then
		if M._toggle_close(M._toggle_kind.context) then
			return
		end
	end

	local cbuf = vim.api.nvim_get_current_buf()

	local file_name = ""
	local buf = M.helpers.get_buffer(".gp.md")
	if buf then
		file_name = vim.api.nvim_buf_get_name(buf)
	else
		local git_root = M.helpers.find_git_root()
		if git_root == "" then
			M.logger.warning("Not in a git repository")
			return
		end
		file_name = git_root .. "/.gp.md"
	end

	if vim.fn.filereadable(file_name) ~= 1 then
		vim.fn.writefile({ "Additional context is provided below.", "" }, file_name)
	end

	params.args = params.args or ""
	if params.args == "" then
		params.args = M.config.toggle_target
	end
	local target = M.resolve_buf_target(params)
	buf = M.open_buf(file_name, target, M._toggle_kind.context, true)

	if params.range == 2 then
		M.render.append_selection(params, cbuf, buf, M.config.template_selection)
	end

	M.helpers.feedkeys("G", "xn")
end

local examplePromptHook = [[
UnitTests = function(gp, params)
    local template = "I have the following code from {{filename}}:\n\n"
        .. "```{{filetype}}\n{{selection}}\n```\n\n"
        .. "Please respond by writing table driven unit tests for the code above."
    local agent = gp.get_command_agent()
    gp.Prompt(params, gp.Target.vnew, agent, template)
end,
]]

---@param params table  # vim command parameters such as range, args, etc.
---@param target number | function | table  # where to put the response
---@param agent table  # obtained from get_command_agent or get_chat_agent
---@param template string  # template with model instructions
---@param prompt string | nil  # nil for non interactive commads
---@param whisper string | nil  # predefined input (e.g. obtained from Whisper)
---@param callback function | nil  # callback after completing the prompt
M.Prompt = function(params, target, agent, template, prompt, whisper, callback)
	if not agent or not type(agent) == "table" or not agent.provider then
		M.logger.warning(
			"The `gp.Prompt` method signature has changed.\n"
				.. "Please update your hook functions as demonstrated in the example below:\n\n"
				.. examplePromptHook
				.. "\nFor more information, refer to the 'Extend Functionality' section in the documentation."
		)
		return
	end

	-- enew, new, vnew, tabnew should be resolved into table
	if type(target) == "function" then
		target = target()
	end

	target = target or M.Target.enew()

	-- get current buffer
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	if M.tasker.is_busy(buf) then
		return
	end

	-- defaults to normal mode
	local selection = nil
	local prefix = ""
	local start_line = vim.api.nvim_win_get_cursor(0)[1]
	local end_line = start_line

	-- handle range
	if params.range == 2 then
		start_line = params.line1
		end_line = params.line2
		local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)

		local min_indent = nil
		local use_tabs = false
		-- measure minimal common indentation for lines with content
		for i, line in ipairs(lines) do
			lines[i] = line
			-- skip whitespace only lines
			if not line:match("^%s*$") then
				local indent = line:match("^%s*")
				-- contains tabs
				if indent:match("\t") then
					use_tabs = true
				end
				if min_indent == nil or #indent < min_indent then
					min_indent = #indent
				end
			end
		end
		if min_indent == nil then
			min_indent = 0
		end
		prefix = string.rep(use_tabs and "\t" or " ", min_indent)

		for i, line in ipairs(lines) do
			lines[i] = line:sub(min_indent + 1)
		end

		selection = table.concat(lines, "\n")

		if selection == "" then
			M.logger.warning("Please select some text to rewrite")
			return
		end
	end

	M._selection_first_line = start_line
	M._selection_last_line = end_line

	local cb = function(command)
		-- dummy handler
		local handler = function() end
		-- default on_exit strips trailing backticks if response was markdown snippet
		local on_exit = function(qid)
			local qt = M.tasker.get_query(qid)
			if not qt then
				return
			end
			-- if buf is not valid, return
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end

			local flc, llc
			local fl = qt.first_line
			local ll = qt.last_line
			-- remove empty lines from the start and end of the response
			while true do
				-- get content of first_line and last_line
				flc = vim.api.nvim_buf_get_lines(buf, fl, fl + 1, false)[1]
				llc = vim.api.nvim_buf_get_lines(buf, ll, ll + 1, false)[1]

				if not flc or not llc then
					break
				end

				local flm = flc:match("%S")
				local llm = llc:match("%S")

				-- break loop if both lines contain non-whitespace characters
				if flm and llm then
					break
				end

				-- break loop lines are equal
				if fl >= ll then
					break
				end

				if not flm then
					M.helpers.undojoin(buf)
					vim.api.nvim_buf_set_lines(buf, fl, fl + 1, false, {})
				else
					M.helpers.undojoin(buf)
					vim.api.nvim_buf_set_lines(buf, ll, ll + 1, false, {})
				end
				ll = ll - 1
			end

			-- if fl and ll starts with triple backticks, remove these lines
			if flc and llc and flc:match("^%s*```") and llc:match("^%s*```") then
				-- remove first line with undojoin
				M.helpers.undojoin(buf)
				vim.api.nvim_buf_set_lines(buf, fl, fl + 1, false, {})
				-- remove last line
				M.helpers.undojoin(buf)
				vim.api.nvim_buf_set_lines(buf, ll - 1, ll, false, {})
				ll = ll - 2
			end
			qt.first_line = fl
			qt.last_line = ll

			-- option to not select response automatically
			if not M.config.command_auto_select_response then
				return
			end

			-- don't select popup response
			if target == M.Target.popup then
				return
			end

			-- default works for rewrite and enew
			local start = fl
			local finish = ll

			if target == M.Target.append then
				start = M._selection_first_line - 1
			end

			if target == M.Target.prepend then
				finish = M._selection_last_line + ll - fl
			end

			-- select from first_line to last_line
			vim.api.nvim_win_set_cursor(0, { start + 1, 0 })
			vim.api.nvim_command("normal! V")
			vim.api.nvim_win_set_cursor(0, { finish + 1, 0 })
		end

		-- prepare messages
		local messages = {}
		local filetype = M.helpers.get_filetype(buf)
		local filename = vim.api.nvim_buf_get_name(buf)

		local sys_prompt = M.render.prompt_template(agent.system_prompt, command, selection, filetype, filename)
		sys_prompt = sys_prompt or ""
		table.insert(messages, { role = "system", content = sys_prompt })

		local repo_instructions = M.repo_instructions()
		if repo_instructions ~= "" then
			table.insert(messages, { role = "system", content = repo_instructions })
		end

		local user_prompt = M.render.prompt_template(template, command, selection, filetype, filename)
		table.insert(messages, { role = "user", content = user_prompt })

		-- cancel possible visual mode before calling the model
		M.helpers.feedkeys("<esc>", "xn")

		local cursor = true
		if not M.config.command_auto_select_response then
			cursor = false
		end

		-- mode specific logic
		if target == M.Target.rewrite then
			-- delete selection
			vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line - 1, false, {})
			-- prepare handler
			handler = M.create_handler(buf, win, start_line - 1, true, prefix, cursor)
		elseif target == M.Target.append then
			-- move cursor to the end of the selection
			vim.api.nvim_win_set_cursor(0, { end_line, 0 })
			-- put newline after selection
			vim.api.nvim_put({ "" }, "l", true, true)
			-- prepare handler
			handler = M.create_handler(buf, win, end_line, true, prefix, cursor)
		elseif target == M.Target.prepend then
			-- move cursor to the start of the selection
			vim.api.nvim_win_set_cursor(0, { start_line, 0 })
			-- put newline before selection
			vim.api.nvim_put({ "" }, "l", false, true)
			-- prepare handler
			handler = M.create_handler(buf, win, start_line - 1, true, prefix, cursor)
		elseif target == M.Target.popup then
			M._toggle_close(M._toggle_kind.popup)
			-- create a new buffer
			local popup_close = nil
			buf, win, popup_close, _ = M.render.popup(nil, M._Name .. " popup (close with <esc>/<C-c>)", function(w, h)
				local top = M.config.style_popup_margin_top or 2
				local bottom = M.config.style_popup_margin_bottom or 8
				local left = M.config.style_popup_margin_left or 1
				local right = M.config.style_popup_margin_right or 1
				local max_width = M.config.style_popup_max_width or 160
				local ww = math.min(w - (left + right), max_width)
				local wh = h - (top + bottom)
				return ww, wh, top, (w - ww) / 2
			end, { on_leave = true, escape = true }, { border = M.config.style_popup_border or "single" })
			-- set the created buffer as the current buffer
			vim.api.nvim_set_current_buf(buf)
			-- set the filetype to markdown
			vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
			-- better text wrapping
			vim.api.nvim_command("setlocal wrap linebreak")
			-- prepare handler
			handler = M.create_handler(buf, win, 0, false, "", false)
			M._toggle_add(M._toggle_kind.popup, { win = win, buf = buf, close = popup_close })
		elseif type(target) == "table" then
			if target.type == M.Target.new().type then
				vim.cmd("split")
				win = vim.api.nvim_get_current_win()
			elseif target.type == M.Target.vnew().type then
				vim.cmd("vsplit")
				win = vim.api.nvim_get_current_win()
			elseif target.type == M.Target.tabnew().type then
				vim.cmd("tabnew")
				win = vim.api.nvim_get_current_win()
			end

			buf = vim.api.nvim_create_buf(true, true)
			vim.api.nvim_set_current_buf(buf)

			local group = M.helpers.create_augroup("GpScratchSave" .. M.helpers.uuid(), { clear = true })
			vim.api.nvim_create_autocmd({ "BufWritePre" }, {
				buffer = buf,
				group = group,
				callback = function(ctx)
					vim.api.nvim_set_option_value("buftype", "", { buf = ctx.buf })
					vim.api.nvim_buf_set_name(ctx.buf, ctx.file)
					vim.api.nvim_command("w!")
					vim.api.nvim_del_augroup_by_id(ctx.group)
				end,
			})

			local ft = target.filetype or filetype
			vim.api.nvim_set_option_value("filetype", ft, { buf = buf })

			handler = M.create_handler(buf, win, 0, false, "", cursor)
		end

		-- call the model and write the response
		M.query(
			buf,
			agent.provider,
			M.prepare_payload(messages, agent.model, agent.provider),
			handler,
			vim.schedule_wrap(function(qid)
				on_exit(qid)
				vim.cmd("doautocmd User GpDone")
			end),
			callback
		)
	end

	vim.schedule(function()
		local args = params.args or ""
		if args:match("%S") then
			cb(args)
			return
		end

		-- if prompt is not provided, run the command directly
		if not prompt or prompt == "" then
			cb(nil)
			return
		end

		-- if prompt is provided, ask the user to enter the command
		vim.ui.input({ prompt = prompt, default = whisper }, function(input)
			if not input or input == "" then
				return
			end
			cb(input)
		end)
	end)
end

---@param callback function # callback function(text)
M.Whisper = function(language, callback)
	-- make sure sox is installed
	if vim.fn.executable("sox") == 0 then
		M.logger.error("sox is not installed")
		return
	end

	local bearer = M.vault.get("openai_api_key")
	if not bearer then
		M.logger.error("OpenAI API key not found")
		return
	end

	local rec_file = M.config.whisper_dir .. "/rec.wav"
	local rec_options = {
		sox = {
			cmd = "sox",
			opts = {
				"-c",
				"1",
				"--buffer",
				"32",
				"-d",
				"rec.wav",
				"trim",
				"0",
				"3600",
			},
			exit_code = 0,
		},
		arecord = {
			cmd = "arecord",
			opts = {
				"-c",
				"1",
				"-f",
				"S16_LE",
				"-r",
				"48000",
				"-d",
				3600,
				"rec.wav",
			},
			exit_code = 1,
		},
		ffmpeg = {
			cmd = "ffmpeg",
			opts = {
				"-y",
				"-f",
				"avfoundation",
				"-i",
				":0",
				"-t",
				"3600",
				"rec.wav",
			},
			exit_code = 255,
		},
	}

	local gid = M.helpers.create_augroup("GpWhisper", { clear = true })

	-- create popup
	local buf, _, close_popup, _ = M.render.popup(
		nil,
		M._Name .. " Whisper",
		function(w, h)
			return 60, 12, (h - 12) * 0.4, (w - 60) * 0.5
		end,
		{ gid = gid, on_leave = false, escape = false, persist = false },
		{ border = M.config.style_popup_border or "single" }
	)

	-- animated instructions in the popup
	local counter = 0
	local timer = uv.new_timer()
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
					"    Cancel the recording with <esc>/<C-c> or :GpStop.",
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

	local close = M.tasker.once(function()
		if timer then
			timer:stop()
			timer:close()
		end
		close_popup()
		vim.api.nvim_del_augroup_by_id(gid)
		M.cmd.Stop()
	end)

	M.helpers.set_keymap({ buf }, { "n", "i", "v" }, "<esc>", function()
		M.cmd.Stop()
	end)

	M.helpers.set_keymap({ buf }, { "n", "i", "v" }, "<C-c>", function()
		M.cmd.Stop()
	end)

	local continue = false
	M.helpers.set_keymap({ buf }, { "n", "i", "v" }, "<cr>", function()
		continue = true
		vim.defer_fn(function()
			M.cmd.Stop()
		end, 300)
	end)

	-- cleanup on buffer exit
	M.helpers.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { buf }, close, gid)

	local curl_params = M.config.curl_params or {}
	local curl = "curl" .. " " .. table.concat(curl_params, " ")

	-- transcribe the recording
	local transcribe = function()
		local cmd = "cd "
			.. M.config.whisper_dir
			.. " && "
			.. "export LC_NUMERIC='C' && "
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
			.. curl
			.. " --max-time 20 "
			.. M.config.whisper_api_endpoint
			.. ' -s -H "Authorization: Bearer '
			.. bearer
			.. '" -H "Content-Type: multipart/form-data" '
			.. '-F model="whisper-1" -F language="'
			.. language
			.. '" -F file="@final.mp3" '
			.. '-F response_format="json"'

		M.tasker.run(nil, "bash", { "-c", cmd }, function(code, signal, stdout, _)
			if code ~= 0 then
				M.logger.error(string.format("Whisper query exited: %d, %d", code, signal))
				return
			end

			if not stdout or stdout == "" or #stdout < 11 then
				M.logger.error("Whisper query, no stdout: " .. vim.inspect(stdout))
				return
			end
			local text = vim.json.decode(stdout).text
			if not text then
				M.logger.error("Whisper query, no text: " .. vim.inspect(stdout))
				return
			end

			text = table.concat(vim.split(text, "\n"), " ")
			text = text:gsub("%s+$", "")

			if callback and stdout then
				callback(text)
			end
		end)
	end

	local cmd = {}

	local rec_cmd = M.config.whisper_rec_cmd
	-- if rec_cmd not set explicitly, try to autodetect
	if not rec_cmd then
		rec_cmd = "sox"
		if vim.fn.executable("ffmpeg") == 1 then
			local devices = vim.fn.system("ffmpeg -devices -v quiet | grep -i avfoundation | wc -l")
			devices = string.gsub(devices, "^%s*(.-)%s*$", "%1")
			if devices == "1" then
				rec_cmd = "ffmpeg"
			end
		end
		if vim.fn.executable("arecord") == 1 then
			rec_cmd = "arecord"
		end
	end

	if type(rec_cmd) == "table" and rec_cmd[1] and rec_options[rec_cmd[1]] then
		rec_cmd = vim.deepcopy(rec_cmd)
		cmd.cmd = table.remove(rec_cmd, 1)
		cmd.exit_code = rec_options[cmd.cmd].exit_code
		cmd.opts = rec_cmd
	elseif type(rec_cmd) == "string" and rec_options[rec_cmd] then
		cmd = rec_options[rec_cmd]
	else
		M.logger.error(string.format("Whisper got invalid recording command: %s", rec_cmd))
		close()
		return
	end
	for i, v in ipairs(cmd.opts) do
		if v == "rec.wav" then
			cmd.opts[i] = rec_file
		end
	end

	M.tasker.run(nil, cmd.cmd, cmd.opts, function(code, signal, stdout, stderr)
		close()

		if code and code ~= cmd.exit_code then
			M.logger.error(
				cmd.cmd
					.. " exited with code and signal:\ncode: "
					.. code
					.. ", signal: "
					.. signal
					.. "\nstdout: "
					.. vim.inspect(stdout)
					.. "\nstderr: "
					.. vim.inspect(stderr)
			)
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

	if params.range == 2 then
		start_line = params.line1
		end_line = params.line2
	end

	local args = vim.split(params.args, " ")

	local language = config.whisper_language
	if args[1] ~= "" then
		language = args[1]
	end

	M.Whisper(language, function(text)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		if text then
			vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line, false, { text })
		end
	end)
end

return M

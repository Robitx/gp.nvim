-- Gp (GPT prompt) lua plugin for Neovim
-- https://github.com/Robitx/gp.nvim/

--------------------------------------------------------------------------------
-- Module structure
--------------------------------------------------------------------------------
local config = require("gp.config")

local M = {
	_Name = "Gp", -- plugin name
	_state = {}, -- table of state variables
	agents = {}, -- table of agents
	cmd = {}, -- default command functions
	config = {}, -- config variables
	hooks = {}, -- user defined command functions
	defaults = require("gp.defaults"), -- some useful defaults
	deprecator = require("gp.deprecator"), -- handle deprecated options
	dispatcher = require("gp.dispatcher"), -- handle communication with LLM providers
	helpers = require("gp.helper"), -- helper functions
	imager = require("gp.imager"), -- image generation module
	logger = require("gp.logger"), -- logger module
	render = require("gp.render"), -- render module
	spinner = require("gp.spinner"), -- spinner module
	tasker = require("gp.tasker"), -- tasker module
	vault = require("gp.vault"), -- handles secrets
	whisper = require("gp.whisper"), -- whisper module
}

--------------------------------------------------------------------------------
-- Module helper functions and variables
--------------------------------------------------------------------------------

local agent_completion = function()
	local buf = vim.api.nvim_get_current_buf()
	local file_name = vim.api.nvim_buf_get_name(buf)
	if M.not_chat(buf, file_name) == nil then
		return M._chat_agents
	end
	return M._command_agents
end

-- setup function
M._setup_called = false
---@param opts GpConfig? # table with options
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

	local curl_params = opts.curl_params or M.config.curl_params
	local cmd_prefix = opts.cmd_prefix or M.config.cmd_prefix
	local state_dir = opts.state_dir or M.config.state_dir
	local openai_api_key = opts.openai_api_key or M.config.openai_api_key

	M.logger.setup(opts.log_file or M.config.log_file, opts.log_sensitive)

	M.vault.setup({ state_dir = state_dir, curl_params = curl_params })

	M.vault.add_secret("openai_api_key", openai_api_key)
	M.config.openai_api_key = nil
	opts.openai_api_key = nil

	M.dispatcher.setup({ providers = opts.providers, curl_params = curl_params })
	M.config.providers = nil
	opts.providers = nil

	local image_opts = opts.image or {}
	image_opts.state_dir = state_dir
	image_opts.cmd_prefix = cmd_prefix
	image_opts.secret = image_opts.secret or openai_api_key
	M.imager.setup(image_opts)
	M.config.image = nil
	opts.image = nil

	local whisper_opts = opts.whisper or {}
	whisper_opts.style_popup_border = opts.style_popup_border or M.config.style_popup_border
	whisper_opts.curl_params = curl_params
	whisper_opts.cmd_prefix = cmd_prefix
	M.whisper.setup(whisper_opts)
	M.config.whisper = nil
	opts.whisper = nil

	-- merge nested tables
	local mergeTables = { "hooks", "agents" }
	for _, tbl in ipairs(mergeTables) do
		M[tbl] = M[tbl] or {}
		---@diagnostic disable-next-line
		for k, v in pairs(M.config[tbl]) do
			if tbl == "hooks" then
				M[tbl][k] = v
			elseif tbl == "agents" then
				---@diagnostic disable-next-line
				M[tbl][v.name] = v
			end
		end
		M.config[tbl] = nil

		opts[tbl] = opts[tbl] or {}
		for k, v in pairs(opts[tbl]) do
			if tbl == "hooks" then
				M[tbl][k] = v
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

	-- prepare agent completions
	M._chat_agents = {}
	M._command_agents = {}
	for name, agent in pairs(M.agents) do
		M.agents[name].provider = M.agents[name].provider or "openai"

		if M.dispatcher.providers[M.agents[name].provider] then
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

	if M.config.default_command_agent then
		M.refresh_state({ command_agent = M.config.default_command_agent })
	end

	if M.config.default_chat_agent then
		M.refresh_state({ chat_agent = M.config.default_chat_agent })
	end

	-- register user commands
	for hook, _ in pairs(M.hooks) do
		M.helpers.create_user_command(M.config.cmd_prefix .. hook, function(params)
			if M.hooks[hook] ~= nil then
				M.refresh_state()
				M.logger.debug("running hook: " .. hook)
				return M.hooks[hook](M, params)
			end
			M.logger.error("The hook '" .. hook .. "' does not exist.")
		end)
	end

	local completions = {
		ChatNew = { "popup", "split", "vsplit", "tabnew" },
		ChatPaste = { "popup", "split", "vsplit", "tabnew" },
		ChatToggle = { "popup", "split", "vsplit", "tabnew" },
		ChatLast = { "popup", "split", "vsplit", "tabnew" },
		Context = { "popup", "split", "vsplit", "tabnew" },
		Agent = agent_completion,
	}

	-- register default commands
	for cmd, _ in pairs(M.cmd) do
		if M.hooks[cmd] == nil then
			M.helpers.create_user_command(M.config.cmd_prefix .. cmd, function(params)
				M.logger.debug("running command: " .. cmd)
				M.refresh_state()
				M.cmd[cmd](params)
			end, completions[cmd])
		end
	end

	M.buf_handler()

	if vim.fn.executable("curl") == 0 then
		M.logger.error("curl is not installed, run :checkhealth gp")
	end

	M.logger.debug("setup finished")
end

---@param update table | nil # table with options
M.refresh_state = function(update)
	local state_file = M.config.state_dir .. "/state.json"
	update = update or {}

	local old_state = vim.deepcopy(M._state)

	local disk_state = {}
	if vim.fn.filereadable(state_file) ~= 0 then
		disk_state = M.helpers.file_to_table(state_file) or {}
	end

	if not disk_state.updated then
		local last = M.config.chat_dir .. "/last.md"
		if vim.fn.filereadable(last) == 1 then
			os.remove(last)
		end
	end

	if not M._state.updated or (disk_state.updated and M._state.updated < disk_state.updated) then
		M._state = vim.deepcopy(disk_state)
	end
	M._state.updated = os.time()

	for k, v in pairs(update) do
		M._state[k] = v
	end

	if not M._state.chat_agent or not M.agents[M._state.chat_agent] then
		M._state.chat_agent = M._chat_agents[1]
	end

	if not M._state.command_agent or not M.agents[M._state.command_agent] then
		M._state.command_agent = M._command_agents[1]
	end

	if M._state.last_chat and vim.fn.filereadable(M._state.last_chat) == 0 then
		M._state.last_chat = nil
	end

	for k, _ in pairs(M._state) do
		if M._state[k] ~= old_state[k] or M._state[k] ~= disk_state[k] then
			M.logger.debug(
				string.format(
					"state[%s]: disk=%s old=%s new=%s",
					k,
					vim.inspect(disk_state[k]),
					vim.inspect(old_state[k]),
					vim.inspect(M._state[k])
				)
			)
		end
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

		local cmd = function(params, whisper)
			local agent = M.get_command_agent()
			-- popup is like ephemeral one off chat
			if target == M.Target.popup then
				agent = M.get_chat_agent()
			end

			-- template is chosen dynamically based on mode in which the command is called
			local template = M.config.template_command
			if params.range > 0 then
				template = M.config.template_selection
			end
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
			if agent then
				M.Prompt(params, target, agent, template, agent.cmd_prefix, whisper)
			end
		end

		M.cmd[command] = function(params)
			cmd(params)
		end

		if not M.whisper.disabled then
			M.cmd["Whisper" .. command] = function(params)
				M.whisper.Whisper(function(text)
					vim.schedule(function()
						cmd(params, text)
					end)
				end)
			end
		end
	end
end

-- stop receiving gpt responses for all processes and clean the handles
---@param signal number | nil # signal to send to the process
M.cmd.Stop = function(signal)
	M.tasker.stop(signal)
end

--------------------------------------------------------------------------------
-- Chat logic
--------------------------------------------------------------------------------

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

M._prepared_bufs = {}
M.prep_chat = function(buf, file_name)
	if M.not_chat(buf, file_name) then
		return
	end

	if buf ~= vim.api.nvim_get_current_buf() then
		return
	end

	M.refresh_state({ last_chat = file_name })
	if M._prepared_bufs[buf] then
		M.logger.debug("buffer already prepared: " .. buf)
		return
	end
	M._prepared_bufs[buf] = true

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
---@param kind number | nil # nil or a toggle kind, must be toggle kind when toggle is true
---@param toggle boolean # whether to toggle
---@return number # buffer number
M.open_buf = function(file_name, target, kind, toggle)
	target = target or M.BufTarget.current

	-- close previous popup if it exists
	M._toggle_close(M._toggle_kind.popup)

	if toggle then
		---@cast kind number
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
			zindex = M.config.zindex,
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

	local filename = M.config.chat_dir .. "/" .. M.logger.now() .. ".md"

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

---@param params table
---@param system_prompt string | nil
---@param agent table | nil # obtained from get_command_agent or get_chat_agent
---@return number # buffer number
M.cmd.ChatNew = function(params, system_prompt, agent)
	if M.deprecator.has_old_chat_signature(agent) then
		return -1
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
		local last = M._state.last_chat
		if last and vim.fn.filereadable(last) == 1 then
			last = vim.fn.resolve(last)
			M.open_buf(last, M.resolve_buf_target(params), M._toggle_kind.chat, true)
			return
		end
	end

	M.new_chat(params, true, system_prompt, agent)
end

---@param params table
---@return number | nil # buffer number or nil if no last chat
M.cmd.ChatLast = function(params)
	local toggle = false
	-- if the range is 2, we want to create a new chat file with the selection
	if M._toggle_close(M._toggle_kind.chat) then
		params.args = params.args or ""
		if params.args == "" then
			params.args = M.config.toggle_target
		end
		toggle = true
	end
	local last = M._state.last_chat
	if last and vim.fn.filereadable(last) == 1 then
		last = vim.fn.resolve(last)
		-- get current buffer, for pasting selection if necessary
		local cbuf = vim.api.nvim_get_current_buf()
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
		buf = win_found and buf or M.open_buf(last, M.resolve_buf_target(params), toggle and M._toggle_kind.chat or nil, toggle)
		-- if there is a selection, paste it
		if params.range == 2 then
			M.render.append_selection(params, cbuf, buf, M.config.template_selection)
			M.helpers.feedkeys("G", "xn")
		end
		return buf
	end
	return nil
end

M.cmd.ChatPaste = function(params)
	-- if there is no selection, do nothing
	if params.range ~= 2 then
		M.logger.warning("Please select some text to paste into the chat.")
		return
	end

	-- get current buffer
	local cbuf = vim.api.nvim_get_current_buf()

	-- make new chat if last doesn't exist
	local last = M._state.last_chat
	if not last or vim.fn.filereadable(last) ~= 1 then
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
	M.dispatcher.query(
		buf,
		headers.provider or agent.provider,
		M.dispatcher.prepare_payload(messages, headers.model or agent.model, headers.provider or agent.provider),
		M.dispatcher.create_handler(buf, win, M.helpers.last_content_line(buf), true, "", not M.config.chat_free_cursor),
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
				local topic_handler = M.dispatcher.create_handler(topic_buf, nil, 0, false, "", false)

				-- call the model (remove thinking_budget for Anthropic topic generation)
				local topic_model = headers.model or agent.model
				local provider = headers.provider or agent.provider
				if provider == "anthropic" and topic_model.thinking_budget then
					topic_model = vim.deepcopy(topic_model)
					topic_model.thinking_budget = nil
				end
				M.dispatcher.query(
					nil,
					provider,
					M.dispatcher.prepare_payload(messages, topic_model, provider),
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
	local delete_shortcut = M.config.chat_finder_mappings.delete or M.config.chat_shortcut_delete

	-- prepare unique group name and register augroup
	local gid = M.helpers.create_augroup("GpChatFinder", { clear = true })

	-- prepare three popup buffers and windows
	local style = { border = M.config.style_chat_finder_border or "single", zindex = M.config.zindex }
	local ratio = M.config.style_chat_finder_preview_ratio or 0.5
	local top = M.config.style_chat_finder_margin_top or 2
	local bottom = M.config.style_chat_finder_margin_bottom or 8
	local left = M.config.style_chat_finder_margin_left or 1
	local right = M.config.style_chat_finder_margin_right or 2
	local picker_buf, picker_win, picker_close, picker_resize = M.render.popup(
		nil,
		"Picker: j/k <Esc>|exit <Enter>|open " .. delete_shortcut.shortcut .. "|del i|srch",
		function(w, h)
			local wh = h - top - bottom - 2
			local ww = w - left - right - 2
			return math.floor(ww * (1 - ratio)), wh, top, left
		end,
		{ gid = gid },
		style
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
		style
	)

	vim.api.nvim_set_option_value("filetype", "markdown", { buf = preview_buf })

	local command_buf, command_win, command_close, command_resize = M.render.popup(
		nil,
		"Search: <Tab>/<Shift+Tab>|navigate <Esc>|picker <C-c>|exit "
			.. "<Enter>/<C-f>/<C-x>/<C-v>/<C-t>/<C-g>t|open/float/split/vsplit/tab/toggle",
		function(w, h)
			return w - left - right, 1, h - bottom, left
		end,
		{ gid = gid },
		style
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
	M.helpers.set_keymap({ picker_buf, preview_buf, command_buf }, { "i", "n", "v" }, "<C-g>t", function()
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
	M.helpers.set_keymap(
		{ command_buf, picker_buf, preview_buf },
		delete_shortcut.modes,
		delete_shortcut.shortcut,
		function()
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
		end
	)
end

--------------------------------------------------------------------------------
-- Prompt logic
--------------------------------------------------------------------------------

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
		M.refresh_state({ chat_agent = agent_name })
		M.logger.info("Chat agent: " .. M._state.chat_agent)
	elseif M.agents[agent_name].command then
		M.refresh_state({ command_agent = agent_name })
		M.logger.info("Command agent: " .. M._state.command_agent)
	else
		M.logger.warning(agent_name .. " is not a valid agent for current buffer")
		M.refresh_state()
	end
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
			M.refresh_state({ chat_agent = agent_name })
			M.logger.info("Chat agent: " .. M._state.chat_agent)
		else
			M.refresh_state({ command_agent = agent_name })
			M.logger.info("Command agent: " .. M._state.command_agent)
		end
	end

	for i, agent_name in ipairs(agent_list) do
		if agent_name == current_agent then
			set_agent(agent_list[i % #agent_list + 1])
			return
		end
	end
	set_agent(agent_list[1])
end

M.cmd.SelectAgent = function()
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

	if #agent_list == 0 then
		M.logger.warning("No agents available")
		return
	end

	-- Create options with current agent highlighted
	local options = {}
	for _, agent_name in ipairs(agent_list) do
		if agent_name == current_agent then
			table.insert(options, agent_name .. " (current)")
		else
			table.insert(options, agent_name)
		end
	end

	vim.ui.select(options, {
		prompt = is_chat and "Select chat agent:" or "Select command agent:",
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if not choice then
			return
		end

		-- Remove " (current)" suffix if present
		local agent_name = choice:gsub(" %(current%)$", "")

		if is_chat then
			M.refresh_state({ chat_agent = agent_name })
			M.logger.info("Chat agent: " .. M._state.chat_agent)
		else
			M.refresh_state({ command_agent = agent_name })
			M.logger.info("Command agent: " .. M._state.command_agent)
		end
	end)
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
	M.logger.debug("getting command agent: " .. name)
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
	M.logger.debug("getting chat agent: " .. name)
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
	if M._prepared_bufs[buf] then
		M.logger.debug("buffer already prepared: " .. buf)
		return
	end
	M._prepared_bufs[buf] = true

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

---@param params table  # vim command parameters such as range, args, etc.
---@param target number | function | table  # where to put the response
---@param agent table  # obtained from get_command_agent or get_chat_agent
---@param template string  # template with model instructions
---@param prompt string | nil  # nil for non interactive commads
---@param whisper string | nil  # predefined input (e.g. obtained from Whisper)
---@param callback function | nil  # callback after completing the prompt
M.Prompt = function(params, target, agent, template, prompt, whisper, callback)
	if M.deprecator.has_old_prompt_signature(agent) then
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

	local start_line = params.line1
	local end_line = params.line2
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
	local prefix = string.rep(use_tabs and "\t" or " ", min_indent)

	for i, line in ipairs(lines) do
		lines[i] = line:sub(min_indent + 1)
	end

	local selection = table.concat(lines, "\n")

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
			while fl < ll do
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
			if fl < ll and flc and llc and flc:match("^%s*```") and llc:match("^%s*```") then
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
			-- validate cursor positions are within buffer bounds
			local buf_line_count = vim.api.nvim_buf_line_count(buf)
			local start_pos = math.min(math.max(start + 1, 1), buf_line_count)
			local finish_pos = math.min(math.max(finish + 1, 1), buf_line_count)
			
			vim.api.nvim_win_set_cursor(0, { start_pos, 0 })
			vim.api.nvim_command("normal! V")
			vim.api.nvim_win_set_cursor(0, { finish_pos, 0 })
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
			if not (start_line - 1 == 0 and end_line - 1 == 0 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "") then
			  vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line - 1, false, {})
			end
			-- prepare handler
			handler = M.dispatcher.create_handler(buf, win, start_line - 1, true, prefix, cursor)
		elseif target == M.Target.append then
			-- move cursor to the end of the selection
			vim.api.nvim_win_set_cursor(0, { end_line, 0 })
			-- put newline after selection
			vim.api.nvim_put({ "" }, "l", true, true)
			-- prepare handler
			handler = M.dispatcher.create_handler(buf, win, end_line, true, prefix, cursor)
		elseif target == M.Target.prepend then
			-- move cursor to the start of the selection
			vim.api.nvim_win_set_cursor(0, { start_line, 0 })
			-- put newline before selection
			vim.api.nvim_put({ "" }, "l", false, true)
			-- prepare handler
			handler = M.dispatcher.create_handler(buf, win, start_line - 1, true, prefix, cursor)
		elseif target == M.Target.popup then
			M._toggle_close(M._toggle_kind.popup)
			-- create a new buffer
			local popup_close = nil
			buf, win, popup_close, _ = M.render.popup(
				nil,
				M._Name .. " popup (close with <esc>/<C-c>)",
				function(w, h)
					local top = M.config.style_popup_margin_top or 2
					local bottom = M.config.style_popup_margin_bottom or 8
					local left = M.config.style_popup_margin_left or 1
					local right = M.config.style_popup_margin_right or 1
					local max_width = M.config.style_popup_max_width or 160
					local ww = math.min(w - (left + right), max_width)
					local wh = h - (top + bottom)
					return ww, wh, top, (w - ww) / 2
				end,
				{ on_leave = true, escape = true },
				{ border = M.config.style_popup_border or "single", zindex = M.config.zindex }
			)
			-- set the created buffer as the current buffer
			vim.api.nvim_set_current_buf(buf)
			-- set the filetype to markdown
			vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
			-- better text wrapping
			vim.api.nvim_command("setlocal wrap linebreak")
			-- prepare handler
			handler = M.dispatcher.create_handler(buf, win, 0, false, "", false)
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

			handler = M.dispatcher.create_handler(buf, win, 0, false, "", cursor)
		end

		-- call the model and write the response
		M.dispatcher.query(
			buf,
			agent.provider,
			M.dispatcher.prepare_payload(messages, agent.model, agent.provider),
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

return M

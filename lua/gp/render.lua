--------------------------------------------------------------------------------
-- Render module for logic related to visualization
--------------------------------------------------------------------------------

local logger = require("gp.logger")
local helpers = require("gp.helper")
local tasker = require("gp.tasker")

local M = {}

---@param template string # template string
---@param key string # key to replace
---@param value string | table | nil # value to replace key with (nil => "")
---@return string # returns rendered template with specified key replaced by value
M.template_replace = function(template, key, value)
	value = value or ""
	if type(value) == "table" then
		value = table.concat(value, "\n")
	end

	value = value:gsub("%%", "%%%%")
	template = template:gsub(key, value)
	template = template:gsub("%%%%", "%%")
	return template
end

---@param template string # template string
---@param key_value_pairs table # table with key value pairs
---@return string # returns rendered template with keys replaced by values from key_value_pairs
M.template = function(template, key_value_pairs)
	for key, value in pairs(key_value_pairs) do
		template = M.template_replace(template, key, value)
	end

	return template
end

---@param template string # template string
---@param command string | nil # command
---@param selection string | nil # selection
---@param filetype string | nil # filetype
---@param filename string | nil # filename
M.prompt_template = function(template, command, selection, filetype, filename)
	local git_root = helpers.find_git_root(filename)
	if git_root ~= "" then
		local git_root_plus_one = vim.fn.fnamemodify(git_root, ":h")
		if git_root_plus_one ~= "" then
			filename = filename or ""
			filename = filename:sub(#git_root_plus_one + 2)
		end
	end

	local key_value_pairs = {
		["{{command}}"] = command,
		["{{selection}}"] = selection,
		["{{filetype}}"] = filetype,
		["{{filename}}"] = filename,
	}
	return M.template(template, key_value_pairs)
end

---@param params table # table with command args
---@param origin_buf number # selection origin buffer
---@param target_buf number # selection target buffer
---@param template string # template to render
M.append_selection = function(params, origin_buf, target_buf, template)
	-- prepare selection
	local lines = vim.api.nvim_buf_get_lines(origin_buf, params.line1 - 1, params.line2, false)
	local selection = table.concat(lines, "\n")
	if selection ~= "" then
		local filetype = helpers.get_filetype(origin_buf)
		local fname = vim.api.nvim_buf_get_name(origin_buf)
		local rendered = M.prompt_template(template, "", selection, filetype, fname)
		if rendered then
			selection = rendered
		end
	end

	-- delete whitespace lines at the end of the file
	local last_content_line = helpers.last_content_line(target_buf)
	vim.api.nvim_buf_set_lines(target_buf, last_content_line, -1, false, {})

	-- insert selection lines
	lines = vim.split("\n" .. selection, "\n")
	vim.api.nvim_buf_set_lines(target_buf, last_content_line, -1, false, lines)
end

---@param buf number | nil # buffer number
---@param title string # title of the popup
---@param size_func function # size_func(editor_width, editor_height) -> width, height, row, col
---@param opts table # options - gid=nul, on_leave=false, persist=false
---@param style table # style - border="single"
---returns table with buffer, window, close function, resize function
M.popup = function(buf, title, size_func, opts, style)
	opts = opts or {}
	style = style or {}
	local border = style.border or "single"
	local zindex = style.zindex or 49

	-- create buffer
	buf = buf or vim.api.nvim_create_buf(false, not opts.persist)

	-- setting to the middle of the editor
	local options = {
		relative = "editor",
		-- dummy values gets resized later
		width = 10,
		height = 10,
		row = 10,
		col = 10,
		style = "minimal",
		border = border,
		title = title,
		title_pos = "center",
		zindex = zindex,
	}

	-- open the window and return the buffer
	local win = vim.api.nvim_open_win(buf, true, options)

	local resize = function()
		-- get editor dimensions
		local ew = vim.api.nvim_get_option_value("columns", {})
		local eh = vim.api.nvim_get_option_value("lines", {})

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
		if o.width <= 0 or o.height <= 0 then
			logger.error("Invalid popup size (window too small to render)")
			return
		end
		vim.api.nvim_win_set_config(win, o)
	end

	local pgid = opts.gid or helpers.create_augroup("GpPopup", { clear = true })

	-- cleanup on exit
	local close = tasker.once(function()
		vim.schedule(function()
			-- delete only internal augroups
			if not opts.gid then
				vim.api.nvim_del_augroup_by_id(pgid)
			end
			if win and vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
			if opts.persist then
				return
			end
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end)
	end)

	-- resize on vim resize
	helpers.autocmd("VimResized", { buf }, resize, pgid)

	-- cleanup on buffer exit
	helpers.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { buf }, close, pgid)

	-- optional cleanup on buffer leave
	if opts.on_leave then
		-- close when entering non-popup buffer
		helpers.autocmd({ "BufEnter" }, nil, function(event)
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
		helpers.set_keymap({ buf }, "n", "<esc>", close, title .. " close on escape")
		helpers.set_keymap({ buf }, { "n", "v", "i" }, "<C-c>", close, title .. " close on escape")
	end

	resize()
	return buf, win, close, resize
end

return M

local u = require("gp.utils")
local context = require("gp.context")
local db = require("gp.db")
local cmp = require("cmp")

-- Gets a buffer variable or returns the default
local function buf_get_var(buf, var_name, default)
	local status, result = pcall(vim.api.nvim_buf_get_var, buf, var_name)
	if status then
		return result
	else
		return default
	end
end

-- This function is only here make the get/set call pair look consistent
local function buf_set_var(buf, var_name, value)
	return vim.api.nvim_buf_set_var(buf, var_name, value)
end

---@class CompletionSource
---@field db Db
local source = {}

source.src_name = "gp_completion"

---@return CompletionSource
function source.new()
	print("source.new called")
	local db_inst = db.open()
	return setmetatable({ db = db_inst }, { __index = source })
end

function source.get_trigger_characters()
	return { "@", ":", "/" }
end

function source.setup_for_buffer(bufnr)
	print("in setup_for_buffer")
	local config = require("cmp").get_config()

	print("cmp.get_config() returned:")
	print(vim.inspect(config))

	print("cmp_config.set_buffer: " .. config.set_buffer)
	config.set_buffer({
		sources = {
			{ name = source.src_name },
		},
	}, bufnr)
end

function source.setup_autocmd_for_markdown()
	print("setting up autocmd...")
	vim.api.nvim_create_autocmd("BufEnter", {
		pattern = { "*.md", "markdown" },
		callback = function(arg)
			local attached_varname = "gp_source_attached"
			local attached = buf_get_var(arg.buf, attached_varname, false)
			if attached then
				return
			end

			print("attaching completion source for buffer: " .. arg.buf)
			local cmp = require("cmp")
			cmp.setup.buffer({
				sources = cmp.config.sources({
					{ name = source.src_name },
				}),
			})

			buf_set_var(arg.buf, attached_varname, true)
		end,
	})
end

function source.register_cmd_source()
	print("registering completion src")
	cmp.register_source(source.src_name, source.new())
end

local function extract_cmd(request)
	local target = request.context.cursor_before_line
	local start = target:match(".*()@")
	if start then
		return string.sub(target, start, request.offset)
	end
end

local function completion_items_for_path(path)
	-- The incoming path should either be
	-- - A relative path that references a directory
	-- - A relative path + partial filename as last component-
	-- We need a bit of logic to figure out which directory content to return

	--------------------------------------------------------------------
	-- Figure out the full path of the directory we're trying to list --
	--------------------------------------------------------------------
	-- Split the path into component parts
	local path_parts = u.path_split(path)
	if path[#path] ~= "/" then
		table.remove(path_parts)
	end

	-- Assuming the cwd is the project root directory...
	local cwd = vim.fn.getcwd()
	local target_dir = u.path_join(cwd, unpack(path_parts))

	--------------------------------------------
	-- List the items in the target directory --
	--------------------------------------------
	local handle = vim.loop.fs_scandir(target_dir)
	local files = {}

	if not handle then
		return files
	end

	while true do
		local name, type = vim.loop.fs_scandir_next(handle)
		if not name then
			break
		end

		local item_name, item_kind
		if type == "file" then
			item_kind = cmp.lsp.CompletionItemKind.File
			item_name = name
		elseif type == "directory" then
			item_kind = cmp.lsp.CompletionItemKind.Folder
			item_name = name .. "/"
		end

		table.insert(files, {
			label = item_name,
			kind = item_kind,
		})
	end

	return files
end

function source:completion_items_for_fn_name(partial_fn_name)
	local result = self.db:find_fn_def_by_name(partial_fn_name)

	local items = {}
	if not result then
		return items
	end

	for _, row in ipairs(result) do
		table.insert(items, {
			-- fields meant for nvim-cmp
			label = row.name,
			kind = cmp.lsp.CompletionItemKind.Function,
			labelDetails = {
				detail = row.file,
			},

			-- fields meant for internal use
			row = row,
			type = "@code",
		})
	end

	return items
end

function source.complete(self, request, callback)
	local input = string.sub(request.context.cursor_before_line, request.offset - 1)
	print("[comp] input: '" .. input .. "'")
	local cmd = extract_cmd(request)
	if not cmd then
		return
	end

	print("[comp] cmd: '" .. cmd .. "'")
	local cmd_parts = context.cmd_split(cmd)

	local items = {}
	local isIncomplete = true

	if cmd_parts[1]:match("@file") then
		-- What's the path we're trying to provide completion for?
		local path = cmd_parts[2]

		-- List the items in the specified directory
		items = completion_items_for_path(path)

		-- Say that the entire list has been provided
		-- cmp won't call us again to provide an updated list
		isIncomplete = false
	elseif cmd_parts[1]:match("@code") then
		local partial_fn_name = cmd_parts[2]
		if not partial_fn_name then
			partial_fn_name = ""
		end

		-- When the user confirms completion of an item, we alter the
		-- command to look like `@code:path/to/file:fn_name` to uniquely
		-- identify a function.
		--
		-- If the user were to hit backspace to delete through the text,
		-- don't process the input until it no longer looks like a path.
		if partial_fn_name:match("/") then
			return
		end

		items = self:completion_items_for_fn_name(partial_fn_name)
		isIncomplete = false
	elseif input:match("^@") then
		print("[complete] @ case")
		items = {
			{ label = "code", kind = require("cmp").lsp.CompletionItemKind.Keyword },
			{ label = "file", kind = require("cmp").lsp.CompletionItemKind.Keyword },
		}
		isIncomplete = false
	else
		print("[complete] default case")
		isIncomplete = false
	end

	local data = { items = items, isIncomplete = isIncomplete }
	callback(data)
	print("[complete] Callback called")
end

local function search_backwards(buf, pattern)
	-- Use nvim_buf_call to execute a Vim command in the buffer context
	return vim.api.nvim_buf_call(buf, function()
		-- Search backwards for the pattern
		local result = vim.fn.searchpos(pattern, "bn")

		if result[1] == 0 and result[2] == 0 then
			return nil
		end
		return result
	end)
end

function source:execute(item, callback)
	if item.type == "@code" then
		-- Locate where @command starts and ends
		local end_pos = vim.api.nvim_win_get_cursor(0)
		local start_pos = search_backwards(0, "@code")

		-- Replace it with a custom piece of text and move the cursor to the end of the string
		local text = string.format("@code:%s:%s", item.row.file, item.row.name)
		vim.api.nvim_buf_set_text(0, start_pos[1] - 1, start_pos[2] - 1, end_pos[1] - 1, end_pos[2], { text })
		vim.api.nvim_win_set_cursor(0, { start_pos[1], start_pos[2] - 1 + #text })
	end

	-- After brief glance at the nvim-cmp source, it appears
	-- we should call `callback` to continue the entry item selection
	-- confirmation handling chain.
	callback()
end

source.setup_autocmd_for_markdown()

return source

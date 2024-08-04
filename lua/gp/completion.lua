local u = require("gp.utils")
local context = require("gp.context")
local db = require("gp.db")
local cmp = require("cmp")

---@class CompletionSource
---@field db Db
local source = {}

source.src_name = "gp_completion"

---@return CompletionSource
function source.new()
	local db_inst = db.open()
	return setmetatable({ db = db_inst }, { __index = source })
end

function source.get_trigger_characters()
	return { "@", ":", "/" }
end

-- Attaches the completion source to the given `bufnr`
function source.setup_for_chat_buffer(bufnr)
	-- Don't attach the completion source if it's already been done
	local attached_varname = "gp_source_attached"
	if vim.b[attached_varname] then
		return
	end

	-- Attach the completion source
	local config = require("cmp.config")
	config.set_buffer({
		sources = {
			{ name = source.src_name },
		},
	}, bufnr)

	-- Set a flag so we don't try to set the source again
	vim.b[attached_varname] = true
end

function source.register_cmd_source()
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
	local result = self.db:find_symbol_by_name(partial_fn_name)

	local items = {}
	if not result then
		return items
	end

	for _, row in ipairs(result) do
		local item = {
			-- fields meant for nvim-cmp
			label = row.name,
			labelDetails = {
				detail = row.file,
			},

			-- fields meant for internal use
			row = row,
			type = "@code",
		}

		if row.type == "class" then
			item.kind = cmp.lsp.CompletionItemKind.Class
		elseif row.type == "class_method" then
			item.kind = cmp.lsp.CompletionItemKind.Method
		else
			item.kind = cmp.lsp.CompletionItemKind.Function
		end

		table.insert(items, item)
	end

	return items
end

function source.complete(self, request, callback)
	local input = string.sub(request.context.cursor_before_line, request.offset - 1)
	local cmd = extract_cmd(request)
	if not cmd then
		return
	end

	local cmd_parts = context.cmd_split(cmd)

	local items = {}
	local isIncomplete = true
	local cmd_type = cmd_parts[1]

	if cmd_type:match("@file") or cmd_type:match("@include") then
		-- What's the path we're trying to provide completion for?
		local path = cmd_parts[2] or ""

		-- List the items in the specified directory
		items = completion_items_for_path(path)

		-- Say that the entire list has been provided
		-- cmp won't call us again to provide an updated list
		isIncomplete = false
	elseif cmd_type:match("@code") then
		local partial_fn_name = cmd_parts[2] or ""

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
		items = {
			{ label = "code", kind = require("cmp").lsp.CompletionItemKind.Keyword },
			{ label = "file", kind = require("cmp").lsp.CompletionItemKind.Keyword },
			{ label = "include", kind = require("cmp").lsp.CompletionItemKind.Keyword },
		}
		isIncomplete = false
	else
		isIncomplete = false
	end

	local data = { items = items, isIncomplete = isIncomplete }
	callback(data)
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

return source

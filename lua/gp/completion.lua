print("top of gp.completion.lua")

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

local source = {}

source.src_name = "gp_completion"

source.new = function()
	print("source.new called")
	return setmetatable({}, { __index = source })
end

source.get_trigger_characters = function()
	return { "@", ":", "/" }
end

source.setup_for_buffer = function(bufnr)
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

source.setup_autocmd_for_markdown = function()
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

source.register_cmd_source = function()
	print("registering completion src")
	require("cmp").register_source(source.src_name, source.new())
end

local function extract_cmd(request)
	local target = request.context.cursor_before_line
	local start = target:match(".*()@")
	if start then
		return string.sub(target, start, request.offset)
	end
end

local function cmd_split(cmd)
	return vim.split(cmd, ":", { plain = true })
end

local function path_split(path)
	return vim.split(path, "/")
end

local function path_join(...)
	local args = { ... }
	local parts = {}

	for i, part in ipairs(args) do
		if type(part) ~= "string" then
			error("Argument #" .. i .. " is not a string", 2)
		end

		-- Remove leading/trailing separators (both / and \)
		part = part:gsub("^[/\\]+", ""):gsub("[/\\]+$", "")

		if #part > 0 then
			table.insert(parts, part)
		end
	end

	local result = table.concat(parts, "/")

	if args[1]:match("^[/\\]") then
		result = "/" .. result
	end

	return result
end

local function completion_items_for_path(path)
	local cmp = require("cmp")

	-- The incoming path should either be
	-- - A relative path that references a directory
	-- - A relative path + partial filename as last component-
	-- We need a bit of logic to figure out which directory content to return

	--------------------------------------------------------------------
	-- Figure out the full path of the directory we're trying to list --
	--------------------------------------------------------------------
	-- Split the path into component parts
	local path_parts = path_split(path)
	if path[#path] ~= "/" then
		table.remove(path_parts)
	end

	-- Assuming the cwd is the project root directory...
	local cwd = vim.fn.getcwd()
	local target_dir = path_join(cwd, unpack(path_parts))

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

source.complete = function(self, request, callback)
	local input = string.sub(request.context.cursor_before_line, request.offset - 1)
	print("[comp] input: '" .. input .. "'")
	local cmd = extract_cmd(request)
	if not cmd then
		return
	end

	print("[comp] cmd: '" .. cmd .. "'")
	local cmd_parts = cmd_split(cmd)

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
	elseif input:match("^@code:") then
		print("[complete] @code: case")
		local parts = vim.split(input, ":", { plain = true })
		if #parts == 1 then
			items = {
				{ label = "filename1.lua", kind = require("cmp").lsp.CompletionItemKind.File },
				{ label = "filename2.lua", kind = require("cmp").lsp.CompletionItemKind.File },
				{ label = "function1", kind = require("cmp").lsp.CompletionItemKind.Function },
				{ label = "function2", kind = require("cmp").lsp.CompletionItemKind.Function },
			}
		elseif #parts == 2 then
			items = {
				{ label = "function1", kind = require("cmp").lsp.CompletionItemKind.Function },
				{ label = "function2", kind = require("cmp").lsp.CompletionItemKind.Function },
			}
		end
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
	print("[complete] Callback data:")
	print(vim.inspect(data))
	callback(data)
	print("[complete] Callback called")
end

source.setup_autocmd_for_markdown()

print("end of gp.completion.lua")
return source

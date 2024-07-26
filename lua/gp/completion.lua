print("top of gp.completion.lua")

local source = {}

source.src_name = "gp_completion"

source.new = function()
	print("source.new called")
	return setmetatable({}, { __index = source })
end

source.get_trigger_characters = function()
	print("in get_trigger_characters...")
	return { "@", ":" }
	-- return { "@" }
end

source.get_keyword_pattern = function()
	print("in get_keyword_pattern...")
	-- return [[@code:[\w:]*]]
	-- return [[@([\w-]+)(?::([\w-]+))?]]
	-- return [[@file:]]
	return [[@(code|file):?]]
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
		callback = function()
			print("attaching completion source for buffer: " .. vim.api.nvim_get_current_buf())

			local cmp = require("cmp")
			cmp.setup.buffer({
				sources = cmp.config.sources({
					{ name = source.src_name },
				}),
			})
		end,
	})
end

source.register_cmd_source = function()
	print("registering completion src")
	local s = source.new()
	print("new instance: ")
	print(vim.inspect(s))
	require("cmp").register_source(source.src_name, s)
end

local function get_project_files()
	-- Assuming the cwd is the project root directory for now
	local cwd = vim.fn.getcwd()
	local handle = vim.loop.fs_scandir(cwd)

	local files = {}

	if handle then
		while true do
			local name, type = vim.loop.fs_scandir_next(handle)
			if not name then
				break
			end

			if type == "file" then
				table.insert(files, {
					label = name,
					kind = require("cmp").lsp.CompletionItemKind.File,
				})
			end
		end
	end

	return files
end

source.complete = function(self, request, callback)
	print("[complete] Function called")
	local input = string.sub(request.context.cursor_before_line, request.offset - 1)
	print("[complete] input: '" .. input .. "'")
	print("[complete] offset: " .. request.offset)
	print("[complete] cursor_before_line: '" .. request.context.cursor_before_line .. "'")

	local items = {}
	local isIncomplete = true

	if request.context.cursor_before_line:match("^@file:$") then
		print("[complete] @file: case")
		items = {
			{ label = "file1.lua", kind = require("cmp").lsp.CompletionItemKind.File },
			{ label = "file2.lua", kind = require("cmp").lsp.CompletionItemKind.File },
		}
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

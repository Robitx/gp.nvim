local u = require("gp.utils")
local gp = require("gp")
local logger = require("gp.logger")
local M = {}

-- Split a context insertion command into its component parts
function M.cmd_split(cmd)
	return vim.split(cmd, ":", { plain = true })
end

---@return string | nil
local function read_file(filepath)
	local file = io.open(filepath, "r")
	if not file then
		return nil
	end
	local content = file:read("*all")
	file:close()
	return content
end

-- Given a single message, parse out all the context insertion
-- commands, then return a new message with all the requested
-- context inserted
function M.insert_contexts(msg)
	local context_texts = {}

	-- Parse out all context insertion commands
	local cmds = {}
	for cmd in msg:gmatch("@file:[%w%p]+") do
		table.insert(cmds, cmd)
	end

	-- Process each command and turn it into a string be
	-- inserted as additional context
	for _, cmd in ipairs(cmds) do
		local cmd_parts = M.cmd_split(cmd)

		if cmd_parts[1] == "@file" then
			-- Read the reqested file and produce a msg snippet to be joined later
			local filepath = cmd_parts[2]

			local cwd = vim.fn.getcwd()
			local fullpath = u.path_join(cwd, filepath)

			local content = read_file(fullpath)
			if content then
				local result = gp._H.template_render("filepath\n```content```", {
					filepath = filepath,
					content = content,
				})
				table.insert(context_texts, result)
			end
		end
	end

	-- If no context insertions are requested, don't alter the original msg
	if #context_texts == 0 then
		return msg
	else
		-- Otherwise, build and return the final message
		return gp._H.template_render("context\n\nmsg", {
			context = table.concat(context_texts, "\n"),
			msg = msg,
		})
	end
end

function find_plugin_path(plugin_name)
	local paths = vim.api.nvim_list_runtime_paths()
	for path in paths do
		local components = u.path_split(path)
		if components[#components] == plugin_name then
			return path
		end
	end
end

function M.treesitter_query(src_filepath, query_filepath)
	-- Read the source file content
	---WARNING: This is probably not a good idea for very large files
	local src_content = read_file(src_filepath)
	if not src_content then
		logger.error("Unable to load src file: " .. src_filepath)
		return nil
	end

	-- Read the query file content
	local query_content = read_file(query_filepath)
	if not query_content then
		logger.error("Unable to load query file: " .. query_filepath)
		return nil
	end

	-- Get the filetype of the source file
	local filetype = vim.filetype.match({ filename = src_filepath })
	if not filetype then
		logger.error("Unable to determine filetype for: " .. src_filepath)
		return nil
	end

	-- Check if the treesitter support for the language is available
	local ok, err = pcall(vim.treesitter.language.add, filetype)
	if not ok then
		print("TreeSitter parser for " .. filetype .. " is not installed")
		logger.error(err)
		return nil
	end

	-- Parse the source text
	-- local parser = vim.treesitter.get_parser(0, filetype)
	local parser = vim.treesitter.get_string_parser(src_content, filetype, {})
	local tree = parser:parse()[1]
	local root = tree:root()

	-- Create and run the query
	local query = vim.treesitter.query.parse(filetype, query_content)

	-- Grab all the captures
	local captures = {}
	for id, node, metadata in query:iter_captures(root, src_content, 0, -1) do
		local name = query.captures[id]
		local start_row, start_col, end_row, end_col = node:range()
		table.insert(captures, {
			name = name,
			node = node,
			range = { start_row, start_col, end_row, end_col },
			text = vim.treesitter.get_node_text(node, src_content),
			metadata = metadata,
		})
	end

	-- Reshape the captures into a structure we'd like to work with
	local results = {}
	for i = 1, #captures, 2 do
		local fn_body = captures[i]
		assert(fn_body.name == "body")
		local fn_name = captures[i + 1]
		assert(fn_name.name == "name")

		table.insert(results, {
			file = src_filepath,
			type = "function_definition",
			name = fn_name.text,
			start_line = fn_body.range[1],
			end_line = fn_body.range[3],
			body = fn_body.text,
		})
	end

	return results
end

return M

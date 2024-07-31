local u = require("gp.utils")
local gp = require("gp")
local logger = require("gp.logger")

---@type Db
local Db = require("gp.db")

local Context = {}

-- Split a context insertion command into its component parts
function Context.cmd_split(cmd)
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

function file_exists(path)
	local file = io.open(path, "r")
	if file then
		file:close()
		return true
	else
		return false
	end
end

-- Given a single message, parse out all the context insertion
-- commands, then return a new message with all the requested
-- context inserted
function Context.insert_contexts(msg)
	local context_texts = {}

	-- Parse out all context insertion commands
	local cmds = {}
	for cmd in msg:gmatch("@file:[%w%p]+") do
		table.insert(cmds, cmd)
	end

	-- Process each command and turn it into a string be
	-- inserted as additional context
	for _, cmd in ipairs(cmds) do
		local cmd_parts = Context.cmd_split(cmd)

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

function Context.find_plugin_path(plugin_name)
	local paths = vim.api.nvim_list_runtime_paths()
	for _, path in ipairs(paths) do
		local components = u.path_split(path)
		if components[#components] == plugin_name then
			return path
		end
	end
end

-- Runs the supplied query on the supplied source file.
-- Returns all the captures as is. It is up to the caller to
-- know what the expected output is and to reshape the data.
function Context.treesitter_query(src_filepath, query_filepath)
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

	return captures
end

function Context.treesitter_extract_function_defs(src_filepath)
	-- Make sure we can locate the source file
	if not file_exists(src_filepath) then
		logger.error("Unable to locate src file: " .. src_filepath)
		return nil
	end

	-- Get the filetype of the source file
	local filetype = vim.filetype.match({ filename = src_filepath })
	if not filetype then
		logger.error("Unable to determine filetype for: " .. src_filepath)
		return nil
	end

	-- We'll use the reported filetype as the name of the language
	-- Try to locate a query file we can use to extract function definitions
	local plugin_path = Context.find_plugin_path("gp.nvim")
	if not plugin_path then
		logger.error("Unable to locate path for gp.nvim...")
		return nil
	end

	-- Find the query file that's approprite for the language
	local query_filepath = u.path_join(plugin_path, "data/ts_queries/" .. filetype .. ".scm")
	if not file_exists(query_filepath) then
		logger.error("Unable to find function extraction ts query file: " .. query_filepath)
		return nil
	end

	-- Run the query
	local captures = Context.treesitter_query(src_filepath, query_filepath)
	if not captures then
		return nil
	end

	-- Reshape the captures into a structure we'd like to work with
	local results = {}
	for i = 1, #captures, 2 do
		-- The captures may arrive out of order.
		-- We're only expecting the query to contain @name and @body returned
		-- Sort out their ordering here.
		local caps = { captures[i], captures[i + 1] }
		local named_caps = {}
		for _, item in ipairs(caps) do
			named_caps[item.name] = item
		end
		local fn_name = named_caps.name
		local fn_body = named_caps.body
		assert(fn_name)
		assert(fn_body)

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

---@param db Db
---@param src_filepath string
function Context.build_function_def_index_for_file(db, src_filepath)
	print("building fn list")
	-- try to retrieve function definitions from the file
	local fnlist = Context.treesitter_extract_function_defs(src_filepath)
	if not fnlist then
		return false
	end
	print("done building fn list")

	-- Grab the src file meta data
	local src_file_entry = db.collect_src_file_data(src_filepath)
	if not src_file_entry then
		logger.error("Unable to collect src file data for:" .. src_filepath)
		return false
	end
	src_file_entry.last_scan_time = os.time()
	print("collected file info")

	-- Update the src file entry and the function definitions in a single transaction
	-- TODO: Remove stale entries?
	local result = db:with_transaction(function()
		print("updating src file entry")
		local success = db:upsert_src_file(src_file_entry)
		if not success then
			return false
		end
		print("upserting fn list")
		return db:upsert_fnlist(fnlist)
	end)
	return result
end

function Context.build_function_def_index(db)
	local git_root = gp._H.find_git_root()
	if not git_root then
		logger.error("[Context.build_function_def_index] Unable to locate project root")
		return false
	end
	local git_root_len = #git_root + 2

	local function scan_directory(dir)
		local entries = vim.fn.readdir(dir)

		for _, entry in ipairs(entries) do
			local full_path = u.path_join(dir, entry)
			local rel_path = full_path:sub(git_root_len)
			-- Ignore hidden files and directories
			if u.string_starts_with(entry, ".") or u.string_ends_with(entry, ".txt") or u.string_ends_with(entry, ".md") then
				goto continue
			end

			if vim.fn.isdirectory(full_path) == 1 then
				if entry == "node_modules" then
					goto continue
				end
				scan_directory(full_path)
			else
				-- Only process files with recognized filetypes
				if vim.filetype.match({ filename = full_path }) then
					local success = Context.build_function_def_index_for_file(db, rel_path)
					if not success then
						logger.warning("Failed to build function def index for: " .. rel_path)
					end
				end
			end
			::continue::
		end
	end

	scan_directory(git_root)
end

function Context.index_all()
	local uv = vim.uv or vim.loop
	local start_time = uv.hrtime()

	local db = Db.open()
	if not db then
		return
	end
	Context.build_function_def_index(db)
	db:close()

	local end_time = uv.hrtime()
	local elapsed_time_ms = (end_time - start_time) / 1e6
	logger.info(string.format("[Gp] Indexing took: %.2f ms", elapsed_time_ms))
end

return Context

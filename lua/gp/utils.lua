local uv = vim.uv or vim.loop

local Utils = {}

function Utils.path_split(path)
	return vim.split(path, "/")
end

function Utils.path_join(...)
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

function Utils.path_is_absolute(path)
	if Utils.string_starts_with(path, "/") then
		return true
	end
	return false
end

function Utils.ensure_path_exists(path)
	-- Check if the path exists
	local stat = uv.fs_stat(path)
	if stat and stat.type == "directory" then
		-- The path exists and is a directory
		return true
	end

	-- Try to create the directory
	return vim.fn.mkdir(path, "p")
end

function Utils.ensure_parent_path_exists(path)
	local components = Utils.path_split(path)

	-- Get the parent directory by removing the last component
	table.remove(components)
	local parent_path = table.concat(components, "/")

	return Utils.ensure_path_exists(parent_path)
end

function Utils.string_starts_with(str, starting)
	return string.sub(str, 1, string.len(starting)) == starting
end

function Utils.string_ends_with(str, ending)
	if #ending > #str then
		return false
	end

	return str:sub(-#ending) == ending
end

---@class WalkDirectoryOptions
---@field should_process function Passed `entry`, `rel_path`, `full_path`, and `is_dir`
---@field process_file function
---@field on_error function
---@field recurse boolean
---@field max_depth number
---
---@param dir string The directory to try to walk
---@param options WalkDirectoryOptions Describes how to walk the directory
---
function Utils.walk_directory(dir, options)
	options = options or {}

	local should_process = options.should_process or function()
		return true
	end

	local process_file = options.process_file or function(rel_path, full_path)
		print(full_path)
	end
	local recurse = not options.recurse

	---@type number
	local max_depth = options.max_depth or math.huge

	local function walk(current_dir, current_depth)
		if current_depth > max_depth then
			return
		end

		local entries = vim.fn.readdir(current_dir)

		for _, entry in ipairs(entries) do
			local full_path = Utils.path_join(current_dir, entry)
			local rel_path = full_path:sub(#dir + 2)
			local is_dir = vim.fn.isdirectory(full_path) == 1

			if should_process(entry, rel_path, full_path, is_dir) then
				if is_dir then
					if recurse then
						walk(full_path, current_depth + 1)
					end
				else
					pcall(process_file, rel_path, full_path)
				end
			end
		end
	end

	walk(dir, 1)
end

--- Locates the git_root using the cwd
function Utils.git_root_from_cwd()
	return require("gp.helper").find_git_root(vim.fn.getcwd())
end

-- If the given path is a relative path, turn it into a fullpath
-- based on the current git_root
---@param path string
function Utils.full_path_for_project_file(path)
	if Utils.path_is_absolute(path) then
		return path
	end

	-- Construct the full path to the file
	local proj_root = Utils.git_root_from_cwd()
	return Utils.path_join(proj_root, path)
end

function Utils.string_find_all_substr(str, substr)
	local result = {}
	local first = 0
	local last = 0

	while true do
		first, last = str:find(substr, first + 1)
		if not first then
			break
		end
		table.insert(result, { first, last })
	end
	return result
end

function Utils.partition_by(pred, list)
	local result = {}
	local current_partition = {}
	local last_key = nil

	for _, item in ipairs(list) do
		local key = pred(item)
		if last_key == nil or key ~= last_key then
			if #current_partition > 0 then
				table.insert(result, current_partition)
			end
			current_partition = {}
		end
		table.insert(current_partition, item)
		last_key = key
	end

	if #current_partition > 0 then
		table.insert(result, current_partition)
	end

	return result
end

function Utils.write_file(filename, content, mode)
	mode = mode or "w" -- Default mode is write
	if not content then
		return true
	end
	local file = io.open(filename, mode)
	if file then
		file:write(content)
		file:close()
	else
		error("Unable to open file: " .. filename)
	end
	return true
end

function Utils.sort_by(key_fn, tbl)
	table.sort(tbl, function(a, b)
		local ka, kb = key_fn(a), key_fn(b)
		if type(ka) == "table" and type(kb) == "table" then
			-- Use table identifiers as tie-breaker
			return tostring(ka) < tostring(kb)
		else
			return ka < kb
		end
	end)
	return tbl
end

function Utils.random_8byte_int()
	return math.random(0, 0xFFFFFFFFFFFFFFFF)
end

-- Gets a buffer variable or returns the default
function Utils.buf_get_var(buf, var_name, default)
	local status, result = pcall(vim.api.nvim_buf_get_var, buf, var_name)
	if status then
		return result
	else
		return default
	end
end

-- This function is only here make the get/set call pair look consistent
function Utils.buf_set_var(buf, var_name, value)
	return vim.api.nvim_buf_set_var(buf, var_name, value)
end

return Utils

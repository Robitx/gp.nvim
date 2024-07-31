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

return Utils

local M = {}

function M.path_split(path)
	return vim.split(path, "/")
end

function M.path_join(...)
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

return M

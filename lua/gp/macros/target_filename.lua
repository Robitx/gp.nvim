local macro = require("gp.macro")
local gp = require("gp")

local M = {}

---@type gp.Macro
M = {
	name = "target_filename`",
	description = "handles target buffer filename for commands",
	default = nil,
	max_occurrences = 1,

	triggered = function(params)
		local cropped_line = params.cropped_line
		return cropped_line:match("@target_filename`[^`]*$")
	end,

	completion = function(params)
		local root_dir = params.state.context_dir or vim.fn.getcwd()
		local files = vim.fn.globpath(root_dir, "**", false, true)
		local root_dir_length = #root_dir + 2
		files = vim.tbl_map(function(file)
			return file:sub(root_dir_length) .. " `"
		end, files)
		return files
	end,

	parser = function(result)
		local template = result.template
		local s, e, value = template:find("@target_filename`([^`]*)`")
		if not value then
			return result
		end

		value = value:match("^%s*(.-)%s*$")
		local placeholder = macro.generate_placeholder(M.name, value)

		local full_path = value
		if vim.fn.fnamemodify(full_path, ":p") ~= value then
			full_path = vim.fn.fnamemodify(result.state.context_dir .. "/" .. value, ":p")
		end

		result.artifacts[placeholder] = ""
		result.template = template:sub(1, s - 1) .. placeholder .. template:sub(e + 1)
		result.state[M.name:sub(1, -2)] = full_path
		return result
	end,
}

return M

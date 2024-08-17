local macro = require("gp.macro")

local M = {}

---@type gp.Macro
M = {
	name = "target_filename`",
	description = "handles target buffer filename for commands",
	default = nil,
	max_occurrences = 1,

	triggered = function(params, state)
		local cropped_line = params.cropped_line
		return cropped_line:match("@target_filename`[^`]*$")
	end,

	completion = function(params, state)
		-- TODO state.root_dir ?
		local files = vim.fn.glob("**", true, true)
		-- local files = vim.fn.getcompletion("", "file")
		files = vim.tbl_map(function(file)
			return file .. " `"
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

		result.template = template:sub(1, s - 2) .. placeholder .. template:sub(e + 1)
		result.state[M.name] = value
		result.artifacts[placeholder] = ""
		return result
	end,
}

return M

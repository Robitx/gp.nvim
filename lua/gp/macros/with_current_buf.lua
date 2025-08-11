local macro = require("gp.macro")
local gp = require("gp")

local M = {}

---@type gp.Macro
M = {
	name = "with_current_buf",
	description = "replaces the macro with the content of the current file",
	default = nil,
	max_occurrences = 1,

	triggered = function(_)
		return false
	end,

	completion = function(_)
		return {}
	end,

	parser = function(result)
		local template = result.template
		local macro_pattern = "@with_current_buf"

		local s, e = template:find(macro_pattern)
		if not s then
			return result
		end

		local placeholder = macro.generate_placeholder(M.name, "")

		local current_buf = vim.api.nvim_get_current_buf()
		local content = table.concat(vim.api.nvim_buf_get_lines(current_buf, 0, -1, false), "\n")
		local full_path = vim.api.nvim_buf_get_name(current_buf)

		content = gp.render.template(gp.config.template_context_file, {
			["{{content}}"] = content,
			["{{filename}}"] = full_path,
		})
		result.artifacts[placeholder] = content

		result.template = template:sub(1, s - 1) .. placeholder .. template:sub(e + 1)

		return result
	end,
}

return M

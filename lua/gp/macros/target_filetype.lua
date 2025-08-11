local macro = require("gp.macro")

local values = nil

local M = {}

---@type gp.Macro
M = {
	name = "target_filetype",
	description = "handles target buffer filetype for commands like GpEnew",
	default = "markdown",
	max_occurrences = 1,

	triggered = function(params)
		return params.cropped_line:match("@target_filetype%s+%S*$")
	end,

	completion = function(params)
		if not values then
			values = vim.fn.getcompletion("", "filetype")
		end
		return values
	end,

	parser = function(result)
		local template = result.template
		local s, e, value = template:find("@target_filetype%s+(%S+)")
		if not value then
			return result
		end

		local placeholder = macro.generate_placeholder(M.name, value)
		result.template = template:sub(1, s - 2) .. placeholder .. template:sub(e + 1)
		result.state[M.name] = value
		result.artifacts[placeholder] = ""
		return result
	end,
}

return M

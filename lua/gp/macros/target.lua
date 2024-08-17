local macro = require("gp.macro")

local values = {
	"rewrite",
	"append",
	"prepend",
	"popup",
	"enew",
	"new",
	"vnew",
	"tabnew",
}

local M = {}

---@type gp.Macro
M = {
	name = "target",
	description = "handles target for commands",
	default = "rewrite",
	max_occurrences = 1,

	triggered = function(params, state)
		local cropped_line = params.cropped_line
		return cropped_line:match("@target%s+%S*$")
	end,

	completion = function(params, state)
		return values
	end,

	parser = function(result)
		local template = result.template
		local s, e, value = template:find("@target%s+(%S+)")
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

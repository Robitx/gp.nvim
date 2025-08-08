local macro = require("gp.macro")
local gp = require("gp")

local M = {}

---@type gp.Macro
M = {
	name = "agent",
	description = "handles agent selection for commands",
	default = "",
	max_occurrences = 1,

	triggered = function(params)
		return params.cropped_line:match("@agent%s+%S*$")
	end,

	completion = function(params)
		if params.state.is_chat then
			return gp._chat_agents
		end
		return gp._command_agents
	end,

	parser = function(result)
		local template = result.template
		local s, e, value = template:find("@agent%s+(%S+)")
		if not value then
			return result
		end

		local placeholder = macro.generate_placeholder(M.name, value)
		result.template = template:sub(1, s - 2) .. placeholder .. template:sub(e + 1)
		if result.state.is_chat then
			result.state[M.name] = gp.get_chat_agent(value)
		else
			result.state[M.name] = gp.get_command_agent(value)
		end
		result.artifacts[placeholder] = ""
		return result
	end,
}

return M

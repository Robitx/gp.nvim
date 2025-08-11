local macro = require("gp.macro")
local gp = require("gp")

---@param git_root? string # optional git root directory
---@return string # returns instructions from the .gp.md file
local repo_instructions = function(git_root)
	git_root = git_root or gp.helpers.find_git_root()

	if git_root == "" then
		return ""
	end

	local instruct_file = (git_root:gsub("/$", "")) .. "/.gp.md"

	if vim.fn.filereadable(instruct_file) == 0 then
		return ""
	end

	local lines = vim.fn.readfile(instruct_file)
	return table.concat(lines, "\n")
end

local M = {}

---@type gp.Macro
M = {
	name = "with_repo_instructions",
	description = "replaces the macro with the content of the .gp.md file in the git root",
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
		local macro_pattern = "@with_repo_instructions"

		local s, e = template:find(macro_pattern)
		if not s then
			return result
		end

		local placeholder = macro.generate_placeholder(M.name, "")

		local instructions = repo_instructions(result.state.context_dir)
		result.artifacts[placeholder] = gp.render.template(gp.config.template_context_file, {
			["{{content}}"] = instructions,
			["{{filename}}"] = ".repository_instructions.md",
		})

		result.template = template:sub(1, s - 1) .. placeholder .. template:sub(e + 1)
		return result
	end,
}

return M

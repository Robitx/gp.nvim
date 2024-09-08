local macro = require("gp.macro")
local gp = require("gp")

local M = {}

---@type gp.Macro
M = {
	name = "context_file`",
	description = "replaces the macro with the content of the specified file",
	default = nil,
	max_occurrences = 100,

	triggered = function(params)
		local cropped_line = params.cropped_line
		return cropped_line:match("@context_file`[^`]*$")
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
		local macro_pattern = "@context_file`([^`]*)`"

		for _ = 1, M.max_occurrences do
			local s, e, value = template:find(macro_pattern)
			if not value then
				break
			end

			value = value:match("^%s*(.-)%s*$")
			local placeholder = macro.generate_placeholder(M.name, value)

			local full_path = value
			if vim.fn.fnamemodify(full_path, ":p") ~= value then
				full_path = vim.fn.fnamemodify(result.state.context_dir .. "/" .. value, ":p")
			end

			if vim.fn.filereadable(full_path) == 0 then
				result.artifacts[placeholder] = ""
				gp.logger.error("Context file not found: " .. full_path)
			else
				local content = table.concat(vim.fn.readfile(full_path), "\n")
				content = gp.render.template(gp.config.template_context_file, {
					["{{content}}"] = content,
					["{{filename}}"] = full_path,
				})
				result.artifacts[placeholder] = content
			end

			template = template:sub(1, s - 1) .. placeholder .. template:sub(e + 1)
		end

		result.template = template
		return result
	end,
}

return M

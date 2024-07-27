local u = require("gp.utils")
local gp = require("gp")
local M = {}

-- Split a context insertion command into its component parts
function M.cmd_split(cmd)
	return vim.split(cmd, ":", { plain = true })
end

local function read_file(filepath)
	local file = io.open(filepath, "r")
	if not file then
		return nil
	end
	local content = file:read("*all")
	file:close()
	return content
end

-- Given a single message, parse out all the context insertion
-- commands, then return a new message with all the requested
-- context inserted
function M.insert_contexts(msg)
	local context_texts = {}

	-- Parse out all context insertion commands
	local cmds = {}
	for cmd in msg:gmatch("@file:[%w%p]+") do
		table.insert(cmds, cmd)
	end

	-- Process each command and turn it into a string be
	-- inserted as additional context
	for _, cmd in ipairs(cmds) do
		local cmd_parts = M.cmd_split(cmd)

		if cmd_parts[1] == "@file" then
			-- Read the reqested file and produce a msg snippet to be joined later
			local filepath = cmd_parts[2]

			local cwd = vim.fn.getcwd()
			local fullpath = u.path_join(cwd, filepath)

			local content = read_file(fullpath)
			if content then
				local result = gp._H.template_render("filepath\n```content```", {
					filepath = filepath,
					content = content,
				})
				table.insert(context_texts, result)
			end
		end
	end

	-- If no context insertions are requested, don't alter the original msg
	if #context_texts == 0 then
		return msg
	else
		-- Otherwise, build and return the final message
		return gp._H.template_render("context\n\nmsg", {
			context = table.concat(context_texts, "\n"),
			msg = msg,
		})
	end
end

return M

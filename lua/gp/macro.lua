local logger = require("gp.logger")
local buffer_state = require("gp.buffer_state")

---@class gp.Macro_cmd_params
---@field arg_lead string
---@field cmd_line string
---@field cursor_pos number
---@field cropped_line string
---@field state table

---@class gp.Macro_parser_result
---@field template string
---@field artifacts table<string, string>
---@field state table

--- gp.Macro Interface
-- @field name string: Name of the macro.
-- @field description string: Description of the macro.
-- @field default string: Default value for the macro (optional).
-- @field max_occurrences number: Maximum number of occurrences for the macro (optional).
-- @field triggered function: Function that determines if the macro is triggered.
-- @field completion function: Function that provides completion options.
-- @field parser function: Function that processes the macro in the template.

---@class gp.Macro
---@field name string
---@field description string
---@field default? string
---@field max_occurrences? number
---@field triggered fun(params: gp.Macro_cmd_params): boolean
---@field completion fun(params: gp.Macro_cmd_params): string[]
---@field parser fun(params: gp.Macro_parser_result): gp.Macro_parser_result

---@param value string # string to hash
---@return string # returns hash of the string
local fnv1a_hash = function(value)
	---@type number
	local hash = 2166136261
	for i = 1, #value do
		hash = vim.fn.xor(hash, string.byte(value, i))
		hash = vim.fn["and"]((hash * 16777619), 0xFFFFFFFF)
	end
	return string.format("%08x", hash) -- return as an 8-character hex string
end

local M = {}

---@param prefix string # prefix for the placeholder
---@param value string # value to hash
---@return string # returns placeholder
M.generate_placeholder = function(prefix, value)
	local hash_value = fnv1a_hash(value)
	local placeholder = "{{" .. prefix .. "." .. hash_value .. "}}"
	return placeholder
end

---@param macros gp.Macro[]
---@return fun(template: string, artifacts: table, state: table): gp.Macro_parser_result
M.build_parser = function(macros)
	---@param template string
	---@param artifacts table
	---@param state table
	---@return {template: string, artifacts: table, state: table}
	local function parser(template, artifacts, state)
		template = template or ""
		---@type gp.Macro_parser_result
		local result = {
			template = " " .. template .. " ",
			artifacts = artifacts or {},
			state = state or buffer_state.get(vim.api.nvim_get_current_buf()),
		}
		logger.debug("macro parser input: " .. vim.inspect(result))

		for _, macro in pairs(macros) do
			logger.debug("macro parser current macro: " .. vim.inspect(macro))
			result = macro.parser(result)
			logger.debug("macro parser result: " .. vim.inspect(result))
		end
		return result
	end

	return parser
end

---@param macros gp.Macro[]
---@param raw boolean | nil # which function to return (completion or raw_completion)
---@return fun(arg_lead: string, cmd_line: string, cursor_pos: number): string[], boolean | nil
M.build_completion = function(macros, raw)
	---@type table<string, gp.Macro>
	local map = {}
	for _, macro in pairs(macros) do
		map[macro.name] = macro
	end

	---@param arg_lead string
	---@param cmd_line string
	---@param cursor_pos number
	---@return string[], boolean # returns suggestions and whether some macro was triggered
	local function raw_completion(arg_lead, cmd_line, cursor_pos)
		local cropped_line = cmd_line:sub(1, cursor_pos)

		---@type gp.Macro_cmd_params
		local params = {
			arg_lead = arg_lead,
			cmd_line = cmd_line,
			cursor_pos = cursor_pos,
			cropped_line = cropped_line,
			state = buffer_state.get(vim.api.nvim_get_current_buf()),
		}

		cropped_line = " " .. cropped_line

		local suggestions = {}
		local triggered = false

		logger.debug("macro completion input: " .. vim.inspect({
			params = params,
		}))

		---@type table<string, number>
		local candidates = {}
		local cand = nil
		for c in cropped_line:gmatch("%s@(%S+)%s") do
			candidates[c] = candidates[c] and candidates[c] + 1 or 1
			cand = c
		end
		logger.debug("macro completion candidates: " .. vim.inspect(candidates))

		if cand and map[cand] and map[cand].triggered(params) then
			suggestions = map[cand].completion(params)
			triggered = true
		elseif cropped_line:match("%s$") or cropped_line:match("%s@%S*$") then
			for _, c in pairs(macros) do
				if not candidates[c.name] or candidates[c.name] < c.max_occurrences then
					table.insert(suggestions, "@" .. c.name)
				end
			end
		end

		logger.debug("macro completion suggestions: " .. vim.inspect(suggestions))
		return vim.deepcopy(suggestions), triggered
	end

	local completion = function(arg_lead, cmd_line, cursor_pos)
		local suggestions, _ = raw_completion(arg_lead, cmd_line, cursor_pos)
		return suggestions
	end

	if raw then
		return raw_completion
	end

	return completion
end

local registered_cmp_sources = {}
M.build_cmp_source = function(name, macros)
	if registered_cmp_sources[name] then
		logger.debug("cmp source " .. name .. " already registered")
		return nil
	end
	local source = {}

	source.new = function()
		return setmetatable({}, { __index = source })
	end

	source.get_trigger_characters = function()
		return { "@", " " }
	end

	local completion = M.build_completion(macros, true)

	source.complete = function(self, params, callback)
		local ctx = params.context
		local suggestions, triggered = completion(ctx.cursor_before_line:match("%S*$"), ctx.cursor_line, ctx.cursor.col)

		if not triggered and not ctx.cursor_before_line:match("%s*@%S*$") then
			suggestions = {}
		end

		logger.debug("macro completion suggestions: " .. vim.inspect(suggestions))

		local items = {}
		for _, suggestion in ipairs(suggestions) do
			table.insert(items, {
				label = suggestion,
				kind = require("cmp").lsp.CompletionItemKind.Keyword,
				documentation = name,
			})
		end
		logger.debug("macro cmp complete output: " .. vim.inspect(items))

		callback(items)
	end

	local has_cmp, cmp = pcall(require, "cmp")
	if not has_cmp then
		logger.warning("cmp not found, skipping cmp source registration")
		return source
	end

	cmp.register_source(name, source)
	registered_cmp_sources[name] = true

	if true then
		return source
	end

	cmp.event:on("complete_done", function(event)
		if not event or not event.entry or event.entry.source.name ~= name then
			return
		end
		local ctx = event.entry.source.context
		local suggestions, triggered = completion(ctx.cursor_before_line:match("%S*$"), ctx.cursor_line, ctx.cursor.col)
		logger.debug(
			"macro cmp complete_done suggestions: " .. vim.inspect(suggestions) .. " triggered: " .. vim.inspect(triggered)
		)
		if not suggestions or not triggered then
			return
		end

		vim.schedule(function()
			-- insert a space if not already present at the cursor
			local cursor_col = vim.api.nvim_win_get_cursor(0)[2]
			local line = vim.api.nvim_get_current_line()
			logger.debug(
				"macro cmp complete_done cursor_col: "
					.. cursor_col
					.. " line: "
					.. line
					.. " char: "
					.. line:sub(cursor_col, cursor_col)
			)
			if line:sub(cursor_col, cursor_col) ~= " " then
				vim.api.nvim_put({ " " }, "c", false, true)
			end
			vim.schedule(function()
				cmp.complete(suggestions)
			end)
		end)
	end)

	return source
end

return M

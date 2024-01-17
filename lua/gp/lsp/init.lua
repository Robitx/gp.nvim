local M = {}

--------------------------------------------------------------------------------
-- LSP
-- Plan (all this should run async over a queue of tasks):
-- 1. Append probe function at the end of the buffer with empty line
-- 2. Try completion on the empty line
-- 3. Filter out the snippets and such
-- 4. Filter out the default completion items for given language
-- 5. Put the remaining items in probe function with continuation (". " etc)
-- 6. Try hover for those which don't have detail
-- 7. Try completion on variables, classes, etc

--------------------------------------------------------------------------------

---@param filetype string
---@return table
M.get_ignored_items = function(filetype)
	local status, data = pcall(require, "gp.lsp.ft." .. filetype)
	---@diagnostic disable-next-line: undefined-field
	if status and data and data.ignore then
		---@diagnostic disable-next-line: undefined-field
		return data.ignore
	end
	return {}
end

---@param filetype string
---@return table
M.get_no_complete_items = function(filetype)
	local status, data = pcall(require, "gp.lsp.ft." .. filetype)
	---@diagnostic disable-next-line: undefined-field
	if status and data and data.no_complete then
		---@diagnostic disable-next-line: undefined-field
		return data.no_complete
	end
	return {}
end

---@param filetype string
---@return table|nil { lines = {string, ..}, insert_line = number }
M.get_probe_template = function(filetype)
	local lines = nil
	local status, data = pcall(require, "gp.lsp.ft." .. filetype)
	if not (status and data and data.template) then
		return nil
	end
	lines = vim.split(data.template, "\n")

	local insert_line = 0
	for i, line in ipairs(lines) do
		if insert_line > 0 and line:match("^%s*$") then
			insert_line = i
			break
		elseif not line:match("^%s*$") then
			insert_line = i
		end
	end

	-- lines are put after extmark => + 1
	return { lines = lines, insert_line = insert_line + 1 }
end

---@param filetype string
---@return table|nil
M.get_affixes = function(filetype)
	local status, data = pcall(require, "gp.lsp.ft." .. filetype)
	if status and data and data.affixes then
		return data.affixes
	end
	return nil
end

---@param lines string[]|nil lines of text
---@return string[]|nil snippet lines
M.first_snippet = function(lines)
	if not lines then
		return nil
	end
	local snippet_started = false
	local snippet_lines = {}
	local non_empty_encountered = false
	for _, line in ipairs(lines) do
		local is_fence = line:match("^```")
		if is_fence and not snippet_started then
			snippet_started = true
			non_empty_encountered = true
		elseif is_fence and snippet_started then
			return snippet_lines
		elseif snippet_started then
			table.insert(snippet_lines, line)
		elseif non_empty_encountered and not is_fence then
			table.insert(snippet_lines, line)
		elseif not non_empty_encountered and line ~= "" and not is_fence then
			non_empty_encountered = true
		end
	end
	return snippet_started and snippet_lines or lines
end

---@param kind string
---@param label string
---@param lines string[] | nil
---@return string
M.first_line = function(kind, label, lines)
	lines = lines or { "" }
	if kind == "Function" or kind == "Method" then
		local line = ""
		for _, l in ipairs(lines) do
			line = line .. l:gsub("^%s*(.-)%s*$", " %1")
			line = line:gsub("%s%s", " ")
		end
		lines = { line }
	end
	local patterns = {
		{ "^%s*", "" },
		{ "^" .. kind:lower() .. "%s*", "" },
		{ "^." .. kind:lower() .. ".%s*", "" },
		{ "^.field.%s*", "" },
		{ "%s*.property.$", "" },
		{ "{%s*$", "" },
		{ "[ ]*$", "" },
		{ "^" .. label .. ": ", "" },
		{ "^" .. label .. ":$", "" },
		{ "^" .. label .. "%(%)$", "" },
		{ "%(%s*", "(" },
		{ "%s*%)", ")" },
		{ "%s*$", "" },
	}
	local line = lines[1]
	if #lines > 1 then
		line = line .. lines[2]
	end
	for _, pattern in ipairs(patterns) do
		line = line:gsub(pattern[1], pattern[2])
	end
	return line
end

---@param row integer|nil mark-indexed line number, defaults to current line
---@param col integer|nil mark-indexed column number, defaults to current column
---@param bufnr integer|nil buffer handle or 0 for current, defaults to current
---@param offset_encoding "utf-8"|"utf-16"|"utf-32"|nil defaults to `offset_encoding` of first client of `bufnr`
---@return table { textDocument = { uri = `current_file_uri` }, position = { line = `row`, character = `col`} }
---@see https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocumentPositionParams
M.make_given_position_param = function(row, col, bufnr, offset_encoding)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	row = row or vim.api.nvim_win_get_cursor(0)[1]
	col = col or vim.api.nvim_win_get_cursor(0)[2]
	local params = vim.lsp.util.make_given_range_params({ row, col }, { row, col }, bufnr, offset_encoding)
	return { textDocument = params.textDocument, position = params.range.start }
end

---@param row integer|nil mark-indexed line number, defaults to current line
---@param col integer|nil mark-indexed column number, defaults to current column
---@param bufnr integer|nil buffer handle or 0 for current, defaults to current
---@param callback function | nil receives hover result
M.hover = function(row, col, bufnr, callback)
	local params = M.make_given_position_param(row, col, bufnr)

	vim.lsp.buf_request_all(bufnr, "textDocument/hover", params, function(results)
		local contents = {}
		for _, r in pairs(results) do
			if r.result and r.result.contents then
				local lines = vim.lsp.util.convert_input_to_markdown_lines(r.result.contents)
				for _, line in ipairs(lines) do
					table.insert(contents, line)
				end
			end
		end

		if callback then
			callback(M.first_snippet(contents))
		end
	end)
end

---@param row integer|nil mark-indexed line number, defaults to current line
---@param col integer|nil mark-indexed column number, defaults to current column
---@param bufnr integer|nil buffer handle or 0 for current, defaults to current
---@see https://microsoft.github.io/language-server-protocol/specifications/specification-current/#completionParams
---@param callback function | nil receives completion result
---@param filtered table | nil filtered out items with given label
---@return table queue of tasks for possible cancellation
M.completion = function(row, col, bufnr, callback, filtered)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	row = row or vim.api.nvim_win_get_cursor(0)[1]
	col = col or vim.api.nvim_win_get_cursor(0)[2]
	local params = M.make_given_position_param(row, col, bufnr)

	local items = {}
	local queue = require("gp.queue").create(function()
		for kind, labels in pairs(items) do
			for label, detail in pairs(labels) do
				local d = detail.value and detail.value or detail
				items[kind][label] = M.first_line(kind, label, M.first_snippet(vim.split(d, "\n")))
			end
		end
		if next(items) == nil then
			items = nil
		end
		if callback then
			callback(items)
		end
	end)

	vim.lsp.buf_request_all(bufnr, "textDocument/completion", params, function(results)
		for client_id, r in pairs(results) do
			local result = {}
			if r.result then
				-- CompletionItem[] | CompletionList => CompletionItem[]
				result = r.result.items and r.result.items or r.result
			end
			for _, item in ipairs(result) do
				local label = item.label:match("^[%s•]*(.-)[%s•]*$")
				local item_kind = vim.lsp.protocol.CompletionItemKind[item.kind]
				if
					item_kind ~= "Snippet"
					and item_kind ~= "Keyword"
					and item_kind ~= "Text"
					and not (filtered and filtered[item_kind] and filtered[item_kind][label])
				then
					items[item_kind] = items[item_kind] or {}
					if not item.documentation and not item.detail then
						queue.addTask(function(data)
							local client = vim.lsp.get_client_by_id(data.client_id)
							if not client then
								queue.runNextTask()
								return
							end
							client.request("completionItem/resolve", data.item, function(_, resolved)
								items[data.kind][data.label] = resolved.detail or resolved.documentation or ""
								queue.runNextTask()
							end, data.bufnr)
						end, { client_id = client_id, item = item, kind = item_kind, bufnr = bufnr, label = label })
					else
						items[item_kind][label] = item.detail or item.documentation or ""
					end
				end
			end
		end
		queue.runNextTask()
	end)
	return queue
end

---@param bufnr integer|nil buffer handle or 0 for current, defaults to current
---@param callback function | nil receives document symbol result
---@param filtered table | nil filtered out items with given label
M.root_document_symbols = function(bufnr, callback, filtered)
	local params = M.make_given_position_param(0, 0, bufnr)

	vim.lsp.buf_request_all(
		bufnr,
		"textDocument/documentSymbol",
		{ textDocument = params.textDocument },
		function(results)
			local items = {}
			for _, r in pairs(results) do
				local result = r.result and r.result or {}
				for _, item in ipairs(result) do
					local kind = vim.lsp.protocol.SymbolKind[item.kind] or ""
					local label = item.name:match("^[%s•]*(.-)[%s•]*$")
					local detail = item.detail or ""
					if not (filtered and filtered[kind] and filtered[kind][label]) then
						items[kind] = items[kind] or {}
						items[kind][label] = detail or ""
					end
				end
			end
			if callback then
				callback(items)
			end
		end
	)
end

M.full_semantic_tokens = function(bufnr, callback)
	local params = M.make_given_position_param(0, 0, bufnr)

	vim.lsp.buf_request_all(
		bufnr,
		"textDocument/semanticTokens/full",
		{ textDocument = params.textDocument },
		function(response)
			if callback then
				callback(response)
			end
		end
	)
end

M.completion_item_resolve = function(item, bufnr, callback)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	vim.lsp.buf_request_all(bufnr, "completionItem/resolve", item, function(response)
		if callback then
			callback(response)
		end
	end)
end
M.workspace_symbols = function(bufnr, query, callback)
	local params = { query = query or "" }
	vim.lsp.buf_request_all(bufnr, "workspace/symbol", params, function(results)
		if callback then
			callback(results)
		end
	end)
end

return M

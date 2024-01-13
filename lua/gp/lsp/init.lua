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
	return snippet_started and snippet_lines or nil
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
M.completion = function(row, col, bufnr, callback, filtered)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	row = row or vim.api.nvim_win_get_cursor(0)[1]
	col = col or vim.api.nvim_win_get_cursor(0)[2]
	local params = M.make_given_position_param(row, col, bufnr)

	vim.lsp.buf_request_all(bufnr, "textDocument/completion", params, function(results)
		local items = {}
		for _, r in pairs(results) do
			local result = {}
			if r.result then
				-- CompletionItem[] | CompletionList => CompletionItem[]
				result = r.result.items and r.result.items or r.result
			end
			for _, item in ipairs(result) do
				local label = item.label:match("^[%s•]*(.-)[%s•]*$")
				item.kind = vim.lsp.protocol.CompletionItemKind[item.kind]
				if
					item.kind ~= "Snippet"
					and item.kind ~= "Text"
					and not (filtered and filtered[item.kind] and filtered[item.kind][label])
				then
					items[item.kind] = items[item.kind] or {}
					items[item.kind][label] = item.detail or ""
				end
			end
		end
		if next(items) == nil then
			items = nil
		end
		if callback then
			callback(items)
		end
	end)
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

M.workspace_symbols = function(bufnr, query, callback)
	local params = { query = query or "" }
	vim.lsp.buf_request_all(bufnr, "workspace/symbol", params, function(results)
		if callback then
			callback(results)
		end
	end)
end

return M

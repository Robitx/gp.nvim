--------------------------------------------------------------------------------
-- Dispatcher handles the communication between the plugin and LLM providers.
--------------------------------------------------------------------------------

local logger = require("gp.logger")
local tasker = require("gp.tasker")
local vault = require("gp.vault")
local render = require("gp.render")
local helpers = require("gp.helper")

local default_config = require("gp.config")

local D = {
	config = {},
	providers = {},
	query_dir = vim.fn.stdpath("cache") .. "/gp/query",
}

---@param opts table #	user config
D.setup = function(opts)
	logger.debug("dispatcher setup started\n" .. vim.inspect(opts))

	D.config.curl_params = opts.curl_params or default_config.curl_params

	D.providers = vim.deepcopy(default_config.providers)
	opts.providers = opts.providers or {}
	for k, v in pairs(opts.providers) do
		D.providers[k] = D.providers[k] or {}
		D.providers[k].disable = false
		for pk, pv in pairs(v) do
			D.providers[k][pk] = pv
		end
		if next(v) == nil then
			D.providers[k].disable = true
		end
	end

	-- remove invalid providers
	for name, provider in pairs(D.providers) do
		if type(provider) ~= "table" or provider.disable then
			D.providers[name] = nil
		elseif not provider.endpoint then
			D.logger.warning("Provider " .. name .. " is missing endpoint")
			D.providers[name] = nil
		end
	end

	for name, provider in pairs(D.providers) do
		vault.add_secret(name, provider.secret)
		provider.secret = nil
	end

	D.query_dir = helpers.prepare_dir(D.query_dir, "query store")

	local files = vim.fn.glob(D.query_dir .. "/*.json", false, true)
	if #files > 200 then
		logger.debug("too many query files, truncating cache")
		table.sort(files, function(a, b)
			return a > b
		end)
		for i = 100, #files do
			helpers.delete_file(files[i])
		end
	end

	logger.debug("dispatcher setup finished\n" .. vim.inspect(D))
end

---@param messages table
---@param model string | table
---@param provider string | nil
D.prepare_payload = function(messages, model, provider)
	if type(model) == "string" then
		return {
			model = model,
			stream = true,
			messages = messages,
		}
	end

	if provider == "googleai" then
		for i, message in ipairs(messages) do
			if message.role == "system" then
				messages[i].role = "user"
			end
			if message.role == "assistant" then
				messages[i].role = "model"
			end
			if message.content then
				messages[i].parts = {
					{
						text = message.content,
					},
				}
				messages[i].content = nil
			end
		end
		local i = 1
		while i < #messages do
			if messages[i].role == messages[i + 1].role then
				table.insert(messages[i].parts, {
					text = messages[i + 1].parts[1].text,
				})
				table.remove(messages, i + 1)
			else
				i = i + 1
			end
		end
		local payload = {
			contents = messages,
			safetySettings = {
				{
					category = "HARM_CATEGORY_HARASSMENT",
					threshold = "BLOCK_NONE",
				},
				{
					category = "HARM_CATEGORY_HATE_SPEECH",
					threshold = "BLOCK_NONE",
				},
				{
					category = "HARM_CATEGORY_SEXUALLY_EXPLICIT",
					threshold = "BLOCK_NONE",
				},
				{
					category = "HARM_CATEGORY_DANGEROUS_CONTENT",
					threshold = "BLOCK_NONE",
				},
			},
			generationConfig = {
				temperature = math.max(0, math.min(2, model.temperature or 1)),
				maxOutputTokens = model.max_tokens or 8192,
				topP = math.max(0, math.min(1, model.top_p or 1)),
				topK = model.top_k or 100,
			},
			model = model.model,
		}
		return payload
	end

	if provider == "anthropic" then
		local system = ""
		local i = 1
		while i < #messages do
			if messages[i].role == "system" then
				system = system .. messages[i].content .. "\n"
				table.remove(messages, i)
			else
				i = i + 1
			end
		end

		local payload = {
			model = model.model,
			stream = true,
			messages = messages,
			system = system,
			max_tokens = model.max_tokens or 4096,
			temperature = model.temperature and math.max(0, math.min(2, model.temperature)) or nil,
			top_p = model.top_p and math.max(0, math.min(1, model.top_p)) or nil,
		}

		if model.thinking_budget ~= nil then
			payload.thinking = {
				type = "enabled",
				budget_tokens = model.thinking_budget
			}
		end

		return payload
	end

	if provider == "ollama" then
		local payload = {
			model = model.model,
			stream = true,
			messages = messages,
		}

		if model.think ~= nil then
			payload.think = model.think
		end

		local options = {}
		if model.temperature then
			options.temperature = math.max(0, math.min(2, model.temperature))
		end
		if model.top_p then
			options.top_p = math.max(0, math.min(1, model.top_p))
		end
		if model.min_p then
			options.min_p = math.max(0, math.min(1, model.min_p))
		end
		if model.num_ctx then
			options.num_ctx = model.num_ctx
		end
		if model.top_k then
			options.top_k = model.top_k
		end

		if next(options) then
			payload.options = options
		end

		return payload
	end

	local output = {
		model = model.model,
		stream = true,
		messages = messages,
		max_completion_tokens = model.max_completion_tokens or 4096,
		temperature = math.max(0, math.min(2, model.temperature or 1)),
		top_p = math.max(0, math.min(1, model.top_p or 1)),
	}

	if (provider == "openai" or provider == "copilot") and model.model:sub(1, 1) == "o" then
		if model.model:sub(1, 2) == "o3" then
			output.reasoning_effort = model.reasoning_effort or "medium"
		end

		for i = #messages, 1, -1 do
			if messages[i].role == "system" then
				table.remove(messages, i)
			end
		end
		-- remove max_tokens, top_p, temperature for o1 models. https://platform.openai.com/docs/guides/reasoning/beta-limitations
		output.max_completion_tokens = nil
		output.temperature = nil
		output.top_p = nil
	end

	if model.model == "gpt-5" or  model.model == "gpt-5-mini" then
		-- remove max_tokens, top_p, temperature for gpt-5 models (duh)
		output.max_tokens = nil
		output.temperature = nil
		output.top_p = nil
	end

	return output
end

-- gpt query
---@param buf number | nil # buffer number
---@param provider string # provider name
---@param payload table # payload for api
---@param handler function # response handler
---@param on_exit function | nil # optional on_exit handler
---@param callback function | nil # optional callback handler
local query = function(buf, provider, payload, handler, on_exit, callback)
	-- make sure handler is a function
	if type(handler) ~= "function" then
		logger.error(
			string.format("query() expects a handler function, but got %s:\n%s", type(handler), vim.inspect(handler))
		)
		return
	end

	local qid = helpers.uuid()
	tasker.set_query(qid, {
		timestamp = os.time(),
		buf = buf,
		provider = provider,
		payload = payload,
		handler = handler,
		on_exit = on_exit,
		raw_response = "",
		response = "",
		first_line = -1,
		last_line = -1,
		ns_id = nil,
		ex_id = nil,
	})

	local out_reader = function()
		local buffer = ""
		local anthropic_thinking = false -- local state for Anthropic thinking blocks

		---@param lines_chunk string
		local function process_lines(lines_chunk)
			local qt = tasker.get_query(qid)
			if not qt then
				return
			end

			local lines = vim.split(lines_chunk, "\n")
			for _, line in ipairs(lines) do
				if line ~= "" and line ~= nil then
					qt.raw_response = qt.raw_response .. line .. "\n"

					line = line:gsub("^data: ", "")
					local content = ""
					if line and line:match("choices") and line:match("delta") and line:match("content") then
						line = vim.json.decode(line)
						if line.choices[1] and line.choices[1].delta and line.choices[1].delta.content then
							content = line.choices[1].delta.content
						end
					end

					if qt.provider == "anthropic" and line and (line:match('"text":') or line:match('"thinking"')) then
						if line:match("content_block_start") or line:match("content_block_delta") then
							line = vim.json.decode(line)
							if line.content_block then
								if line.content_block.type == "thinking" then
									anthropic_thinking = true
									content = "<think>"
								elseif line.content_block.type == "text" and anthropic_thinking then
									anthropic_thinking = false
									content = "</think>\n\n"
								end
							end
							if line.delta then
								if line.delta.type == "thinking_delta" then
									content = line.delta.thinking or ""
								elseif line.delta.type == "text_delta" then
									content = line.delta.text or ""
								end
							end
						end
					end

					if qt.provider == "googleai" then
						if line and line:match('"text":') then
							content = vim.json.decode("{" .. line .. "}").text
						end
					end

					if qt.provider == "ollama" then
						if line and line:match('"message":') and line:match('"content":') then
							local success, decoded = pcall(vim.json.decode, line)
							if success and decoded.message and decoded.message.content then
								content = decoded.message.content
							end
						end
					end

					if content and type(content) == "string" then
						qt.response = qt.response .. content
						handler(qid, content)
					end
				end
			end
		end

		-- closure for uv.read_start(stdout, fn)
		return function(err, chunk)
			local qt = tasker.get_query(qid)
			if not qt then
				return
			end

			if err then
				logger.error(qt.provider .. " query stdout error: " .. vim.inspect(err))
			elseif chunk then
				-- add the incoming chunk to the buffer
				buffer = buffer .. chunk
				local last_newline_pos = buffer:find("\n[^\n]*$")
				if last_newline_pos then
					local complete_lines = buffer:sub(1, last_newline_pos - 1)
					-- save the rest of the buffer for the next chunk
					buffer = buffer:sub(last_newline_pos + 1)

					process_lines(complete_lines)
				end
				-- chunk is nil when EOF is reached
			else
				-- if there's remaining data in the buffer, process it
				if #buffer > 0 then
					process_lines(buffer)
				end
				local raw_response = qt.raw_response
				local content = qt.response
				if (qt.provider == 'openai' or qt.provider == 'copilot') and content == "" and raw_response:match('choices') and raw_response:match("content") then
					local response = vim.json.decode(raw_response)
					if response.choices and response.choices[1] and response.choices[1].message and response.choices[1].message.content then
						content = response.choices[1].message.content
					end
					if content and type(content) == "string" then
						qt.response = qt.response .. content
						handler(qid, content)
					end
				end


				if qt.response == "" then
					logger.error(qt.provider .. " response is empty: \n" .. vim.inspect(qt.raw_response))
				end

				-- optional on_exit handler
				if type(on_exit) == "function" then
					on_exit(qid)
					if qt.ns_id and qt.buf then
						vim.schedule(function()
							vim.api.nvim_buf_clear_namespace(qt.buf, qt.ns_id, 0, -1)
						end)
					end
				end

				-- optional callback handler
				if type(callback) == "function" then
					vim.schedule(function()
						callback(qt.response)
					end)
				end
			end
		end
	end

	---TODO: this could be moved to a separate function returning endpoint and headers
	local endpoint = D.providers[provider].endpoint
	local headers = {}

	local secret = provider
	if provider == "copilot" then
		secret = "copilot_bearer"
	end
	local bearer = vault.get_secret(secret)
	if not bearer then
		logger.warning(provider .. " bearer token is missing")
		return
	end

	if provider == "copilot" then
		headers = {
			"-H",
			"editor-version: vscode/1.85.1",
			"-H",
			"Authorization: Bearer " .. bearer,
		}
	elseif provider == "openai" then
		headers = {
			"-H",
			"Authorization: Bearer " .. bearer,
			-- backwards compatibility
			"-H",
			"api-key: " .. bearer,
		}
	elseif provider == "googleai" then
		headers = {}
		endpoint = render.template_replace(endpoint, "{{secret}}", bearer)
		endpoint = render.template_replace(endpoint, "{{model}}", payload.model)
		payload.model = nil
	elseif provider == "anthropic" then
		headers = {
			"-H",
			"x-api-key: " .. bearer,
			"-H",
			"anthropic-version: 2023-06-01",
		}
	elseif provider == "azure" then
		headers = {
			"-H",
			"api-key: " .. bearer,
		}
		endpoint = render.template_replace(endpoint, "{{model}}", payload.model)
	elseif provider == "ollama" then
		headers = {}
	else -- default to openai compatible headers
		headers = {
			"-H",
			"Authorization: Bearer " .. bearer,
		}
	end

	local temp_file = D.query_dir ..
		"/" .. logger.now() .. "." .. string.format("%x", math.random(0, 0xFFFFFF)) .. ".json"
	helpers.table_to_file(payload, temp_file)

	local curl_params = vim.deepcopy(D.config.curl_params or {})
	local args = {
		"--no-buffer",
		"-s",
		endpoint,
		"-H",
		"Content-Type: application/json",
		"-d",
		"@" .. temp_file,
	}

	for _, arg in ipairs(args) do
		table.insert(curl_params, arg)
	end

	for _, header in ipairs(headers) do
		table.insert(curl_params, header)
	end

	tasker.run(buf, "curl", curl_params, nil, out_reader(), nil)
end

-- gpt query
---@param buf number | nil # buffer number
---@param provider string # provider name
---@param payload table # payload for api
---@param handler function # response handler
---@param on_exit function | nil # optional on_exit handler
---@param callback function | nil # optional callback handler
D.query = function(buf, provider, payload, handler, on_exit, callback)
	if provider == "copilot" then
		return vault.run_with_secret(provider, function()
			vault.refresh_copilot_bearer(function()
				query(buf, provider, payload, handler, on_exit, callback)
			end)
		end)
	end
	vault.run_with_secret(provider, function()
		query(buf, provider, payload, handler, on_exit, callback)
	end)
end

-- response handler
---@param buf number | nil # buffer to insert response into
---@param win number | nil # window to insert response into
---@param line number | nil # line to insert response into
---@param first_undojoin boolean | nil # whether to skip first undojoin
---@param prefix string | nil # prefix to insert before each response line
---@param cursor boolean # whether to move cursor to the end of the response
D.create_handler = function(buf, win, line, first_undojoin, prefix, cursor)
	buf = buf or vim.api.nvim_get_current_buf()
	prefix = prefix or ""
	local first_line = line or vim.api.nvim_win_get_cursor(win or 0)[1] - 1
	local finished_lines = 0
	local skip_first_undojoin = not first_undojoin

	local hl_handler_group = "GpHandlerStandout"
	vim.cmd("highlight default link " .. hl_handler_group .. " CursorLine")

	local ns_id = vim.api.nvim_create_namespace("GpHandler_" .. helpers.uuid())

	local ex_id = vim.api.nvim_buf_set_extmark(buf, ns_id, first_line, 0, {
		strict = false,
		right_gravity = false,
	})

	local response = ""
	return vim.schedule_wrap(function(qid, chunk)
		local qt = tasker.get_query(qid)
		if not qt then
			return
		end
		-- if buf is not valid, stop
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		-- undojoin takes previous change into account, so skip it for the first chunk
		if skip_first_undojoin then
			skip_first_undojoin = false
		else
			helpers.undojoin(buf)
		end

		if not qt.ns_id then
			qt.ns_id = ns_id
		end

		if not qt.ex_id then
			qt.ex_id = ex_id
		end

		first_line = vim.api.nvim_buf_get_extmark_by_id(buf, ns_id, ex_id, {})[1]

		-- clean previous response
		local line_count = #vim.split(response, "\n")
		vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + line_count, false, {})

		-- append new response
		response = response .. chunk
		helpers.undojoin(buf)

		-- prepend prefix to each line
		local lines = vim.split(response, "\n")
		for i, l in ipairs(lines) do
			lines[i] = prefix .. l
		end

		local unfinished_lines = {}
		for i = finished_lines + 1, #lines do
			table.insert(unfinished_lines, lines[i])
		end

		vim.api.nvim_buf_set_lines(buf, first_line + finished_lines, first_line + finished_lines, false, unfinished_lines)

		local new_finished_lines = math.max(0, #lines - 1)
		for i = finished_lines, new_finished_lines do
			vim.api.nvim_buf_add_highlight(buf, qt.ns_id, hl_handler_group, first_line + i, 0, -1)
		end
		finished_lines = new_finished_lines

		local end_line = first_line + #vim.split(response, "\n")
		qt.first_line = first_line
		qt.last_line = end_line - 1

		-- move cursor to the end of the response
		if cursor then
			helpers.cursor_to_line(end_line, buf, win)
		end
	end)
end

return D

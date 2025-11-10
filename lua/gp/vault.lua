--------------------------------------------------------------------------------
-- Vault module for managing secrets
--------------------------------------------------------------------------------

local logger = require("gp.logger")
local tasker = require("gp.tasker")
local helpers = require("gp.helper")
local default_config = require("gp.config")

local V = {
	_obfuscated_secrets = {},
	_state = {},
	config = {},
}

local secrets = {} -- private secretes accessible only via vault.get_secret

-- backwards compatibility
local alias = {
	openai = "openai_api_key",
}

---@param opts table # user config
V.setup = function(opts)
	logger.debug("vault setup started\n" .. vim.inspect(opts), true)

	V.config.curl_params = opts.curl_params or default_config.curl_params
	V.config.state_dir = opts.state_dir or default_config.state_dir

	helpers.prepare_dir(V.config.state_dir, "vault state")

	logger.debug("vault setup finished\n" .. vim.inspect(V), true)
end

---@param name string # provider name
---@param secret string | table | nil # secret or command to retrieve it
V.add_secret = function(name, secret)
	name = alias[name] or name
	if secrets[name] then
		logger.debug("vault secret " .. name .. " already exists", true)
		return
	end
	local s = { secret = secret }
	s = vim.deepcopy(s)
	secrets[name] = s.secret
	logger.debug("vault adding secret " .. name .. ": " .. vim.inspect(s.secret), true)
end

---@param name string # secret name
---@return string | nil # secret or nil if not found
V.get_secret = function(name)
	name = alias[name] or name

	local secret = secrets[name]
	logger.debug("vault get_secret:" .. name .. ": " .. vim.inspect(secret), true)

	if not secret then
		logger.warning("vault secret " .. name .. " not found", true)
		return nil
	end

	if type(secret) == "table" then
		logger.warning("vault secret " .. name .. " is still an unresolved command: " .. vim.inspect(secret), true)
		return nil
	end
	return secret
end

---@param name string # provider name
---@param secret string | table | nil # secret or command to retrieve it
---@param callback function | nil # callback to run after secret is resolved
V.resolve_secret = function(name, secret, callback)
	logger.debug("vault resolver started for " .. name .. ": " .. vim.inspect(secret), true)
	name = alias[name] or name
	callback = callback or function() end
	if secrets[name] and type(secrets[name]) ~= "table" then
		logger.debug("vault resolver secret " .. name .. " already resolved", true)
		callback()
		return
	end

	local post_process = function()
		local s = secrets[name]
		if s and type(s) == "string" then
			secrets[name] = s:gsub("^%s*(.-)%s*$", "%1")
		end
		logger.debug("vault resolver finished for " .. name .. ": " .. vim.inspect(secrets[name]), true)

		V._obfuscated_secrets[name] = s:sub(1, 3) .. string.rep("*", #s - 6) .. s:sub(-3)

		callback()
	end

	if not secret then
		logger.warning("vault resolver for " .. name .. " got empty secret", true)
		return
	end

	if type(secret) == "table" then
		local copy = vim.deepcopy(secret)
		local cmd = table.remove(copy, 1)
		local args = copy
		tasker.run(nil, cmd, args, function(code, signal, stdout_data, stderr_data)
			if code == 0 then
				local content = stdout_data:match("^%s*(.-)%s*$")
				if not string.match(content, "%S") then
					logger.warning("vault resolver got empty response for " ..
						name .. " secret command " .. vim.inspect(secret))
					return
				end
				secrets[name] = content
				post_process()
			else
				logger.warning(
					"vault resolver for "
					.. name
					.. "secret command "
					.. vim.inspect(secret)
					.. " failed:\ncode: "
					.. code
					.. ", signal: "
					.. signal
					.. "\nstdout: "
					.. stdout_data
					.. "\nstderr: "
					.. stderr_data
				)
			end
		end)
	else
		secrets[name] = secret
		post_process()
	end
end

V.refresh_copilot_bearer = function(callback)
	local secret = secrets.copilot
	if not secret or type(secret) == "table" then
		return
	end
	logger.debug("vault refresh_copilot_bearer: started", true)

	callback = callback or function() end

	local state_file = V.config.state_dir .. "/vault_state.json"

	local state = {}
	if vim.fn.filereadable(state_file) ~= 0 then
		state = helpers.file_to_table(state_file) or {}
	end

	local bearer = V._state.copilot_bearer or state.copilot_bearer or {}
	if bearer.token and bearer.expires_at and bearer.expires_at > os.time() then
		secrets.copilot_bearer = bearer.token
		logger.debug("vault refresh_copilot_bearer: token still valid, running callback", true)
		callback()
		return
	end

	local curl_params = vim.deepcopy(V.config.curl_params or {})
	local args = {
		"-s",
		"-v",
		"https://api.github.com/copilot_internal/v2/token",
		"-H",
		"Content-Type: application/json",
		"-H",
		"accept: */*",
		"-H",
		"authorization: token " .. secret,
		"-H",
		"editor-version: vscode/1.90.2",
		"-H",
		"editor-plugin-version: copilot-chat/0.17.2024062801",
		"-H",
		"user-agent: GitHubCopilotChat/0.17.2024062801",
	}

	for _, arg in ipairs(args) do
		table.insert(curl_params, arg)
	end

	tasker.run(nil, "curl", curl_params, function(code, signal, stdout, stderr)
		if code ~= 0 then
			logger.error(string.format("copilot bearer resolve failed: %d, %d", code, signal, stderr))
			return
		end

		V._state.copilot_bearer = vim.json.decode(stdout)
		secrets.copilot_bearer = V._state.copilot_bearer.token
		helpers.table_to_file(V._state, state_file)

		logger.debug("vault refresh_copilot_bearer: token resolved, running callback", true)
		callback()
	end, nil, nil)
end

---@param name string # secret name
---@param callback function # function to run after secret is resolved
V.run_with_secret = function(name, callback)
	name = alias[name] or name
	if not secrets[name] then
		logger.warning("vault secret " .. name .. " not found", true)
		return
	end
	if type(secrets[name]) == "table" then
		V.resolve_secret(name, secrets[name], function()
			logger.debug("vault run_with_secret: " .. name .. " resolved, running callback", true)
			callback()
		end)
	else
		logger.debug("vault run_with_secret: " .. name .. " already resolved, running callback", true)
		callback()
	end
end

return V

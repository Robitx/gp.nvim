--------------------------------------------------------------------------------
-- Imager module for generating images
--------------------------------------------------------------------------------

local logger = require("gp.logger")
local tasker = require("gp.tasker")
local spinner = require("gp.spinner")
local render = require("gp.render")
local helpers = require("gp.helper")
local vault = require("gp.vault")

local default_config = require("gp.config")

local I = {
	config = {},
	_state = {},
	_agents = {},
	cmd = {},
	disabled = false,
}

---@param opts table # user config
I.setup = function(opts)
	logger.debug("imager setup started\n" .. vim.inspect(opts))

	I.config = vim.deepcopy(default_config.image)

	if opts.disable then
		I.disabled = true
		logger.debug("imager is disabled")
		return
	end

	I.agents = {}
	for _, v in pairs(I.config.agents) do
		I.agents[v.name] = v
	end
	I.config.agents = nil

	opts.agents = opts.agents or {}
	for _, v in pairs(opts.agents) do
		I.agents[v.name] = v
	end
	opts.agents = nil

	for k, v in pairs(opts) do
		I.config[k] = v
	end

	I.config.store_dir = helpers.prepare_dir(I.config.store_dir, "imager store")
	I.config.state_dir = helpers.prepare_dir(I.config.state_dir, "imager state")

	for name, agent in pairs(I.agents) do
		if type(agent) ~= "table" or agent.disable then
			logger.debug("imager agent " .. name .. " disabled")
			I.agents[name] = nil
		elseif not agent.model then
			logger.warning(
				"Image agent "
					.. name
					.. " is missing model\n"
					.. "If you want to disable an agent, use: { name = '"
					.. name
					.. "', disable = true },"
			)
			I.agents[name] = nil
		end
	end

	for name, _ in pairs(I.agents) do
		table.insert(I._agents, name)
	end
	table.sort(I._agents)

	I.refresh()

	for cmd, _ in pairs(I.cmd) do
		helpers.create_user_command(I.config.cmd_prefix .. cmd, I.cmd[cmd], function()
			if cmd == "ImageAgent" then
				return I._agents
			end

			return {}
		end)
	end

	vault.add_secret("imager_secret", I.config.secret)
	I.config.secret = nil

	logger.debug("imager setup finished")
end

I.refresh = function()
	logger.debug("imager state refresh")

	local state_file = I.config.state_dir .. "/imager_state.json"

	local state = {}
	if vim.fn.filereadable(state_file) ~= 0 then
		state = helpers.file_to_table(state_file) or {}
	end

	logger.debug("imager loaded state:\n" .. vim.inspect(state))

	I._state.agent = I._state.agent or state.agent or nil
	if not I._state.agent == nil or not I.agents[I._state.agent] then
		I._state.agent = I._agents[1]
	end

	helpers.table_to_file(I._state, state_file)
end

I.cmd.ImageAgent = function(params)
	local agent_name = string.gsub(params.args, "^%s*(.-)%s*$", "%1")
	if agent_name == "" then
		logger.info("imager agent: " .. (I._state.agent or "none"))
		return
	end

	if not I.agents[agent_name] then
		logger.warning("imager unknown agent: " .. agent_name)
		return
	end

	I._state.agent = agent_name
	logger.info("imager agent: " .. I._state.agent)

	I.refresh()
end

---@return table # { cmd_prefix, name, model, quality, style, size }
I.get_image_agent = function()
	local template = I.config.prompt_prefix_template
	local name = I._state.agent
	local cmd_prefix = render.template(template, { ["{{agent}}"] = name })
	local model = I.agents[name].model
	local quality = I.agents[name].quality
	local style = I.agents[name].style
	local size = I.agents[name].size
	return { cmd_prefix = cmd_prefix, name = name, model = model, quality = quality, style = style, size = size }
end

I.cmd.Image = function(params)
	local prompt = params.args
	local agent = I.get_image_agent()
	if prompt == "" then
		vim.ui.input({ prompt = agent.cmd_prefix }, function(input)
			prompt = input
			if not prompt then
				return
			end
			I.generate_image(prompt, agent.model, agent.quality, agent.style, agent.size)
		end)
	else
		I.generate_image(prompt, agent.model, agent.quality, agent.style, agent.size)
	end
end

local generate_image = function(prompt, model, quality, style, size)
	local bearer = vault.get_secret("imager_secret")
	if not bearer then
		return
	end

	local cmd = "curl"
	local payload = {
		model = model,
		prompt = prompt,
		n = 1,
		size = size,
		style = style,
		quality = quality,
	}
	local args = {
		-- "-s",
		"-H",
		"Content-Type: application/json",
		"-H",
		"Authorization: Bearer " .. bearer,
		"-d",
		vim.json.encode(payload),
		"https://api.openai.com/v1/images/generations",
	}

	local qid = helpers.uuid()
	tasker.set_query(qid, {
		timestamp = os.time(),
		payload = payload,
		raw_response = "",
		error = "",
		url = "",
		prompt = "",
		save_path = "",
		save_raw_response = "",
		save_error = "",
	})
	local query = tasker.get_query(qid)

	spinner.start_spinner("Generating image...")

	tasker.run(nil, cmd, args, function(code, signal, stdout_data, stderr_data)
		spinner.stop_spinner()
		query.raw_response = stdout_data
		query.error = stderr_data
		if code ~= 0 then
			logger.error(
				"Image generation exited: code: "
					.. code
					.. " signal: "
					.. signal
					.. " stdout: "
					.. stdout_data
					.. " stderr: "
					.. stderr_data
			)
			return
		end
		local result = vim.json.decode(stdout_data)
		query.parsed_response = vim.inspect(result)
		if result and result.data and result.data[1] and result.data[1].url then
			local image_url = result.data[1].url
			query.url = image_url
			-- query.prompt = result.data[1].prompt
			vim.ui.input(
				{ prompt = I.config.prompt_save, completion = "file", default = I.config.store_dir },
				function(save_path)
					if not save_path or save_path == "" then
						logger.info("Image URL: " .. image_url)
						return
					end
					query.save_path = save_path
					spinner.start_spinner("Saving image...")
					tasker.run(
						nil,
						"curl",
						{ "-s", "-o", save_path, image_url },
						function(save_code, save_signal, save_stdout_data, save_stderr_data)
							spinner.stop_spinner()
							query.save_raw_response = save_stdout_data
							query.save_error = save_stderr_data
							if save_code == 0 then
								logger.info("Image saved to: " .. save_path)
							else
								logger.error(
									"Failed to save image: path: "
										.. save_path
										.. " code: "
										.. save_code
										.. " signal: "
										.. save_signal
										.. " stderr: "
										.. save_stderr_data
								)
							end
						end
					)
				end
			)
		else
			logger.error("Image generation failed: " .. vim.inspect(stdout_data))
		end
	end)
end

I.generate_image = function(prompt, model, quality, style, size)
	vault.run_with_secret("imager_secret", function()
		generate_image(prompt, model, quality, style, size)
	end)
end

return I

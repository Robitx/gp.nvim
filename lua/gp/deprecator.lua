--------------------------------------------------------------------------------
-- Deprecator module
--------------------------------------------------------------------------------

local logger = require("gp.logger")
local helpers = require("gp.helper")
local render = require("gp.render")

local M = {}
M._deprecated = {}

local switch_to_agent = "Please use `agents` table and switch agents in runtime via `:GpAgent XY`"

local nested = function(variable, prefix)
	local new_variable = variable:gsub(prefix .. "_", "")
	return render.template(
		"`{{old}}`\nPlease use `{{prefix}} = { {{new}} = ... }`",
		{ ["{{old}}"] = variable, ["{{new}}"] = new_variable, ["{{prefix}}"] = prefix }
	)
end

local deprecated = {
	chat_toggle_target = "`chat_toggle_target`\nPlease rename it to `toggle_target` which is also used by other commands",
	command_model = "`command_model`\n" .. switch_to_agent,
	command_system_prompt = "`command_system_prompt`\n" .. switch_to_agent,
	chat_custom_instructions = "`chat_custom_instructions`\n" .. switch_to_agent,
	chat_model = "`chat_model`\n" .. switch_to_agent,
	chat_system_prompt = "`chat_system_prompt`\n" .. switch_to_agent,
	command_prompt_prefix = "`command_prompt_prefix`\nPlease use `command_prompt_prefix_template`"
		.. " with support for \n`{{agent}}` variable so you know which agent is currently active",
	whisper_max_time = "`whisper_max_time`\nPlease use fully customizable `whisper_rec_cmd`",

	openai_api_endpoint = "`openai_api_endpoint`\n\n"
		.. "Gp.nvim finally supports multiple LLM providers; sorry it took so long.\n"
		.. "I've dreaded merging this, because I hate breaking people's setups.\n"
		.. "But this change is necessary for future improvements.\n\n"
		.. "Migration hints are below; for more help, try the readme docs or open an issue.\n\n"
		.. "If you're using the `https://api.openai.com/v1/chat/completions` endpoint,\n"
		.. "just drop `openai_api_endpoint` in your config and you're done."
		.. "\n\nOtherwise sorry for probably breaking your setup, "
		.. "please use `endpoint` and `secret` fields in:\n\nproviders "
		.. "= {\n  openai = {\n    endpoint = '...',\n    secret = '...'\n   },"
		.. "\n  -- azure = {...},\n  -- copilot = {...},\n  -- ollama = {...},\n  -- googleai= {...},\n  -- pplx = {...},\n  -- anthropic = {...},\n},\n"
		.. "\nThe `openai_api_key` is still supported for backwards compatibility,\n"
		.. "and automatically converted to `providers.openai.secret` if the new config is not set.",
	image_dir = "`image_dir`\nPlease use `image = { store_dir = ... }`",
	whisper_dir = "`whisper_dir`\nPlease use `whisper = { store_dir = ... }`",
	whisper_api_endpoint = "`whisper_api_endpoint`\nPlease use `whisper = { endpoint = ... }`",
}

M.is_valid = function(k, v)
	if deprecated[k] then
		table.insert(M._deprecated, { name = k, msg = deprecated[k], value = v })
		return false
	end
	if helpers.starts_with(k, "image_") then
		table.insert(M._deprecated, { name = k, msg = nested(k, "image"), value = v })
		return false
	end
	if helpers.starts_with(k, "whisper_") then
		table.insert(M._deprecated, { name = k, msg = nested(k, "whisper"), value = v })
		return false
	end
	return true
end

M.report = function()
	if #M._deprecated == 0 then
		return
	end

	local msg = "Hey there, I have good news and bad news for you."
		.. "\n\nThe good news is that you've updated Gp.nvim and got some new features."
		.. "\nThe bad news is that some of the config options you are using are deprecated."
		.. "\n\nThis is shown only at startup and deprecated options are ignored"
		.. "\nso everything should work without problems and you can deal with this later."
		.. "\n\nYou can check deprecated options any time with `:checkhealth gp`"
		.. "\nSorry for the inconvenience and thank you for using Gp.nvim."
		.. "\n\n********************************************************************************"
		.. "\n********************************************************************************"
	table.sort(M._deprecated, function(a, b)
		return a.msg < b.msg
	end)
	for _, v in ipairs(M._deprecated) do
		msg = msg .. "\n\n- " .. v.msg
	end

	logger.info(msg)
end

local examplePromptHook = [[
UnitTests = function(gp, params)
    local template = "I have the following code from {{filename}}:\n\n"
        .. "```{{filetype}}\n{{selection}}\n```\n\n"
        .. "Please respond by writing table driven unit tests for the code above."
    local agent = gp.get_command_agent()
    gp.Prompt(params, gp.Target.vnew, agent, template)
end,
]]

M.has_old_prompt_signature = function(agent)
	if not agent or not type(agent) == "table" or not agent.provider then
		logger.warning(
			"The `gp.Prompt` method signature has changed.\n"
				.. "Please update your hook functions as demonstrated in the example below:\n\n"
				.. examplePromptHook
				.. "\nFor more information, refer to the 'Extend Functionality' section in the documentation."
		)
		return true
	end
	return false
end

local exampleChatHook = [[
Translator = function(gp, params)
    local chat_system_prompt = "You are a Translator, please translate between English and Chinese."
    gp.cmd.ChatNew(params, chat_system_prompt)

    -- -- you can also create a chat with a specific fixed agent like this:
    -- local agent = gp.get_chat_agent("ChatGPT4o")
    -- gp.cmd.ChatNew(params, chat_system_prompt, agent)
end,
]]

M.has_old_chat_signature = function(agent)
	if agent then
		if not type(agent) == "table" or not agent.provider then
			logger.warning(
				"The `gp.cmd.ChatNew` method signature has changed.\n"
					.. "Please update your hook functions as demonstrated in the example below:\n\n"
					.. exampleChatHook
					.. "\nFor more information, refer to the 'Extend Functionality' section in the documentation."
			)
			return true
		end
	end
	return false
end

M.check_health = function()
	if #M._deprecated == 0 then
		vim.health.ok("no deprecated config options")
		return
	end

	local msg = "deprecated config option(s) in setup():"
	for _, v in ipairs(M._deprecated) do
		msg = msg .. "\n\n- " .. v.msg
	end
	vim.health.warn(msg)
end

return M

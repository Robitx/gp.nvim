-- Gp (GPT prompt) lua plugin for Neovim
-- https://github.com/Robitx/gp.nvim/

--------------------------------------------------------------------------------
-- Default config
--------------------------------------------------------------------------------

local default_chat_system_prompt = "You are a general AI assistant.\n\n"
	.. "The user provided the additional info about how they would like you to respond:\n\n"
	.. "- If you're unsure don't guess and say you don't know instead.\n"
	.. "- Ask question if you need clarification to provide better answer.\n"
	.. "- Think deeply and carefully from first principles step by step.\n"
	.. "- Zoom out first to see the big picture and then zoom in to details.\n"
	.. "- Use Socratic method to improve your thinking and coding skills.\n"
	.. "- Don't elide any code from your output if the answer requires coding.\n"
	.. "- Take a deep breath; You've got this!\n"

local default_code_system_prompt = "You are an AI working as a code editor.\n\n"
	.. "Please AVOID COMMENTARY OUTSIDE OF THE SNIPPET RESPONSE.\n"
	.. "START AND END YOUR ANSWER WITH:\n\n```"

local config = {
	-- Please start with minimal config possible.
	-- Just openai_api_key if you don't have OPENAI_API_KEY env set up.
	-- Defaults change over time to improve things, options might get deprecated.
	-- It's better to change only things where the default doesn't fit your needs.

	-- required openai api key (string or table with command and arguments)
	-- openai_api_key = { "cat", "path_to/openai_api_key" },
	-- openai_api_key = { "bw", "get", "password", "OPENAI_API_KEY" },
	-- openai_api_key: "sk-...",
	-- openai_api_key = os.getenv("env_name.."),
	openai_api_key = os.getenv("OPENAI_API_KEY"),

	-- at least one working provider is required
	-- to disable a provider set it to empty table like openai = {}
	providers = {
		-- secrets can be strings or tables with command and arguments
		-- secret = { "cat", "path_to/openai_api_key" },
		-- secret = { "bw", "get", "password", "OPENAI_API_KEY" },
		-- secret : "sk-...",
		-- secret = os.getenv("env_name.."),
		openai = {
			endpoint = "https://api.openai.com/v1/chat/completions",
			-- secret = os.getenv("OPENAI_API_KEY"),
		},
		azure = {
			-- endpoint = "https://$URL.openai.azure.com/openai/deployments/{{model}}/chat/completions",
			-- secret = os.getenv("AZURE_API_KEY"),
		},
		copilot = {
			-- endpoint = "https://api.githubcopilot.com/chat/completions",
			-- secret = {
			-- 	"bash",
			-- 	"-c",
			-- 	"cat ~/.config/github-copilot/hosts.json | sed -e 's/.*oauth_token...//;s/\".*//'",
			-- },
		},
		ollama = {
			-- endpoint = "http://localhost:11434/v1/chat/completions",
		},
		lmstudio = {
			-- endpoint = "http://localhost:1234/v1/chat/completions",
		},
		googleai = {
			-- endpoint = "https://generativelanguage.googleapis.com/v1beta/models/{{model}}:streamGenerateContent?key={{secret}}",
			-- secret = os.getenv("GOOGLEAI_API_KEY"),
		},
		pplx = {
			-- endpoint = "https://api.perplexity.ai/chat/completions",
			-- secret = os.getenv("PPLX_API_KEY"),
		},
		anthropic = {
			-- endpoint = "https://api.anthropic.com/v1/messages",
			-- secret = os.getenv("ANTHROPIC_API_KEY"),
		},
	},

	-- prefix for all commands
	cmd_prefix = "Gp",
	-- optional curl parameters (for proxy, etc.)
	-- curl_params = { "--proxy", "http://X.X.X.X:XXXX" }
	curl_params = {},

	-- directory for persisting state dynamically changed by user (like model or persona)
	state_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/gp/persisted",

	-- default command agents (model + persona)
	-- name, model and system_prompt are mandatory fields
	-- to use agent for chat set chat = true, for command set command = true
	-- to remove some default agent completely set it just with the name like:
	-- agents = {  { name = "ChatGPT4" }, ... },
	agents = {
		{
			name = "ChatGPT4o",
			chat = true,
			command = false,
			-- string with model name or table with model name and parameters
			model = { model = "gpt-4o", temperature = 1.1, top_p = 1 },
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = default_chat_system_prompt,
		},
		{
			provider = "openai",
			name = "ChatGPT3-5",
			chat = true,
			command = false,
			-- string with model name or table with model name and parameters
			model = { model = "gpt-3.5-turbo", temperature = 1.1, top_p = 1 },
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = default_chat_system_prompt,
		},
		{
			provider = "copilot",
			name = "ChatCopilot",
			chat = true,
			command = false,
			-- string with model name or table with model name and parameters
			model = { model = "gpt-4", temperature = 1.1, top_p = 1 },
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = default_chat_system_prompt,
		},
		{
			provider = "googleai",
			name = "ChatGemini",
			chat = true,
			command = false,
			-- string with model name or table with model name and parameters
			model = { model = "gemini-pro", temperature = 1.1, top_p = 1 },
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = default_chat_system_prompt,
		},
		{
			provider = "pplx",
			name = "ChatPerplexityMixtral",
			chat = true,
			command = false,
			-- string with model name or table with model name and parameters
			model = { model = "mixtral-8x7b-instruct", temperature = 1.1, top_p = 1 },
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = default_chat_system_prompt,
		},
		{
			provider = "anthropic",
			name = "ChatClaude-3-Haiku",
			chat = true,
			command = false,
			-- string with model name or table with model name and parameters
			model = { model = "claude-3-haiku-20240307", temperature = 0.8, top_p = 1 },
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = default_chat_system_prompt,
		},
		{
			provider = "ollama",
			name = "ChatOllamaLlama3",
			chat = true,
			command = false,
			-- string with model name or table with model name and parameters
			model = {
				model = "llama3",
				num_ctx = 8192,
			},
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = "You are a general AI assistant.",
		},
		{
			provider = "lmstudio",
			name = "ChatLMStudio",
			chat = true,
			command = false,
			-- string with model name or table with model name and parameters
			model = {
				model = "dummy",
				temperature = 0.97,
				top_p = 1,
				num_ctx = 8192,
			},
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = "You are a general AI assistant.",
		},
		{
			provider = "openai",
			name = "CodeGPT4o",
			chat = false,
			command = true,
			-- string with model name or table with model name and parameters
			model = { model = "gpt-4o", temperature = 0.8, top_p = 1 },
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = default_code_system_prompt,
		},
		{
			provider = "openai",
			name = "CodeGPT3-5",
			chat = false,
			command = true,
			-- string with model name or table with model name and parameters
			model = { model = "gpt-3.5-turbo", temperature = 0.8, top_p = 1 },
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = default_code_system_prompt,
		},
		{
			provider = "copilot",
			name = "CodeCopilot",
			chat = false,
			command = true,
			-- string with the Copilot engine name or table with engine name and parameters if applicable
			model = { model = "gpt-4", temperature = 0.8, top_p = 1, n = 1 },
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = default_code_system_prompt,
		},
		{
			provider = "googleai",
			name = "CodeGemini",
			chat = false,
			command = true,
			-- string with model name or table with model name and parameters
			model = { model = "gemini-pro", temperature = 0.8, top_p = 1 },
			system_prompt = default_code_system_prompt,
		},
		{
			provider = "pplx",
			name = "CodePerplexityMixtral",
			chat = false,
			command = true,
			-- string with model name or table with model name and parameters
			model = { model = "mixtral-8x7b-instruct", temperature = 0.8, top_p = 1 },
			system_prompt = default_code_system_prompt,
		},
		{
			provider = "anthropic",
			name = "CodeClaude-3-Haiku",
			chat = false,
			command = true,
			-- string with model name or table with model name and parameters
			model = { model = "claude-3-haiku-20240307", temperature = 0.8, top_p = 1 },
			system_prompt = default_code_system_prompt,
		},
		{
			provider = "ollama",
			name = "CodeOllamaLlama3",
			chat = false,
			command = true,
			-- string with the Copilot engine name or table with engine name and parameters if applicable
			model = {
				model = "llama3",
				temperature = 1.9,
				top_p = 1,
				num_ctx = 8192,
			},
			-- system prompt (use this to specify the persona/role of the AI)
			system_prompt = "You are an AI working as a code editor providing answers.\n\n"
				.. "Use 4 SPACES FOR INDENTATION.\n"
				.. "Please AVOID COMMENTARY OUTSIDE OF THE SNIPPET RESPONSE.\n"
				.. "START AND END YOUR ANSWER WITH:\n\n```",
		},
	},

	-- directory for storing chat files
	chat_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/gp/chats",
	-- chat user prompt prefix
	chat_user_prefix = "💬:",
	-- chat assistant prompt prefix (static string or a table {static, template})
	-- first string has to be static, second string can contain template {{agent}}
	-- just a static string is legacy and the [{{agent}}] element is added automatically
	-- if you really want just a static string, make it a table with one element { "🤖:" }
	chat_assistant_prefix = { "🤖:", "[{{agent}}]" },
	-- chat topic generation prompt
	chat_topic_gen_prompt = "Summarize the topic of our conversation above"
		.. " in two or three words. Respond only with those words.",
	-- chat topic model (string with model name or table with model name and parameters)
	-- explicitly confirm deletion of a chat file
	chat_confirm_delete = true,
	-- conceal model parameters in chat
	chat_conceal_model_params = true,
	-- local shortcuts bound to the chat buffer
	-- (be careful to choose something which will work across specified modes)
	chat_shortcut_respond = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g><C-g>" },
	chat_shortcut_delete = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>d" },
	chat_shortcut_stop = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>s" },
	chat_shortcut_new = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>c" },
	-- default search term when using :GpChatFinder
	chat_finder_pattern = "topic ",
	-- if true, finished ChatResponder won't move the cursor to the end of the buffer
	chat_free_cursor = false,
	-- use prompt buftype for chats (:h prompt-buffer)
	chat_prompt_buf_type = false,

	-- how to display GpChatToggle or GpContext: popup / split / vsplit / tabnew
	toggle_target = "vsplit",

	-- styling for chatfinder
	-- border can be "single", "double", "rounded", "solid", "shadow", "none"
	style_chat_finder_border = "single",
	-- margins are number of characters or lines
	style_chat_finder_margin_bottom = 8,
	style_chat_finder_margin_left = 1,
	style_chat_finder_margin_right = 2,
	style_chat_finder_margin_top = 2,
	-- how wide should the preview be, number between 0.0 and 1.0
	style_chat_finder_preview_ratio = 0.5,

	-- styling for popup
	-- border can be "single", "double", "rounded", "solid", "shadow", "none"
	style_popup_border = "single",
	-- margins are number of characters or lines
	style_popup_margin_bottom = 8,
	style_popup_margin_left = 1,
	style_popup_margin_right = 2,
	style_popup_margin_top = 2,
	style_popup_max_width = 160,

	-- command config and templates bellow are used by commands like GpRewrite, GpEnew, etc.
	-- command prompt prefix for asking user for input (supports {{agent}} template variable)
	command_prompt_prefix_template = "🤖 {{agent}} ~ ",
	-- auto select command response (easier chaining of commands)
	-- if false it also frees up the buffer cursor for further editing elsewhere
	command_auto_select_response = true,

	-- templates
	template_selection = "I have the following from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}",
	template_rewrite = "I have the following from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond exclusively with the snippet that should replace the selection above.",
	template_append = "I have the following from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond exclusively with the snippet that should be appended after the selection above.",
	template_prepend = "I have the following from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond exclusively with the snippet that should be prepended before the selection above.",
	template_command = "{{command}}",

	-- https://platform.openai.com/docs/guides/speech-to-text/quickstart
	-- Whisper costs $0.006 / minute (rounded to the nearest second)
	-- by eliminating silence and speeding up the tempo of the recording
	-- we can reduce the cost by 50% or more and get the results faster
	-- directory for storing whisper files
	whisper_dir = (os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp") .. "/gp_whisper",
	-- multiplier of RMS level dB for threshold used by sox to detect silence vs speech
	-- decibels are negative, the recording is normalized to -3dB =>
	-- increase this number to pick up more (weaker) sounds as possible speech
	-- decrease this number to pick up only louder sounds as possible speech
	-- you can disable silence trimming by setting this a very high number (like 1000.0)
	whisper_silence = "1.75",
	-- whisper tempo (1.0 is normal speed)
	whisper_tempo = "1.75",
	-- The language of the input audio, in ISO-639-1 format.
	whisper_language = "en",
	-- command to use for recording can be nil (unset) for automatic selection
	-- string ("sox", "arecord", "ffmpeg") or table with command and arguments:
	-- sox is the most universal, but can have start/end cropping issues caused by latency
	-- arecord is linux only, but has no cropping issues and is faster
	-- ffmpeg in the default configuration is macos only, but can be used on any platform
	-- (see https://trac.ffmpeg.org/wiki/Capture/Desktop for more info)
	-- below is the default configuration for all three commands:
	-- whisper_rec_cmd = {"sox", "-c", "1", "--buffer", "32", "-d", "rec.wav", "trim", "0", "60:00"},
	-- whisper_rec_cmd = {"arecord", "-c", "1", "-f", "S16_LE", "-r", "48000", "-d", "3600", "rec.wav"},
	-- whisper_rec_cmd = {"ffmpeg", "-y", "-f", "avfoundation", "-i", ":0", "-t", "3600", "rec.wav"},
	whisper_rec_cmd = nil,

	-- image generation settings
	-- image prompt prefix for asking user for input (supports {{agent}} template variable)
	image_prompt_prefix_template = "🖌️ {{agent}} ~ ",
	-- image prompt prefix for asking location to save the image
	image_prompt_save = "🖌️💾 ~ ",
	-- default folder for saving images
	image_dir = (os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp") .. "/gp_images",
	-- default image agents (model + settings)
	-- to remove some default agent completely set it just with the name like:
	-- image_agents = {  { name = "DALL-E-3-1024x1792-vivid" }, ... },
	image_agents = {
		{
			name = "DALL-E-3-1024x1024-vivid",
			model = "dall-e-3",
			quality = "standard",
			style = "vivid",
			size = "1024x1024",
		},
		{
			name = "DALL-E-3-1792x1024-vivid",
			model = "dall-e-3",
			quality = "standard",
			style = "vivid",
			size = "1792x1024",
		},
		{
			name = "DALL-E-3-1024x1792-vivid",
			model = "dall-e-3",
			quality = "standard",
			style = "vivid",
			size = "1024x1792",
		},
		{
			name = "DALL-E-3-1024x1024-natural",
			model = "dall-e-3",
			quality = "standard",
			style = "natural",
			size = "1024x1024",
		},
		{
			name = "DALL-E-3-1792x1024-natural",
			model = "dall-e-3",
			quality = "standard",
			style = "natural",
			size = "1792x1024",
		},
		{
			name = "DALL-E-3-1024x1792-natural",
			model = "dall-e-3",
			quality = "standard",
			style = "natural",
			size = "1024x1792",
		},
		{
			name = "DALL-E-3-1024x1024-vivid-hd",
			model = "dall-e-3",
			quality = "hd",
			style = "vivid",
			size = "1024x1024",
		},
		{
			name = "DALL-E-3-1792x1024-vivid-hd",
			model = "dall-e-3",
			quality = "hd",
			style = "vivid",
			size = "1792x1024",
		},
		{
			name = "DALL-E-3-1024x1792-vivid-hd",
			model = "dall-e-3",
			quality = "hd",
			style = "vivid",
			size = "1024x1792",
		},
		{
			name = "DALL-E-3-1024x1024-natural-hd",
			model = "dall-e-3",
			quality = "hd",
			style = "natural",
			size = "1024x1024",
		},
		{
			name = "DALL-E-3-1792x1024-natural-hd",
			model = "dall-e-3",
			quality = "hd",
			style = "natural",
			size = "1792x1024",
		},
		{
			name = "DALL-E-3-1024x1792-natural-hd",
			model = "dall-e-3",
			quality = "hd",
			style = "natural",
			size = "1024x1792",
		},
	},

	-- example hook functions (see Extend functionality section in the README)
	hooks = {
		InspectPlugin = function(plugin, params)
			local bufnr = vim.api.nvim_create_buf(false, true)
			local copy = vim.deepcopy(plugin)
			local key = copy.config.openai_api_key
			copy.config.openai_api_key = key:sub(1, 3) .. string.rep("*", #key - 6) .. key:sub(-3)
			for provider, _ in pairs(copy.providers) do
				local s = copy.providers[provider].secret
				if s and type(s) == "string" then
					copy.providers[provider].secret = s:sub(1, 3) .. string.rep("*", #s - 6) .. s:sub(-3)
				end
			end
			local plugin_info = string.format("Plugin structure:\n%s", vim.inspect(copy))
			local params_info = string.format("Command params:\n%s", vim.inspect(params))
			local lines = vim.split(plugin_info .. "\n" .. params_info, "\n")
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
			vim.api.nvim_win_set_buf(0, bufnr)
		end,

		-- GpImplement rewrites the provided selection/range based on comments in it
		Implement = function(gp, params)
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please rewrite this according to the contained instructions."
				.. "\n\nRespond exclusively with the snippet that should replace the selection above."

			local agent = gp.get_command_agent()
			gp.info("Implementing selection with agent: " .. agent.name)

			gp.Prompt(
				params,
				gp.Target.rewrite,
				nil, -- command will run directly without any prompting for user input
				agent.model,
				template,
				agent.system_prompt
			)
		end,

		-- your own functions can go here, see README for more examples like
		-- :GpExplain, :GpUnitTests.., :GpTranslator etc.

		-- -- example of making :%GpChatNew a dedicated command which
		-- -- opens new chat with the entire current buffer as a context
		-- BufferChatNew = function(gp, _)
		-- 	-- call GpChatNew command in range mode on whole buffer
		-- 	vim.api.nvim_command("%" .. gp.config.cmd_prefix .. "ChatNew")
		-- end,

		-- -- example of adding command which opens new chat dedicated for translation
		-- Translator = function(gp, params)
		-- 	local agent = gp.get_command_agent()
		-- 	local chat_system_prompt = "You are a Translator, please translate between English and Chinese."
		-- 	gp.cmd.ChatNew(params, agent.model, chat_system_prompt)
		-- end,

		-- -- example of adding command which writes unit tests for the selected code
		-- UnitTests = function(gp, params)
		-- 	local template = "I have the following code from {{filename}}:\n\n"
		-- 		.. "```{{filetype}}\n{{selection}}\n```\n\n"
		-- 		.. "Please respond by writing table driven unit tests for the code above."
		-- 	local agent = gp.get_command_agent()
		-- 	gp.Prompt(params, gp.Target.enew, nil, agent.model, template, agent.system_prompt)
		-- end,

		-- -- example of adding command which explains the selected code
		-- Explain = function(gp, params)
		-- 	local template = "I have the following code from {{filename}}:\n\n"
		-- 		.. "```{{filetype}}\n{{selection}}\n```\n\n"
		-- 		.. "Please respond by explaining the code above."
		-- 	local agent = gp.get_chat_agent()
		-- 	gp.Prompt(params, gp.Target.popup, nil, agent.model, template, agent.system_prompt)
		-- end,
	},
}

return config

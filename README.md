# Gp (GPT prompt) plugin for Neovim
![GitHub](https://img.shields.io/github/license/robitx/gp.nvim)
![GitHub Repo stars](https://img.shields.io/github/stars/Robitx/gp.nvim)
![GitHub closed issues](https://img.shields.io/github/issues-closed/Robitx/gp.nvim)
![GitHub closed pull requests](https://img.shields.io/github/issues-pr-closed/Robitx/gp.nvim)
![GitHub contributors](https://img.shields.io/github/contributors-anon/Robitx/gp.nvim)



Gp.nvim provides you ChatGPT like sessions and instructable text/code operations in your favorite editor.

<p align="left">
<img src="https://github.com/Robitx/gp.nvim/assets/8431097/cb288094-2308-42d6-9060-4eb21b3ba74c" width="49%">
<img src="https://github.com/Robitx/gp.nvim/assets/8431097/c538f0a2-4667-444e-8671-13f8ea261be1" width="49%">
</p>

### [Here is an older 5 minute example of using the plugin (needs update)]( https://www.youtube.com/watch?v=wPDcBnQgNCc )

## Goals and Features

The goal is to extend Neovim with the **power of GPT models in a simple unobtrusive extensible way.**  
Trying to keep things as native as possible - reusing and integrating well with the natural features of (Neo)vim.

-   **Streaming responses**
    -   no spinner wheel and waiting for the full answer
    -   response generation can be canceled half way through
    -   properly working undo (response can be undone with a single `u`)
-   **Infinitely extensible** via hook functions specified as part of the config
    -   hooks have access to everything in the plugin and are automatically registered as commands
    -   see [Configuration](#4-configuration) and [Extend functionality](#extend-functionality) sections for details
-   **Minimum dependencies** (`neovim`, `curl`, `grep` and optionally `sox`)
    -   zero dependencies on other lua plugins to minimize chance of breakage
-   **ChatGPT like sessions**
    -   just good old neovim buffers formated as markdown with autosave and few buffer bound shortcuts
    -   last chat also quickly accessible via toggable popup window
    -   chat finder - management popup for searching, previewing, deleting and opening chat sessions
-   **Instructable text/code operations**
    -   templating mechanism to combine user instructions, selections etc into the gpt query
    -   multimodal - same command works for normal/insert mode, with selection or a range
    -   many possible output targets - rewrite, prepend, append, new buffer, popup
    -   non interactive command mode available for common repetitive tasks implementable as simple hooks  
        (explain something in a popup window, write unit tests for selected code into a new buffer,  
        finish selected code based on comments in it, etc.)
    -   custom instructions per repository with `.gp.md` file  
        (instruct gpt to generate code using certain libs, packages, conventions and so on)
-   **Speech to text support**
    -   a mouth is 2-4x faster than fingers when it comes to outputting words - use it where it makes sense  
        (dicating comments and notes, asking gpt questions, giving instructions for code operations, ..)

## Install

### 1. Install the plugin with your preferred package manager:

```lua
-- lazy.nvim
{
	"robitx/gp.nvim",
	config = function()
		require("gp").setup()

		-- or setup with your own config (see Install > Configuration in Readme)
		-- require("gp").setup(conf)

        	-- shortcuts might be setup here (see Usage > Shortcuts in Readme)
	end,
}
```

```lua
-- packer.nvim
use({
    "robitx/gp.nvim",
    config = function()
        require("gp").setup()

	-- or setup with your own config (see Install > Configuration in Readme)
	-- require("gp").setup(conf)

        -- shortcuts might be setup here (see Usage > Shortcuts in Readme)
    end,
})
```

### 2. OpenAI API key

Make sure you have OpenAI API key. [Get one here](https://platform.openai.com/account/api-keys)
and use it in the [config](#4-configuration) (or **setup env `OPENAI_API_KEY`**).

Also consider setting up [usage limits](https://platform.openai.com/account/billing/limits) so you won't get suprised at the end of the month.

### 3. Dependencies

The core plugin only needs `curl` installed to make calls to OpenAI API and `grep` for ChatFinder. So Linux, BSD and Mac OS should be covered.

Voice commands (`:GpWhisper*`) depend on `SoX` (Sound eXchange) to handle audio recording and processing:

-   Mac OS: `brew install sox`
-   Ubuntu/Debian: `apt-get install sox`
-   Arch Linux: `pacman -S sox`
-   Redhat/CentOS: `yum install sox`
-   NixOS: `nix-env -i sox`

### 4. Configuration

Here are the default values:

````lua
local conf = {
	-- required openai api key
	openai_api_key = os.getenv("OPENAI_API_KEY"),
	-- api endpoint (you can change this to azure endpoint)
	openai_api_endpoint = "https://api.openai.com/v1/chat/completions",
	-- openai_api_endpoint = "https://$URL.openai.azure.com/openai/deployments/{{model}}/chat/completions?api-version=2023-03-15-preview",
	-- prefix for all commands
	cmd_prefix = "Gp",

	-- directory for storing chat files
	chat_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/gp/chats",
	-- chat model (string with model name or table with model name and parameters)
	chat_model = { model = "gpt-3.5-turbo-16k", temperature = 1.1, top_p = 1 },
	-- chat model system prompt (use this to specify the persona/role of the AI)
	chat_system_prompt = "You are a general AI assistant.",
	-- chat custom instructions (not visible in the chat but prepended to model prompt)
	chat_custom_instructions = "The user provided the additional info about how they would like you to respond:\n\n"
		.. "- If you're unsure don't guess and say you don't know instead.\n"
		.. "- Ask question if you need clarification to provide better answer.\n"
		.. "- Think deeply and carefully from first principles step by step.\n"
		.. "- Zoom out first to see the big picture and then zoom in to details.\n"
		.. "- Use Socratic method to improve your thinking and coding skills.\n"
		.. "- Don't elide any code from your output if the answer requires coding.\n"
		.. "- Take a deep breath; You've got this!\n",
	-- chat user prompt prefix
	chat_user_prefix = "🗨:",
	-- chat assistant prompt prefix
	chat_assistant_prefix = "🤖:",
	-- chat topic generation prompt
	chat_topic_gen_prompt = "Summarize the topic of our conversation above"
		.. " in two or three words. Respond only with those words.",
	-- chat topic model (string with model name or table with model name and parameters)
	chat_topic_gen_model = "gpt-3.5-turbo-16k",
	-- explicitly confirm deletion of a chat file
	chat_confirm_delete = true,
	-- conceal model parameters in chat
	chat_conceal_model_params = true,
	-- local shortcuts bound to the chat buffer
	-- (be careful to choose something which will work across specified modes)
	chat_shortcut_respond = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g><C-g>" },
	chat_shortcut_delete = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>d" },
	chat_shortcut_new = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g>n" },

	-- command config and templates bellow are used by commands like GpRewrite, GpEnew, etc.
	-- command prompt prefix for asking user for input
	command_prompt_prefix = "🤖 ~ ",
	-- command model (string with model name or table with model name and parameters)
	command_model = { model = "gpt-3.5-turbo-16k", temperature = 1.1, top_p = 1 },
	-- command system prompt
	command_system_prompt = "You are an AI that strictly generates just the formated final code.",

	-- templates
	template_selection = "I have the following code from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}",
	template_rewrite = "I have the following code from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond just with the snippet of code that should be inserted.",
	template_append = "I have the following code from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond just with the snippet of code that should be appended after the code above.",
	template_prepend = "I have the following code from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond just with the snippet of code that should be prepended before the code above.",
	template_command = "{{command}}",

	-- https://platform.openai.com/docs/guides/speech-to-text/quickstart
	-- Whisper costs $0.006 / minute (rounded to the nearest second)
	-- by eliminating silence and speeding up the tempo of the recording
	-- we can reduce the cost by 50% or more and get the results faster
	-- directory for storing whisper files
	whisper_dir = "/tmp/gp_whisper",
	-- multiplier of RMS level dB for threshold used by sox to detect silence vs speech
	-- decibels are negative, the recording is normalized to -3dB =>
	-- increase this number to pick up more (weaker) sounds as possible speech
	-- decrease this number to pick up only louder sounds as possible speech
	-- you can disable silence trimming by setting this a very high number (like 1000.0)
	whisper_silence = "1.75",
	-- whisper max recording time (mm:ss)
	whisper_max_time = "05:00",
	-- whisper tempo (1.0 is normal speed)
	whisper_tempo = "1.75",

	-- example hook functions (see Extend functionality section in the README)
	hooks = {
		InspectPlugin = function(plugin, params)
			print(string.format("Plugin structure:\n%s", vim.inspect(plugin)))
			print(string.format("Command params:\n%s", vim.inspect(params)))
		end,

		-- GpImplement rewrites the provided selection/range based on comments in the code
		Implement = function(gp, params)
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please rewrite this code according to the comment instructions."
				.. "\n\nRespond only with the snippet of finalized code:"

			gp.Prompt(
				params,
				gp.Target.rewrite,
				nil, -- command will run directly without any prompting for user input
				gp.config.command_model,
				template,
				gp.config.command_system_prompt
			)
		end,

		-- your own functions can go here, see README for more examples like
		-- :GpExplain, :GpUnitTests.., :GpBetterChatNew, ..

	},
}

...

-- call setup on your config
require("gp").setup(conf)

-- shortcuts might be setup here (see Usage > Shortcuts in Readme)
````

## Usage

### Commands

-   Have ChatGPT experience directly in neovim:
    -   `:GpChatNew` - open fresh chat in the current window  
        (either empty or with the visual selection or specified range as a context)
    -   `:GpChatPaste` - paste the selection or specified range to the latest chat
        (simplifies adding code from multiple files into a single chat buffer)
    -   `:GpChatToggle` - open chat in toggleable popup window  
        (the last active chat or a fresh one with selection or a range as a context)
    -   `:GpChatFinder` - open a dialog to search through chats
    -   `:GpChatRespond` - request new gpt response for the current chat
    -   `:GpChatRespond N` - request new gpt response with only last N messages as a context  
	(using everything from the end up to Nth instance of `🗨:..` => `N=1` is like asking a question in a new chat)
	
    -   `:GpChatDelete` - delete the current chat
-   Ask GPT and get response to the specified output:

    -   `:GpRewrite` - answer replaces the current line, visual selection or range
    -   `:GpAppend` - answers after the current line, visual selection or range
    -   `:GpPrepend` - answers before the current line, selection or range
    -   `:GpEnew` - answers into new buffer
    -   `:GpPopup` - answers into pop up window
    -   `:GpImplement` - default example hook command for finishing the code  
        based on comments provided in visual selection or specified range

    all these command work either:

    -   as pure user commands without any other context in normal/insert mode
    -   with current selection (using whole lines) as a context in visual/Visual mode
    -   with specified range (such as `%` for the entire current buffer => `:%GpRewrite`)

-   Voice commands transcribed by Whisper API:
    -   `:GpWhisper` - transcription replaces the current line, visual selection or range
    -   `:GpWhisperRewrite` - answer replaces the current line, visual selection or range
    -   `:GpWhisperAppend` - answers after the current line, visual selection or range
    -   `:GpWhisperPrepend` - answers before the current line, selection or range
    -   `:GpWhisperEnew` - answers into new buffer
    -   `:GpWhisperPopup` - answers into pop up window
-   To stop the stream of currently running gpt response you can use `:GpStop`
-   Run your own custom hook commands:
    -   `:GpInspectPlugin` - inspect GPT prompt plugin object

### Custom instructions per repository
You can make `.gp.md` (markdown) file in a root of a repository and commands such as `:GpRewrite`, `:GpAppend` will respect instructions provided in this file (works better with gpt4, gpt 3.5 doesn't always listen to system commands). For example:
``` md
Use ‎C++17.
Use Testify library when writing Go tests.
Use Early return/Guard Clauses pattern to avoid excessive nesting.
...
```

### Shortcuts

There are no default global shortcuts to mess with your own config. Bellow are examples for you to adjust or just use directly.

#### Native

You can use the good old `vim.keymap.set` and paste the following after `require("gp").setup(conf)` call
(or anywhere you keep shortcuts if you want them at one place).

```lua
local function keymapOptions(desc)
    return {
        noremap = true,
        silent = true,
        nowait = true,
        desc = "GPT prompt " .. desc,
    }
end

-- Chat commands
vim.keymap.set({"n", "i"}, "<C-g>c", "<cmd>GpChatNew<cr>", keymapOptions("New Chat"))
vim.keymap.set({"n", "i"}, "<C-g>t", "<cmd>GpChatToggle<cr>", keymapOptions("Toggle Popup Chat"))
vim.keymap.set({"n", "i"}, "<C-g>f", "<cmd>GpChatFinder<cr>", keymapOptions("Chat Finder"))

vim.keymap.set("v", "<C-g>c", ":<C-u>'<,'>GpChatNew<cr>", keymapOptions("Visual Chat New"))
vim.keymap.set("v", "<C-g>v", ":<C-u>'<,'>GpChatPaste<cr>", keymapOptions("Visual Chat Paste"))
vim.keymap.set("v", "<C-g>t", ":<C-u>'<,'>GpChatToggle<cr>", keymapOptions("Visual Popup Chat"))

-- Prompt commands
vim.keymap.set({"n", "i"}, "<C-g>r", "<cmd>GpRewrite<cr>", keymapOptions("Inline Rewrite"))
vim.keymap.set({"n", "i"}, "<C-g>a", "<cmd>GpAppend<cr>", keymapOptions("Append"))
vim.keymap.set({"n", "i"}, "<C-g>b", "<cmd>GpPrepend<cr>", keymapOptions("Prepend"))
vim.keymap.set({"n", "i"}, "<C-g>e", "<cmd>GpEnew<cr>", keymapOptions("Enew"))
vim.keymap.set({"n", "i"}, "<C-g>p", "<cmd>GpPopup<cr>", keymapOptions("Popup"))

vim.keymap.set("v", "<C-g>r", ":<C-u>'<,'>GpRewrite<cr>", keymapOptions("Visual Rewrite"))
vim.keymap.set("v", "<C-g>a", ":<C-u>'<,'>GpAppend<cr>", keymapOptions("Visual Append"))
vim.keymap.set("v", "<C-g>b", ":<C-u>'<,'>GpPrepend<cr>", keymapOptions("Visual Prepend"))
vim.keymap.set("v", "<C-g>e", ":<C-u>'<,'>GpEnew<cr>", keymapOptions("Visual Enew"))
vim.keymap.set("v", "<C-g>p", ":<C-u>'<,'>GpPopup<cr>", keymapOptions("Visual Popup"))


vim.keymap.set({"n", "i", "v", "x"}, "<C-g>s", "<cmd>GpStop<cr>", keymapOptions("Stop"))


-- optional Whisper commands
vim.keymap.set({"n", "i"}, "<C-g>w", "<cmd>GpWhisper<cr>", keymapOptions("Whisper"))
vim.keymap.set({"n", "i"}, "<C-g>R", "<cmd>GpWhisperRewrite<cr>", keymapOptions("Inline Rewrite"))
vim.keymap.set({"n", "i"}, "<C-g>A", "<cmd>GpWhisperAppend<cr>", keymapOptions("Append"))
vim.keymap.set({"n", "i"}, "<C-g>B", "<cmd>GpWhisperPrepend<cr>", keymapOptions("Prepend"))
vim.keymap.set({"n", "i"}, "<C-g>E", "<cmd>GpWhisperEnew<cr>", keymapOptions("Enew"))
vim.keymap.set({"n", "i"}, "<C-g>P", "<cmd>GpWhisperPopup<cr>", keymapOptions("Popup"))

vim.keymap.set("v", "<C-g>w", ":<C-u>'<,'>GpWhisper<cr>", keymapOptions("Whisper"))
vim.keymap.set("v", "<C-g>R", ":<C-u>'<,'>GpWhisperRewrite<cr>", keymapOptions("Visual Rewrite"))
vim.keymap.set("v", "<C-g>A", ":<C-u>'<,'>GpWhisperAppend<cr>", keymapOptions("Visual Append"))
vim.keymap.set("v", "<C-g>B", ":<C-u>'<,'>GpWhisperPrepend<cr>", keymapOptions("Visual Prepend"))
vim.keymap.set("v", "<C-g>E", ":<C-u>'<,'>GpWhisperEnew<cr>", keymapOptions("Visual Enew"))
vim.keymap.set("v", "<C-g>P", ":<C-u>'<,'>GpWhisperPopup<cr>", keymapOptions("Visual Popup"))
```

#### Whichkey

Or go more fancy by using [which-key.nvim](https://github.com/folke/which-key.nvim) plugin:

```lua
-- VISUAL mode mappings
-- s, x, v modes are handled the same way by which_key
require("which-key").register({
    -- ...
	["<C-g>"] = {
		c = { ":<C-u>'<,'>GpChatNew<cr>", "Visual Chat New" },
		v = { ":<C-u>'<,'>GpChatPaste<cr>", "Visual Chat Paste" },
		t = { ":<C-u>'<,'>GpChatToggle<cr>", "Visual Popup Chat" },

		r = { ":<C-u>'<,'>GpRewrite<cr>", "Visual Rewrite" },
		a = { ":<C-u>'<,'>GpAppend<cr>", "Visual Append" },
		b = { ":<C-u>'<,'>GpPrepend<cr>", "Visual Prepend" },
		e = { ":<C-u>'<,'>GpEnew<cr>", "Visual Enew" },
		p = { ":<C-u>'<,'>GpPopup<cr>", "Visual Popup" },
		s = { "<cmd>GpStop<cr>", "Stop" },


                -- optional Whisper commands
		w = { ":<C-u>'<,'>GpWhisper<cr>", "Whisper" },
		R = { ":<C-u>'<,'>GpWhisperRewrite<cr>", "Whisper Visual Rewrite" },
		A = { ":<C-u>'<,'>GpWhisperAppend<cr>", "Whisper Visual Append" },
		B = { ":<C-u>'<,'>GpWhisperPrepend<cr>", "Whisper Visual Prepend" },
		E = { ":<C-u>'<,'>GpWhisperEnew<cr>", "Whisper Visual Enew" },
		P = { ":<C-u>'<,'>GpWhisperPopup<cr>", "Whisper Visual Popup" },
	},
    -- ...
}, {
	mode = "v", -- VISUAL mode
	prefix = "",
	buffer = nil,
	silent = true,
	noremap = true,
	nowait = true,
})

-- NORMAL mode mappings
require("which-key").register({
    -- ...
	["<C-g>"] = {
		c = { "<cmd>GpChatNew<cr>", "New Chat" },
		t = { "<cmd>GpChatToggle<cr>", "Toggle Popup Chat" },
		f = { "<cmd>GpChatFinder<cr>", "Chat Finder" },

		r = { "<cmd>GpRewrite<cr>", "Inline Rewrite" },
		a = { "<cmd>GpAppend<cr>", "Append" },
		b = { "<cmd>GpPrepend<cr>", "Prepend" },
		e = { "<cmd>GpEnew<cr>", "Enew" },
		p = { "<cmd>GpPopup<cr>", "Popup" },
		s = { "<cmd>GpStop<cr>", "Stop" },

                -- optional Whisper commands
		w = { "<cmd>GpWhisper<cr>", "Whisper" },
		R = { "<cmd>GpWhisperRewrite<cr>", "Whisper Inline Rewrite" },
		A = { "<cmd>GpWhisperAppend<cr>", "Whisper Append" },
		B = { "<cmd>GpWhisperPrepend<cr>", "Whisper Prepend" },
		E = { "<cmd>GpWhisperEnew<cr>", "Whisper Enew" },
		P = { "<cmd>GpWhisperPopup<cr>", "Whisper Popup" },
	},
    -- ...
}, {
	mode = "n", -- NORMAL mode
	prefix = "",
	buffer = nil,
	silent = true,
	noremap = true,
	nowait = true,
})

-- INSERT mode mappings
require("which-key").register({
    -- ...
	["<C-g>"] = {
		c = { "<cmd>GpChatNew<cr>", "New Chat" },
		t = { "<cmd>GpChatToggle<cr>", "Toggle Popup Chat" },
		f = { "<cmd>GpChatFinder<cr>", "Chat Finder" },

		r = { "<cmd>GpRewrite<cr>", "Inline Rewrite" },
		a = { "<cmd>GpAppend<cr>", "Append" },
		b = { "<cmd>GpPrepend<cr>", "Prepend" },
		e = { "<cmd>GpEnew<cr>", "Enew" },
		p = { "<cmd>GpPopup<cr>", "Popup" },
		s = { "<cmd>GpStop<cr>", "Stop" },

                -- optional Whisper commands
		w = { "<cmd>GpWhisper<cr>", "Whisper" },
		R = { "<cmd>GpWhisperRewrite<cr>", "Whisper Inline Rewrite" },
		A = { "<cmd>GpWhisperAppend<cr>", "Whisper Append" },
		B = { "<cmd>GpWhisperPrepend<cr>", "Whisper Prepend" },
		E = { "<cmd>GpWhisperEnew<cr>", "Whisper Enew" },
		P = { "<cmd>GpWhisperPopup<cr>", "Whisper Popup" },
	},
    -- ...
}, {
	mode = "i", -- INSERT mode
	prefix = "",
	buffer = nil,
	silent = true,
	noremap = true,
	nowait = true,
})
```

## Extend functionality

You can extend/override the plugin functionality with your own, by putting functions into `config.hooks`.
Hooks have access to everything (see `InspectPlugin` example in defaults) and are
automatically registered as commands (`GpInspectPlugin`).

Here are some more examples:

-   `:GpUnitTests`

    ````lua
    -- example of adding command which writes unit tests for the selected code
    UnitTests = function(gp, params)
        local template = "I have the following code from {{filename}}:\n\n"
            .. "```{{filetype}}\n{{selection}}\n```\n\n"
            .. "Please respond by writing table driven unit tests for the code above."
        gp.Prompt(params, gp.Target.enew, nil, gp.config.command_model,
            template, gp.config.command_system_prompt)
    end,
    ````

-   `:GpExplain`

    ````lua
    -- example of adding command which explains the selected code
    Explain = function(gp, params)
        local template = "I have the following code from {{filename}}:\n\n"
            .. "```{{filetype}}\n{{selection}}\n```\n\n"
            .. "Please respond by explaining the code above."
        gp.Prompt(params, gp.Target.popup, nil, gp.config.command_model,
            template, gp.config.chat_system_prompt)
    end,
    ````

-   `:GpCodeReview`

    ````lua
    -- example of usig enew as a function specifying type for the new buffer
    CodeReview = function(gp, params)
        local template = "I have the following code from {{filename}}:\n\n"
            .. "```{{filetype}}\n{{selection}}\n```\n\n"
            .. "Please analyze for code smells and suggest improvements."
            gp.Prompt(params, gp.Target.enew("markdown"), nil, gp.config.command_model,
                template, gp.config.command_system_prompt)
        end
    ````

-   `:GpBufferChatNew`

    ```lua
    -- example of making :%GpChatNew a dedicated command which
    -- opens new chat with the entire current buffer as a context
    BufferChatNew = function(gp, _)
        -- call GpChatNew command in range mode on whole buffer
        vim.api.nvim_command("%" .. gp.config.cmd_prefix .. "ChatNew")
    end,
    ```

-   `:GpBetterChatNew`

    ```lua
    -- example of adding a custom chat command with non-default parameters
    -- (configured default might be gpt-3 and sometimes you might want to use gpt-4)
    BetterChatNew = function(gp, params)
        local chat_model = { model = "gpt-4", temperature = 0.7, top_p = 1 }
        local chat_system_prompt = "You are a general AI assistant."
        gp.cmd.ChatNew(params, chat_model, chat_system_prompt)
    end,
    ```

The raw plugin text editing method `Prompt` has seven aprameters:

-   `params` is a [table passed to neovim user commands](https://neovim.io/doc/user/lua-guide.html#lua-guide-commands-create), `Prompt` currently uses:
	-   `range, line1, line2` to work with [ranges](https://neovim.io/doc/user/usr_10.html#10.3)
 	-   `args` so instructions can be passed directly after command (`:GpRewrite something something`)
 
    ```lua
    params = {
          args = "",
          bang = false,
          count = -1,
          fargs = {},
          line1 = 1352,
          line2 = 1352,
          mods = "",
          name = "GpChatNew",
          range = 0,
          reg = "",
          smods = {
                browse = false,
                confirm = false,
                emsg_silent = false,
                hide = false,
                horizontal = false,
                keepalt = false,
                keepjumps = false,
                keepmarks = false,
                keeppatterns = false,
                lockmarks = false,
                noautocmd = false,
                noswapfile = false,
                sandbox = false,
                silent = false,
                split = "",
                tab = -1,
                unsilent = false,
                verbose = -1,
                vertical = false
          }
    }
    ```
-   `target` specifying where to direct GPT response

    -   enew can be used as a function so you can pass in a filetype
        for the new buffer (`enew/enew()/enew("markdown")/..`)

    ```lua
    M.Target = {
        rewrite = 0, -- for replacing the selection, range or the current line
        append = 1, -- for appending after the selection, range or the current line
        prepend = 2, -- for prepending before the selection, range or the current line
        popup = 3, -- for writing into the popup window

        -- for writing into a new buffer
        ---@param filetype nil | string # nil = same as the original buffer
        ---@return table # a table with type=4 and filetype=filetype
        enew = function(filetype)
            return { type = 4, filetype = filetype }
        end,
    }
    ```

-   `prompt`
    -   string used similarly as bash/zsh prompt in terminal, when plugin asks for user command to gpt.
    -   if `nil`, user is not asked to provide input (for specific predefined commands - document this, explain that, write tests ..)
    -   simple `🤖 ~ ` might be used or you could use different msg to convey info about the method which is called  
        (`🤖 rewrite ~`, `🤖 popup ~`, `🤖 enew ~`, `🤖 inline ~`, etc.)
-   `model`
    -   see [gpt model overview](https://platform.openai.com/docs/models/overview)
-   `template`

    -   template of the user message send to gpt
    -   string can include variables bellow:

        | name            | Description                       |
        | --------------- | --------------------------------- |
        | `{{filetype}}`  | filetype of the current buffer    |
        | `{{selection}}` | last or currently selected text   |
        | `{{command}}`   | instructions provided by the user |

-   `system_template`
    -   See [gpt api intro](https://platform.openai.com/docs/guides/chat/introduction)
-   `whisper`
    -   optional string serving as a default for input prompt (for example generated from speech by Whisper)

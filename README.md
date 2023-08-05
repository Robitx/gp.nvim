# Gp (GPT prompt) plugin for Neovim

Gp.nvim provides you ChatGPT like sessions and instructable text/code operations in your favorite editor.

<p align="left">
<img src="https://github.com/Robitx/gp.nvim/assets/8431097/cb288094-2308-42d6-9060-4eb21b3ba74c" width="49%">
<img src="https://github.com/Robitx/gp.nvim/assets/8431097/c538f0a2-4667-444e-8671-13f8ea261be1" width="49%">
</p>

### [Here is the full 5 minute example of using the plugin](https://youtu.be/UBc5dL1qBrc)

## Changelog
### !! Version 1.x.x brings a breaking change !!

The commands now work with [ranges](https://neovim.io/doc/user/usr_10.html#10.3) and the commands with `Visual` prefix were dropped.

Specifically the commands`:GpChatNew`, `:GpRewrite`, `:GpAppend`, `:GpPrepend`, `:GpEnew`, `:GpPopup` and their shortcuts now work across modes, either:
- as pure user commands without context in normal/insert mode
- with current selection (using whole lines) as a context in visual/Visual mode
- with specified range (such as `%` for the entire current buffer => `:%GpRewrite`)

Please update your shortcuts if you use them.

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
and use it in the [config](#configuration) (or **setup env `OPENAI_API_KEY`**).

Also consider setting up [usage limits](https://platform.openai.com/account/billing/limits) so you won't get suprised at the end of the month.

### 3. Dependencies
The plugin only needs `curl` installed to make calls to OpenAI API and `grep` for ChatFinder. So Linux / BSD / Mac OS should be covered.

### 4. Configuration

Here are the default values:

```lua
local conf = {
	-- required openai api key
	openai_api_key = os.getenv("OPENAI_API_KEY"),
	-- prefix for all commands
	cmd_prefix = "Gp",

	-- directory for storing chat files
	chat_dir = vim.fn.stdpath("data"):gsub("/$", "") .. "/gp/chats",
	-- chat model (string with model name or table with model name and parameters)
	chat_model = { model = "gpt-3.5-turbo-16k", temperature = 0.7, top_p = 1 },
	-- chat model system prompt
	chat_system_prompt = "You are a general AI assistant.",
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

	-- command config and templates bellow are used by commands like GpRewrite, GpEnew, etc.
	-- command prompt prefix for asking user for input
	command_prompt_prefix = "🤖 ~ ",
	-- command model (string with model name or table with model name and parameters)
	command_model = { model = "gpt-3.5-turbo-16k", temperature = 0.7, top_p = 1 },
	-- command system prompt
	command_system_prompt = "You are an AI that strictly generates just the formated final code.",

	-- templates
	template_selection = "I have the following code from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}",
	template_rewrite = "I have the following code from {{filename}}:"
		.. "\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond just with the snippet of code that should be inserted.",
	template_command = "{{command}}",

	-- example hook functions (see Extend functionality section in the README)
	hooks = {
		InspectPlugin = function(plugin, params)
			print(string.format("Plugin structure:\n%s", vim.inspect(plugin)))
			print(string.format("Command params:\n%s", vim.inspect(params)))
		end,

		-- GpImplement finishes the provided selection/range based on comments in the code
		Implement = function(gp, params)
			local template = "I have the following code from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please finish the code above according to comment instructions."
				.. "\n\nRespond just with the snippet of code that should be inserted."

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
```

## Usage

### Commands
- Have ChatGPT experience directly in neovim:
	- `:GpChatNew` - open fresh chat - either empty or with the visual selection or specified range as a context
	- `:GpChatFinder` - open a dialog to search through chats
	- `:GpChatRespond` - request new gpt response for the current chat
  	- `:GpChatDelete` - delete the current chat
- Ask GPT and get response to the specified output:
	- `:GpRewrite` - answer replaces the current line, visual selection or range
	- `:GpAppend` - answers after the current line, visual selection or range
	- `:GpPrepend` - answers before the current line, selection or range
	- `:GpEnew` - answers into new buffer
	- `:GpPopup` - answers into pop up window
	- `:GpImplement` - default example hook command for finishing the code
	  in visual selection or range based on provided comments

  all these command work either:
    - as pure user commands without any other context in normal/insert mode
    - with current selection (using whole lines) as a context in visual/Visual mode
    - with specified range (such as `%` for the entire current buffer => `:%GpRewrite`)
- To stop the stream of currently running gpt response you can use `:GpStop`
- Run your own custom hook commands:
    - `:GpInspectPlugin` - inspect GPT prompt plugin object

### Shortcuts

There are no default global shortcuts to mess with your own config. Bellow are examples for you to adjust or just use directly.

#### Native

You can use the good old `vim.keymap.set` and paste the following after `require("gp").setup(conf)` call 
(or anywhere you keep shortcuts if you want them at one place).
``` lua
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
vim.keymap.set({"n", "i"}, "<C-g>f", "<cmd>GpChatFinder<cr>", keymapOptions("Chat Finder"))

-- Prompt commands
vim.keymap.set({"n", "i"}, "<C-g>r", "<cmd>GpRewrite<cr>", keymapOptions("Inline Rewrite"))
vim.keymap.set({"n", "i"}, "<C-g>a", "<cmd>GpAppend<cr>", keymapOptions("Append"))
vim.keymap.set({"n", "i"}, "<C-g>b", "<cmd>GpPrepend<cr>", keymapOptions("Prepend"))
vim.keymap.set({"n", "i"}, "<C-g>e", "<cmd>GpEnew<cr>", keymapOptions("Enew"))
vim.keymap.set({"n", "i"}, "<C-g>p", "<cmd>GpPopup<cr>", keymapOptions("Popup"))

-- Visual commands
vim.keymap.set("v", "<C-g>c", ":<C-u>'<,'>GpChatNew<cr>", keymapOptions("Visual Chat New"))
vim.keymap.set("v", "<C-g>r", ":<C-u>'<,'>GpRewrite<cr>", keymapOptions("Visual Rewrite"))
vim.keymap.set("v", "<C-g>a", ":<C-u>'<,'>GpAppend<cr>", keymapOptions("Visual Append"))
vim.keymap.set("v", "<C-g>b", ":<C-u>'<,'>GpPrepend<cr>", keymapOptions("Visual Prepend"))
vim.keymap.set("v", "<C-g>e", ":<C-u>'<,'>GpEnew<cr>", keymapOptions("Visual Enew"))
vim.keymap.set("v", "<C-g>p", ":<C-u>'<,'>GpPopup<cr>", keymapOptions("Visual Popup"))

vim.keymap.set({"n", "i", "v", "x"}, "<C-g>s", "<cmd>GpStop<cr>", keymapOptions("Stop"))
```

#### Whichkey

Or go more fancy by using [which-key.nvim](https://github.com/folke/which-key.nvim) plugin:
``` lua
-- VISUAL mode mappings
-- s, x, v modes are handled the same way by which_key
require("which-key").register({
    -- ...
	["<C-g>"] = {
		c = { ":<C-u>'<,'>GpChatNew<cr>", "Visual Chat New" },

		r = { ":<C-u>'<,'>GpRewrite<cr>", "Visual Rewrite" },
		a = { ":<C-u>'<,'>GpAppend<cr>", "Visual Append" },
		b = { ":<C-u>'<,'>GpPrepend<cr>", "Visual Prepend" },
		e = { ":<C-u>'<,'>GpEnew<cr>", "Visual Enew" },
		p = { ":<C-u>'<,'>GpPopup<cr>", "Visual Popup" },
		s = { "<cmd>GpStop<cr>", "Stop" },
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
		f = { "<cmd>GpChatFinder<cr>", "Chat Finder" },

		r = { "<cmd>GpRewrite<cr>", "Inline Rewrite" },
		a = { "<cmd>GpAppend<cr>", "Append" },
		b = { "<cmd>GpPrepend<cr>", "Prepend" },
		e = { "<cmd>GpEnew<cr>", "Enew" },
		p = { "<cmd>GpPopup<cr>", "Popup" },
		s = { "<cmd>GpStop<cr>", "Stop" },
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
		f = { "<cmd>GpChatFinder<cr>", "Chat Finder" },

		r = { "<cmd>GpRewrite<cr>", "Inline Rewrite" },
		a = { "<cmd>GpAppend<cr>", "Append" },
		b = { "<cmd>GpPrepend<cr>", "Prepend" },
		e = { "<cmd>GpEnew<cr>", "Enew" },
		p = { "<cmd>GpPopup<cr>", "Popup" },
		s = { "<cmd>GpStop<cr>", "Stop" },
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
- `:GpBufferChatNew`
    ``` lua
    -- example of making :%GpChatNew a dedicated command which
    -- opens new chat with the entire current buffer as a context
    BufferChatNew = function(gp, _)
        -- call GpChatNew command in range mode on whole buffer
        vim.api.nvim_command("%" .. gp.config.cmd_prefix .. "ChatNew")
    end,
    ```

- `:GpBetterChatNew`
    ``` lua
    -- example of adding a custom chat command with non-default parameters
    -- (configured default might be gpt-3 and sometimes you might want to use gpt-4)
    BetterChatNew = function(gp, params)
        local chat_model = { model = "gpt-4", temperature = 0.7, top_p = 1 }
        local chat_system_prompt = "You are a general AI assistant."
        gp.cmd.ChatNew(params, chat_model, chat_system_prompt)
    end,
    ```

- `:GpUnitTests`
    ``` lua
    -- example of adding command which writes unit tests for the selected code
    UnitTests = function(gp, params)
        local template = "I have the following code from {{filename}}:\n\n"
            .. "```{{filetype}}\n{{selection}}\n```\n\n"
            .. "Please respond by writing table driven unit tests for the code above."
        gp.Prompt(params, gp.Target.enew, nil, gp.config.command_model,
            template, gp.config.command_system_prompt)
    end,
    ```

- `:GpExplain`
    ``` lua
    -- example of adding command which explains the selected code
    Explain = function(gp, params)
        local template = "I have the following code from {{filename}}:\n\n"
            .. "```{{filetype}}\n{{selection}}\n```\n\n"
            .. "Please respond by explaining the code above."
        gp.Prompt(params, gp.Target.popup, nil, gp.config.command_model,
            template, gp.config.chat_system_prompt)
    end,
    ```

The raw plugin text editing method `Prompt`  has six aprameters:
- `params` is a [table passed to neovim user commands](https://neovim.io/doc/user/lua-guide.html#lua-guide-commands-create), `Prompt` currently uses `range, line1, line2` to work with [ranges](https://neovim.io/doc/user/usr_10.html#10.3)
    ``` lua
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
- `target` specifying where to direct GPT response
    ``` lua
    M.target = {
        replace = 0, -- for replacing the selection or the current line
        append = 1, -- for appending after the selection or the current line
        prepend = 2, -- for prepending before the selection or the current line
        enew = 3, -- for writing into the new buffer
        popup = 4, -- for writing into the popup window
    }
    ```
- `prompt`
	- string used similarly as bash/zsh prompt in terminal, when plugin asks for user command to gpt.
	- if `nil`, user is not asked to provide input (for specific predefined commands - document this, explain that, write tests ..)
	- simple `🤖 ~ ` might be used or you could use different msg to convey info about the method which is called  
	  (`🤖 rewrite ~`, `🤖 popup ~`, `🤖 enew ~`, `🤖 inline ~`, etc.)
- `model`
    - see [gpt model overview](https://platform.openai.com/docs/models/overview)
- `template`
	- template of the user message send to gpt
	- string can include variables bellow:  
	 
		| name      | Description |
		|--------------|----------|
		| `{{filetype}}` |  filetype of the current buffer |
		| `{{selection}}` | last or currently selected text |
		| `{{command}}` | instructions provided by the user |
- `system_template`
	- See [gpt api intro](https://platform.openai.com/docs/guides/chat/introduction)



## Attribution/Alternatives
There is already a bunch of similar plugins which served as sources of inspiration
- [thmsmlr/gpt.nvim](https://github.com/thmsmlr/gpt.nvim)
    - \+ nicely implemented streaming response from OpenAI API
    - \+ later added chat sessions
    - \- a lots of things are hard coded
    - \- undo isn't handled properly
    - \- originally considered forking it, but it has no licence so far
- [dpayne/CodeGPT.nvim](https://github.com/dpayne/CodeGPT.nvim) 
    - \+ templating mechanism to combine user input selection and so on for gpt query
    - \- doesn't use streaming (one has to wait for the whole answer to show up)
- [jackMort/ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim)
    - most popular at the moment but overcomplicated for my taste  
      (its like a GUI over the vim itself and I'd like to stay inside vim 🙂)

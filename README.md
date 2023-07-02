# Gp (GPT prompt) plugin for Neovim

## Install

Install the plugin with your preferred package manager:

```lua
-- lazy.nvim
{
	"robitx/gp.nvim",
	dependencies = {
        -- Telescope (see Dependencies in Readme)
        { "nvim-telescope/telescope.nvim" },
        { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
	config = function()
		require("gp").setup(conf)
        	-- shortcuts might be setup here (see Usage > Shortcuts in Readme)
	end,
}
```

```lua
-- packer.nvim
use({
    "robitx/gp.nvim",
    requires = {
        -- Telescope (see Dependencies in Readme)
        { "nvim-telescope/telescope.nvim" },
        { "nvim-telescope/telescope-fzf-native.nvim", run = "make" },
    },
    config = function()
        require("gp").setup(conf)
        -- shortcuts might be setup here (see Usage > Shortcuts in Readme)
    end,
})
```

### OpenAI API key
Make sure you have OpenAI API key. [Get one here](https://platform.openai.com/account/api-keys)
and use it in the config (either directly or setup env `OPENAI_API_KEY`).

Also consider setting up [usage limits](https://platform.openai.com/account/billing/limits) so you won't get suprised at the end of the month.

### Dependencies
The core functionality only needs `curl` installed to make calls to OpenAI API.

The `:GpChatFinder` (for searching through old chat sessions) requires Telescope, 
which needs setup on its own for the best experience. See [fzf-setup](https://github.com/nvim-telescope/telescope-fzf-native.nvim#telescope-setup-and-configuration) 
or canibalize my own config:
``` lua
-- example telescope setup
local status_ok, telescope = pcall(require, "telescope")
if not status_ok then
	return
end

local actions = require("telescope.actions")

telescope.setup({
	defaults = {

		prompt_prefix = " ",
		selection_caret = " ",
		path_display = { "smart" },
		file_ignore_patterns = { ".git/", "node_modules" },
		extensions = {
			fzf = {
				fuzzy = true, -- false will only do exact matching
				override_generic_sorter = true, -- override the generic sorter
				override_file_sorter = true, -- override the file sorter
				case_mode = "smart_case", -- or "ignore_case" or "respect_case"
				-- the default case_mode is "smart_case"
			},
		},
		mappings = {
			i = {
				["<Down>"] = actions.cycle_history_next,
				["<Up>"] = actions.cycle_history_prev,
				["<C-j>"] = actions.move_selection_next,
				["<C-k>"] = actions.move_selection_previous,
			},
		},
	},
})

telescope.load_extension("fzf")
```

### Configuration

Here are the default values:

```lua
local config = {
	-- required openai api key
	openai_api_key = os.getenv("OPENAI_API_KEY"),
	-- prefix for all commands
	cmd_prefix = "Gp",
	-- example hook functions
	hooks = {
		InspectPlugin = function(plugin)
			print(string.format("Plugin structure:\n%s", vim.inspect(plugin)))
		end,
	},

	-- directory for storing chat files
	chat_dir = os.getenv("HOME") .. "/.local/share/nvim/gp/chats",
	-- chat model
	chat_model = "gpt-3.5-turbo-16k",
	-- chat temperature
	chat_temperature = 0.7,
	-- chat model system prompt
	chat_system_prompt = "You are a general AI assistant.",
	-- chat user prompt prefix
	chat_user_prefix = "🗨:",
	-- chat assistant prompt prefix
	chat_assistant_prefix = "🤖:",
	-- chat topic generation prompt
	chat_topic_gen_prompt = "Summarize the topic of our conversation above"
		.. " in two or three words. Respond only with those words.",
	-- chat topic model
	chat_topic_gen_model = "gpt-3.5-turbo-16k",

	-- prompt prefix for asking user for input
	prompt_prefix = "🤖 ~ ",
	-- prompt model
	prompt_model = "gpt-3.5-turbo-16k",

	-- templates
	template_system = "You are a general AI assistant.",
	template_selection = "I have the following code:\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}",
	template_rewrite = "I have the following code:\n\n```{{filetype}}\n{{selection}}\n```\n\n{{command}}"
		.. "\n\nRespond just with the pure formated final code. !!And please: No ``` code ``` blocks.",
	template_command = "{{command}}",
}

...

-- call setup on your config
require("gp").setup(config)

-- shortcuts might be setup here (see Usage > Shortcuts in Readme)
```

### Extend functionality

You can extend/override the plugin functionality with your own, by putting functions into `config.hooks`.
Hooks have access to everything (see `InspectPlugin` example in defaults) and are 
automatically registered as commands (`GpInspectPlugin`).  

The raw plugin text editing method `prompt`  has six aprameters:
- `mode` specifying if the prompt works with selection or just the command
    ``` lua
    M.mode = {
        normal = 0, -- based just on the command
        visual = 1, -- uses the current or the last visual selection
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

## Usage

### Commands
- Have ChatGPT experience directly in neovim:
	- `:GpChatNew` - open fresh chat
  	- `:GpVisualChatNew` - open fresh chat using current or last selection
	- `:GpChatFinder` - open telescope to search through chats
	- `:GpChatRespond` - request new gpt response for the current chat
  	- `:GpChatDelete` - delete the current chat
- Ask GPT and get response to the specified output:
	- `:GpInline` - answers into the current line (gets replaced)
	- `:GpAppend` - answers after the current line
	- `:GpPrepend` - answers before the before the current line
	- `:GpEnew` - answers into new buffer
	- `:GpPopup` - answers into pop up window
- Ask GPT with the current or last selection as a context:
	- `:GpVisualRewrite` - answer replaces selection
	- `:GpVisualAppend` - answers after the selection
	- `:GpVisualPrepend` - answers before the selection
	- `:GpVisualEnew` - answers into a new buffer
	- `:GpVisualPopup` - answers into a popup window
- Run your own custom hook commands:
    - `:GpInspectPlugin` - inspect GPT prompt plugin object

### Shortcuts

There are no default shortcuts to mess with your own config. Bellow are examples for you to adjust or just use directly.

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
vim.keymap.set({"n", "i"}, "<C-g><C-g>", "<cmd>GpChatRespond<cr>", keymapOptions("Chat Respond"))
vim.keymap.set({"n", "i"}, "<C-g>d", "<cmd>GpChatDelete<cr>", keymapOptions("Chat Delete"))

-- Prompt commands
vim.keymap.set({"n", "i"}, "<C-g>i", "<cmd>GpInline<cr>", keymapOptions("Inline"))
vim.keymap.set({"n", "i"}, "<C-g>a", "<cmd>GpAppend<cr>", keymapOptions("Append"))
vim.keymap.set({"n", "i"}, "<C-g>b", "<cmd>GpPrepend<cr>", keymapOptions("Prepend"))
vim.keymap.set({"n", "i"}, "<C-g>e", "<cmd>GpEnew<cr>", keymapOptions("Enew"))
vim.keymap.set({"n", "i"}, "<C-g>p", "<cmd>GpPopup<cr>", keymapOptions("Popup"))

-- Visual commands
vim.keymap.set("v", "<C-g>c", "<cmd>GpVisualChatNew<cr>", keymapOptions("Visual Chat New"))
vim.keymap.set("v", "<C-g>r", "<cmd>GpVisualRewrite<cr>", keymapOptions("Visual Rewrite"))
vim.keymap.set("v", "<C-g>a", "<cmd>GpVisualAppend<cr>", keymapOptions("Visual Append"))
vim.keymap.set("v", "<C-g>b", "<cmd>GpVisualPrepend<cr>", keymapOptions("Visual Prepend"))
vim.keymap.set("v", "<C-g>e", "<cmd>GpVisualEnew<cr>", keymapOptions("Visual Enew"))
vim.keymap.set("v", "<C-g>p", "<cmd>GpVisualPopup<cr>", keymapOptions("Visual Popup"))
```

#### Whichkey

Or go more fancy by using [which-key.nvim](https://github.com/folke/which-key.nvim) plugin:
``` lua
-- VISUAL mode mappings
-- s, x, v modes are handled the same way by which_key
require("which-key").register({
    -- ...
	["<C-g>"] = {
		c = { "<cmd>GpVisualChatNew<cr>", "Visual Chat New" },

		r = { "<cmd>GpVisualRewrite<cr>", "Visual Rewrite" },
		a = { "<cmd>GpVisualAppend<cr>", "Visual Append" },
		b = { "<cmd>GpVisualPrepend<cr>", "Visual Prepend" },
		e = { "<cmd>GpVisualEnew<cr>", "Visual Enew" },
		p = { "<cmd>GpVisualPopup<cr>", "Visual Popup" },
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
		d = { "<cmd>GpChatDelete<cr>", "Chat Delete" },
		["<C-g>"] = { "<cmd>GpChatRespond<cr>", "Chat Respond" },

		i = { "<cmd>GpInline<cr>", "Inline" },
		a = { "<cmd>GpAppend<cr>", "Append" },
		b = { "<cmd>GpPrepend<cr>", "Prepend" },
		e = { "<cmd>GpEnew<cr>", "Enew" },
		p = { "<cmd>GpPopup<cr>", "Popup" },
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
		d = { "<cmd>GpChatDelete<cr>", "Chat Delete" },
		["<C-g>"] = { "<cmd>GpChatRespond<cr>", "Chat Respond" },

		i = { "<cmd>GpInline<cr>", "Inline" },
		a = { "<cmd>GpAppend<cr>", "Append" },
		b = { "<cmd>GpPrepend<cr>", "Prepend" },
		e = { "<cmd>GpEnew<cr>", "Enew" },
		p = { "<cmd>GpPopup<cr>", "Popup" },
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

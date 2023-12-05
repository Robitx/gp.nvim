# Gp (GPT prompt) plugin for Neovim

<a href="https://github.com/Robitx/gp.nvim/blob/main/LICENSE"><img alt="GitHub" src="https://img.shields.io/github/license/robitx/gp.nvim"></a>
<a href="https://github.com/Robitx/gp.nvim/stargazers"><img alt="GitHub Repo stars" src="https://img.shields.io/github/stars/Robitx/gp.nvim"></a>
<a href="https://github.com/Robitx/gp.nvim/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues-closed/Robitx/gp.nvim"></a>
<a href="https://github.com/Robitx/gp.nvim/pulls"><img alt="GitHub closed pull requests" src="https://img.shields.io/github/issues-pr-closed/Robitx/gp.nvim"></a>
<a href="https://github.com/Robitx/gp.nvim/graphs/contributors"><img alt="GitHub contributors" src="https://img.shields.io/github/contributors-anon/Robitx/gp.nvim"></a>
<a href="https://github.com/search?q=%2F%5E%5B%5Cs%5D*require%5C%28%5B%27%22%5Dgp%5B%27%22%5D%5C%29%5C.setup%2F+language%3ALua&type=code&p=1"><img alt="Static Badge" src="https://img.shields.io/badge/Use%20in%20the%20Wild-8A2BE2"></a>

Gp.nvim provides you ChatGPT like sessions and instructable text/code operations in your favorite editor.

<p align="left">
<img src="https://github.com/Robitx/gp.nvim/assets/8431097/cb288094-2308-42d6-9060-4eb21b3ba74c" width="49%">
<img src="https://github.com/Robitx/gp.nvim/assets/8431097/c538f0a2-4667-444e-8671-13f8ea261be1" width="49%">
</p>

### [5 minute demo from December 2023](https://www.youtube.com/watch?v=X-cT7s47PLo)

#### [Older 5 minute demo (screen capture, no sound)](https://www.youtube.com/watch?v=wPDcBnQgNCc)

## Goals and Features

The goal is to extend Neovim with the **power of GPT models in a simple unobtrusive extensible way.**
Trying to keep things as native as possible - reusing and integrating well with the natural features of (Neo)vim.

- **Streaming responses**
  - no spinner wheel and waiting for the full answer
  - response generation can be canceled half way through
  - properly working undo (response can be undone with a single `u`)
- **Infinitely extensible** via hook functions specified as part of the config
  - hooks have access to everything in the plugin and are automatically registered as commands
  - see [Configuration](#4-configuration) and [Extend functionality](#extend-functionality) sections for details
- **Minimum dependencies** (`neovim`, `curl`, `grep` and optionally `sox`)
  - zero dependencies on other lua plugins to minimize chance of breakage
- **ChatGPT like sessions**
  - just good old neovim buffers formated as markdown with autosave and few buffer bound shortcuts
  - last chat also quickly accessible via toggable popup window
  - chat finder - management popup for searching, previewing, deleting and opening chat sessions
- **Instructable text/code operations**
  - templating mechanism to combine user instructions, selections etc into the gpt query
  - multimodal - same command works for normal/insert mode, with selection or a range
  - many possible output targets - rewrite, prepend, append, new buffer, popup
  - non interactive command mode available for common repetitive tasks implementable as simple hooks
    (explain something in a popup window, write unit tests for selected code into a new buffer,
    finish selected code based on comments in it, etc.)
  - custom instructions per repository with `.gp.md` file
    (instruct gpt to generate code using certain libs, packages, conventions and so on)
- **Speech to text support**
  - a mouth is 2-4x faster than fingers when it comes to outputting words - use it where it makes sense
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
		-- require("gp").setup(config)

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
	-- require("gp").setup(config)

        -- shortcuts might be setup here (see Usage > Shortcuts in Readme)
    end,
})
```

### 2. OpenAI API key

Make sure you have OpenAI API key. [Get one here](https://platform.openai.com/account/api-keys)
and use it in the [config](#4-configuration) (or **setup env `OPENAI_API_KEY`** or use one system command which returned the API key).

There are two options to set OpenAI API key:
1. use `openai_api_key`: it is a string. You can set the key directly (not recommended) or use env `OPENAI_API_KEY`.
2. use `openai_api_key_cmd`: it is highly secure when you use some password managers like [1Password](https://1password.com/) or [Bitwarden](https://bitwarden.com/).

Also consider setting up [usage limits](https://platform.openai.com/account/billing/limits) so you won't get suprised at the end of the month.

### 3. Dependencies

The core plugin only needs `curl` installed to make calls to OpenAI API and `grep` for ChatFinder. So Linux, BSD and Mac OS should be covered.

Voice commands (`:GpWhisper*`) depend on `SoX` (Sound eXchange) to handle audio recording and processing:

- Mac OS: `brew install sox`
- Ubuntu/Debian: `apt-get install sox libsox-fmt-mp3`
- Arch Linux: `pacman -S sox`
- Redhat/CentOS: `yum install sox`
- NixOS: `nix-env -i sox`

### 4. Configuration

Bellow are the default values, but I suggest starting with minimal config possible (just `openai_api_key` if you don't have `OPENAI_API_KEY` env set up). Defaults change over time to improve things, options might get deprecated and so on - it's better to change only things where the default doesn't fit your needs.

https://github.com/Robitx/gp.nvim/blob/84a39ce557ac771b42c38e9b9d211ec3f3bd32cc/lua/gp/config.lua#L8-L246

## Usage

### Commands

- Have ChatGPT experience directly in neovim:

  - `:GpChatNew` - open fresh chat in the current window
    (either empty or with the visual selection or specified range as a context)
  - `:GpChatPaste` - paste the selection or specified range to the latest chat
    (simplifies adding code from multiple files into a single chat buffer)
  - `:GpChatToggle` - open chat in toggleable popup window
    (the last active chat or a fresh one with selection or a range as a context)
  - `:GpChatFinder` - open a dialog to search through chats
  - `:GpChatRespond` - request new gpt response for the current chat
  - `:GpChatRespond N` - request new gpt response with only last N messages as a context
    (using everything from the end up to Nth instance of `🗨:..` => `N=1` is like asking a question in a new chat)
  - `:GpChatDelete` - delete the current chat

  when calling `:GpChatNew` or `:GpChatPaste` and `GpChatToggle` you can also specify where to display chat using subcommands:
  ![image](https://github.com/Robitx/gp.nvim/assets/8431097/350b38ce-52fb-4df7-b2a5-d6e51581f0c3)

- Ask GPT and get response to the specified output:

  - `:GpRewrite` - answer replaces the current line, visual selection or range
  - `:GpAppend` - answers after the current line, visual selection or range
  - `:GpPrepend` - answers before the current line, selection or range
  - `:GpEnew` - answers into a new buffer in the current window
  - `:GpNew` - answers into new horizontal split window
  - `:GpVnew` - answers into new vertical split window
  - `:GpTabnew` - answers into new tab
  - `:GpPopup` - answers into pop up window
  - `:GpImplement` - default example hook command for finishing the code
    based on comments provided in visual selection or specified range

  all these command work either:

  - as pure user commands without any other context in normal/insert mode
  - with current selection (using whole lines) as a context in visual/Visual mode
  - with specified range (such as `%` for the entire current buffer => `:%GpRewrite`)

- Provide custom context per repository with`:GpContext`:

  - opens `.gp.md` file for given repository in toggable window
  - if used with selection/range it appends it to the context file
  - supports display targeting subcommands just like `GpChatNew`
  - see [Custom instructions](#custom-instructions-per-repository) section

- Switch between configured agents (model + persona):

  - `:GpNextAgent` - cycle between available agents
  - `:GpAgent` - display currently used agents for chat and command instructions
  - `:GpAgent XY` - choose new agent based on its name

  commands are context aware (they switch chat or command agent based on the current buffer)

- Voice commands transcribed by Whisper API:
  - `:GpWhisper` - transcription replaces the current line, visual selection or range
  - `:GpWhisperRewrite` - answer replaces the current line, visual selection or range
  - `:GpWhisperAppend` - answers after the current line, visual selection or range
  - `:GpWhisperPrepend` - answers before the current line, selection or range
  - `:GpWhisperEnew` - answers into new buffer in the current window
  - `:GpWhisperNew` - answers into new horizontal split
  - `:GpWhisperVnew` - answers into new vertical split
  - `:GpWhisperTabnew` - answers into new tab
  - `:GpWhisperPopup` - answers into pop up window
- To stop the stream of currently running gpt response you can use `:GpStop`
- Run your own custom hook commands:
  - `:GpInspectPlugin` - inspect GPT prompt plugin object

### GpDone autocommand to run consequent actions

Commands like `GpRewrite`, `GpAppend` etc. run asynchronously and generate event `GpDone`, so you can define autocmd (like auto formating) to run when gp finishes:

```lua
    vim.api.nvim_create_autocmd({ "User" }, {
        pattern = {"GpDone"},
        callback = function(event)
            print("event fired:\n", vim.inspect(event))
            -- local b = event.buf
            -- DO something
        end,
    })
```

### Custom instructions per repository

By calling `:GpContext` you can make `.gp.md` markdown file in a root of a repository. Commands such as `:GpRewrite`, `:GpAppend` etc. will respect instructions provided in this file (works better with gpt4, gpt 3.5 doesn't always listen to system commands). For example:

```md
Use ‎C++17.
Use Testify library when writing Go tests.
Use Early return/Guard Clauses pattern to avoid excessive nesting.
...
```

Here is [another example](https://github.com/Robitx/gp.nvim/blob/main/.gp.md).

### Scripting and multifile edits

`GpDone` event + `.gp.md` custom instructions provide a possibility to run gp.nvim using headless (neo)vim from terminal or shell script. So you can let gp run edits accross many files if you put it in a loop.

`test` file:

```
1
2
3
4
5
```

`.gp.md` file:

````
If user says hello, please respond with:

```
Ahoy there!
```
````

calling gp.nvim from terminal/script:

- register autocommand to save and quit nvim when Gp is done
- second jumps to occurrence of something I want to rewrite/append/prepend to (in this case number `3`)
- selecting the line
- calling gp.nvim acction

```
$ nvim --headless -c "autocmd User GpDone wq" -c "/3" -c "normal V" -c "GpAppend hello there"  test
```

resulting `test` file:

```
1
2
3
Ahoy there!
4
5
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
vim.keymap.set({"n", "i"}, "<C-g>t", "<cmd>GpChatToggle<cr>", keymapOptions("Toggle Chat"))
vim.keymap.set({"n", "i"}, "<C-g>f", "<cmd>GpChatFinder<cr>", keymapOptions("Chat Finder"))

vim.keymap.set("v", "<C-g>c", ":<C-u>'<,'>GpChatNew<cr>", keymapOptions("Visual Chat New"))
vim.keymap.set("v", "<C-g>p", ":<C-u>'<,'>GpChatPaste<cr>", keymapOptions("Visual Chat Paste"))
vim.keymap.set("v", "<C-g>t", ":<C-u>'<,'>GpChatToggle<cr>", keymapOptions("Visual Toggle Chat"))

vim.keymap.set({ "n", "i" }, "<C-g><C-x>", "<cmd>GpChatNew split<cr>", keymapOptions("New Chat split"))
vim.keymap.set({ "n", "i" }, "<C-g><C-v>", "<cmd>GpChatNew vsplit<cr>", keymapOptions("New Chat vsplit"))
vim.keymap.set({ "n", "i" }, "<C-g><C-t>", "<cmd>GpChatNew tabnew<cr>", keymapOptions("New Chat tabnew"))

vim.keymap.set("v", "<C-g><C-x>", ":<C-u>'<,'>GpChatNew split<cr>", keymapOptions("Visual Chat New split"))
vim.keymap.set("v", "<C-g><C-v>", ":<C-u>'<,'>GpChatNew vsplit<cr>", keymapOptions("Visual Chat New vsplit"))
vim.keymap.set("v", "<C-g><C-t>", ":<C-u>'<,'>GpChatNew tabnew<cr>", keymapOptions("Visual Chat New tabnew"))

-- Prompt commands
vim.keymap.set({"n", "i"}, "<C-g>r", "<cmd>GpRewrite<cr>", keymapOptions("Inline Rewrite"))
vim.keymap.set({"n", "i"}, "<C-g>a", "<cmd>GpAppend<cr>", keymapOptions("Append (after)"))
vim.keymap.set({"n", "i"}, "<C-g>b", "<cmd>GpPrepend<cr>", keymapOptions("Prepend (before)"))

vim.keymap.set("v", "<C-g>r", ":<C-u>'<,'>GpRewrite<cr>", keymapOptions("Visual Rewrite"))
vim.keymap.set("v", "<C-g>a", ":<C-u>'<,'>GpAppend<cr>", keymapOptions("Visual Append (after)"))
vim.keymap.set("v", "<C-g>b", ":<C-u>'<,'>GpPrepend<cr>", keymapOptions("Visual Prepend (before)"))
vim.keymap.set("v", "<C-g>i", ":<C-u>'<,'>GpImplement<cr>", keymapOptions("Implement selection"))

vim.keymap.set({"n", "i"}, "<C-g>gp", "<cmd>GpPopup<cr>", keymapOptions("Popup"))
vim.keymap.set({"n", "i"}, "<C-g>ge", "<cmd>GpEnew<cr>", keymapOptions("GpEnew"))
vim.keymap.set({"n", "i"}, "<C-g>gn", "<cmd>GpNew<cr>", keymapOptions("GpNew"))
vim.keymap.set({"n", "i"}, "<C-g>gv", "<cmd>GpVnew<cr>", keymapOptions("GpVnew"))
vim.keymap.set({"n", "i"}, "<C-g>gt", "<cmd>GpTabnew<cr>", keymapOptions("GpTabnew"))

vim.keymap.set("v", "<C-g>gp", ":<C-u>'<,'>GpPopup<cr>", keymapOptions("Visual Popup"))
vim.keymap.set("v", "<C-g>ge", ":<C-u>'<,'>GpEnew<cr>", keymapOptions("Visual GpEnew"))
vim.keymap.set("v", "<C-g>gn", ":<C-u>'<,'>GpNew<cr>", keymapOptions("Visual GpNew"))
vim.keymap.set("v", "<C-g>gv", ":<C-u>'<,'>GpVnew<cr>", keymapOptions("Visual GpVnew"))
vim.keymap.set("v", "<C-g>gt", ":<C-u>'<,'>GpTabnew<cr>", keymapOptions("Visual GpTabnew"))

vim.keymap.set({"n", "i"}, "<C-g>x", "<cmd>GpContext<cr>", keymapOptions("Toggle Context"))
vim.keymap.set("v", "<C-g>x", ":<C-u>'<,'>GpContext<cr>", keymapOptions("Visual Toggle Context"))

vim.keymap.set({"n", "i", "v", "x"}, "<C-g>s", "<cmd>GpStop<cr>", keymapOptions("Stop"))
vim.keymap.set({"n", "i", "v", "x"}, "<C-g>n", "<cmd>GpNextAgent<cr>", keymapOptions("Next Agent"))

-- optional Whisper commands with prefix <C-g>w
vim.keymap.set({"n", "i"}, "<C-g>ww", "<cmd>GpWhisper<cr>", keymapOptions("Whisper"))
vim.keymap.set("v", "<C-g>ww", ":<C-u>'<,'>GpWhisper<cr>", keymapOptions("Visual Whisper"))

vim.keymap.set({"n", "i"}, "<C-g>wr", "<cmd>GpWhisperRewrite<cr>", keymapOptions("Whisper Inline Rewrite"))
vim.keymap.set({"n", "i"}, "<C-g>wa", "<cmd>GpWhisperAppend<cr>", keymapOptions("Whisper Append (after)"))
vim.keymap.set({"n", "i"}, "<C-g>wb", "<cmd>GpWhisperPrepend<cr>", keymapOptions("Whisper Prepend (before) "))

vim.keymap.set("v", "<C-g>wr", ":<C-u>'<,'>GpWhisperRewrite<cr>", keymapOptions("Visual Whisper Rewrite"))
vim.keymap.set("v", "<C-g>wa", ":<C-u>'<,'>GpWhisperAppend<cr>", keymapOptions("Visual Whisper Append (after)"))
vim.keymap.set("v", "<C-g>wb", ":<C-u>'<,'>GpWhisperPrepend<cr>", keymapOptions("Visual Whisper Prepend (before)"))

vim.keymap.set({"n", "i"}, "<C-g>wp", "<cmd>GpWhisperPopup<cr>", keymapOptions("Whisper Popup"))
vim.keymap.set({"n", "i"}, "<C-g>we", "<cmd>GpWhisperEnew<cr>", keymapOptions("Whisper Enew"))
vim.keymap.set({"n", "i"}, "<C-g>wn", "<cmd>GpWhisperNew<cr>", keymapOptions("Whisper New"))
vim.keymap.set({"n", "i"}, "<C-g>wv", "<cmd>GpWhisperVnew<cr>", keymapOptions("Whisper Vnew"))
vim.keymap.set({"n", "i"}, "<C-g>wt", "<cmd>GpWhisperTabnew<cr>", keymapOptions("Whisper Tabnew"))

vim.keymap.set("v", "<C-g>wp", ":<C-u>'<,'>GpWhisperPopup<cr>", keymapOptions("Visual Whisper Popup"))
vim.keymap.set("v", "<C-g>we", ":<C-u>'<,'>GpWhisperEnew<cr>", keymapOptions("Visual Whisper Enew"))
vim.keymap.set("v", "<C-g>wn", ":<C-u>'<,'>GpWhisperNew<cr>", keymapOptions("Visual Whisper New"))
vim.keymap.set("v", "<C-g>wv", ":<C-u>'<,'>GpWhisperVnew<cr>", keymapOptions("Visual Whisper Vnew"))
vim.keymap.set("v", "<C-g>wt", ":<C-u>'<,'>GpWhisperTabnew<cr>", keymapOptions("Visual Whisper Tabnew"))
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
        p = { ":<C-u>'<,'>GpChatPaste<cr>", "Visual Chat Paste" },
        t = { ":<C-u>'<,'>GpChatToggle<cr>", "Visual Toggle Chat" },

        ["<C-x>"] = { ":<C-u>'<,'>GpChatNew split<cr>", "Visual Chat New split" },
        ["<C-v>"] = { ":<C-u>'<,'>GpChatNew vsplit<cr>", "Visual Chat New vsplit" },
        ["<C-t>"] = { ":<C-u>'<,'>GpChatNew tabnew<cr>", "Visual Chat New tabnew" },

        r = { ":<C-u>'<,'>GpRewrite<cr>", "Visual Rewrite" },
        a = { ":<C-u>'<,'>GpAppend<cr>", "Visual Append (after)" },
        b = { ":<C-u>'<,'>GpPrepend<cr>", "Visual Prepend (before)" },
        i = { ":<C-u>'<,'>GpImplement<cr>", "Implement selection" },

        g = {
            name = "generate into new ..",
            p = { ":<C-u>'<,'>GpPopup<cr>", "Visual Popup" },
            e = { ":<C-u>'<,'>GpEnew<cr>", "Visual GpEnew" },
            n = { ":<C-u>'<,'>GpNew<cr>", "Visual GpNew" },
            v = { ":<C-u>'<,'>GpVnew<cr>", "Visual GpVnew" },
            t = { ":<C-u>'<,'>GpTabnew<cr>", "Visual GpTabnew" },
        },

        n = { "<cmd>GpNextAgent<cr>", "Next Agent" },
        s = { "<cmd>GpStop<cr>", "GpStop" },
        x = { ":<C-u>'<,'>GpContext<cr>", "Visual GpContext" },

        w = {
            name = "Whisper",
            w = { ":<C-u>'<,'>GpWhisper<cr>", "Whisper" },
            r = { ":<C-u>'<,'>GpWhisperRewrite<cr>", "Whisper Rewrite" },
            a = { ":<C-u>'<,'>GpWhisperAppend<cr>", "Whisper Append (after)" },
            b = { ":<C-u>'<,'>GpWhisperPrepend<cr>", "Whisper Prepend (before)" },
            p = { ":<C-u>'<,'>GpWhisperPopup<cr>", "Whisper Popup" },
            e = { ":<C-u>'<,'>GpWhisperEnew<cr>", "Whisper Enew" },
            n = { ":<C-u>'<,'>GpWhisperNew<cr>", "Whisper New" },
            v = { ":<C-u>'<,'>GpWhisperVnew<cr>", "Whisper Vnew" },
            t = { ":<C-u>'<,'>GpWhisperTabnew<cr>", "Whisper Tabnew" },
        },
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
        t = { "<cmd>GpChatToggle<cr>", "Toggle Chat" },
        f = { "<cmd>GpChatFinder<cr>", "Chat Finder" },

        ["<C-x>"] = { "<cmd>GpChatNew split<cr>", "New Chat split" },
        ["<C-v>"] = { "<cmd>GpChatNew vsplit<cr>", "New Chat vsplit" },
        ["<C-t>"] = { "<cmd>GpChatNew tabnew<cr>", "New Chat tabnew" },

        r = { "<cmd>GpRewrite<cr>", "Inline Rewrite" },
        a = { "<cmd>GpAppend<cr>", "Append (after)" },
        b = { "<cmd>GpPrepend<cr>", "Prepend (before)" },

        g = {
            name = "generate into new ..",
            p = { "<cmd>GpPopup<cr>", "Popup" },
            e = { "<cmd>GpEnew<cr>", "GpEnew" },
            n = { "<cmd>GpNew<cr>", "GpNew" },
            v = { "<cmd>GpVnew<cr>", "GpVnew" },
            t = { "<cmd>GpTabnew<cr>", "GpTabnew" },
        },

        n = { "<cmd>GpNextAgent<cr>", "Next Agent" },
        s = { "<cmd>GpStop<cr>", "GpStop" },
        x = { "<cmd>GpContext<cr>", "Toggle GpContext" },

        w = {
            name = "Whisper",
            w = { "<cmd>GpWhisper<cr>", "Whisper" },
            r = { "<cmd>GpWhisperRewrite<cr>", "Whisper Inline Rewrite" },
            a = { "<cmd>GpWhisperAppend<cr>", "Whisper Append (after)" },
            b = { "<cmd>GpWhisperPrepend<cr>", "Whisper Prepend (before)" },
            p = { "<cmd>GpWhisperPopup<cr>", "Whisper Popup" },
            e = { "<cmd>GpWhisperEnew<cr>", "Whisper Enew" },
            n = { "<cmd>GpWhisperNew<cr>", "Whisper New" },
            v = { "<cmd>GpWhisperVnew<cr>", "Whisper Vnew" },
            t = { "<cmd>GpWhisperTabnew<cr>", "Whisper Tabnew" },
        },
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
        t = { "<cmd>GpChatToggle<cr>", "Toggle Chat" },
        f = { "<cmd>GpChatFinder<cr>", "Chat Finder" },

        ["<C-x>"] = { "<cmd>GpChatNew split<cr>", "New Chat split" },
        ["<C-v>"] = { "<cmd>GpChatNew vsplit<cr>", "New Chat vsplit" },
        ["<C-t>"] = { "<cmd>GpChatNew tabnew<cr>", "New Chat tabnew" },

        r = { "<cmd>GpRewrite<cr>", "Inline Rewrite" },
        a = { "<cmd>GpAppend<cr>", "Append (after)" },
        b = { "<cmd>GpPrepend<cr>", "Prepend (before)" },

        g = {
            name = "generate into new ..",
            p = { "<cmd>GpPopup<cr>", "Popup" },
            e = { "<cmd>GpEnew<cr>", "GpEnew" },
            n = { "<cmd>GpNew<cr>", "GpNew" },
            v = { "<cmd>GpVnew<cr>", "GpVnew" },
            t = { "<cmd>GpTabnew<cr>", "GpTabnew" },
        },

        x = { "<cmd>GpContext<cr>", "Toggle GpContext" },
        s = { "<cmd>GpStop<cr>", "GpStop" },
        n = { "<cmd>GpNextAgent<cr>", "Next Agent" },

        w = {
            name = "Whisper",
            w = { "<cmd>GpWhisper<cr>", "Whisper" },
            r = { "<cmd>GpWhisperRewrite<cr>", "Whisper Inline Rewrite" },
            a = { "<cmd>GpWhisperAppend<cr>", "Whisper Append (after)" },
            b = { "<cmd>GpWhisperPrepend<cr>", "Whisper Prepend (before)" },
            p = { "<cmd>GpWhisperPopup<cr>", "Whisper Popup" },
            e = { "<cmd>GpWhisperEnew<cr>", "Whisper Enew" },
            n = { "<cmd>GpWhisperNew<cr>", "Whisper New" },
            v = { "<cmd>GpWhisperVnew<cr>", "Whisper Vnew" },
            t = { "<cmd>GpWhisperTabnew<cr>", "Whisper Tabnew" },
        },
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

- `:GpUnitTests`

  ````lua
  -- example of adding command which writes unit tests for the selected code
  UnitTests = function(gp, params)
      local template = "I have the following code from {{filename}}:\n\n"
          .. "```{{filetype}}\n{{selection}}\n```\n\n"
          .. "Please respond by writing table driven unit tests for the code above."
      local agent = gp.get_command_agent()
      gp.Prompt(params, gp.Target.enew, nil, agent.model, template, agent.system_prompt)
  end,
  ````

- `:GpExplain`

  ````lua
  -- example of adding command which explains the selected code
  Explain = function(gp, params)
      local template = "I have the following code from {{filename}}:\n\n"
          .. "```{{filetype}}\n{{selection}}\n```\n\n"
          .. "Please respond by explaining the code above."
      local agent = gp.get_chat_agent()
      gp.Prompt(params, gp.Target.popup, nil, agent.model, template, agent.system_prompt)
  end,
  ````

- `:GpCodeReview`

  ````lua
  -- example of usig enew as a function specifying type for the new buffer
  CodeReview = function(gp, params)
      local template = "I have the following code from {{filename}}:\n\n"
          .. "```{{filetype}}\n{{selection}}\n```\n\n"
          .. "Please analyze for code smells and suggest improvements."
      local agent = gp.get_chat_agent()
      gp.Prompt(params, gp.Target.enew("markdown"), nil, agent.model, template, agent.system_prompt)
  end,
  ````

- `:GpTranslator`

  ```lua
  -- example of adding command which opens new chat dedicated for translation
  Translator = function(gp, params)
    local agent = gp.get_command_agent()
  local chat_system_prompt = "You are a Translator, please translate between English and Chinese."
  gp.cmd.ChatNew(params, agent.model, chat_system_prompt)
  end,
  ```

- `:GpBufferChatNew`

  ```lua
  -- example of making :%GpChatNew a dedicated command which
  -- opens new chat with the entire current buffer as a context
  BufferChatNew = function(gp, _)
      -- call GpChatNew command in range mode on whole buffer
      vim.api.nvim_command("%" .. gp.config.cmd_prefix .. "ChatNew")
  end,
  ```

The raw plugin text editing method `Prompt` has seven aprameters:

- `params` is a [table passed to neovim user commands](https://neovim.io/doc/user/lua-guide.html#lua-guide-commands-create), `Prompt` currently uses:

  - `range, line1, line2` to work with [ranges](https://neovim.io/doc/user/usr_10.html#10.3)
  - `args` so instructions can be passed directly after command (`:GpRewrite something something`)

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

- `target` specifying where to direct GPT response

  - enew/new/vnew/tabnew can be used as a function so you can pass in a filetype
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

      --- for creating a new horizontal split
      ---@param filetype nil | string # nil = same as the original buffer
      ---@return table # a table with type=5 and filetype=filetype
      new = function(filetype)
          return { type = 5, filetype = filetype }
      end,

      --- for creating a new vertical split
      ---@param filetype nil | string # nil = same as the original buffer
      ---@return table # a table with type=6 and filetype=filetype
      vnew = function(filetype)
          return { type = 6, filetype = filetype }
      end,

      --- for creating a new tab
      ---@param filetype nil | string # nil = same as the original buffer
      ---@return table # a table with type=7 and filetype=filetype
      tabnew = function(filetype)
          return { type = 7, filetype = filetype }
      end,
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

    | name            | Description                       |
    | --------------- | --------------------------------- |
    | `{{filetype}}`  | filetype of the current buffer    |
    | `{{selection}}` | last or currently selected text   |
    | `{{command}}`   | instructions provided by the user |

- `system_template`
  - See [gpt api intro](https://platform.openai.com/docs/guides/chat/introduction)
- `whisper`
  - optional string serving as a default for input prompt (for example generated from speech by Whisper)

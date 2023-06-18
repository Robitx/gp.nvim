# Gp (GPT prompt) plugin for Neovim

## Install

Install the plugin with your preferred package manager:

```lua
-- lazy.nvim
{
	"robitx/gp.nvim",
	dependencies = {},

	config = function()
		require("gp").setup()
	end,
}
```

### Configure
Here are default config values:
``` lua
local config = {
	cmd_prefix = "Gp",
	hooks = {
		InspectPlugin = function(plugin)
			print(string.format("%s plugin structure:\n%s", M._Name, vim.inspect(plugin)))
		end,
	},
}

...
-- call setup on your config
require("gp").setup(config)
```

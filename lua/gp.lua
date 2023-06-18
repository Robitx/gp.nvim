-- Gp (GPT prompt) lua plugin for Neovim
-- https://github.com/Robitx/gp.nvim/

-- Define module structure
local _H = {}
M = {
	_Name = "Gp (GPT prompt)", -- plugin name
	_H = _H, -- helper functions
	config = {}, -- config variables
	cmd = {}, -- default command functions
	cmd_hooks = {}, -- user defined command functions
}

-- nicer error messages
M.error = function(msg)
	error(string.format("\n\n%s error:\n%s\n", M._Name, msg))
end

-- default config also serving as documentation example
local config = {
	-- default prefix for all commands
	cmd_prefix = "G",
	-- example hook functions
	hooks = {
		InspectPlugin = function(plugin)
			print(string.format("%s plugin structure:\n%s", M._Name, vim.inspect(plugin)))
		end,
	},
	chat_dir = os.getenv("HOME") .. "/.local/share/nvim/gp/chats",
}

-- setup function
M.setup = function(opts)
	-- make sure opts is a table
	opts = opts or {}
	if type(opts) ~= "table" then
		M.error(string.format("setup() expects table, but got %s:\n%s", type(opts), vim.inspect(opts)))
		opts = {}
	end

	-- reset M.config
	M.config = vim.deepcopy(config)

	-- mv default M.config.hooks to M.cmd_hooks
	for k, v in pairs(M.config.hooks) do
		M.cmd_hooks[k] = v
	end
	M.config.hooks = nil

	-- merge user hooks to M.cmd_hooks
	if opts.hooks then
		for k, v in pairs(opts.hooks) do
			M.cmd_hooks[k] = v
		end
		opts.hooks = nil
	end

	-- merge user opts to M.config
	for k, v in pairs(opts) do
		M.config[k] = v
	end

	-- make sure _dirs exists
	for k, v in pairs(M.config) do
		if k:match("_dir$") and vim.fn.isdirectory(v) == 0 then
			print(M._Name .. ": creating directory " .. v)
			vim.fn.mkdir(v, "p")
		end
	end

	-- register user commands
	for hook, _ in pairs(M.cmd_hooks) do
		vim.api.nvim_create_user_command(M.config.cmd_prefix .. hook, function()
			M.call_hook(hook)
		end, { nargs = "?", range = (hook:match("^Visual") ~= nil), desc = "GPT Prompt plugin" })
	end

    -- register default commands
	for cmd, _ in pairs(M.cmd) do
		if M.cmd_hooks[cmd] == nil then
			vim.api.nvim_create_user_command(M.config.cmd_prefix .. cmd, function()
				M.cmd[cmd]()
			end, { nargs = "?", range = (cmd:match("^Visual") ~= nil), desc = "GPT Prompt plugin" })
		end
	end
end

M.call_hook = function(name)
	if M.cmd_hooks[name] ~= nil then
		return M.cmd_hooks[name](M)
	end
	M.error("The hook '" .. name .. "' does not exist.")
end

--[[ M.setup({chat_dir = "/tmp/gp/chats"}) ]]
--[[ M.setup() ]]
--[[ M.setup("") ]]
--[[ M.call_hook("InsectPlugin") ]]
--[[ M.call_hook("InspectPlugin") ]]

return M

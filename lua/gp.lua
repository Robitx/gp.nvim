-- Gp (GPT prompt) lua plugin for Neovim
-- https://github.com/Robitx/gp.nvim/

-- Define module structure
local _H = {}
M = {
	_Name = "Gp (GPT prompt)", -- plugin name
	_H = _H, -- helper functions
	config = {}, -- config variables
}

-- default config also serving as documentation example
M.config = {}

-- setup function
M.setup = function(opts)
	-- make sure opts is a table
	opts = opts or {}
	if type(opts) ~= "table" then
		error(
			string.format(
				"\n\n%s error:\nrequire('gp').setup() expects table, but got %s:\n%s\n",
				M._Name,
				type(opts),
				vim.inspect(opts)
			)
		)
		opts = {}
	end

	-- merge user opts to M.config
	for k, v in pairs(opts) do
		M.config[k] = v
	end
end

--[[ M.setup("") ]]

return M

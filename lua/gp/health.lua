local M = {}

function M.check()
	vim.health.start("gp.nvim checks")

	local ok, gp = pcall(require, "gp")
	if not ok then
		vim.health.error("require('gp') failed")
	else
		vim.health.ok("require('gp') succeeded")

		-- check if setup has been run
		if gp._setup_called then
			vim.health.ok("require('gp').setup() has been called")
		else
			vim.health.error("require('gp').setup() has not been called")
		end

		-- check if openai_api_key is set
		local api_key = gp.config.openai_api_key

		if api_key == nil or api_key == "" then
			vim.health.error("require('gp').setup({openai_api_key: ???}) is not set: " .. vim.inspect(api_key))
		else
			vim.health.ok("config.openai_api_key is set")
		end
	end

	-- check if curl is installed
	if vim.fn.executable("curl") == 1 then
		vim.health.ok("curl is installed")
	else
		vim.health.error("curl is not installed")
	end

	-- check if grep is installed
	if vim.fn.executable("grep") == 1 then
		vim.health.ok("grep is installed")
	else
		vim.health.error("grep is not installed")
	end

	-- check if ln is installed
	if vim.fn.executable("ln") == 1 then
		vim.health.ok("ln is installed")
	else
		vim.health.error("ln is not installed")
	end

	-- check if sox is installed
	if vim.fn.executable("sox") == 1 then
		vim.health.ok("sox is installed")
	else
		vim.health.warn("sox is not installed")
	end
end

return M

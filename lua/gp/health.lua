local M = {}

function M.check()
	vim.health.start("gp.nvim checks")

	local ok, gp = pcall(require, "gp")
	if not ok then
		vim.health.error("require('gp') failed")
	else
		vim.health.ok("require('gp') succeeded")

		if gp._setup_called then
			vim.health.ok("require('gp').setup() has been called")
		else
			vim.health.error("require('gp').setup() has not been called")
		end

		---@diagnostic disable-next-line: undefined-field
		local api_key = gp.config.openai_api_key

		if api_key == nil or api_key == "" then
			vim.health.error("require('gp').setup({openai_api_key: ???}) is not set: " .. vim.inspect(api_key))
		else
			vim.health.ok("config.openai_api_key is set")
		end
	end

	if vim.fn.executable("curl") == 1 then
		vim.health.ok("curl is installed")
	else
		vim.health.error("curl is not installed")
	end

	if vim.fn.executable("grep") == 1 then
		vim.health.ok("grep is installed")
	else
		vim.health.error("grep is not installed")
	end

	if vim.fn.executable("ln") == 1 then
		vim.health.ok("ln is installed")
	else
		vim.health.error("ln is not installed")
	end

	if vim.fn.executable("sox") == 1 then
		vim.health.ok("sox is installed")
	else
		vim.health.warn("sox is not installed")
	end

	if #gp._deprecated > 0 then
		local msg = "deprecated config option(s) in setup():"
		for _, v in ipairs(gp._deprecated) do
			msg = msg .. "\n\n- " .. v.msg
		end
		vim.health.warn(msg)
	else
		vim.health.ok("no deprecated config options")
	end
end

return M

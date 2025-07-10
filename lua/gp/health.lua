--------------------------------------------------------------------------------
-- :checkhealth gp
--------------------------------------------------------------------------------

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

	require("gp.deprecator").check_health()

	vim.health.info("checking image module started")
	require("gp.image").check_health()
	vim.health.info("checking image module finished")

	vim.health.info("checking command module started")
	require("gp.cmd").check_health()
	vim.health.info("checking command module finished")
end

return M

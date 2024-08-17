local M = require("gp")

M.logger.debug("gpmd: loading ftplugin")

vim.opt_local.swapfile = false
vim.opt_local.wrap = true
vim.opt_local.linebreak = true

local buf = vim.api.nvim_get_current_buf()

vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
	buffer = buf,
	callback = function(event)
		if M.helpers.deleted_invalid_autocmd(buf, event) then
			return
		end
		M.logger.debug("gpmd: saving buffer " .. buf .. " " .. vim.json.encode(event))
		vim.api.nvim_command("silent! write")
	end,
})

-- ensure normal mode
vim.cmd.stopinsert()
M.helpers.feedkeys("<esc>", "xn")

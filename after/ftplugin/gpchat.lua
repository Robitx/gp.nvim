local M = require("gp")

M.logger.debug("gpchat: loading ftplugin")

vim.opt_local.swapfile = false
vim.opt_local.wrap = true
vim.opt_local.linebreak = true

local buf = vim.api.nvim_get_current_buf()
local ns_id = vim.api.nvim_create_namespace("GpChatExt_" .. buf)

-- ensure normal mode
vim.cmd.stopinsert()
M.helpers.feedkeys("<esc>", "xn")

M.logger.debug("gpchat: ns_id " .. ns_id .. " for buffer " .. buf)

if M.config.chat_prompt_buf_type then
	vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
	vim.fn.prompt_setprompt(buf, "")
	vim.fn.prompt_setcallback(buf, function()
		M.cmd.ChatRespond({ args = "" })
	end)
end

-- setup chat specific commands
local commands = {
	{
		command = "ChatRespond",
		modes = M.config.chat_shortcut_respond.modes,
		shortcut = M.config.chat_shortcut_respond.shortcut,
		comment = "GPT prompt Chat Respond",
	},
	{
		command = "ChatNew",
		modes = M.config.chat_shortcut_new.modes,
		shortcut = M.config.chat_shortcut_new.shortcut,
		comment = "GPT prompt Chat New",
	},
}
for _, rc in ipairs(commands) do
	local cmd = M.config.cmd_prefix .. rc.command .. "<cr>"
	for _, mode in ipairs(rc.modes) do
		if mode == "n" or mode == "i" then
			M.helpers.set_keymap({ buf }, mode, rc.shortcut, function()
				vim.api.nvim_command(M.config.cmd_prefix .. rc.command)
				-- go to normal mode
				vim.api.nvim_command("stopinsert")
				M.helpers.feedkeys("<esc>", "xn")
			end, rc.comment)
		else
			M.helpers.set_keymap({ buf }, mode, rc.shortcut, ":<C-u>'<,'>" .. cmd, rc.comment)
		end
	end
end

local ds = M.config.chat_shortcut_delete
M.helpers.set_keymap({ buf }, ds.modes, ds.shortcut, M.cmd.ChatDelete, "GPT prompt Chat Delete")

local ss = M.config.chat_shortcut_stop
M.helpers.set_keymap({ buf }, ss.modes, ss.shortcut, M.cmd.Stop, "GPT prompt Chat Stop")

-- conceal parameters in model header so it's not distracting
if M.config.chat_conceal_model_params then
	vim.opt_local.conceallevel = 2
	vim.opt_local.concealcursor = ""
	vim.fn.matchadd("Conceal", [[^- model: .*model.:.[^"]*\zs".*\ze]], 10, -1, { conceal = "…" })
	vim.fn.matchadd("Conceal", [[^- model: \zs.*model.:.\ze.*]], 10, -1, { conceal = "…" })
	vim.fn.matchadd("Conceal", [[^- role: .\{64,64\}\zs.*\ze]], 10, -1, { conceal = "…" })
	vim.fn.matchadd("Conceal", [[^- role: .[^\\]*\zs\\.*\ze]], 10, -1, { conceal = "…" })
end

vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
	buffer = buf,
	callback = function(event)
		if M.helpers.deleted_invalid_autocmd(buf, event) then
			return
		end
		-- M.logger.debug("gpchat: entering buffer " .. buf .. " " .. vim.json.encode(event))

		vim.cmd("doautocmd User GpRefresh")
	end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave" }, {
	buffer = buf,
	callback = function(event)
		if M.helpers.deleted_invalid_autocmd(buf, event) then
			return
		end
		-- M.logger.debug("gpchat: saving buffer " .. buf .. " " .. vim.json.encode(event))
		vim.api.nvim_command("silent! write")
	end,
})
vim.api.nvim_create_autocmd({ "User" }, {
	callback = function(event)
		if event.event == "User" and event.match ~= "GpRefresh" then
			return
		end
		if M.helpers.deleted_invalid_autocmd(buf, event) then
			return
		end

		M.logger.debug("gpchat: refreshing buffer " .. buf .. " " .. vim.json.encode(event))

		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		vim.api.nvim_buf_set_extmark(buf, ns_id, 0, 0, {
			strict = false,
			right_gravity = true,
			virt_text_pos = "right_align",
			virt_text = {
				{ "Current Agent: [" .. M._state.chat_agent .. "]", "DiagnosticHint" },
			},
			hl_mode = "combine",
		})
	end,
})

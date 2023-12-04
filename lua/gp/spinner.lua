local M = {}
M._spinner_frames = {
	"01010010",
	"01101111",
	"01100010",
	"01101001",
	"01110100",
	"01111000",
	"00101111",
	"01100111",
	"01110000",
	"00101110",
	"01101110",
	"01110110",
	"01101001",
	"01101101",
}

M._spinner_timer = nil
M._current_spinner_frame = 1

M._display_spinner = function(msg)
	local spinner_msg = M._spinner_frames[M._current_spinner_frame] .. " " .. msg
	vim.api.nvim_echo({ { spinner_msg, "Normal" } }, false, {})
	M._current_spinner_frame = (M._current_spinner_frame % #M._spinner_frames) + 1
end

function M.start_spinner(msg)
	-- Set or update the spinner message
	M._msg = msg

	-- Display the initial frame with the message
	M._display_spinner(M._msg)

	if not M._spinner_timer then
		M._spinner_timer = vim.loop.new_timer()
		M._spinner_timer:start(
			0,
			100,
			vim.schedule_wrap(function()
				M._display_spinner(M._msg)
			end)
		)
	end
end

function M.stop_spinner()
	if M._spinner_timer then
		M._spinner_timer:stop()
		M._spinner_timer:close()
		M._spinner_timer = nil
	end
end

return M

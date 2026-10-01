--------------------------------------------------------------------------------
-- Whisper module for transcribing speech
--------------------------------------------------------------------------------

local uv = vim.uv or vim.loop

local logger = require("gp.logger")
local tasker = require("gp.tasker")
local render = require("gp.render")
local helpers = require("gp.helper")
local vault = require("gp.vault")

local default_config = require("gp.config")

local W = {
	config = {},
	cmd = {},
	disabled = false,
}

---@param opts table # user config
W.setup = function(opts)
	logger.debug("whisper setup started\n" .. vim.inspect(opts), true)

	W.config = vim.deepcopy(default_config.whisper)

	if opts.disable then
		W.disabled = true
		logger.debug("whisper is disabled")
		return
	end

	for k, v in pairs(opts) do
		W.config[k] = v
	end

	if W.config.provider == "60db" then
		vault.add_secret("sixtydb_stt", opts.secret or os.getenv("SIXTYDB_API_KEY"))
		W.config.endpoint = opts.endpoint or "https://api.60db.ai/stt"
	end
	W.config.secret = nil

	W.config.store_dir = helpers.prepare_dir(W.config.store_dir, "whisper store")

	for cmd, _ in pairs(W.cmd) do
		helpers.create_user_command(W.config.cmd_prefix .. cmd, W.cmd[cmd])
	end
	logger.debug("whisper setup finished")
end

---@param callback function # callback function(text)
---@param language string | nil # language code
local whisper = function(callback, language)
	language = language or W.config.language
	-- make sure sox is installed
	if vim.fn.executable("sox") == 0 then
		logger.error("sox is not installed")
		return
	end

	local bearer = vault.get_secret(W.config.provider == "60db" and "sixtydb_stt" or "openai_api_key")
	if not bearer then
		logger.error("Transcription API key not found")
		return
	end

	local rec_file = W.config.store_dir .. "/rec.wav"
	local rec_options = {
		sox = {
			cmd = "sox",
			opts = {
				"-c",
				"1",
				"--buffer",
				"32",
				"-d",
				"rec.wav",
				"trim",
				"0",
				"3600",
			},
			exit_code = 0,
		},
		arecord = {
			cmd = "arecord",
			opts = {
				"-c",
				"1",
				"-f",
				"S16_LE",
				"-r",
				"48000",
				"-d",
				3600,
				"rec.wav",
			},
			exit_code = 1,
		},
		ffmpeg = {
			cmd = "ffmpeg",
			opts = {
				"-y",
				"-f",
				"avfoundation",
				"-i",
				":0",
				"-t",
				"3600",
				"rec.wav",
			},
			exit_code = 255,
		},
	}

	local gid = helpers.create_augroup("GpWhisper", { clear = true })

	-- create popup
	local buf, _, close_popup, _ = render.popup(
		nil,
		W.config.cmd_prefix .. " Whisper",
		function(w, h)
			return 60, 12, (h - 12) * 0.4, (w - 60) * 0.5
		end,
		{ gid = gid, on_leave = false, escape = false, persist = false },
		{ border = W.config.style_popup_border or "single" }
	)

	-- animated instructions in the popup
	local counter = 0
	local timer = uv.new_timer()
	timer:start(
		0,
		200,
		vim.schedule_wrap(function()
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
					"    ",
					"    Speak 👄 loudly 📣 into the microphone 🎤: ",
					"    " .. string.rep("👂", counter),
					"    ",
					"    Pressing <Enter> starts the transcription.",
					"    ",
					"    Cancel the recording with <esc>/<C-c> or :GpStop.",
					"    ",
					"    The last recording is in /tmp/gp_whisper/.",
				})
			end
			counter = counter + 1
			if counter % 22 == 0 then
				counter = 0
			end
		end)
	)

	local close = tasker.once(function()
		if timer then
			timer:stop()
			timer:close()
		end
		close_popup()
		vim.api.nvim_del_augroup_by_id(gid)
		tasker.stop()
	end)

	helpers.set_keymap({ buf }, { "n", "i", "v" }, "<esc>", function()
		tasker.stop()
	end)

	helpers.set_keymap({ buf }, { "n", "i", "v" }, "<C-c>", function()
		tasker.stop()
	end)

	local continue = false
	helpers.set_keymap({ buf }, { "n", "i", "v" }, "<cr>", function()
		continue = true
		vim.defer_fn(function()
			tasker.stop()
		end, 300)
	end)

	-- cleanup on buffer exit
	helpers.autocmd({ "BufWipeout", "BufHidden", "BufDelete" }, { buf }, close, gid)

	-- Process audio first; pass credentials and form fields as argv, never shell code.
	local transcribe = function()
		local cmd = "cd " .. vim.fn.shellescape(W.config.store_dir)
			.. " && export LC_NUMERIC='C' && sox --norm=-3 rec.wav norm.wav && "
			.. "t=$(sox norm.wav -n channels 1 stats 2>&1 | grep 'RMS lev dB' "
			.. "| sed -e 's/.* //' | awk '{print $1*" .. W.config.silence .. "}') && "
			.. "sox -q norm.wav -C 196.5 final.mp3 silence -l 1 0.05 $t'dB' -1 1.0 $t'dB'"
			.. " pad 0.1 0.1 tempo " .. W.config.tempo

		tasker.run(nil, "bash", { "-c", cmd }, function(code)
			if code ~= 0 then
				logger.error("Transcription audio processing failed")
				return
			end
			local file = W.config.store_dir .. "/final.mp3"
			if W.config.provider == "60db" then
				local stat = uv.fs_stat(file)
				if not stat or stat.size == 0 or stat.size > 10 * 1024 * 1024 then
					logger.error("60db requires a nonempty audio file up to 10 MB")
					return
				end
			end
			local args = vim.deepcopy(W.config.curl_params or {})
			vim.list_extend(args, {
				"--max-time", W.config.provider == "60db" and "60" or "20", "--silent", "--show-error", "--fail",
				"--header", "Authorization: Bearer " .. bearer,
				"--form", 'file=@"' .. file:gsub("\\", "\\\\"):gsub('"', '\\"') .. '";type=audio/mpeg',
				"--form-string", "language=" .. language,
			})
			if W.config.provider ~= "60db" then
				vim.list_extend(args, { "--form-string", "model=whisper-1", "--form-string", "response_format=json" })
			end
			table.insert(args, W.config.endpoint)
			tasker.run(nil, "curl", args, function(status, _, stdout)
				if status ~= 0 then
					logger.error("Transcription request failed (curl exit " .. tostring(status) .. ")")
					return
				end
				local ok, response = pcall(vim.json.decode, stdout or "")
				if not ok or type(response) ~= "table" or response.success == false or type(response.text) ~= "string" then
					logger.error("Transcription returned an invalid response")
					return
				end
				local text = table.concat(vim.split(response.text, "\n"), " "):gsub("%s+$", "")
				if callback then
					callback(text)
				end
			end)
		end)
	end

	local cmd = {}

	local rec_cmd = W.config.rec_cmd
	-- if rec_cmd not set explicitly, try to autodetect
	if not rec_cmd then
		rec_cmd = "sox"
		if vim.fn.executable("ffmpeg") == 1 then
			local devices = vim.fn.system("ffmpeg -devices -v quiet | grep -i avfoundation | wc -l")
			devices = string.gsub(devices, "^%s*(.-)%s*$", "%1")
			if devices == "1" then
				rec_cmd = "ffmpeg"
			end
		end
		if vim.fn.executable("arecord") == 1 then
			rec_cmd = "arecord"
		end
	end

	if type(rec_cmd) == "table" and rec_cmd[1] and rec_options[rec_cmd[1]] then
		rec_cmd = vim.deepcopy(rec_cmd)
		cmd.cmd = table.remove(rec_cmd, 1)
		cmd.exit_code = rec_options[cmd.cmd].exit_code
		cmd.opts = rec_cmd
	elseif type(rec_cmd) == "string" and rec_options[rec_cmd] then
		cmd = rec_options[rec_cmd]
	else
		logger.error(string.format("Whisper got invalid recording command: %s", rec_cmd))
		close()
		return
	end
	for i, v in ipairs(cmd.opts) do
		if v == "rec.wav" then
			cmd.opts[i] = rec_file
		end
	end

	tasker.run(nil, cmd.cmd, cmd.opts, function(code, signal, stdout, stderr)
		close()

		if code and code ~= cmd.exit_code then
			logger.error(
				cmd.cmd
					.. " exited with code and signal:\ncode: "
					.. code
					.. ", signal: "
					.. signal
					.. "\nstdout: "
					.. vim.inspect(stdout)
					.. "\nstderr: "
					.. vim.inspect(stderr)
			)
			return
		end

		if not continue then
			return
		end

		vim.schedule(function()
			transcribe()
		end)
	end)
end

---@param callback function # callback function(text)
---@param language string | nil # language code
W.Whisper = function(callback, language)
	if W.config.provider ~= "openai" and W.config.provider ~= "60db" then
		logger.error("Unknown transcription provider: " .. tostring(W.config.provider))
		return
	end
	vault.run_with_secret(W.config.provider == "60db" and "sixtydb_stt" or "openai_api_key", function()
		whisper(callback, language)
	end)
end

W.cmd.Whisper = function(params)
	local buf = vim.api.nvim_get_current_buf()
	local start_line = vim.api.nvim_win_get_cursor(0)[1]
	local end_line = start_line

	if params.range == 2 then
		start_line = params.line1
		end_line = params.line2
	end

	local args = vim.split(params.args, " ")

	local language = W.config.language
	if args[1] ~= "" then
		language = args[1]
	end

	W.Whisper(function(text)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		if text then
			vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line, false, { text })
		end
	end, language)
end

W.check_health = function()
	if W.disabled then
		vim.health.warn("whisper is disabled")
		return
	end
	if vim.fn.executable("sox") == 1 then
		vim.health.ok("sox is installed")
		local output = vim.fn.system("sox -h | grep -i mp3 | wc -l 2>/dev/null")
		if output:sub(1, 1) == "0" then
			vim.health.error("sox is not compiled with mp3 support" .. "\n  on debian/ubuntu install libsox-fmt-mp3")
		else
			vim.health.ok("sox is compiled with mp3 support")
		end
	else
		vim.health.warn("sox is not installed")
	end

	if vim.fn.executable("arecord") == 1 then
		vim.health.ok("arecord found - will be used for recording (sox for post-processing)")
	elseif vim.fn.executable("ffmpeg") == 1 then
		local devices = vim.fn.system("ffmpeg -devices -v quiet | grep -i avfoundation | wc -l")
		devices = string.gsub(devices, "^%s*(.-)%s*$", "%1")
		if devices == "1" then
			vim.health.ok("ffmpeg with avfoundation found - will be used for recording (sox for post-processing)")
		end
	end
end

return W

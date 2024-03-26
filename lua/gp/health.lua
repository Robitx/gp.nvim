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

		--TODO: obsolete
		---@diagnostic disable-next-line: undefined-field
		local api_key = gp.config.openai_api_key

		if type(api_key) == "table" then
			vim.health.error(
				"require('gp').setup({openai_api_key: ???}) is still an unresolved command: " .. vim.inspect(api_key)
			)
		elseif api_key and string.match(api_key, "%S") then
			vim.health.ok("config.openai_api_key is set")
		else
			vim.health.error("require('gp').setup({openai_api_key: ???}) is not set: " .. vim.inspect(api_key))
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

	if gp._deprecated and #gp._deprecated > 0 then
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

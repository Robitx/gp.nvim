-- Run from the repository root: nvim --headless -u NONE -l tests/whisper.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local errors, calls, mappings, recording, processing, request, secret_name
local size
local key = 'test-key;$(false)'
local uv = vim.uv
local old_timer, old_stat = uv.new_timer, uv.fs_stat
uv.new_timer = function() return { start = function() end, stop = function() end, close = function() end } end
uv.fs_stat = function() return { size = size } end
vim.schedule = function(fn) fn() end
vim.defer_fn = function(fn) fn() end
vim.fn.executable = function() return 1 end
vim.api.nvim_del_augroup_by_id = function() end
package.loaded["gp.logger"] = {
	debug = function() end,
	error = function(message) table.insert(errors, message) end,
}
package.loaded["gp.helper"] = {
	prepare_dir = function(path) return path end,
	create_user_command = function() end,
	create_augroup = function() return 1 end,
	autocmd = function() end,
	set_keymap = function(_, _, name, fn) mappings[name] = fn end,
}
package.loaded["gp.render"] = { popup = function() return 1, 1, function() end end }
package.loaded["gp.vault"] = {
	add_secret = function(name, value) assert(name == "sixtydb_stt" and value == key) end,
	run_with_secret = function(name, fn) secret_name = name; fn() end,
	get_secret = function(name) assert(name == secret_name); return key end,
}
package.loaded["gp.tasker"] = {
	once = function(fn) return fn end,
	stop = function() end,
	run = function(_, command, args, callback)
		table.insert(calls, { command = command, args = args })
		if command == "sox" then recording = callback
		elseif command == "bash" then processing = callback
		else assert(command == "curl"); request = callback end
	end,
}
local whisper = require("gp.whisper")
local function contains(args, value)
	for _, arg in ipairs(args) do if arg == value then return true end end
	return false
end
local function run(provider, body, status, bytes, process_status, accept)
	errors, calls, mappings = {}, {}, {}
	recording, processing, request = nil, nil, nil
	size = bytes or 100
	local output
	whisper.setup({ provider = provider, secret = key, rec_cmd = "sox", cmd_prefix = "Gp", store_dir = "/tmp/audio with spaces" })
	assert(whisper.config.secret == nil)
	whisper.Whisper(function(text) output = text end, "auto")
	if not recording then return output end
	if accept ~= false then mappings["<cr>"]() else mappings["<esc>"]() end
	recording(0, 0, "", "")
	if not processing then return output end
	assert(not calls[2].args[2]:find(key, 1, true))
	processing(process_status or 0)
	if request then request(status or 0, 0, body) end
	return output
end
assert(run("60db", '{"text":"hello\\nworld  "}') == "hello world")
assert(secret_name == "sixtydb_stt")
local args = calls[3].args
assert(contains(args, "https://api.60db.ai/stt"))
assert(contains(args, "Authorization: Bearer " .. key))
assert(contains(args, 'file=@"/tmp/audio with spaces/final.mp3";type=audio/mpeg'))
assert(contains(args, "language=auto") and contains(args, "--fail"))
assert(not contains(args, "model=whisper-1"))
assert(run(nil, '{"text":"default"}') == "default")
assert(secret_name == "openai_api_key")
assert(contains(calls[3].args, "model=whisper-1"))
assert(contains(calls[3].args, "https://api.openai.com/v1/audio/transcriptions"))
assert(run("60db", '{"text":""}') == "")
for _, body in ipairs({ "not json", "null", '{"text":42}', '{"success":false,"text":"bad"}' }) do
	assert(run("60db", body) == nil and #errors == 1)
end
assert(run("60db", '{"text":"bad"}', 22) == nil and #errors == 1)
assert(run("60db", '{"text":"bad"}', 0, 11 * 1024 * 1024) == nil and not request)
assert(run("60db", '{"text":"bad"}', 0, 0) == nil and not request)
assert(run("60db", '{"text":"bad"}', 0, 100, 1) == nil and not request)
assert(run("60db", '{"text":"cancelled"}', 0, 100, 0, false) == nil and #calls == 1)
assert(run("unknown", '{}') == nil and #errors == 1 and #calls == 0)
uv.new_timer, uv.fs_stat = old_timer, old_stat
print("Whisper provider flow checks passed")

print("in after/plugin/gp.lua")
local completion = require("gp.completion")

print(vim.inspect(completion))

completion.register_cmd_source()
print("done after/plugin/gp.lua")

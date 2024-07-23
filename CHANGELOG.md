# Changelog

## [3.3.0](https://github.com/Robitx/gp.nvim/compare/v3.2.0...v3.3.0) (2024-07-23)


### Features

* add logging to file ([#166](https://github.com/Robitx/gp.nvim/issues/166)) ([33812a6](https://github.com/Robitx/gp.nvim/commit/33812a62d6e3a34a10d24c696106337a5e2ef4b3))

## [3.2.0](https://github.com/Robitx/gp.nvim/compare/v3.1.0...v3.2.0) (2024-07-23)


### Features

* replace gpt3.5 agents with gpt-4o-mini ([a062dbe](https://github.com/Robitx/gp.nvim/commit/a062dbea91340fc6423fd06b6c3f84f252ba8f38))

## [3.1.0](https://github.com/Robitx/gp.nvim/compare/v3.0.1...v3.1.0) (2024-07-23)


### Features

* add claude 3.5 sonnet among default agents ([3409487](https://github.com/Robitx/gp.nvim/commit/34094879c4ea9f654245cb70dc011c57151f4a94))
* chat templates with {{tag}} syntax ([5b5f944](https://github.com/Robitx/gp.nvim/commit/5b5f94460ee163763d45a5f1dbad97cb2f2dd775))
* configurable whisper endpoint ([12cedc7](https://github.com/Robitx/gp.nvim/commit/12cedc70b4fdf190034f9294e2839b684d078f84))
* expose default_(chat|code)_system_prompt to user ([56740e0](https://github.com/Robitx/gp.nvim/commit/56740e089ac0117e7a61e3c03e979c1bfbe1a498))
* improve gp.cmd.ChatNew signature ([f3664de](https://github.com/Robitx/gp.nvim/commit/f3664deee8fc99013c28523d1069f19d5f3ea854))
* keep git repo name in template_render ([2409cd5](https://github.com/Robitx/gp.nvim/commit/2409cd56b29df499a5907c441966b51bfbd83a05))
* picking specific agent via get_chat_agent/get_command_agent(name) ([e1acbca](https://github.com/Robitx/gp.nvim/commit/e1acbcad9c254e241a06f3d1339658cf1af836c1))
* simplify Prompt function signature ([272eee1](https://github.com/Robitx/gp.nvim/commit/272eee103b5d426b2fd203db0c8082536c50d136))


### Bug Fixes

* sys_prompt render for Prompt commands (resolve: [#162](https://github.com/Robitx/gp.nvim/issues/162)) ([6172e15](https://github.com/Robitx/gp.nvim/commit/6172e15d859baf842e4ba4dbfb57f06e6b9878d8))

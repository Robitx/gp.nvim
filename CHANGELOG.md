# Changelog

## [3.5.0](https://github.com/Robitx/gp.nvim/compare/v3.4.1...v3.5.0) (2024-07-29)


### Features

* capture the preceding number for ChatRespond ([#178](https://github.com/Robitx/gp.nvim/issues/178)) ([14a37df](https://github.com/Robitx/gp.nvim/commit/14a37dfed125782a5a337b26c06201a30d02ca6e))
* configurable sensitive logging to file ([7794e8a](https://github.com/Robitx/gp.nvim/commit/7794e8adf361682ab1488bd910be4ba3828aab03))
* deprecate image_ conf vars in favor of nesting under image table ([dcf116a](https://github.com/Robitx/gp.nvim/commit/dcf116a3390150e2d975e8e74be5fec7c35370e3))
* **logger:** sensitive flag ([85a5f1c](https://github.com/Robitx/gp.nvim/commit/85a5f1cfd976a70677092165b5b1923c9acf9638))
* reuse chat_confirm_delete shortcut in chat picker ([919fdd4](https://github.com/Robitx/gp.nvim/commit/919fdd49fa42a9c2bef3ce85f1532d891c71b953))
* truncating log file and GpInspectLog ([bf38d16](https://github.com/Robitx/gp.nvim/commit/bf38d16e7151db86287ca54b167b8afd990a632a))


### Bug Fixes

* rm obsolete api key validation ([352b0c3](https://github.com/Robitx/gp.nvim/commit/352b0c363bfb1574528743f5771dbd1efbba0046))

## [3.4.1](https://github.com/Robitx/gp.nvim/compare/v3.4.0...v3.4.1) (2024-07-26)


### Bug Fixes

* handle symlinks for ChatDelete ([#171](https://github.com/Robitx/gp.nvim/issues/171)) ([129c2f8](https://github.com/Robitx/gp.nvim/commit/129c2f8a1b068b93763c1a5ef950966d1c10ec37))

## [3.4.0](https://github.com/Robitx/gp.nvim/compare/v3.3.0...v3.4.0) (2024-07-24)


### Features

* default to openai compatible headers ([#168](https://github.com/Robitx/gp.nvim/issues/168)) ([7b84846](https://github.com/Robitx/gp.nvim/commit/7b8484667b6ddd16189b156f72c1af0ff8e35131))

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

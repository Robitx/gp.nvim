# Changelog

## [3.9.0](https://github.com/Robitx/gp.nvim/compare/v3.8.0...v3.9.0) (2024-08-12)


### Features

* cmds without selection (issue: [#194](https://github.com/Robitx/gp.nvim/issues/194)) ([03f34e6](https://github.com/Robitx/gp.nvim/commit/03f34e6db6ed47b4ed1f75d30c1f8de056bbc366))


### Bug Fixes

* avoid cmd len limit on windows (issue: [#192](https://github.com/Robitx/gp.nvim/issues/192)) ([a2df34c](https://github.com/Robitx/gp.nvim/commit/a2df34cd3879e33333757ee6674fc5d41440ccd0))

## [3.8.0](https://github.com/Robitx/gp.nvim/compare/v3.7.1...v3.8.0) (2024-08-05)


### Features

* ollama and perplexity with llama3.1-8B ([8b448c0](https://github.com/Robitx/gp.nvim/commit/8b448c06651ebfc6b810bf37029d0a1ee43c237e))


### Bug Fixes

* git root search infinite loop on windows (issue: [#126](https://github.com/Robitx/gp.nvim/issues/126)) ([7eb91da](https://github.com/Robitx/gp.nvim/commit/7eb91daa43d5c6b318be699e2af770904625a4d6))

## [3.7.1](https://github.com/Robitx/gp.nvim/compare/v3.7.0...v3.7.1) (2024-08-05)


### Bug Fixes

* check for underflow during backticks trimming (issue: [#152](https://github.com/Robitx/gp.nvim/issues/152)) ([3510217](https://github.com/Robitx/gp.nvim/commit/3510217650e2c3fffb3fc71fd4f5233504851d02))
* don't override already added secrets (issue: [#188](https://github.com/Robitx/gp.nvim/issues/188)) ([757c78f](https://github.com/Robitx/gp.nvim/commit/757c78fb4cb17b3ec16108704a19c7b7a41ab10b))

## [3.7.0](https://github.com/Robitx/gp.nvim/compare/v3.6.1...v3.7.0) (2024-08-04)


### Features

* remember last chat without symlinks ([#176](https://github.com/Robitx/gp.nvim/issues/176)) ([df9adc2](https://github.com/Robitx/gp.nvim/commit/df9adc22450c052c9228714cde9b9cf90d6ca3e5))
* copilot with gpt4-o ([c782f9a](https://github.com/Robitx/gp.nvim/commit/c782f9ace9c95f42c3e169df8366537d8980a62f))
* better state logging ([63098a5](https://github.com/Robitx/gp.nvim/commit/63098a530a0fd5ba6dae5d7fb45236d9290ac8c2))
* lazy load secrets (issue: [#152](https://github.com/Robitx/gp.nvim/issues/152)) ([4cea5ae](https://github.com/Robitx/gp.nvim/commit/4cea5aecd1bc4ce0081d2407710ba4741f193b6e))
* configurable default agents ([#85](https://github.com/Robitx/gp.nvim/issues/85), [#148](https://github.com/Robitx/gp.nvim/issues/148)) ([49d1986](https://github.com/Robitx/gp.nvim/commit/49d1986aa98ef748397594aa26e137dbc9cb2798))

### Bug Fixes

* skip BufEnter logic if buf already prepared (issue: [#139](https://github.com/Robitx/gp.nvim/issues/139)) ([2c3d818](https://github.com/Robitx/gp.nvim/commit/2c3d818a47a9b156af921c9b768c7a31dcccf00f))

## [3.6.1](https://github.com/Robitx/gp.nvim/compare/v3.6.0...v3.6.1) (2024-08-01)


### Bug Fixes

* remove code remnant ([4c2f1d4](https://github.com/Robitx/gp.nvim/commit/4c2f1d42083905e41fe68f0fe8bc6f1b920b45e5))

## [3.6.0](https://github.com/Robitx/gp.nvim/compare/v3.5.1...v3.6.0) (2024-08-01)


### Features

* configurable zindex with default to 49 (resolve: [#132](https://github.com/Robitx/gp.nvim/issues/132)) ([6dca8ea](https://github.com/Robitx/gp.nvim/commit/6dca8ead9ffcfdb97d09a97369613ddd30170605))


### Bug Fixes

* agent refreshing for default commands ([d5fcd00](https://github.com/Robitx/gp.nvim/commit/d5fcd00b06d2dab95481f15c79eb1455ff3a4da7))
* win32 detection ([6d0f1b5](https://github.com/Robitx/gp.nvim/commit/6d0f1b5f23c3353b89d8ebadb397a5652e29cead))

## [3.5.1](https://github.com/Robitx/gp.nvim/compare/v3.5.0...v3.5.1) (2024-07-31)


### Bug Fixes

* symbolic links on Windows without admin rights ([#177](https://github.com/Robitx/gp.nvim/issues/177)) ([0f3b5bd](https://github.com/Robitx/gp.nvim/commit/0f3b5bd090871471890502a22fda3ee1abb7c8a2))

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

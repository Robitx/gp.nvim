local OPENAI_KEY = "<your_key>"
local GROQ_KEY = "<your_key>"
local OPENAI_HOST = "https://api.openai.com/v1/chat/completions"
local GROQ_HOST = "https://api.groq.com/openai/v1/chat/completions"
local GROQ_AUDIO = "https://api.groq.com/openai/v1/audio/transcriptions"

local GROQ_WHISPER_MODEL = "distil-whisper-large-v3-en";

-- Gp (GPT prompt) lua plugin for Neovim
-- https://github.com/Robitx/gp.nvim/

--------------------------------------------------------------------------------
-- Default config
--------------------------------------------------------------------------------
---@class GpConfig
-- README_REFERENCE_MARKER_START
local config = {
  providers = {
    openai = {
      endpoint = OPENAI_HOST,
      secret = OPENAI_KEY,
    },
    groq = {
      endpoint = GROQ_HOST,
      secret = GROQ_KEY,
    },
  },

  chat_shortcut_respond = { modes = { "n", "i", "v", "x" }, shortcut = "<C-g><cr>" },
  chat_confirm_delete = false,

  -- prefix for all commands
  cmd_prefix = "Gp",

  default_chat_agent = "GroqLLAMA_8B",
  whisper = {
    -- -- TODO: In the future, when gpnvim will support whisper options
    endpoint = GROQ_AUDIO,
    secret = GROQ_KEY,
    model = GROQ_WHISPER_MODEL,
    store_dir = "/tmp/gp_whisper"
  },

  agents = {
    {
      provider = "openai",
      name = "ChatGPT4o",
      chat = false,
      command = true,
      -- string with model name or table with model name and parameters
      model = { model = "gpt-4o", temperature = 0.8, top_p = 1 },
      -- system prompt (use this to specify the persona/role of the AI)
      system_prompt = "You are an AI working as a code editor.\n\n"
        .. "Please AVOID COMMENTARY OUTSIDE OF THE SNIPPET RESPONSE.\n"
        .. "START AND END YOUR ANSWER WITH:\n\n```",
    },
    {
      provider = "openai",
      name = "ChatGPT4o-mini",
      chat = true,
      command = true,
      -- string with model name or table with model name and parameters
      model = { model = "gpt-4o-mini", temperature = 0.8, top_p = 1 },
      -- system prompt (use this to specify the persona/role of the AI)
      system_prompt = "You are an AI working as a code editor.\n\n"
        .. "Please AVOID COMMENTARY OUTSIDE OF THE SNIPPET RESPONSE.\n"
        .. "START AND END YOUR ANSWER WITH:\n\n```",
    },
    {
      provider = "groq",
      name = "GroqLLAMA_8B",
      chat = true,
      command = true,
      -- string with model name or table with model name and parameters
      model = { model = "llama-3.1-70b-versatile", temperature = 0.8, top_p = 1 },
      system_prompt = "You are an AI helping the user with code and other tasks\n\n"
        .. "Please AVOID COMMENTARY OUTSIDE OF THE SNIPPET RESPONSE.\n",
    },
    {
      provider = "groq",
      name = "GroqLLAMA_8B",
      chat = true,
      command = true,
      -- string with model name or table with model name and parameters
      model = { model = "llama-3.2-11b-text-preview", temperature = 0.8, top_p = 1 },
      system_prompt = "Given a task or problem, please provide a concise and well-formatted solution or answer.\n\n"
        .. "Please keep your response within a code snippet, and avoid unnecessary commentary.\n",
    },
  },
}

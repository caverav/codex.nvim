local M = {}

local default_window = {
  width = 0.52,
  height = 0.9,
  border = "rounded",
  title = " Codex ",
}

local defaults = {
  cmd = { "codex-acp" }, -- legacy ACP path (unused when cli_cmd is set)
  cli_cmd = { "codex", "chat" }, -- direct Codex CLI invocation (default)
  cli_prompt_arg = nil,          -- e.g. "--prompt" (when set, prompt is passed as an argument instead of stdin)
  cli_env = nil,                 -- extra env for Codex CLI
  cwd = nil,
  auth_method = nil,
  prefer_embedded_context = true,
  window = default_window,
  debug = false,
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
  return M.options
end

return M

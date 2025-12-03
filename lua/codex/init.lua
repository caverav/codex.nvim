local config = require("codex.config")
local acp = require("codex.acp")
local ui = require("codex.ui")
local log = require("codex.log")

local M = {}

function M.setup(opts)
  config.setup(opts or {})
  ui.attach(acp)
  ui.on_submit = function(text)
    M.ask(text, { context_mode = config.options.prefer_embedded_context and "selection" or "file", embed_context = config.options.prefer_embedded_context })
  end
  return M
end

function M.open()
  ui.open()
end

function M.ask(prompt_text, opts)
  if not prompt_text or prompt_text == "" then
    log.error("Prompt text required")
    return
  end
  local bufnr = opts and opts.bufnr or vim.api.nvim_get_current_buf()
  ui.ask(acp, prompt_text, vim.tbl_extend("keep", opts or {}, {
    bufnr = bufnr,
    context_mode = opts and opts.context_mode or "selection",
    embed_context = config.options.prefer_embedded_context,
  }))
end

function M.cancel()
  acp.cancel()
  ui.status("Cancellation requested")
end

function M.restart()
  acp.restart(function()
    ui.status("Codex restarted")
  end)
end

function M.toggle_debug()
  config.options.debug = not config.options.debug
  ui.status("Debug " .. (config.options.debug and "on" or "off"))
end

return M

local config = require("codex.config")

local M = {}

local function fmt_message(...)
  local parts = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    table.insert(parts, type(v) == "string" and v or vim.inspect(v))
  end
  return table.concat(parts, " ")
end

function M.info(...)
  vim.notify(fmt_message(...), vim.log.levels.INFO, { title = "codex.nvim" })
end

function M.error(...)
  vim.notify(fmt_message(...), vim.log.levels.ERROR, { title = "codex.nvim" })
end

function M.debug(...)
  if not config.options.debug then
    return
  end
  vim.notify(fmt_message(...), vim.log.levels.DEBUG, { title = "codex.nvim" })
end

return M

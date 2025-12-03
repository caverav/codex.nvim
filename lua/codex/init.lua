local config = require("codex.config")
local ui = require("codex.ui")
local log = require("codex.log")
local plan = require("codex.plan")
local annotate = require("codex.annotate")

local M = {}

function M.setup(opts)
  config.setup(opts or {})
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
  ui.ask(prompt_text, vim.tbl_extend("keep", opts or {}, {
    bufnr = bufnr,
    context_mode = opts and opts.context_mode or "selection",
    embed_context = config.options.prefer_embedded_context,
  }))
end

function M.cancel()
  ui.status("Cancellation requested (no-op in CLI mode)")
end

function M.restart()
  ui.status("Restart not required in CLI mode; rerun ask.")
end

function M.plan_menu()
  plan.pick_entry(function(idx)
    local statuses = { "pending", "in_progress", "completed" }
    vim.ui.select(statuses, { prompt = "Set status" }, function(choice)
      if choice then
        plan.set_status(idx, choice)
        ui.status(("Plan %d -> %s"):format(idx, choice))
      end
    end)
  end)
end

function M.pick_mode()
  log.error("Mode picking is only available in ACP mode.")
end

function M.pick_model()
  log.error("Model picking is only available in ACP mode.")
end

function M.clear_annotations()
  annotate.clear()
  ui.status("Cleared Codex diff annotations")
end

function M.mcp_status()
  vim.notify("MCP status not available in direct CLI mode.", vim.log.levels.INFO)
end

function M.diffs_preview()
  local diffs = annotate.list()
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for path, d in pairs(diffs) do
    table.insert(lines, "==== " .. path .. " ====")
    local old_text = d.old_text or (d.diff and d.diff.old_text) or ""
    local new_text = d.new_text or d.newText or (d.diff and (d.diff.new_text or d.diff.newText)) or ""
    table.insert(lines, "--- old")
    vim.list_extend(lines, vim.split(old_text, "\n", { plain = true }))
    table.insert(lines, "+++ new")
    vim.list_extend(lines, vim.split(new_text, "\n", { plain = true }))
    table.insert(lines, "")
  end
  if #lines == 0 then
    lines = { "No diffs captured yet." }
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "diff"
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = math.floor(vim.o.columns * 0.6),
    height = math.floor(vim.o.lines * 0.7),
    row = math.floor(vim.o.lines * 0.15),
    col = math.floor(vim.o.columns * 0.2),
    style = "minimal",
    border = "rounded",
    title = " Codex diffs ",
  })
end

function M.toggle_debug()
  config.options.debug = not config.options.debug
  ui.status("Debug " .. (config.options.debug and "on" or "off"))
end

return M

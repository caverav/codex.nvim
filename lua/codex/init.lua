local config = require("codex.config")
local acp = require("codex.acp")
local ui = require("codex.ui")
local log = require("codex.log")
local plan = require("codex.plan")
local annotate = require("codex.annotate")

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
  local modes = acp.state().modes
  if not modes or not modes.available_modes then
    log.error("No modes available")
    return
  end
  local items = {}
  for _, m in ipairs(modes.available_modes) do
    table.insert(items, { id = m.id or m.modeId or m.mode_id, name = m.name or m.id, desc = m.description })
  end
  vim.ui.select(items, {
    prompt = "Select Codex mode",
    format_item = function(item)
      return string.format("%s — %s", item.name, item.desc or item.id)
    end,
  }, function(item)
    if item then
      acp.set_mode(item.id)
      ui.status("Mode -> " .. item.name)
    end
  end)
end

function M.pick_model()
  local models = acp.state().models
  local list = nil
  if models and models.available_models then
    list = models.available_models
  elseif type(models) == "table" then
    list = models
  end
  if not list or #list == 0 then
    log.error("No models available")
    return
  end
  vim.ui.select(list, { prompt = "Select Codex model" }, function(choice)
    if choice then
      local model_id = choice.id or choice.model_id or choice
      acp.set_model(model_id)
      ui.status("Model -> " .. tostring(model_id))
    end
  end)
end

function M.clear_annotations()
  annotate.clear()
  ui.status("Cleared Codex diff annotations")
end

function M.mcp_status()
  local st = acp.state()
  local mcp = st.mcp_capabilities or (st.agent_capabilities and st.agent_capabilities.mcpCapabilities)
  if not mcp then
    vim.notify("No MCP capabilities reported yet.", vim.log.levels.INFO)
    return
  end
  vim.notify(vim.inspect(mcp), vim.log.levels.INFO)
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

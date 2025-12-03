local config = require("codex.config")
local log = require("codex.log")
local context = require("codex.context")
local terminal = require("codex.terminal")
local plan = require("codex.plan")
local annotate = require("codex.annotate")

local M = {}

local state = {
  buf = nil,
  win = nil,
  input_buf = nil,
  input_win = nil,
  tool_states = {},
  source_buf = nil,
}

local highlights_applied = false

local function ensure_highlights()
  if highlights_applied then
    return
  end
  local function set(name, opts)
    if vim.fn.hlexists(name) == 0 then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end
  set("CodexHeader", { fg = "#9ece6a", bold = true })
  set("CodexAgent", { fg = "#7aa2f7" })
  set("CodexUser", { fg = "#e0af68" })
  set("CodexThought", { fg = "#bb9af7", italic = true })
  set("CodexTool", { fg = "#7dcfff" })
  set("CodexPlan", { fg = "#b4f9f8" })
  set("CodexError", { fg = "#f7768e", bold = true })
  highlights_applied = true
end

local function append_line(prefix, text, hl)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local lines = vim.split(text or "", "\n", { plain = true })
  if prefix and prefix ~= "" then
    lines[1] = prefix .. lines[1]
    for i = 2, #lines do
      lines[i] = string.rep(" ", #prefix) .. lines[i]
    end
  end
  local line_count = vim.api.nvim_buf_line_count(state.buf)
  vim.api.nvim_buf_set_lines(state.buf, line_count, line_count, false, lines)
  if hl then
    for i = 0, #lines - 1 do
      vim.api.nvim_buf_add_highlight(state.buf, -1, hl, line_count + i, 0, -1)
    end
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
  end
end

local function render_plan(update)
  if not update.entries then
    return
  end
  plan.set(update.entries)
  append_line(" PLAN ", "updated:", "CodexPlan")
  for idx, entry in ipairs(update.entries) do
    local badge = string.format(" %d. ", idx)
    local status = entry.status or "pending"
    append_line(badge, string.format("[%s] %s", status, entry.content or ""), "CodexPlan")
  end
end

local function render_tool_call(update)
  local id = update.toolCallId or update.tool_call_id or (update.id and update.id.toolCallId)
  local title = update.title or "tool"
  local status = update.status or (update.fields and update.fields.status) or "pending"
  local label = id and (" TOOL " .. tostring(id) .. " ") or " TOOL "
  append_line(label, string.format("%s (%s)", title, status), "CodexTool")
  if update.content then
    for _, block in ipairs(update.content) do
      if block.type == "text" and block.text then
        append_line("   ", block.text, "CodexTool")
      elseif block.type == "diff" and block.diff and block.diff.newText then
        append_line("   ", block.diff.newText, "CodexTool")
        annotate.annotate_diff(block.diff)
      end
    end
  end
end

local function render_content_chunk(kind, chunk)
  local block = chunk.content or chunk
  if block.type == "text" and block.text then
    local label = kind == "thought" and " » " or " ▸ "
    local hl = kind == "thought" and "CodexThought" or "CodexAgent"
    append_line(label, block.text, hl)
  elseif block.type == "resource_link" and block.uri then
    append_line(" ▸ ", ("Context: %s"):format(block.uri), "CodexAgent")
  end
end

local function handle_session_update(update)
  local tag = update.sessionUpdate or update.session_update
  if tag == "agent_message_chunk" then
    render_content_chunk("agent", update.content)
  elseif tag == "agent_thought_chunk" then
    render_content_chunk("thought", update.content)
  elseif tag == "user_message_chunk" then
    render_content_chunk("user", update.content)
  elseif tag == "tool_call" then
    render_tool_call(update)
  elseif tag == "tool_call_update" then
    render_tool_call(update.fields or update)
  elseif tag == "plan" then
    render_plan(update)
  elseif tag == "available_commands_update" then
    local cmds = update.available_commands or update.availableCommands or {}
    append_line(" CMD ", "Available: " .. #cmds, "CodexHeader")
  elseif tag == "current_mode_update" then
    append_line(" MODE ", update.current_mode_id or update.currentModeId or "updated", "CodexHeader")
  else
    append_line(" • ", vim.inspect(update), "CodexAgent")
  end
end

local function ensure_windows()
  ensure_highlights()
  local opts = config.options.window
  local total_width = math.floor(vim.o.columns * (opts.width or 0.5))
  local total_height = math.floor(vim.o.lines * (opts.height or 0.8))
  local row = math.floor((vim.o.lines - total_height) / 2)
  local col = math.floor((vim.o.columns - total_width) / 2)

  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].filetype = "codexlog"
    vim.bo[state.buf].bufhidden = "wipe"
  end

  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    state.source_buf = vim.api.nvim_get_current_buf()
    state.win = vim.api.nvim_open_win(state.buf, true, {
      relative = "editor",
      row = row,
      col = col,
      width = total_width,
      height = total_height - 4,
      style = "minimal",
      border = opts.border or "rounded",
      title = opts.title or " Codex ",
    })
    vim.wo[state.win].wrap = true
  end

  if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
    state.input_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.input_buf].filetype = "codexprompt"
    vim.bo[state.input_buf].bufhidden = "wipe"
  end

  if not state.input_win or not vim.api.nvim_win_is_valid(state.input_win) then
    state.input_win = vim.api.nvim_open_win(state.input_buf, false, {
      relative = "win",
      win = state.win,
      row = (total_height - 4) - 1,
      col = 1,
      width = total_width - 2,
      height = 3,
      border = "single",
      style = "minimal",
      focusable = true,
    })
    vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
    vim.keymap.set("n", "<CR>", function()
      local line = vim.api.nvim_get_current_line()
      if line ~= "" then
        if M.on_submit then
          M.on_submit(line)
        end
        vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
      end
    end, { buffer = state.input_buf, silent = true })
    vim.keymap.set("i", "<CR>", function()
      local line = vim.api.nvim_get_current_line()
      if line ~= "" then
        if M.on_submit then
          M.on_submit(line)
        end
        vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
      end
    end, { buffer = state.input_buf, silent = true })
    vim.api.nvim_set_current_win(state.input_win)
    vim.cmd("startinsert")
  end
end

function M.open()
  ensure_windows()
end

function M.set_source_buf(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    state.source_buf = bufnr
  end
end

function M.attach(acp)
  acp.on("session_update", function(params)
    if not params or not params.update then
      return
    end
    handle_session_update(params.update)
  end)
  acp.on("error", function(err)
    append_line(" ERR ", vim.inspect(err), "CodexError")
  end)
  acp.on("ready", function()
    append_line(" READY ", "Session started", "CodexHeader")
  end)
  terminal.on("output", function(ev)
    local chunk = table.concat(ev.chunk or {}, "\n")
    if chunk ~= "" then
      append_line(" TERM ", chunk, "CodexTool")
    end
  end)
  terminal.on("exit", function(ev)
    local status = ev.status or {}
    append_line(
      " TERM ",
      ("exit code=%s signal=%s"):format(tostring(status.exit_code), tostring(status.signal)),
      "CodexHeader"
    )
  end)
end

function M.ask(acp, prompt_text, opts)
  if opts and opts.bufnr then
    M.set_source_buf(opts.bufnr)
  end
  ensure_windows()
  append_line(" YOU ", prompt_text, "CodexUser")
  local source_buf = opts and opts.bufnr or state.source_buf or vim.api.nvim_get_current_buf()
  local blocks = context.build_prompt(prompt_text, {
    context_mode = opts and opts.context_mode or "selection",
    embed_context = opts and opts.embed_context,
    bufnr = source_buf,
    fallback_to_file = true,
  })
  acp.prompt(blocks, function(err, res)
    if err then
      append_line(" ERR ", vim.inspect(err), "CodexError")
    elseif res and (res.stop_reason or res.stopReason) then
      local reason = res.stop_reason or res.stopReason
      append_line(" DONE ", "stop_reason: " .. tostring(reason), "CodexHeader")
    end
  end)
end

function M.status(msg)
  append_line(" • ", msg, "CodexHeader")
end

return M

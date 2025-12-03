local config = require("codex.config")
local log = require("codex.log")
local Transport = require("codex.transport")

local M = {}

local listeners = {
  session_update = {},
  status = {},
  error = {},
  ready = {},
}

local function emit(kind, payload)
  if not listeners[kind] then
    return
  end
  for _, cb in ipairs(listeners[kind]) do
    local ok, err = pcall(cb, payload)
    if not ok then
      log.error("listener error", err)
    end
  end
end

function M.on(kind, cb)
  if listeners[kind] then
    table.insert(listeners[kind], cb)
  end
end

local state = {
  transport = nil,
  initialized = false,
  session_id = nil,
  agent_capabilities = nil,
  auth_methods = {},
  models = nil,
  modes = nil,
  permission_cache = {},
}

local function choose_cmd()
  local cmd = config.options.cmd
  if #cmd == 0 then
    return nil
  end
  if vim.fn.executable(cmd[1]) == 1 then
    return cmd
  end
  if cmd[1] ~= "codex" and vim.fn.executable("codex") == 1 then
    return { "codex", "acp" }
  end
  return cmd
end

local function start_transport()
  if state.transport and state.transport:is_running() then
    return true
  end
  local cmd = choose_cmd()
  if not cmd then
    log.error("No codex command configured")
    return false
  end
  state.transport = Transport.new(cmd, config.options.cwd or vim.loop.cwd())

  -- Notifications we care about
  state.transport:on_notification("session/update", function(params)
    emit("session_update", params)
  end)

  state.transport:on_request("session/request_permission", function(params)
    local request = params
    local tool_call = request.tool_call or request.toolCall or {}
    local options = request.options or {}
    local cache_key = tool_call.toolCallId or tool_call.tool_call_id or tool_call.id
    if cache_key and state.permission_cache[cache_key] then
      return { outcome = state.permission_cache[cache_key] }
    end

    local items = {}
    for _, opt in ipairs(options) do
      table.insert(items, string.format("%s — %s", opt.name, opt.kind or "choice"))
    end
    if #options == 0 then
      return { outcome = { outcome = "cancelled" } }
    end

    local choice = nil
    vim.ui.select(
      items,
      { prompt = ("Codex permission: %s"):format(tool_call.title or "tool") },
      function(_, idx)
        if not idx then
          choice = { outcome = { outcome = "cancelled" } }
          return
        end
        local selected = options[idx]
        local outcome = { outcome = "selected", optionId = selected.id or selected.optionId }
        if cache_key then
          state.permission_cache[cache_key] = outcome
        end
        choice = { outcome = outcome }
      end
    )

    -- Wait until the selection callback runs on the main loop.
    vim.wait(10000, function()
      return choice ~= nil
    end, 20)

    return choice or { outcome = { cancelled = true } }
  end)

  state.transport:on_request("fs/read_text_file", function(params)
    local path = params.path
    local limit = params.limit
    local content
    local ok, err = pcall(function()
      local fp = assert(io.open(path, "r"))
      if limit then
        local lines = {}
        for i = 1, limit do
          local line = fp:read("*line")
          if not line then
            break
          end
          table.insert(lines, line)
        end
        content = table.concat(lines, "\n")
      else
        content = fp:read("*a")
      end
      fp:close()
    end)
    if not ok then
      return nil, { code = -32000, message = err }
    end
    return { content = content }
  end)

  state.transport:on_request("fs/write_text_file", function(params)
    local path = params.path
    local content = params.content
    local ok, err = pcall(function()
      local fp = assert(io.open(path, "w"))
      fp:write(content)
      fp:close()
    end)
    if not ok then
      return nil, { code = -32000, message = err }
    end
    return {}
  end)

  local ok = state.transport:start()
  if not ok then
    return false
  end
  return true
end

local function with_request(method, params, cb)
  if not state.transport then
    emit("error", { message = "Codex transport not started" })
    return
  end
  state.transport:request(method, params, function(err, res)
    if err then
      emit("error", err)
      if cb then
        cb(err, nil)
      end
      return
    end
    if cb then
      cb(nil, res)
    end
  end)
end

local function maybe_authenticate(cb)
  if not state.auth_methods or #state.auth_methods == 0 then
    cb()
    return
  end

  local method = config.options.auth_method
  if not method or method == "" then
    if vim.env.CODEX_API_KEY then
      method = "codex-api-key"
    elseif vim.env.OPENAI_API_KEY then
      method = "openai-api-key"
    else
      method = state.auth_methods[1].id
    end
  end

  with_request("authenticate", { methodId = method }, function(err)
    if err then
      emit("error", err)
      return
    end
    cb()
  end)
end

local function new_session(cb)
  with_request("session/new", {
    cwd = vim.loop.cwd(),
    mcpServers = {},
  }, function(err, res)
    if err then
      emit("error", err)
      return
    end
    state.session_id = res.sessionId or res.session_id
    state.modes = res.modes
    state.models = res.models
    emit("ready", state)
    if cb then
      cb()
    end
  end)
end

local function initialize(cb)
  local capabilities = {
    fs = { readTextFile = true, writeTextFile = true },
    terminal = false,
    _meta = { terminal_output = false },
  }

  with_request("initialize", {
    protocolVersion = 1,
    clientCapabilities = capabilities,
    clientInfo = {
      name = "codex.nvim",
      title = "Codex.nvim",
      version = "0.1.0",
    },
  }, function(err, res)
    if err then
      emit("error", err)
      return
    end
    state.initialized = true
    state.agent_capabilities = res.agentCapabilities or res.agent_capabilities
    state.auth_methods = res.authMethods or res.auth_methods or {}
    maybe_authenticate(function()
      new_session(cb)
    end)
  end)
end

local function ensure_session(cb)
  if state.session_id and state.transport and state.transport:is_running() then
    cb()
    return
  end
  if not start_transport() then
    emit("error", { message = "Failed to start codex process" })
    return
  end
  initialize(cb)
end

function M.prompt(prompt_blocks, cb)
  ensure_session(function()
    with_request("session/prompt", {
      sessionId = state.session_id,
      prompt = prompt_blocks,
    }, cb)
  end)
end

function M.cancel()
  if not state.session_id or not state.transport then
    return
  end
  state.transport:notify("session/cancel", { sessionId = state.session_id })
end

function M.set_mode(mode_id)
  if not state.session_id then
    return
  end
  with_request("session/set_mode", {
    sessionId = state.session_id,
    modeId = mode_id,
  })
end

function M.set_model(model_id)
  if not state.session_id then
    return
  end
  with_request("session/set_model", {
    sessionId = state.session_id,
    modelId = model_id,
  })
end

function M.restart(cb)
  if state.transport then
    state.transport:stop()
  end
  state.session_id = nil
  state.initialized = false
  state.permission_cache = {}
  start_transport()
  initialize(cb)
end

function M.state()
  return state
end

return M

local log = require("codex.log")

local uv = vim.loop
local trim = vim.trim or function(s)
  return s:match("^%s*(.-)%s*$")
end

---@class CodexTransport
---@field cmd string[]
---@field cwd string|nil
---@field stdout uv_pipe_t
---@field stderr uv_pipe_t
---@field stdin uv_pipe_t
---@field handle uv_process_t
---@field buf string
---@field pending table<number, fun(err: table|string|nil, result: any|nil)>
---@field next_id integer
---@field request_handlers table<string, fun(params: table): table|nil, table|nil>
---@field notification_handlers table<string, fun(params: table)>
local Transport = {}
Transport.__index = Transport

local function encode(msg)
  msg.jsonrpc = "2.0"
  return vim.json.encode(msg) .. "\n"
end

function Transport.new(cmd, cwd)
  local t = {
    cmd = cmd,
    cwd = cwd,
    buf = "",
    pending = {},
    next_id = 0,
    request_handlers = {},
    notification_handlers = {},
    running = false,
  }
  return setmetatable(t, Transport)
end

function Transport:on_request(method, handler)
  self.request_handlers[method] = handler
end

function Transport:on_notification(method, handler)
  self.notification_handlers[method] = handler
end

local function parse_lines(state)
  while true do
    local nl = state.buf:find("\n", 1, true)
    if not nl then
      break
    end
    local line = state.buf:sub(1, nl - 1)
    state.buf = state.buf:sub(nl + 1)
    if line:match("^%s*$") then
      goto continue
    end
    local ok, msg = pcall(vim.json.decode, line)
    if not ok then
      log.error("codex transport parse error", line)
      goto continue
    end
    state:handle_message(msg)
    ::continue::
  end
end

local function send_error(self, id, code, message)
  local payload = encode({
    id = id,
    error = {
      code = code or -32603,
      message = message or "Internal error",
    },
  })
  self.stdin:write(payload)
end

function Transport:handle_message(msg)
  -- Response
  if msg.id ~= nil and (msg.result ~= nil or msg.error ~= nil) then
    local cb = self.pending[msg.id]
    if cb then
      self.pending[msg.id] = nil
      if msg.error then
        cb(msg.error, nil)
      else
        cb(nil, msg.result)
      end
    else
      log.debug("unexpected response id", msg.id)
    end
    return
  end

  -- Notification
  if msg.method and msg.id == nil then
    local handler = self.notification_handlers[msg.method]
    if handler then
      handler(msg.params or {})
    else
      log.debug("unhandled notification", msg.method, msg.params)
    end
    return
  end

  -- Request from agent -> client
  if msg.method and msg.id ~= nil then
    local handler = self.request_handlers[msg.method]
    if not handler then
      send_error(self, msg.id, -32601, "Method not found: " .. msg.method)
      return
    end
    local ok, result, err_obj = pcall(handler, msg.params or {})
    if not ok then
      send_error(self, msg.id, -32603, result)
      return
    end
    if err_obj then
      send_error(self, msg.id, err_obj.code or -32603, err_obj.message or "error")
      return
    end
    local payload = encode({ id = msg.id, result = result or {} })
    self.stdin:write(payload)
  end
end

function Transport:request(method, params, cb)
  self.next_id = self.next_id + 1
  local id = self.next_id
  if cb then
    self.pending[id] = cb
  end
  local payload = encode({
    id = id,
    method = method,
    params = params,
  })
  self.stdin:write(payload)
  return id
end

function Transport:notify(method, params)
  local payload = encode({
    method = method,
    params = params,
  })
  self.stdin:write(payload)
end

function Transport:is_running()
  return self.running
end

function Transport:stop()
  if not self.running then
    return
  end
  self.running = false
  if self.handle and not self.handle:is_closing() then
    self.handle:kill("sigterm")
    self.handle:close()
  end
  if self.stdin and not self.stdin:is_closing() then
    self.stdin:close()
  end
  if self.stdout and not self.stdout:is_closing() then
    self.stdout:close()
  end
  if self.stderr and not self.stderr:is_closing() then
    self.stderr:close()
  end
end

function Transport:start()
  if self.running then
    return true
  end

  local cmd = self.cmd
  if #cmd == 0 then
    log.error("codex transport missing command")
    return false
  end

  self.stdin = uv.new_pipe(false)
  self.stdout = uv.new_pipe(false)
  self.stderr = uv.new_pipe(false)
  self.buf = ""

  local args = {}
  for i = 2, #cmd do
    table.insert(args, cmd[i])
  end
  local spawn_opts = {
    args = args,
    stdio = { self.stdin, self.stdout, self.stderr },
  }
  if self.cwd then
    spawn_opts.cwd = self.cwd
  end

  local handle, pid = uv.spawn(cmd[1], spawn_opts, function(code, signal)
    log.debug("codex process exited", code, signal)
    self:stop()
  end)

  if not handle then
    log.error("failed to start codex process: " .. tostring(pid))
    return false
  end

  self.handle = handle
  self.running = true
  log.debug("codex process started pid=" .. pid)

  self.stdout:read_start(function(err, chunk)
    if err then
      log.error("codex stdout error", err)
      return
    end
    if not chunk then
      return
    end
    self.buf = self.buf .. chunk
    parse_lines(self)
  end)

  self.stderr:read_start(function(err, chunk)
    if err then
      log.error("codex stderr error", err)
      return
    end
    if chunk then
      log.debug("codex stderr", trim(chunk))
    end
  end)

  return true
end

return Transport

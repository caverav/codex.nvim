local log = require("codex.log")

local uv = vim.loop

local M = {}

local terminals = {}
local seq = 0
local listeners = {
  output = {},
  exit = {},
}

local function emit(kind, payload)
  for _, cb in ipairs(listeners[kind] or {}) do
    local ok, err = pcall(cb, payload)
    if not ok then
      log.error("terminal listener error", err)
    end
  end
end

function M.on(kind, cb)
  if not listeners[kind] then
    listeners[kind] = {}
  end
  table.insert(listeners[kind], cb)
end

local function enforce_limit(term, limit)
  if not limit then
    return
  end
  if #term.output > limit then
    term.output = term.output:sub(#term.output - limit + 1)
    term.truncated = true
  end
end

local function capture_output(id, data)
  local term = terminals[id]
  if not term then
    return
  end
  if data and #data > 0 then
    term.output = term.output .. table.concat(data, "\n") .. "\n"
    enforce_limit(term, term.output_byte_limit)
    emit("output", { id = id, chunk = data })
  end
end

local function decode_env(env_list)
  if not env_list then
    return nil
  end
  local env = {}
  for _, pair in ipairs(env_list) do
    if pair.name and pair.value then
      env[pair.name] = pair.value
    end
  end
  return env
end

function M.create(params)
  seq = seq + 1
  local id = tostring(seq)

  local cmd = params.command
  local args = params.args or {}
  local command = {}
  table.insert(command, cmd)
  for _, a in ipairs(args) do
    table.insert(command, a)
  end

  local term = {
    id = id,
    output = "",
    truncated = false,
    output_byte_limit = params.output_byte_limit or params.outputByteLimit,
    exit_status = nil,
    job = nil,
    waiters = {},
  }
  terminals[id] = term

  local job_id = vim.fn.jobstart(command, {
    cwd = params.cwd,
    env = decode_env(params.env),
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data, _)
      capture_output(id, data)
    end,
    on_stderr = function(_, data, _)
      capture_output(id, data)
    end,
    on_exit = function(_, code, signal)
      term.exit_status = {
        exit_code = code >= 0 and code or nil,
        signal = signal ~= 0 and tostring(signal) or nil,
      }
      emit("exit", { id = id, status = term.exit_status })
      for _, waiter in ipairs(term.waiters) do
        waiter(term.exit_status)
      end
      term.waiters = {}
    end,
  })

  if job_id <= 0 then
    terminals[id] = nil
    return nil, "failed to start terminal job"
  end

  term.job = job_id
  return id
end

function M.output(id)
  local term = terminals[id]
  if not term then
    return nil, "terminal not found"
  end
  return {
    output = term.output,
    truncated = term.truncated,
    exit_status = term.exit_status,
  }
end

function M.kill(id)
  local term = terminals[id]
  if not term then
    return nil, "terminal not found"
  end
  if term.job then
    pcall(vim.fn.jobstop, term.job)
  end
  return {}
end

function M.release(id)
  local term = terminals[id]
  if not term then
    return nil, "terminal not found"
  end
  if term.job then
    pcall(vim.fn.jobstop, term.job)
  end
  terminals[id] = nil
  return {}
end

function M.wait_for_exit(id)
  local term = terminals[id]
  if not term then
    return nil, "terminal not found"
  end
  if term.exit_status then
    return term.exit_status
  end
  local status
  local done = false
  table.insert(term.waiters, function(s)
    status = s
    done = true
  end)
  -- Block briefly waiting; fallback to whatever status is known
  vim.wait(10000, function()
    return done
  end, 50)
  return status or term.exit_status or { exit_code = nil, signal = nil }
end

return M

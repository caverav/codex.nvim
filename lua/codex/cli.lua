local uv = vim.loop
local log = require("codex.log")
local config = require("codex.config")

---@class CodexJob
---@field pid integer
---@field handle uv_process_t
---@field stdin uv_pipe_t
---@field stdout uv_pipe_t
---@field stderr uv_pipe_t
---@field buf string

local M = {}

local function spawn(cmd, cwd, on_line, on_exit)
  local stdin = uv.new_pipe(false)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  local handle, pid = uv.spawn(cmd[1], {
    args = { unpack(cmd, 2) },
    stdio = { stdin, stdout, stderr },
    cwd = cwd,
  }, function(code, signal)
    if on_exit then
      vim.schedule(function()
        on_exit(code, signal)
      end)
    end
    if handle and not handle:is_closing() then
      handle:close()
    end
    if stdin and not stdin:is_closing() then
      stdin:close()
    end
    if stdout and not stdout:is_closing() then
      stdout:close()
    end
    if stderr and not stderr:is_closing() then
      stderr:close()
    end
  end)

  if not handle then
    return nil, pid
  end

  local job = {
    pid = pid,
    handle = handle,
    stdin = stdin,
    stdout = stdout,
    stderr = stderr,
    buf = "",
  }

  stdout:read_start(function(err, chunk)
    if err then
      log.error("codex stdout err", err)
      return
    end
    if not chunk then
      return
    end
    job.buf = job.buf .. chunk
    while true do
      local nl = job.buf:find("\n", 1, true)
      if not nl then
        break
      end
      local line = job.buf:sub(1, nl - 1)
      job.buf = job.buf:sub(nl + 1)
      if on_line then
        vim.schedule(function()
          on_line(line)
        end)
      end
    end
  end)

  stderr:read_start(function(err, chunk)
    if err then
      log.error("codex stderr err", err)
      return
    end
    if chunk then
      log.debug("codex stderr", chunk)
    end
  end)

  return job
end

---Run Codex CLI with streaming output. Writes the prompt to stdin, then closes it.
---@param prompt string
---@param opts table|nil {cwd, cmd}
---@param handlers table|nil {on_line=function(line), on_exit=function(code, signal)}
function M.run(prompt, opts, handlers)
  opts = opts or {}
  handlers = handlers or {}
  local cmd = opts.cmd or config.options.cli_cmd or { "codex", "chat" }
  local cwd = opts.cwd or config.options.cwd or vim.loop.cwd()
  local job, err = spawn(cmd, cwd, handlers.on_line, handlers.on_exit)
  if not job then
    log.error("Failed to start codex CLI: " .. tostring(err))
    return
  end
  job.stdin:write(prompt .. "\n")
  job.stdin:shutdown()
end

return M

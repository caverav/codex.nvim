local ns = vim.api.nvim_create_namespace("codex-annotations")

local M = {}

local noted_paths = {}

local function place(path, text)
  local bufnr = vim.fn.bufnr(path, false)
  if bufnr == -1 then
    return
  end
  local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, 0, 0, {
    virt_text = { { text, "CodexTool" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
  if ok then
    noted_paths[path] = true
  end
end

function M.annotate_diff(diff)
  local path = diff.path or (diff.diff and diff.diff.path)
  if not path or noted_paths[path] then
    return
  end
  local label = ("Codex patch pending: %s"):format(tostring(path))
  place(path, label)
end

function M.clear()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
  end
  noted_paths = {}
end

return M

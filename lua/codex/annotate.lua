local ns = vim.api.nvim_create_namespace("codex-annotations")

local M = {}

local noted_paths = {}
local stored_diffs = {}

local function buf_for_path(path)
  return vim.fn.bufnr(path, false)
end

local function find_match(bufnr, old_lines)
  if #old_lines == 0 then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local n = #lines
  local m = #old_lines
  for i = 1, n - m + 1 do
    local match = true
    for j = 1, m do
      if lines[i + j - 1] ~= old_lines[j] then
        match = false
        break
      end
    end
    if match then
      return i - 1 -- zero-based
    end
  end
  return nil
end

local function virt_lines_for_diff(old_lines, new_lines)
  local virt = {}
  for _, l in ipairs(old_lines) do
    table.insert(virt, { { "- " .. l, "DiffDelete" } })
  end
  for _, l in ipairs(new_lines) do
    table.insert(virt, { { "+ " .. l, "DiffAdd" } })
  end
  return virt
end

local function annotate_block(bufnr, start_line, old_lines, new_lines, path)
  local virt = virt_lines_for_diff(old_lines, new_lines)
  if #virt > 0 then
    local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, start_line, 0, {
      virt_lines = virt,
      virt_lines_above = true,
      hl_mode = "combine",
    })
    if ok then
      noted_paths[path] = true
    end
  end
end

function M.annotate_diff(diff)
  if not diff then
    return
  end
  local path = diff.path or (diff.diff and diff.diff.path)
  if not path then
    return
  end
  stored_diffs[path] = diff

  local bufnr = buf_for_path(path)
  if bufnr == -1 then
    return
  end

  local old_text = diff.old_text or (diff.diff and diff.diff.old_text)
  local new_text = diff.new_text or diff.newText or (diff.diff and (diff.diff.new_text or diff.diff.newText))

  local old_lines = vim.split(old_text or "", "\n", { plain = true })
  local new_lines = vim.split(new_text or "", "\n", { plain = true })

  local pos = find_match(bufnr, old_lines)
  if not pos then
    -- fallback: top-of-file marker
    local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, 0, 0, {
      virt_text = { { "Codex patch pending for " .. path, "CodexTool" } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
    if ok then
      noted_paths[path] = true
    end
    return
  end

  annotate_block(bufnr, pos, old_lines, new_lines, path)
end

function M.clear()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
  end
  noted_paths = {}
  stored_diffs = {}
end

function M.list()
  return stored_diffs
end

return M

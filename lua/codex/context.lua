local M = {}

local function current_file_uri(range, bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr or 0)
  if path == "" then
    return nil
  end
  local uri = "file://" .. path
  if range and range.start_line and range.end_line then
    uri = string.format("%s#L%d-L%d", uri, range.start_line, range.end_line)
  end
  return uri
end

function M.text_block(text)
  return {
    type = "text",
    text = text,
  }
end

function M.resource_block(content, uri)
  return {
    type = "resource",
    resource = {
      text = content,
      uri = uri or "untitled://buffer",
      mimeType = "text/plain",
    },
  }
end

function M.resource_link(name, uri)
  return {
    type = "resource_link",
    name = name or "context",
    uri = uri,
    mimeType = "text/plain",
  }
end

local function get_visual_selection(bufnr)
  local mode = vim.fn.mode()
  if not mode:match("[vV\x16]") then
    return nil
  end
  bufnr = bufnr or 0
  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")
  local start_line = math.min(start_pos[2], end_pos[2])
  local end_line = math.max(start_pos[2], end_pos[2])
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  return table.concat(lines, "\n"), start_line, end_line
end

function M.build_prompt(prompt_text, opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  if bufnr and not vim.api.nvim_buf_is_valid(bufnr) then
    return blocks
  end
  local blocks = { M.text_block(prompt_text) }

  local context_mode = opts.context_mode or "selection"
  local embed = opts.embed_context ~= false
  local fallback_to_file = opts.fallback_to_file ~= false

  if context_mode == "selection" then
    local selected, s_line, e_line = get_visual_selection(bufnr)
    if selected and selected ~= "" then
      local uri = current_file_uri({ start_line = s_line, end_line = e_line }, bufnr) or "selection://"
      table.insert(blocks, embed and M.resource_block(selected, uri) or M.resource_link("selection", uri))
    elseif fallback_to_file then
      context_mode = "file"
    end
  elseif context_mode == "file" then
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path ~= "" then
      local uri = "file://" .. path
      if embed then
        local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        table.insert(blocks, M.resource_block(content, uri))
      else
        local name = vim.fs.basename(path)
        table.insert(blocks, M.resource_link(name, uri))
      end
    end
  end

  return blocks
end

local function read_file(path)
  local ok, data = pcall(vim.fn.readfile, path)
  if not ok or not data then
    return nil
  end
  return table.concat(data, "\n")
end

function M.build_cli_prompt(prompt_text, opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  local context_mode = opts.context_mode or "selection"
  local embed = opts.embed_context ~= false
  local text = prompt_text

  local function append_block(title, body)
    text = text
      .. "\n\n"
      .. title
      .. "\n```\n"
      .. body
      .. "\n```"
  end

  if context_mode == "selection" then
    local selected, _, _ = get_visual_selection(bufnr)
    if selected and selected ~= "" then
      local uri = current_file_uri(nil, bufnr) or "selection://"
      if embed then
        append_block("Context (" .. uri .. ")", selected)
      else
        text = text .. "\n\nContext: " .. uri
      end
    end
  end

  if context_mode == "file" then
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path ~= "" then
      local uri = "file://" .. path
      if embed then
        local content = read_file(path)
        if content and content ~= "" then
          append_block("Context (" .. uri .. ")", content)
        end
      else
        text = text .. "\n\nContext: " .. uri
      end
    end
  end

  return text
end

return M

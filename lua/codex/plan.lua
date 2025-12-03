local M = {}

local plan = {
  entries = {},
}

function M.set(entries)
  plan.entries = entries or {}
end

function M.get()
  return plan.entries
end

local function status_label(entry)
  local status = entry.status or "pending"
  return status
end

function M.pick_entry(on_choice)
  if #plan.entries == 0 then
    vim.notify("No plan entries", vim.log.levels.INFO)
    return
  end
  local items = {}
  for i, entry in ipairs(plan.entries) do
    table.insert(items, string.format("%d. [%s] %s", i, status_label(entry), entry.content or ""))
  end
  vim.ui.select(items, { prompt = "Select plan item" }, function(_, idx)
    if idx and on_choice then
      on_choice(idx, plan.entries[idx])
    end
  end)
end

function M.set_status(idx, status)
  if not plan.entries[idx] then
    return
  end
  plan.entries[idx].status = status
end

return M

local codex = require("codex")

codex.setup()

vim.api.nvim_create_user_command("CodexOpen", function()
  codex.open()
end, { desc = "Open Codex chat UI" })

vim.api.nvim_create_user_command("CodexAsk", function(opts)
  codex.ask(opts.args, { context_mode = "selection" })
end, { nargs = "*", desc = "Send a prompt to Codex using selection/file context" })

vim.api.nvim_create_user_command("CodexCancel", function()
  codex.cancel()
end, { desc = "Cancel the current Codex turn" })

vim.api.nvim_create_user_command("CodexRestart", function()
  codex.restart()
end, { desc = "Restart Codex agent process" })

vim.api.nvim_create_user_command("CodexDebug", function()
  codex.toggle_debug()
end, { desc = "Toggle Codex debug logging" })

vim.api.nvim_create_user_command("CodexPlan", function()
  codex.plan_menu()
end, { desc = "Inspect and edit Codex plan entries" })

vim.api.nvim_create_user_command("CodexMode", function()
  codex.pick_mode()
end, { desc = "Pick Codex session mode" })

vim.api.nvim_create_user_command("CodexModel", function()
  codex.pick_model()
end, { desc = "Pick Codex model" })

vim.api.nvim_create_user_command("CodexClearAnnotations", function()
  codex.clear_annotations()
end, { desc = "Clear Codex diff annotations" })

vim.api.nvim_create_user_command("CodexMcp", function()
  codex.mcp_status()
end, { desc = "Show MCP status (from session)" })

vim.api.nvim_create_user_command("CodexDiffs", function()
  codex.diffs_preview()
end, { desc = "Preview captured Codex diffs" })

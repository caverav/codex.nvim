# codex.nvim

Neovim bridge for the Codex CLI (and `codex-acp`). It speaks the [Agent Client Protocol](https://agentclientprotocol.com) directly over stdio, streams Codex output into a sleek floating UI, and lets you push buffer context or selected code to Codex with one command.

## Highlights
- **Native ACP client** – JSON‑RPC v2 over newline frames; implements `initialize`, `authenticate`, `session/new`, `session/prompt`, `session/cancel`, `session/set_mode`, `fs/*`, and `session/request_permission`.
- **Streaming chat UI** – minimal, responsive floating window with inline status chips for thoughts, tool calls, and plan updates. Designed to stay out of your way while coding.
- **Context pipes** – send visual selection, current file, or arbitrary resource blocks (embedded or links) with the prompt. File reads/writes are served back to Codex via ACP `fs/*` when enabled.
- **Permission workflows** – `session/request_permission` prompts through `vim.ui.select`; approvals are remembered per session.
- **Graceful failure modes** – reconnect/restart the agent, surface structured errors, and keep a tail buffer of raw ACP traffic for debugging.

## Installation

Use your favorite plugin manager. Example with `lazy.nvim`:

```lua
{
  "caverav/codex.nvim",
  opts = {
    cmd = { "codex-acp" },       -- or { "codex", "acp" }
    auth_method = nil,           -- override: "codex-api-key", "openai-api-key", "chatgpt"
    prefer_embedded_context = true,
    window = { width = 0.5, height = 0.9, border = "rounded" },
  },
}
```

Requirements:
- `codex-acp` (from https://github.com/zed-industries/codex-acp) or Codex CLI with `codex acp` on your PATH.
- Neovim >= 0.9 with `vim.json` and `vim.ui.select`.

Once pushed to GitHub (`caverav/codex.nvim`), it can be required directly by lazy.nvim or any other manager.

## Usage

### Commands
- `:CodexOpen` – open the floating chat view (auto-starts the agent).
- `:CodexAsk {prompt}` – send a one-off prompt using visual selection or current buffer as context.
- `:CodexCancel` – send `session/cancel`.
- `:CodexRestart` – restart the Codex agent process.
- `:CodexMode` / `:CodexModel` – pick session mode or model.
- `:CodexPlan` – inspect/edit the current plan statuses (local).
- `:CodexDiffs` – preview captured diffs in a scratch window.
- `:CodexClearAnnotations` – clear inline diff annotations.
- `:CodexMcp` – show MCP status (placeholder).

### Lua API

```lua
local codex = require("codex")

codex.setup({
  cmd = { "codex-acp" },
  cwd = vim.loop.cwd(),
})

codex.open() -- open UI

codex.ask("Refactor this function", {
  context = { mode = "selection" }, -- "selection" | "file" | "none"
  embed_context = true,
})
```

### Context sending
- **Selection**: visual selection is embedded as a `resource` block (`type: resource` with `text` + `uri`).
- **File**: current file is referenced as a `resourceLink` (`uri: file://...`), optionally embedded if `prefer_embedded_context = true`.

### Terminals
- Advertises `terminal/*` support to the agent.
- Agent-driven commands run via `jobstart`; output is streamed to the Codex UI and served back through `terminal/output`.
- Kill/Release/Wait are implemented; output truncation honors `outputByteLimit` when provided.

### Authentication
The plugin tries to auto-pick a method after `initialize`:
1. `auth_method` option if set.
2. `CODEX_API_KEY` env → `"codex-api-key"`.
3. `OPENAI_API_KEY` env → `"openai-api-key"`.
4. Fall back to the first method offered by the agent (usually `"chatgpt"`).

## Design notes
- **Transport**: newline-delimited JSON-RPC 2.0 (no `Content-Length` headers). Each message contains `jsonrpc: "2.0"`.
- **Capabilities**: advertises `fs.read_text_file`/`write_text_file` when the agent runs locally, `terminal = false` by default.
- **Permissions**: `session/request_permission` is mapped to `vim.ui.select`; the choice is cached for the tool call id.
- **UI**: uses a dedicated scratch buffer for the transcript and a second buffer for the input line. Colors are namespaced under `Codex*` highlight groups; override them in your colorscheme as desired.

## Debugging
- Run with `:lua require('codex').toggle_debug()` to mirror raw ACP messages into `:messages`.
- If the agent dies, `:CodexRestart` respawns the process and re-runs `initialize`/`new_session`.

## Roadmap
- Plan sync back to agent when supported.
- MCP server discovery UI.
- Rich diff annotations (hunks, virtual lines).

## License
MIT

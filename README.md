# codex.nvim

Neovim bridge for the Codex CLI. Streams Codex output into a sleek floating UI, and lets you push buffer context or selected code to Codex with one command. Uses the Codex CLI directly (no ACP required).

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
    cli_cmd = { "codex", "review" }, -- good for code review; or { "codex", "chat" } for general chat
    prefer_embedded_context = true,
    window = { width = 0.5, height = 0.9, border = "rounded" },
  },
}
```

Requirements:
- Codex CLI on your PATH (`codex review` or `codex chat`).
- Neovim >= 0.9 with `vim.json` and `vim.ui.select`.

## Usage

### Commands
- `:CodexOpen` – open the floating chat view.
- `:CodexAsk {prompt}` – send a one-off prompt using visual selection or current buffer as context.
- `gf` inside the Codex window – jump to file paths mentioned in output (respects `path:line`).
- `:CodexPlan` – inspect/edit the current plan statuses (local).
- `:CodexDiffs` – preview captured diffs in a scratch window.
- `:CodexClearAnnotations` – clear inline diff annotations.

### Lua API

```lua
local codex = require("codex")

codex.setup({
  cli_cmd = { "codex", "review" },
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

### CLI mode
- Streams Codex CLI stdout line-by-line into the floating buffer.
- Uses `cli_cmd` (default `{ "codex", "chat" }`, recommended `{ "codex", "review" }` for code reviews).
- Writes the user prompt to stdin, then closes it.
- Paths in output are underlined; press `gf` on them to jump to the file (line numbers respected).

## Roadmap
- Full Codex/ACP dual mode with selectable backend.
- Richer diff annotations (hunks, virtual lines) and patch application helpers.

## License
MIT

---
name: auto-shutdown
description: >-
  Control the Auto Shutdown guard for Antigravity: open the native Auto Shutdown
  side panel or inline status card, arm one-shot or continuous auto-shutdown,
  hibernate, or sleep after all active conversations and background tasks finish,
  cancel countdowns, or run a safe dry-run preview. Use when the user mentions
  auto-shutdown, shutting down after tasks finish, overnight runs, or opening
  the Auto Shutdown panel.
---

# Auto Shutdown Control Skill

Prefer the plugin's built-in **MCP App tools** (namespaced under `auto-shutdown_guard`) so the native-themed UI renders directly inside Antigravity:

- **Open native side panel** (`open_panel`): Opens Auto Shutdown right beside the conversation in the Side Panel (also available anytime from the side panel `+` menu and **Plugins** in the left sidebar).
- **Show compact inline card** (`show_status_card`): Renders a sleek live status and one-click Arm / Cancel card directly inside the chat thread.
- **Arm guard** (`arm_guard`): Accepts `{ mode: "once" | "continuous", action: "shutdown" | "hibernate" | "sleep", graceSeconds: 10..3600 }`. Default to `"once"` unless the user explicitly asks for `"continuous"`.
- **Disarm guard** (`disarm_guard`): Disarms the guard and cancels any active countdown.
- **Cancel countdown** (`cancel_countdown`): Immediately aborts an active countdown.

## CLI Fallback (Antigravity CLI or Terminal)

If MCP tools are unavailable (for example in terminal-only sessions), resolve the plugin root (`../../scripts/ctl.mjs` relative to this skill folder):

```bash
node ../../scripts/ctl.mjs status
node ../../scripts/ctl.mjs arm --mode once --action shutdown --grace 120
node ../../scripts/ctl.mjs disarm
node ../../scripts/ctl.mjs cancel
node ../../scripts/ctl.mjs preview --seconds 15
node ../../scripts/ctl.mjs clear-stale
# Optional Windows-only standalone desktop pill:
node ../../scripts/ctl.mjs ui
```

## Safety Rules

- Always default to `mode: "once"` so the guard auto-disarms before powering off.
- Never trigger immediate shutdown unless the user explicitly asks to shut down right now.
- Mention the configured grace countdown and note that any new turn or clicking **Cancel** immediately aborts shutdown.

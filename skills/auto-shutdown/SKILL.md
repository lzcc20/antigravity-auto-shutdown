---
name: auto-shutdown
description: >-
  Control the Auto Shutdown guard for Antigravity: arm one-shot or continuous
  auto-shutdown/hibernate/sleep after all active conversations and background
  tasks finish, inspect active tasks, cancel countdowns, run a safe dry-run
  preview, or open the bottom-right floating control widget. Use when the user
  mentions auto-shutdown, shutting down after tasks finish, overnight runs,
  or opening the bottom-right shutdown widget.
---

# Auto Shutdown Control Skill

Use the bundled controller script (`../../scripts/ctl.mjs` relative to this skill directory) via `run_command` to manage the Auto Shutdown guard and its bottom-right floating UI.

## Common Operations

Resolve the plugin root from this skill directory (two levels up from `skills/auto-shutdown/`) and run:

- **Check status & active tasks**:
  ```bash
  node ../../scripts/ctl.mjs status
  ```
- **Arm one-shot auto-shutdown** (recommended for overnight runs; auto-disarms before executing):
  ```bash
  node ../../scripts/ctl.mjs arm --mode once --action shutdown --grace 120
  ```
- **Arm with hibernate or sleep**:
  ```bash
  node ../../scripts/ctl.mjs arm --mode once --action hibernate --grace 120
  node ../../scripts/ctl.mjs arm --mode once --action sleep --grace 60
  ```
- **Arm continuous guard** (stays armed across runs until manually disarmed):
  ```bash
  node ../../scripts/ctl.mjs arm --mode continuous --action shutdown --grace 120
  ```
- **Disarm guard and cancel any active countdown**:
  ```bash
  node ../../scripts/ctl.mjs disarm
  ```
- **Cancel an active countdown without changing armed preference**:
  ```bash
  node ../../scripts/ctl.mjs cancel
  ```
- **Open the minimalist bottom-right floating widget (Windows)**:
  ```bash
  node ../../scripts/ctl.mjs ui
  # Or open expanded directly:
  node ../../scripts/ctl.mjs ui --expanded
  ```
- **Run a safe 15-second dry-run preview** (never powers off the machine):
  ```bash
  node ../../scripts/ctl.mjs preview --seconds 15
  ```
- **Update appearance or safety options**:
  ```bash
  node ../../scripts/ctl.mjs config --theme dark --lang zh-CN --ignore-cancel true --always-on-top true
  ```
- **Clear stale tracked sessions**:
  ```bash
  node ../../scripts/ctl.mjs clear-stale
  ```

## Safety Rules

- Always default to `--mode once` unless the user explicitly asks for continuous monitoring.
- Never run `execute-now` unless the user explicitly asks to shut down immediately.
- Remind the user of the configured grace countdown and that any new turn or clicking **Cancel** in the bottom-right widget immediately aborts shutdown.

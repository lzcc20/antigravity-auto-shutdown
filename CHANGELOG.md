# Changelog

All notable changes to **Auto Shutdown** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-11-23

### Added
- Official Antigravity plugin manifest (`plugin.json`) passing `agy plugin validate --strict`.
- Cross-conversation lifecycle hook engine (`hooks.json` + `scripts/engine.mjs` + `scripts/hook.mjs`):
  - Tracks concurrent Antigravity conversations (`PreInvocation`, `PostToolUse`, `PostInvocation`, `Stop`).
  - Respects `fullyIdle` so background tasks, timers, and subagents keep the session alive until completion.
  - Cross-process lockfile and atomic JSON writes for safe parallel execution.
  - Stale session pruning with `transcriptPath` mtime awareness.
- Detached countdown supervisor (`scripts/countdown-worker.mjs`):
  - Double-checked locking before power execution.
  - Auto-cancels immediately if any new agent turn starts during the grace window.
  - One-shot guard auto-disarms before executing shutdown/hibernate/sleep so the next boot starts clean.
  - Safe dry-run preview mode (`preview`) for testing the full countdown UX without powering off.
- Minimalist bottom-right Windows floating widget (`scripts/widget.ps1`):
  - Compact floating pill pinned cleanly to the bottom-right corner above the taskbar; expands upward into a refined control card.
  - Obsidian Matte Dark & Warm Alabaster Light themes (auto-follows Windows dark/light theme or manual toggle).
  - Bilingual `zh-CN` / `en` instant switch.
  - System tray icon with live semantic status dot and quick context menu.
- Bundled Antigravity Skill (`skills/auto-shutdown/SKILL.md`) for `/auto-shutdown` and natural-language control.
- Zero-dependency unit test suite (`tests/engine.test.mjs`) and GitHub Actions CI workflow.
- Cross-platform install & uninstall scripts (`install.bat`, `uninstall.bat`, `install.sh`, `uninstall.sh`).

# Contributing to Auto Shutdown

Thank you for your interest in contributing to **Auto Shutdown**!

## Project Layout

```text
antigravity-auto-shutdown/
├── plugin.json                  # Antigravity plugin manifest
├── hooks.json                   # Lifecycle hooks (SessionStart, PreInvocation, PostToolUse, PostInvocation, Stop)
├── assets/                      # Bundled SVG logo and UI preview screenshots
├── skills/auto-shutdown/        # Antigravity Skill (/auto-shutdown)
├── scripts/
│   ├── engine.mjs               # Zero-dependency state machine, lockfile, atomic storage, OS power commands
│   ├── hook.mjs                 # Hook stdin/stdout runner
│   ├── countdown-worker.mjs     # Detached countdown supervisor
│   ├── ctl.mjs                  # CLI controller
│   ├── launch-widget.mjs        # Detached widget & worker launcher
│   ├── widget.ps1               # Windows native WPF bottom-right floating UI + system tray
│   └── i18n.json                # UTF-8 zh-CN / en UI strings
└── tests/
    └── engine.test.mjs          # Unit tests (node --test)
```

## Development & Verification

1. **Zero external runtime dependencies**: Keep the core engine pure Node.js ESM (`>= 18`) and the Windows UI pure built-in WPF (`PresentationFramework`).
2. **Run unit tests**:
   ```bash
   node --test tests/engine.test.mjs
   ```
3. **Validate Antigravity plugin compliance**:
   ```bash
   agy plugin validate --strict .
   ```
4. **Safe UI testing**: Always use dry-run preview (`node scripts/ctl.mjs preview --seconds 15`) or `-DataDir <temp-dir>` when testing countdown flows so your machine never powers off unexpectedly.
5. **PowerShell 5.1 encoding safety**: Keep `scripts/widget.ps1` pure ASCII and place all localized strings in `scripts/i18n.json` (read explicitly as UTF-8) so Windows systems of any locale render text cleanly.

## Pull Requests

- Keep PRs focused and include unit tests for any state-machine or hook behavior changes.
- Update `CHANGELOG.md` and `README.md` / `README.zh-CN.md` when adding user-facing options.

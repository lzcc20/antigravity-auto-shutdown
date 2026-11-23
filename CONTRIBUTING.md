# Contributing to Auto Shutdown

Thank you for your interest in contributing to **Auto Shutdown**!

## Project Layout

```text
antigravity-auto-shutdown/
├── plugin.json                  # Antigravity plugin manifest
├── hooks.json                   # Lifecycle hooks (SessionStart, PreInvocation, PostToolUse, PostInvocation, Stop)
├── mcp_config.json              # Native MCP App server declaration
├── ui/app.html                  # Pre-bundled single-file MCP App UI (zero runtime install needed)
├── web/app.html                 # Source template for the native MCP App UI
├── assets/                      # Bundled SVG logo and UI preview screenshots
├── skills/auto-shutdown/        # Antigravity Skill (/auto-shutdown)
├── scripts/
│   ├── engine.mjs               # Zero-dependency state machine, lockfile, atomic storage, OS power commands
│   ├── hook.mjs                 # Hook stdin/stdout runner
│   ├── mcp-server.mjs           # Zero-dependency stdio MCP App server
│   ├── countdown-worker.mjs     # Detached countdown supervisor
│   ├── ctl.mjs                  # CLI controller
│   ├── build-ui.mjs             # Rebuilds ui/app.html from web/app.html + @modelcontextprotocol/ext-apps
│   ├── launch-widget.mjs        # Detached worker & optional Windows widget launcher
│   ├── widget.ps1               # Optional standalone Windows WPF desktop widget
│   └── i18n.json                # UTF-8 zh-CN / en strings for optional widget
└── tests/
    ├── engine.test.mjs          # State machine unit tests
    └── mcp.test.mjs             # Stdio MCP App server integration tests
```

## Development & Verification

1. **Zero external runtime dependencies**: End users should never need `npm install`. Keep all `scripts/*.mjs` pure Node.js ESM (`>= 18`), and rebuild `ui/app.html` via `node scripts/build-ui.mjs` whenever editing `web/app.html`.
2. **Run all tests**:
   ```bash
   node --test tests/engine.test.mjs tests/mcp.test.mjs
   ```
3. **Validate Antigravity plugin compliance**:
   ```bash
   agy plugin validate --strict .
   ```
4. **Safe UI testing**: Use `Safe Dry-Run Preview` (`演练`) or isolated temp directories (`AUTO_SHUTDOWN_DATA_DIR`) so countdown tests never power off your development machine.

# Changelog

All notable changes to **Auto Shutdown** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-11-23

### Added
- **Native Antigravity MCP App UI** (`mcp_config.json` + `scripts/mcp-server.mjs` + `ui/app.html`):
  - Seamless first-party Antigravity look & feel using `@modelcontextprotocol/ext-apps` host CSS tokens (`--color-background-*`, `--color-text-*`, `--color-border-*`, `--font-sans`) and `prefersBorder: false`.
  - **Side Panel (`aux_pane`)**: Open directly beside any conversation from the Side Panel **`+`** menu, **Overview → Plugins**, or agent tools.
  - **Left Sidebar Full Page (`global`)**: Open full-width from **Plugins → Auto Shutdown** in Antigravity's left sidebar (responsive Settings-like layout).
  - **Inline Chat Card (`show_status_card`)**: Compact live status & one-click Arm/Cancel card rendered directly in the chat stream.
  - Zero runtime dependencies: pure Node.js stdio MCP server + pre-bundled single-file `ui/app.html`, working identically across Windows, macOS, and Linux.
- Added end-to-end stdio MCP server test suite (`tests/mcp.test.mjs`).
- Added `THIRD-PARTY-NOTICES.md` for bundled `@modelcontextprotocol/ext-apps` (MIT).
- Added dedicated English and Simplified Chinese high-DPI preview screenshots (`README.md` and `README.zh-CN.md`).

### Changed
- Disabled automatic launch of the external Windows floating widget (`autoLaunchWidget: false`) so the native Antigravity MCP App UI is the default unobtrusive experience (the optional Windows floating pill remains available via `node scripts/ctl.mjs ui`).

## [1.0.0] - 2026-11-23

### Added
- Initial release with Antigravity official lifecycle hooks (`hooks.json`), multi-conversation tracking with `fullyIdle` awareness, one-shot auto-disarm guardrails, detached countdown supervisor, `/auto-shutdown` Skill, and optional Windows WPF floating widget.

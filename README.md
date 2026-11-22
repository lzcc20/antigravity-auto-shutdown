<div align="center">
  <img src="assets/logo.svg" alt="Auto Shutdown Logo" width="76" height="76" />
  <h1>Auto Shutdown for Antigravity</h1>
  <p>
    <strong>Understated, rock-solid auto-shutdown guard for overnight Antigravity agent runs.</strong><br/>
    Tracks every active conversation and background task via official lifecycle hooks, then gracefully shuts down, hibernates, or sleeps your machine once all work is truly idle — paired with a quiet, minimalist bottom-right floating UI.
  </p>

  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="#installation">Installation</a> ·
    <a href="#how-it-works">How It Works</a> ·
    <a href="#cli--skill-commands">CLI &amp; Skill</a> ·
    <a href="CHANGELOG.md">Changelog</a>
  </p>

  <p>
    <img src="https://img.shields.io/badge/Antigravity-Plugin_v1-181A1F?style=flat-square&logoColor=white" alt="Antigravity Plugin" />
    <img src="https://img.shields.io/badge/Dependencies-Zero-2F855A?style=flat-square" alt="Zero Dependencies" />
    <img src="https://img.shields.io/badge/License-MIT-555?style=flat-square" alt="MIT License" />
    <img src="https://img.shields.io/badge/Platform-Windows_UI_%7C_macOS_%7C_Linux-3A3F4B?style=flat-square" alt="Platform Support" />
  </p>
</div>

---

## Preview

Minimalist matte aesthetics anchored cleanly to the **bottom-right corner** above the taskbar — collapses into a whisper-quiet capsule pill and expands upward into a tactile control card. Auto-adapts to Windows Dark / Light mode with one-click `ZH` / `EN` switching.

<div align="center">
  <p><strong>Compact Bottom-Right Capsule</strong></p>
  <img src="assets/preview-pill-dark.png" alt="Compact Bottom-Right Pill" />
</div>

<br/>

<div align="center">
  <table>
    <tr>
      <td align="center"><strong>Obsidian Matte (Dark · Countdown)</strong></td>
      <td align="center"><strong>Warm Alabaster (Light · Active Tasks)</strong></td>
    </tr>
    <tr>
      <td align="center"><img src="assets/preview-card-dark.png" alt="Expanded Dark Card" width="330" /></td>
      <td align="center"><img src="assets/preview-card-light.png" alt="Expanded Light Card" width="330" /></td>
    </tr>
  </table>
</div>

---

## Features

- **Accurate Multi-Task & Background Detection** — Uses Antigravity's official `hooks.json` (`SessionStart`, `PreInvocation`, `PostToolUse`, `PostInvocation`, `Stop`) without altering or weakening tool permissions (`PreToolUse` is untouched). Respects `fullyIdle` so background commands, timers, and subagents keep the session alive until every single job completes.
- **Multi-Conversation Safe** — Tracks all parallel Antigravity conversations concurrently with cross-process file locking and atomic JSON writes. Countdown begins only when **every** tracked session has finished.
- **Anti-Misfire Guardrails**
  - **One-shot by default**: Disarms itself *before* issuing the OS power command so your next boot starts cleanly disarmed.
  - **Grace countdown + Instant auto-cancel**: Defaults to a 120-second grace window (`30s / 60s / 2m / 5m`). If any new turn, tool call, or reactive subagent wakes up during the countdown, it aborts automatically.
  - **Skip on manual cancel**: Optionally ignores `USER_CANCELED` stops so pressing Stop while debugging never shuts down your PC.
  - **Stale session pruning**: Auto-expires abandoned/crashed tabs using activity timestamps and `transcriptPath` mtime checks.
  - **Safe Dry-Run Preview**: Built-in `Preview` (`演练`) button lets you experience the live countdown & cancel flow without ever powering off.
- **Zero Dependencies** — Core engine runs on pure Node.js ESM (`>= 18`); the Windows bottom-right widget & system tray run natively on built-in Windows WPF (no Electron, no npm packages).
- **Natural-Language Control (`/auto-shutdown`)** — Bundled Antigravity Skill lets you arm, disarm, inspect tasks, or summon the bottom-right widget directly from chat.

---

## Installation

### Option 1: Antigravity CLI (Recommended)

```bash
git clone https://github.com/lzcc20/antigravity-auto-shutdown.git
agy plugin install ./antigravity-auto-shutdown
```

### Option 2: One-Click Install Scripts

**Windows**
```cmd
git clone https://github.com/lzcc20/antigravity-auto-shutdown.git
cd antigravity-auto-shutdown
install.bat
```

**macOS / Linux**
```bash
git clone https://github.com/lzcc20/antigravity-auto-shutdown.git
cd antigravity-auto-shutdown
sh install.sh
```

> User settings and runtime state are stored separately at `~/.gemini/config/auto-shutdown/`, so updating or reinstalling the plugin preserves your preferences.

### Uninstall

Run `uninstall.bat` (Windows), `sh uninstall.sh` (macOS/Linux), or uninstall directly from Antigravity's **Customizations** page.

---

## How It Works

```text
Antigravity Lifecycle Hooks                     Bottom-Right UI / CLI / Skill
───────────────────────────                     ─────────────────────────────
PreInvocation / PostToolUse ──▶ engine.mjs ◀──▶ config.json & state.json (atomic + lock)
                                     │                         │
Stop (fullyIdle: false)     ──▶ keep active                    ▼
Stop (fullyIdle: true)      ──▶ remove session        widget.ps1 (Windows WPF)
                                     │                · Bottom-right pill ↔ card
                     activeSessions == 0 && armed?    · System tray icon + menu
                                     │                · Live task list & 1-click Cancel
                                     ▼
                         countdown-worker.mjs
                         · Re-checks state every 500ms
                         · Auto-aborts on any new task
                         · Disarms one-shot BEFORE power off
                         · Executes shutdown / hibernate / sleep
```

> **Tip for overnight runs**: Pair this plugin with Antigravity's `/goal` command when kicking off long unattended jobs, and arm **One-shot** (`单次布防`) right before stepping away. Note that conversations already running *before* the plugin was enabled won't be registered until their next hook event.

---

## CLI & Skill Commands

In Antigravity chat, invoke `/auto-shutdown` or simply say *"arm auto-shutdown after tasks finish"* / *"open the bottom-right shutdown widget"*.

From a terminal (inside the plugin folder):

| Command | Description |
| --- | --- |
| `node scripts/ctl.mjs status` | Show guard status, active tasks, and countdown state |
| `node scripts/ctl.mjs arm --mode once --action shutdown --grace 120` | Arm one-shot auto-shutdown with 120s grace period |
| `node scripts/ctl.mjs arm --mode continuous --action hibernate --grace 60` | Arm continuous hibernate guard |
| `node scripts/ctl.mjs disarm` | Disarm guard and cancel any active countdown |
| `node scripts/ctl.mjs cancel` | Cancel current countdown immediately |
| `node scripts/ctl.mjs ui` | Show / focus the bottom-right floating widget (Windows) |
| `node scripts/ctl.mjs ui --expanded` | Open the widget directly in expanded card mode |
| `node scripts/ctl.mjs preview --seconds 15` | Run a safe 15s dry-run preview (never powers off) |
| `node scripts/ctl.mjs clear-stale` | Clear tracked sessions manually |

---

## Configuration

Stored at `~/.gemini/config/auto-shutdown/config.json`:

| Field | Default | Values / Notes |
| --- | --- | --- |
| `armed` | `false` | Whether the guard is currently armed |
| `mode` | `"once"` | `"once"` (auto-disarms before execution) or `"continuous"` |
| `action` | `"shutdown"` | `"shutdown"`, `"hibernate"`, or `"sleep"` |
| `graceSeconds` | `120` | Countdown buffer in seconds (`10`–`3600`) |
| `ignoreUserCancel` | `true` | Skip countdown when `terminationReason === "USER_CANCELED"` |
| `ignoreErrors` | `false` | Skip countdown when `terminationReason === "ERROR"` |
| `staleTimeoutMinutes` | `15` | Auto-prune sessions inactive beyond N minutes (also checks transcript mtime) |
| `alwaysOnTop` | `true` | Keep bottom-right widget floating above windows |
| `autoLaunchWidget` | `true` | Automatically start the Windows widget on `SessionStart` |
| `theme` | `"auto"` | `"auto"` (follows Windows theme), `"dark"`, or `"light"` |
| `language` | `"zh-CN"` | `"zh-CN"` or `"en"` |
| `dryRun` | `false` | Simulate power actions without shutting down |

---

## Development & Testing

```bash
# Run unit tests
node --test tests/engine.test.mjs

# Validate Antigravity plugin manifest & hooks strictly
agy plugin validate --strict .
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE) © 2026 lzcc20

import {
  getDataDir,
  readConfig,
  readState,
  updateConfig,
  cancelCountdown,
  startPreviewCountdown,
  clearActiveSessions,
  finalizeCountdownExecution,
  pruneStaleSessions,
} from './engine.mjs';
import { launchWidget, spawnCountdownWorker } from './launch-widget.mjs';

function parseFlags(argv) {
  const flags = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      flags[key] = true;
    } else {
      flags[key] = next;
      i++;
    }
  }
  return flags;
}

function parseBool(v) {
  if (typeof v === 'boolean') return v;
  if (v === 'true' || v === '1' || v === 'yes') return true;
  if (v === 'false' || v === '0' || v === 'no') return false;
  return undefined;
}

function formatStatus(config, state) {
  const sessions = Object.values(state.activeSessions || {});
  const cd = state.countdown || {};
  const lines = [
    `Auto Shutdown Guard`,
    `  Armed:           ${config.armed ? `YES (${config.mode})` : 'NO'}`,
    `  Power action:    ${config.action}`,
    `  Grace period:    ${config.graceSeconds}s`,
    `  Active tasks:    ${sessions.length}`,
  ];
  for (const s of sessions) {
    const elapsedSec = Math.max(0, Math.floor((Date.now() - (s.startedAt || Date.now())) / 1000));
    lines.push(`    - [${s.status}] ${s.label} (${elapsedSec}s)`);
  }
  if (cd.active) {
    const remainSec = Math.max(0, Math.ceil(((cd.executeAt || 0) - Date.now()) / 1000));
    lines.push(`  Countdown:       ACTIVE (${remainSec}s -> ${cd.action}${cd.preview ? ', DRY RUN' : ''})`);
  } else {
    lines.push(`  Countdown:       inactive`);
  }
  return lines.join('\n');
}

function main() {
  const [cmd = 'status', ...rest] = process.argv.slice(2);
  const flags = parseFlags(rest);
  const dataDir = flags['data-dir'] || getDataDir();
  const asJson = Boolean(flags.json);

  if (cmd === 'status') {
    const config = readConfig(dataDir);
    const state = readState(dataDir);
    pruneStaleSessions(state, config);
    if (asJson) {
      process.stdout.write(JSON.stringify({ dataDir, config, state }, null, 2) + '\n');
    } else {
      process.stdout.write(formatStatus(config, state) + '\n');
    }
    return;
  }

  if (cmd === 'arm') {
    const patch = { armed: true };
    if (flags.mode) patch.mode = flags.mode;
    if (flags.action) patch.action = flags.action;
    if (flags.grace) patch.graceSeconds = Number(flags.grace);
    const config = updateConfig(dataDir, patch);
    if (flags.ui !== 'false' && config.autoLaunchWidget && process.platform === 'win32') {
      launchWidget({ dataDir });
    }
    process.stdout.write(
      asJson
        ? JSON.stringify({ ok: true, config }, null, 2) + '\n'
        : `Guard armed (${config.mode}): ${config.action} after ${config.graceSeconds}s grace period.\n`
    );
    return;
  }

  if (cmd === 'disarm') {
    const config = updateConfig(dataDir, { armed: false });
    cancelCountdown(dataDir, 'Disarmed via CLI');
    process.stdout.write(asJson ? JSON.stringify({ ok: true, config }, null, 2) + '\n' : 'Guard disarmed.\n');
    return;
  }

  if (cmd === 'cancel') {
    const res = cancelCountdown(dataDir, 'Cancelled via CLI');
    process.stdout.write(
      asJson ? JSON.stringify({ ok: true, ...res }, null, 2) + '\n' : 'Countdown cancelled.\n'
    );
    return;
  }

  if (cmd === 'config') {
    const patch = {};
    if (flags.armed !== undefined) patch.armed = parseBool(flags.armed);
    if (flags.mode) patch.mode = flags.mode;
    if (flags.action) patch.action = flags.action;
    if (flags.grace) patch.graceSeconds = Number(flags.grace);
    if (flags.theme) patch.theme = flags.theme;
    if (flags.lang) patch.language = flags.lang;
    if (flags['ignore-cancel'] !== undefined) patch.ignoreUserCancel = parseBool(flags['ignore-cancel']);
    if (flags['ignore-errors'] !== undefined) patch.ignoreErrors = parseBool(flags['ignore-errors']);
    if (flags['always-on-top'] !== undefined) patch.alwaysOnTop = parseBool(flags['always-on-top']);
    if (flags['auto-launch'] !== undefined) patch.autoLaunchWidget = parseBool(flags['auto-launch']);
    if (flags['dry-run'] !== undefined) patch.dryRun = parseBool(flags['dry-run']);
    const config = updateConfig(dataDir, patch);
    process.stdout.write(JSON.stringify(config, null, 2) + '\n');
    return;
  }

  if (cmd === 'ui') {
    const res = launchWidget({ dataDir, expanded: Boolean(flags.expanded), forceShow: true });
    process.stdout.write(JSON.stringify(res) + '\n');
    return;
  }

  if (cmd === 'preview') {
    const seconds = Number(flags.seconds || 15);
    const res = startPreviewCountdown(dataDir, seconds);
    spawnCountdownWorker({ dataDir, startedAt: res.startedAt });
    if (process.platform === 'win32') {
      launchWidget({ dataDir });
    }
    process.stdout.write(
      asJson
        ? JSON.stringify({ ok: true, ...res }, null, 2) + '\n'
        : `Dry-run preview countdown started (${seconds}s). No actual power action will run.\n`
    );
    return;
  }

  if (cmd === 'execute-now') {
    const res = finalizeCountdownExecution(dataDir, { force: true });
    process.stdout.write(JSON.stringify(res) + '\n');
    return;
  }

  if (cmd === 'clear-stale') {
    const res = clearActiveSessions(dataDir);
    process.stdout.write(
      asJson
        ? JSON.stringify({ ok: true, cleared: res.cleared }, null, 2) + '\n'
        : `Cleared ${res.cleared} tracked session(s).\n`
    );
    return;
  }

  process.stderr.write(
    `Unknown command: ${cmd}\nUsage: node scripts/ctl.mjs <status|arm|disarm|cancel|config|ui|preview|execute-now|clear-stale>\n`
  );
  process.exit(1);
}

main();

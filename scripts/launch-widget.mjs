import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { getDataDir } from './engine.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function launchWidget({ dataDir = getDataDir(), expanded = false, forceShow = false } = {}) {
  if (process.platform !== 'win32') {
    return { launched: false, reason: 'native_widget_windows_only' };
  }

  const widgetScript = path.join(__dirname, 'widget.ps1');
  const i18nPath = path.join(__dirname, 'i18n.json');
  const psArgs = [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-STA',
    '-WindowStyle',
    'Hidden',
    '-File',
    widgetScript,
    '-DataDir',
    dataDir,
    '-I18nPath',
    i18nPath,
  ];
  if (expanded) psArgs.push('-StartExpanded');
  if (forceShow) psArgs.push('-ForceShow');

  try {
    const child = spawn('powershell.exe', psArgs, {
      detached: true,
      stdio: 'ignore',
      windowsHide: true,
    });
    child.unref();
    return { launched: true, pid: child.pid };
  } catch (err) {
    return { launched: false, reason: err?.message || 'spawn_failed' };
  }
}

export function spawnCountdownWorker({ dataDir = getDataDir(), startedAt } = {}) {
  const workerScript = path.join(__dirname, 'countdown-worker.mjs');
  const args = [workerScript, '--data-dir', dataDir];
  if (Number.isFinite(startedAt)) {
    args.push('--expected-started-at', String(startedAt));
  }
  const child = spawn(process.execPath, args, {
    detached: true,
    stdio: 'ignore',
    windowsHide: true,
  });
  child.unref();
  return { pid: child.pid };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const expanded = process.argv.includes('--expanded');
  const res = launchWidget({ expanded, forceShow: true });
  process.stdout.write(JSON.stringify(res) + '\n');
}

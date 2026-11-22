import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

export const DEFAULT_CONFIG = Object.freeze({
  armed: false,
  mode: 'once', // 'once' | 'continuous'
  action: 'shutdown', // 'shutdown' | 'hibernate' | 'sleep'
  graceSeconds: 120,
  ignoreUserCancel: true,
  ignoreErrors: false,
  staleTimeoutMinutes: 15,
  alwaysOnTop: true,
  autoLaunchWidget: true,
  theme: 'auto', // 'auto' | 'dark' | 'light'
  language: 'zh-CN', // 'zh-CN' | 'en'
  dryRun: false,
});

const VALID_MODES = new Set(['once', 'continuous']);
const VALID_ACTIONS = new Set(['shutdown', 'hibernate', 'sleep']);
const VALID_THEMES = new Set(['auto', 'dark', 'light']);
const VALID_LANGUAGES = new Set(['zh-CN', 'en']);

export function getDataDir(env = process.env) {
  const custom = env.AUTO_SHUTDOWN_DATA_DIR?.trim();
  if (custom) return path.resolve(custom);
  // Keep a deterministic shared location across hook invocations, CLI, and widget.
  return path.join(os.homedir(), '.gemini', 'config', 'auto-shutdown');
}

export function getConfigPath(dataDir = getDataDir()) {
  return path.join(dataDir, 'config.json');
}

export function getStatePath(dataDir = getDataDir()) {
  return path.join(dataDir, 'state.json');
}

export function ensureDataDir(dataDir = getDataDir()) {
  fs.mkdirSync(dataDir, { recursive: true });
  return dataDir;
}

export function createEmptyState(now = Date.now()) {
  return {
    version: 1,
    updatedAt: now,
    activeSessions: {},
    countdown: {
      active: false,
      preview: false,
      action: 'shutdown',
      startedAt: null,
      executeAt: null,
      graceSeconds: 120,
      reason: '',
      workerPid: null,
    },
    lastEvent: null,
    history: [],
  };
}

export function sanitizeConfig(raw = {}) {
  const cfg = { ...DEFAULT_CONFIG };
  if (typeof raw?.armed === 'boolean') cfg.armed = raw.armed;
  if (VALID_MODES.has(raw?.mode)) cfg.mode = raw.mode;
  if (VALID_ACTIONS.has(raw?.action)) cfg.action = raw.action;
  if (Number.isFinite(Number(raw?.graceSeconds))) {
    cfg.graceSeconds = Math.max(10, Math.min(3600, Math.round(Number(raw.graceSeconds))));
  }
  if (typeof raw?.ignoreUserCancel === 'boolean') cfg.ignoreUserCancel = raw.ignoreUserCancel;
  if (typeof raw?.ignoreErrors === 'boolean') cfg.ignoreErrors = raw.ignoreErrors;
  if (Number.isFinite(Number(raw?.staleTimeoutMinutes))) {
    cfg.staleTimeoutMinutes = Math.max(1, Math.min(240, Math.round(Number(raw.staleTimeoutMinutes))));
  }
  if (typeof raw?.alwaysOnTop === 'boolean') cfg.alwaysOnTop = raw.alwaysOnTop;
  if (typeof raw?.autoLaunchWidget === 'boolean') cfg.autoLaunchWidget = raw.autoLaunchWidget;
  if (VALID_THEMES.has(raw?.theme)) cfg.theme = raw.theme;
  if (VALID_LANGUAGES.has(raw?.language)) cfg.language = raw.language;
  if (typeof raw?.dryRun === 'boolean') cfg.dryRun = raw.dryRun;
  return cfg;
}

function sleepSync(ms) {
  const arr = new Int32Array(new SharedArrayBuffer(4));
  Atomics.wait(arr, 0, 0, Math.max(1, ms));
}

export function writeJsonAtomic(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const payload = JSON.stringify(data, null, 2) + '\n';
  const tmpPath = `${filePath}.${process.pid}.${Date.now()}.${Math.random().toString(16).slice(2, 8)}.tmp`;
  fs.writeFileSync(tmpPath, payload, 'utf8');
  let lastErr = null;
  for (let attempt = 0; attempt < 8; attempt++) {
    try {
      fs.renameSync(tmpPath, filePath);
      return;
    } catch (err) {
      lastErr = err;
      if (err?.code === 'EPERM' || err?.code === 'EBUSY' || err?.code === 'EACCES') {
        sleepSync(15 + attempt * 15);
        continue;
      }
      break;
    }
  }
  try {
    // Fallback direct write if rename was temporarily blocked by a reader on Windows.
    fs.writeFileSync(filePath, payload, 'utf8');
  } finally {
    try { fs.unlinkSync(tmpPath); } catch {}
  }
  if (lastErr && !fs.existsSync(filePath)) throw lastErr;
}

export function readJsonSafe(filePath, fallback) {
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const raw = fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '');
      if (!raw.trim()) return fallback;
      return JSON.parse(raw);
    } catch (err) {
      if (err?.code === 'ENOENT') return fallback;
      if (attempt < 4) sleepSync(15);
    }
  }
  return fallback;
}

export function withLock(dataDir, fn, { timeoutMs = 2500, staleLockMs = 6000 } = {}) {
  ensureDataDir(dataDir);
  const lockPath = path.join(dataDir, 'state.lock');
  const deadline = Date.now() + timeoutMs;
  let fd = null;

  while (Date.now() <= deadline) {
    try {
      fd = fs.openSync(lockPath, 'wx');
      fs.writeFileSync(fd, `${process.pid}:${Date.now()}`, 'utf8');
      break;
    } catch (err) {
      if (err?.code !== 'EEXIST') throw err;
      try {
        const stat = fs.statSync(lockPath);
        if (Date.now() - stat.mtimeMs > staleLockMs) {
          try { fs.unlinkSync(lockPath); } catch {}
          continue;
        }
      } catch {}
      sleepSync(15 + Math.floor(Math.random() * 25));
    }
  }

  try {
    return fn();
  } finally {
    if (fd !== null) {
      try { fs.closeSync(fd); } catch {}
      try { fs.unlinkSync(lockPath); } catch {}
    }
  }
}

export function readConfig(dataDir = getDataDir()) {
  const raw = readJsonSafe(getConfigPath(dataDir), null);
  return sanitizeConfig(raw || {});
}

export function writeConfig(dataDir, config) {
  const sanitized = sanitizeConfig(config);
  writeJsonAtomic(getConfigPath(dataDir), sanitized);
  return sanitized;
}

export function updateConfig(dataDir, patch) {
  return withLock(dataDir, () => {
    const current = readConfig(dataDir);
    const next = sanitizeConfig({ ...current, ...patch });
    writeJsonAtomic(getConfigPath(dataDir), next);

    // If user disarmed while a real countdown was active, cancel the countdown immediately.
    if (!next.armed) {
      const state = readStateUnlocked(dataDir);
      if (state.countdown?.active && !state.countdown.preview) {
        clearCountdownFields(state, 'Disarmed by user', Date.now());
        writeJsonAtomic(getStatePath(dataDir), state);
      }
    }
    return next;
  });
}

function readStateUnlocked(dataDir) {
  const raw = readJsonSafe(getStatePath(dataDir), null);
  const base = createEmptyState();
  if (!raw || typeof raw !== 'object') return base;
  return {
    ...base,
    ...raw,
    activeSessions: raw.activeSessions && typeof raw.activeSessions === 'object' ? raw.activeSessions : {},
    countdown: { ...base.countdown, ...(raw.countdown || {}) },
    history: Array.isArray(raw.history) ? raw.history.slice(-20) : [],
  };
}

export function readState(dataDir = getDataDir()) {
  return readStateUnlocked(dataDir);
}

function appendHistory(state, entry) {
  if (!Array.isArray(state.history)) state.history = [];
  state.history.push(entry);
  if (state.history.length > 20) {
    state.history = state.history.slice(-20);
  }
}

function clearCountdownFields(state, note, now = Date.now()) {
  state.countdown = {
    active: false,
    preview: false,
    action: state.countdown?.action || 'shutdown',
    startedAt: null,
    executeAt: null,
    graceSeconds: state.countdown?.graceSeconds || 120,
    reason: note || '',
    workerPid: null,
  };
  state.updatedAt = now;
  state.lastEvent = {
    event: 'CountdownCancelled',
    conversationId: '',
    timestamp: now,
    note: note || 'Countdown cancelled',
  };
  appendHistory(state, state.lastEvent);
}

export function pruneStaleSessions(state, config, now = Date.now()) {
  const staleMs = Math.max(1, config.staleTimeoutMinutes || 15) * 60 * 1000;
  const removed = [];
  for (const [id, session] of Object.entries(state.activeSessions || {})) {
    const lastActivity = Number(session?.lastActivityAt || session?.startedAt || 0);
    if (now - lastActivity <= staleMs) continue;

    // If the transcript file was touched recently (e.g. long streaming or command), keep the session alive.
    let transcriptFresh = false;
    if (session?.transcriptPath) {
      try {
        const st = fs.statSync(session.transcriptPath);
        if (now - st.mtimeMs <= staleMs) {
          session.lastActivityAt = Math.max(lastActivity, Math.floor(st.mtimeMs));
          transcriptFresh = true;
        }
      } catch {}
    }

    if (!transcriptFresh) {
      delete state.activeSessions[id];
      removed.push(id);
    }
  }
  return removed;
}

function deriveLabel(payload) {
  const input = typeof payload?.lastUserInput === 'string' ? payload.lastUserInput.trim().replace(/\s+/g, ' ') : '';
  if (input) return input.length > 44 ? `${input.slice(0, 44)}…` : input;
  const cwd = payload?.cwd || (Array.isArray(payload?.workspacePaths) ? payload.workspacePaths[0] : '');
  if (cwd) return path.basename(cwd) || cwd;
  const cid = String(payload?.conversationId || 'session');
  return `Session ${cid.slice(0, 8)}`;
}

function deriveWorkspace(payload) {
  const cwd = payload?.cwd || (Array.isArray(payload?.workspacePaths) ? payload.workspacePaths[0] : '');
  return cwd ? path.basename(cwd) : '';
}

export function processHookEvent(payload = {}, { dataDir = getDataDir(), now = Date.now() } = {}) {
  const eventName = String(payload?.hookEventName || '');
  const conversationId = String(payload?.conversationId || '').trim() || 'default';

  return withLock(dataDir, () => {
    const config = readConfig(dataDir);
    const state = readStateUnlocked(dataDir);
    const actions = {
      spawnCountdown: null,
      cancelOsShutdown: false,
      launchWidget: false,
    };

    pruneStaleSessions(state, config, now);

    const recordEvent = (note) => {
      state.updatedAt = now;
      state.lastEvent = {
        event: eventName || 'Unknown',
        conversationId,
        timestamp: now,
        note,
      };
      appendHistory(state, state.lastEvent);
    };

    const touchSession = (status, extra = {}) => {
      const existing = state.activeSessions[conversationId];
      state.activeSessions[conversationId] = {
        conversationId,
        label: deriveLabel(payload) || existing?.label || `Session ${conversationId.slice(0, 8)}`,
        workspace: deriveWorkspace(payload) || existing?.workspace || '',
        status,
        lastTool: extra.lastTool ?? existing?.lastTool ?? '',
        transcriptPath: payload?.transcriptPath || existing?.transcriptPath || '',
        startedAt: existing?.startedAt || now,
        lastActivityAt: now,
      };
    };

    const cancelActiveCountdown = (note) => {
      if (state.countdown?.active) {
        clearCountdownFields(state, note, now);
        actions.cancelOsShutdown = true;
      }
    };

    if (eventName === 'SessionStart') {
      if (config.autoLaunchWidget) {
        actions.launchWidget = true;
      }
      recordEvent('Session started');
      writeJsonAtomic(getStatePath(dataDir), state);
      return { hookOutput: {}, actions, state, config };
    }

    if (eventName === 'PreInvocation') {
      touchSession('thinking');
      cancelActiveCountdown('Auto-cancelled: new agent turn started');
      recordEvent('Agent turn started');
      writeJsonAtomic(getStatePath(dataDir), state);
      return { hookOutput: {}, actions, state, config };
    }

    if (eventName === 'PostToolUse') {
      const toolName = payload?.toolCall?.name || '';
      touchSession('thinking', { lastTool: toolName });
      cancelActiveCountdown('Auto-cancelled: tool activity detected');
      recordEvent(toolName ? `Tool completed: ${toolName}` : 'Tool completed');
      writeJsonAtomic(getStatePath(dataDir), state);
      return { hookOutput: {}, actions, state, config };
    }

    if (eventName === 'PostInvocation') {
      if (state.activeSessions[conversationId]) {
        touchSession('thinking');
      }
      recordEvent('Invocation finished');
      writeJsonAtomic(getStatePath(dataDir), state);
      return { hookOutput: {}, actions, state, config };
    }

    if (eventName === 'Stop') {
      const fullyIdle = payload?.fullyIdle !== false;
      const reason = String(payload?.terminationReason || 'NO_TOOL_CALL');

      if (!fullyIdle) {
        // Background tasks / subagents / timers are still running in this conversation.
        touchSession('waiting_background');
        recordEvent('Waiting for background tasks');
        writeJsonAtomic(getStatePath(dataDir), state);
        return { hookOutput: { decision: 'allow' }, actions, state, config };
      }

      delete state.activeSessions[conversationId];
      const remaining = Object.keys(state.activeSessions).length;

      if (remaining > 0) {
        recordEvent(`Session stopped; ${remaining} session(s) still active`);
        writeJsonAtomic(getStatePath(dataDir), state);
        return { hookOutput: { decision: 'allow' }, actions, state, config };
      }

      if (!config.armed) {
        recordEvent('All sessions idle (guard disarmed)');
        writeJsonAtomic(getStatePath(dataDir), state);
        return { hookOutput: { decision: 'allow' }, actions, state, config };
      }

      if (reason === 'USER_CANCELED' && config.ignoreUserCancel) {
        recordEvent('All sessions idle (skipped: user canceled)');
        writeJsonAtomic(getStatePath(dataDir), state);
        return { hookOutput: { decision: 'allow' }, actions, state, config };
      }

      if (reason === 'ERROR' && config.ignoreErrors) {
        recordEvent('All sessions idle (skipped: terminated with error)');
        writeJsonAtomic(getStatePath(dataDir), state);
        return { hookOutput: { decision: 'allow' }, actions, state, config };
      }

      // All sessions are genuinely idle and guard is armed -> schedule countdown!
      const graceSeconds = config.graceSeconds || 120;
      const executeAt = now + graceSeconds * 1000;
      state.countdown = {
        active: true,
        preview: Boolean(config.dryRun),
        action: config.action,
        startedAt: now,
        executeAt,
        graceSeconds,
        reason: `All tasks idle (${reason})`,
        workerPid: null,
      };
      actions.spawnCountdown = {
        startedAt: now,
        executeAt,
        action: config.action,
        preview: Boolean(config.dryRun),
      };
      if (config.autoLaunchWidget) {
        actions.launchWidget = true;
      }
      recordEvent(`Countdown started (${graceSeconds}s -> ${config.action})`);
      writeJsonAtomic(getStatePath(dataDir), state);
      return { hookOutput: { decision: 'allow' }, actions, state, config };
    }

    recordEvent(`Unhandled hook event: ${eventName}`);
    writeJsonAtomic(getStatePath(dataDir), state);
    return { hookOutput: {}, actions, state, config };
  });
}

export function cancelCountdown(dataDir = getDataDir(), note = 'Cancelled by user', now = Date.now()) {
  const result = withLock(dataDir, () => {
    const state = readStateUnlocked(dataDir);
    const wasActive = Boolean(state.countdown?.active);
    clearCountdownFields(state, note, now);
    writeJsonAtomic(getStatePath(dataDir), state);
    return { wasActive, state };
  });
  abortOsShutdown();
  return result;
}

export function startPreviewCountdown(dataDir = getDataDir(), seconds = 15, now = Date.now()) {
  const graceSeconds = Math.max(5, Math.min(120, Math.round(Number(seconds) || 15)));
  return withLock(dataDir, () => {
    const config = readConfig(dataDir);
    const state = readStateUnlocked(dataDir);
    const executeAt = now + graceSeconds * 1000;
    state.countdown = {
      active: true,
      preview: true,
      action: config.action,
      startedAt: now,
      executeAt,
      graceSeconds,
      reason: 'Dry-run preview countdown',
      workerPid: null,
    };
    state.updatedAt = now;
    state.lastEvent = {
      event: 'PreviewStarted',
      conversationId: '',
      timestamp: now,
      note: `Dry-run preview (${graceSeconds}s)`,
    };
    appendHistory(state, state.lastEvent);
    writeJsonAtomic(getStatePath(dataDir), state);
    return { startedAt: now, executeAt, action: config.action, preview: true, state };
  });
}

export function clearActiveSessions(dataDir = getDataDir(), now = Date.now()) {
  return withLock(dataDir, () => {
    const state = readStateUnlocked(dataDir);
    const count = Object.keys(state.activeSessions || {}).length;
    state.activeSessions = {};
    state.updatedAt = now;
    state.lastEvent = {
      event: 'SessionsCleared',
      conversationId: '',
      timestamp: now,
      note: `Cleared ${count} tracked session(s)`,
    };
    appendHistory(state, state.lastEvent);
    writeJsonAtomic(getStatePath(dataDir), state);
    return { cleared: count, state };
  });
}

export function finalizeCountdownExecution(
  dataDir,
  { expectedStartedAt = null, force = false, now = Date.now(), executor = executePowerAction } = {}
) {
  let actionToRun = null;
  let isPreview = false;

  const decision = withLock(dataDir, () => {
    const config = readConfig(dataDir);
    const state = readStateUnlocked(dataDir);

    if (!force) {
      if (!state.countdown?.active) return { execute: false, reason: 'not_active' };
      if (expectedStartedAt !== null && state.countdown.startedAt !== expectedStartedAt) {
        return { execute: false, reason: 'superseded' };
      }
      pruneStaleSessions(state, config, now);
      if (!state.countdown.preview && Object.keys(state.activeSessions).length > 0) {
        clearCountdownFields(state, 'Auto-cancelled before execution: active session found', now);
        writeJsonAtomic(getStatePath(dataDir), state);
        return { execute: false, reason: 'sessions_active' };
      }
      if (now < (state.countdown.executeAt || 0)) {
        return { execute: false, reason: 'not_due' };
      }
    }

    actionToRun = state.countdown?.action || config.action || 'shutdown';
    isPreview = Boolean(state.countdown?.preview || config.dryRun);

    // Clear countdown state BEFORE executing power command so reboot starts clean.
    state.countdown = {
      active: false,
      preview: false,
      action: actionToRun,
      startedAt: null,
      executeAt: null,
      graceSeconds: config.graceSeconds,
      reason: isPreview ? 'Preview finished (no power action taken)' : `Executed ${actionToRun}`,
      workerPid: null,
    };
    state.updatedAt = now;
    state.lastEvent = {
      event: isPreview ? 'PreviewCompleted' : 'PowerActionExecuted',
      conversationId: '',
      timestamp: now,
      note: isPreview ? `Dry-run completed (${actionToRun})` : `Executing ${actionToRun}`,
    };
    appendHistory(state, state.lastEvent);
    writeJsonAtomic(getStatePath(dataDir), state);

    // One-shot mode: disarm BEFORE shutting down so the next boot starts safely disarmed.
    if (!isPreview && config.mode === 'once' && config.armed) {
      writeJsonAtomic(getConfigPath(dataDir), sanitizeConfig({ ...config, armed: false }));
    }

    return { execute: true, action: actionToRun, preview: isPreview };
  });

  if (decision.execute && !decision.preview) {
    executor(decision.action, { dryRun: false });
  }
  return decision;
}

export function abortOsShutdown({ platform = process.platform, execSyncImpl = execFileSync } = {}) {
  try {
    if (platform === 'win32') {
      execSyncImpl('shutdown.exe', ['/a'], { stdio: 'ignore', windowsHide: true });
    } else if (platform === 'linux') {
      execSyncImpl('shutdown', ['-c'], { stdio: 'ignore' });
    }
  } catch {
    // Expected when no OS-level shutdown is currently scheduled.
  }
}

export function executePowerAction(action = 'shutdown', { dryRun = false, platform = process.platform, execSyncImpl = execFileSync } = {}) {
  if (dryRun) return { executed: false, dryRun: true, action };

  if (platform === 'win32') {
    if (action === 'shutdown') {
      execSyncImpl('shutdown.exe', ['/s', '/t', '0', '/c', 'Antigravity Auto Shutdown: all tasks completed'], {
        stdio: 'ignore',
        windowsHide: true,
      });
    } else if (action === 'hibernate') {
      execSyncImpl('shutdown.exe', ['/h'], { stdio: 'ignore', windowsHide: true });
    } else if (action === 'sleep') {
      execSyncImpl(
        'powershell.exe',
        [
          '-NoProfile',
          '-WindowStyle',
          'Hidden',
          '-Command',
          'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, $false, $false) | Out-Null',
        ],
        { stdio: 'ignore', windowsHide: true }
      );
    }
    return { executed: true, platform, action };
  }

  if (platform === 'darwin') {
    if (action === 'shutdown') {
      execSyncImpl('osascript', ['-e', 'tell app "System Events" to shut down'], { stdio: 'ignore' });
    } else if (action === 'sleep' || action === 'hibernate') {
      execSyncImpl('pmset', ['sleepnow'], { stdio: 'ignore' });
    }
    return { executed: true, platform, action };
  }

  // Linux
  const verb = action === 'hibernate' ? 'hibernate' : action === 'sleep' ? 'suspend' : 'poweroff';
  execSyncImpl('systemctl', [verb], { stdio: 'ignore' });
  return { executed: true, platform, action };
}

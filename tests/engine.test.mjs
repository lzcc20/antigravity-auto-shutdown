import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  readConfig,
  readState,
  updateConfig,
  processHookEvent,
  cancelCountdown,
  startPreviewCountdown,
  finalizeCountdownExecution,
  clearActiveSessions,
} from '../scripts/engine.mjs';

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'agy-auto-shutdown-test-'));
}

test('single session finishes while disarmed -> does NOT start countdown', () => {
  const dir = makeTempDir();
  const t0 = 1_700_000_000_000;

  processHookEvent(
    { hookEventName: 'PreInvocation', conversationId: 'conv-1', lastUserInput: 'Build app' },
    { dataDir: dir, now: t0 }
  );
  assert.equal(Object.keys(readState(dir).activeSessions).length, 1);

  const stopRes = processHookEvent(
    { hookEventName: 'Stop', conversationId: 'conv-1', fullyIdle: true, terminationReason: 'NO_TOOL_CALL' },
    { dataDir: dir, now: t0 + 5000 }
  );
  assert.equal(stopRes.hookOutput.decision, 'allow');
  assert.equal(stopRes.actions.spawnCountdown, null);
  assert.equal(readState(dir).countdown.active, false);
  assert.equal(Object.keys(readState(dir).activeSessions).length, 0);
});

test('multi-session parallel tracking -> countdown starts ONLY after ALL sessions become fullyIdle', () => {
  const dir = makeTempDir();
  const t0 = 1_700_000_000_000;
  updateConfig(dir, { armed: true, mode: 'once', action: 'shutdown', graceSeconds: 90 });

  processHookEvent({ hookEventName: 'PreInvocation', conversationId: 'conv-a', lastUserInput: 'Task A' }, { dataDir: dir, now: t0 });
  processHookEvent({ hookEventName: 'PreInvocation', conversationId: 'conv-b', lastUserInput: 'Task B' }, { dataDir: dir, now: t0 + 1000 });
  assert.equal(Object.keys(readState(dir).activeSessions).length, 2);

  // Task A stops while Task B is still running -> no countdown
  const resA = processHookEvent(
    { hookEventName: 'Stop', conversationId: 'conv-a', fullyIdle: true, terminationReason: 'NO_TOOL_CALL' },
    { dataDir: dir, now: t0 + 2000 }
  );
  assert.equal(resA.actions.spawnCountdown, null);
  assert.equal(Object.keys(readState(dir).activeSessions).length, 1);

  // Task B stops with fullyIdle: false (background task still running) -> still no countdown
  const resBWait = processHookEvent(
    { hookEventName: 'Stop', conversationId: 'conv-b', fullyIdle: false, terminationReason: 'NO_TOOL_CALL' },
    { dataDir: dir, now: t0 + 3000 }
  );
  assert.equal(resBWait.actions.spawnCountdown, null);
  assert.equal(readState(dir).activeSessions['conv-b'].status, 'waiting_background');

  // Task B wakes up and completes fullyIdle: true -> countdown starts!
  const resBDone = processHookEvent(
    { hookEventName: 'Stop', conversationId: 'conv-b', fullyIdle: true, terminationReason: 'NO_TOOL_CALL' },
    { dataDir: dir, now: t0 + 4000 }
  );
  assert.ok(resBDone.actions.spawnCountdown);
  assert.equal(resBDone.actions.spawnCountdown.action, 'shutdown');
  assert.equal(resBDone.state.countdown.active, true);
  assert.equal(resBDone.state.countdown.graceSeconds, 90);
});

test('new invocation during countdown immediately auto-cancels countdown', () => {
  const dir = makeTempDir();
  const t0 = 1_700_000_000_000;
  updateConfig(dir, { armed: true, mode: 'once', graceSeconds: 60 });

  processHookEvent({ hookEventName: 'PreInvocation', conversationId: 'c1' }, { dataDir: dir, now: t0 });
  processHookEvent({ hookEventName: 'Stop', conversationId: 'c1', fullyIdle: true }, { dataDir: dir, now: t0 + 1000 });
  assert.equal(readState(dir).countdown.active, true);

  const wakeRes = processHookEvent({ hookEventName: 'PreInvocation', conversationId: 'c2' }, { dataDir: dir, now: t0 + 5000 });
  assert.equal(wakeRes.actions.cancelOsShutdown, true);
  assert.equal(readState(dir).countdown.active, false);
  assert.equal(Object.keys(readState(dir).activeSessions).length, 1);
});

test('USER_CANCELED skips countdown when ignoreUserCancel is true', () => {
  const dir = makeTempDir();
  const t0 = 1_700_000_000_000;
  updateConfig(dir, { armed: true, ignoreUserCancel: true });

  processHookEvent({ hookEventName: 'PreInvocation', conversationId: 'c1' }, { dataDir: dir, now: t0 });
  const res = processHookEvent(
    { hookEventName: 'Stop', conversationId: 'c1', fullyIdle: true, terminationReason: 'USER_CANCELED' },
    { dataDir: dir, now: t0 + 1000 }
  );
  assert.equal(res.actions.spawnCountdown, null);
  assert.equal(readState(dir).countdown.active, false);
});

test('one-shot mode disarms BEFORE executing power action', () => {
  const dir = makeTempDir();
  const t0 = 1_700_000_000_000;
  updateConfig(dir, { armed: true, mode: 'once', action: 'hibernate', graceSeconds: 30 });

  processHookEvent({ hookEventName: 'PreInvocation', conversationId: 'c1' }, { dataDir: dir, now: t0 });
  const stopRes = processHookEvent({ hookEventName: 'Stop', conversationId: 'c1', fullyIdle: true }, { dataDir: dir, now: t0 + 1000 });

  let executedAction = null;
  let armedDuringExecution = null;
  const result = finalizeCountdownExecution(dir, {
    expectedStartedAt: stopRes.actions.spawnCountdown.startedAt,
    now: t0 + 35_000,
    executor: (action) => {
      executedAction = action;
      armedDuringExecution = readConfig(dir).armed;
    },
  });

  assert.equal(result.execute, true);
  assert.equal(executedAction, 'hibernate');
  assert.equal(armedDuringExecution, false, 'Config must be disarmed BEFORE OS power action executes');
  assert.equal(readState(dir).countdown.active, false);
});

test('preview dry-run countdown never invokes power executor and preserves armed state', () => {
  const dir = makeTempDir();
  const t0 = 1_700_000_000_000;
  updateConfig(dir, { armed: true, mode: 'once' });

  const prev = startPreviewCountdown(dir, 15, t0);
  let called = false;
  const fin = finalizeCountdownExecution(dir, {
    expectedStartedAt: prev.startedAt,
    now: t0 + 20_000,
    executor: () => {
      called = true;
    },
  });

  assert.equal(fin.execute, true);
  assert.equal(fin.preview, true);
  assert.equal(called, false);
  assert.equal(readConfig(dir).armed, true);
});

test('stale abandoned session is pruned when past timeout', () => {
  const dir = makeTempDir();
  const t0 = 1_700_000_000_000;
  updateConfig(dir, { armed: true, staleTimeoutMinutes: 5, graceSeconds: 60 });

  processHookEvent({ hookEventName: 'PreInvocation', conversationId: 'stale-conv' }, { dataDir: dir, now: t0 });
  processHookEvent({ hookEventName: 'PreInvocation', conversationId: 'live-conv' }, { dataDir: dir, now: t0 + 10 * 60_000 });

  // stale-conv should have been pruned; stopping live-conv should trigger countdown
  const res = processHookEvent(
    { hookEventName: 'Stop', conversationId: 'live-conv', fullyIdle: true },
    { dataDir: dir, now: t0 + 10 * 60_000 + 5000 }
  );
  assert.ok(res.actions.spawnCountdown);
});

test('cancelCountdown & clearActiveSessions reset runtime state cleanly', () => {
  const dir = makeTempDir();
  const t0 = 1_700_000_000_000;
  updateConfig(dir, { armed: true });
  processHookEvent({ hookEventName: 'PreInvocation', conversationId: 'c1' }, { dataDir: dir, now: t0 });
  clearActiveSessions(dir, t0 + 1000);
  assert.equal(Object.keys(readState(dir).activeSessions).length, 0);

  startPreviewCountdown(dir, 20, t0 + 2000);
  assert.equal(readState(dir).countdown.active, true);
  cancelCountdown(dir, 'Manual test cancel', t0 + 3000);
  assert.equal(readState(dir).countdown.active, false);
});

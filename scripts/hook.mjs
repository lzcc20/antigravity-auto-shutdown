import { getDataDir, processHookEvent, abortOsShutdown } from './engine.mjs';
import { launchWidget, spawnCountdownWorker } from './launch-widget.mjs';

function readStdin() {
  return new Promise((resolve) => {
    let chunks = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => {
      chunks += chunk;
    });
    process.stdin.on('end', () => resolve(chunks));
    process.stdin.on('error', () => resolve(chunks));
  });
}

async function main() {
  let payload = {};
  try {
    const raw = (await readStdin()).trim();
    if (raw) payload = JSON.parse(raw);
  } catch {
    payload = {};
  }

  let output = {};
  try {
    const dataDir = getDataDir();
    const { hookOutput, actions } = processHookEvent(payload, { dataDir });
    output = hookOutput || {};

    if (actions?.cancelOsShutdown) {
      abortOsShutdown();
    }
    if (actions?.spawnCountdown) {
      spawnCountdownWorker({
        dataDir,
        startedAt: actions.spawnCountdown.startedAt,
      });
    }
    if (actions?.launchWidget) {
      launchWidget({ dataDir });
    }
  } catch {
    output = payload?.hookEventName === 'Stop' ? { decision: 'allow' } : {};
  }

  process.stdout.write(JSON.stringify(output) + '\n');
}

main();

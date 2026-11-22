import { getDataDir, readState, finalizeCountdownExecution } from './engine.mjs';

function parseArgs(argv) {
  const args = { dataDir: getDataDir(), expectedStartedAt: null };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--data-dir' && argv[i + 1]) {
      args.dataDir = argv[++i];
    } else if (argv[i] === '--expected-started-at' && argv[i + 1]) {
      args.expectedStartedAt = Number(argv[++i]);
    }
  }
  return args;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  const { dataDir, expectedStartedAt } = parseArgs(process.argv.slice(2));

  while (true) {
    const state = readState(dataDir);
    const cd = state?.countdown;

    if (!cd?.active) {
      process.exit(0);
    }
    if (expectedStartedAt !== null && cd.startedAt !== expectedStartedAt) {
      process.exit(0);
    }

    const remainingMs = (cd.executeAt || 0) - Date.now();
    if (remainingMs <= 0) {
      const result = finalizeCountdownExecution(dataDir, { expectedStartedAt });
      if (result.reason === 'not_due') {
        await sleep(300);
        continue;
      }
      process.exit(0);
    }

    await sleep(Math.min(500, Math.max(100, remainingMs)));
  }
}

main().catch(() => {
  process.exit(0);
});

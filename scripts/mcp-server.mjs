import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import {
  getDataDir,
  getSnapshot,
  updateConfig,
  cancelCountdown,
  startPreviewCountdown,
  clearActiveSessions,
  finalizeCountdownExecution,
} from './engine.mjs';
import { spawnCountdownWorker } from './launch-widget.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = path.resolve(__dirname, '..');
const DEFAULT_HTML_PATH = path.join(PLUGIN_ROOT, 'ui', 'app.html');
const APP_URI = 'ui://auto-shutdown/app.html';
const APP_MIME = 'text/html;profile=mcp-app';

function getHtmlPath() {
  return process.env.AUTO_SHUTDOWN_APP_HTML?.trim() || DEFAULT_HTML_PATH;
}

function summarizeSnapshot(snap) {
  const { config, state, activeCount } = snap;
  const cd = state.countdown || {};
  const lines = [
    `Auto Shutdown Guard`,
    `- Status: ${config.armed ? `Armed (${config.mode})` : 'Standby (disarmed)'}`,
    `- Power action: ${config.action} (grace: ${config.graceSeconds}s)`,
    `- Active Antigravity tasks: ${activeCount}`,
  ];
  if (cd.active) {
    const remainSec = Math.max(0, Math.ceil(((cd.executeAt || 0) - snap.serverTime) / 1000));
    lines.push(`- Countdown: ACTIVE (${remainSec}s -> ${cd.action}${cd.preview ? ', dry-run preview' : ''})`);
  } else {
    lines.push(`- Countdown: inactive`);
  }
  return lines.join('\n');
}

const TOOLS = [
  {
    name: 'open_panel',
    title: 'Auto Shutdown',
    description:
      'Open the native Auto Shutdown control panel in the Antigravity side panel or full-page sidebar view to monitor active tasks and manage auto-shutdown settings.',
    inputSchema: {
      type: 'object',
      properties: {},
      additionalProperties: false,
    },
    _meta: {
      ui: {
        resourceUri: APP_URI,
      },
      'com.google.antigravity/ui': {
        entrypoints: [
          { type: 'aux_pane', title: 'Auto Shutdown' },
          { type: 'global', title: 'Auto Shutdown' },
        ],
      },
    },
  },
  {
    name: 'show_status_card',
    title: 'Auto Shutdown Status',
    description:
      'Display a compact live Auto Shutdown status and one-click guard control card inline inside the conversation.',
    inputSchema: {
      type: 'object',
      properties: {},
      additionalProperties: false,
    },
    _meta: {
      ui: {
        resourceUri: APP_URI,
      },
    },
  },
  {
    name: 'arm_guard',
    title: 'Arm Auto Shutdown',
    description:
      'Arm the Auto Shutdown guard so your machine automatically shuts down, hibernates, or sleeps after all Antigravity conversations and background tasks finish.',
    inputSchema: {
      type: 'object',
      properties: {
        mode: {
          type: 'string',
          enum: ['once', 'continuous'],
          description: 'Use "once" (recommended) to auto-disarm before executing, or "continuous" to keep monitoring.',
        },
        action: {
          type: 'string',
          enum: ['shutdown', 'hibernate', 'sleep'],
          description: 'Power action to run once all tasks are idle.',
        },
        graceSeconds: {
          type: 'integer',
          minimum: 10,
          maximum: 3600,
          description: 'Countdown buffer in seconds before executing the power action.',
        },
      },
      additionalProperties: false,
    },
    _meta: {
      ui: {
        resourceUri: APP_URI,
      },
    },
  },
  {
    name: 'disarm_guard',
    title: 'Disarm Auto Shutdown',
    description: 'Disarm the Auto Shutdown guard and cancel any active countdown.',
    inputSchema: {
      type: 'object',
      properties: {},
      additionalProperties: false,
    },
    _meta: {
      ui: {
        resourceUri: APP_URI,
      },
    },
  },
  {
    name: 'cancel_countdown',
    title: 'Cancel Shutdown Countdown',
    description: 'Immediately abort an active shutdown/hibernate/sleep countdown.',
    inputSchema: {
      type: 'object',
      properties: {},
      additionalProperties: false,
    },
    _meta: {
      ui: {
        resourceUri: APP_URI,
      },
    },
  },
  // App-only RPC helpers (hidden from model, called live by ui/app.html via app.callServerTool)
  {
    name: 'app_get_state',
    title: 'Get Auto Shutdown State',
    description: 'Fetch the latest live guard configuration, active sessions, and countdown state.',
    inputSchema: {
      type: 'object',
      properties: {},
      additionalProperties: false,
    },
    _meta: {
      ui: {
        visibility: ['app'],
      },
    },
  },
  {
    name: 'app_update_config',
    title: 'Update Auto Shutdown Settings',
    description: 'Update Auto Shutdown preferences atomically from the UI.',
    inputSchema: {
      type: 'object',
      properties: {
        armed: { type: 'boolean' },
        mode: { type: 'string', enum: ['once', 'continuous'] },
        action: { type: 'string', enum: ['shutdown', 'hibernate', 'sleep'] },
        graceSeconds: { type: 'integer', minimum: 10, maximum: 3600 },
        ignoreUserCancel: { type: 'boolean' },
        ignoreErrors: { type: 'boolean' },
        language: { type: 'string', enum: ['zh-CN', 'en'] },
      },
      additionalProperties: false,
    },
    _meta: {
      ui: {
        visibility: ['app'],
      },
    },
  },
  {
    name: 'app_cancel_countdown',
    title: 'Cancel Active Countdown',
    description: 'Cancel the currently running countdown from the UI.',
    inputSchema: {
      type: 'object',
      properties: {},
      additionalProperties: false,
    },
    _meta: {
      ui: {
        visibility: ['app'],
      },
    },
  },
  {
    name: 'app_start_preview',
    title: 'Start Safe Dry-Run Preview',
    description: 'Start a safe dry-run preview countdown that never powers off the system.',
    inputSchema: {
      type: 'object',
      properties: {
        seconds: { type: 'integer', minimum: 5, maximum: 120 },
      },
      additionalProperties: false,
    },
    _meta: {
      ui: {
        visibility: ['app'],
      },
    },
  },
  {
    name: 'app_execute_now',
    title: 'Execute Pending Power Action Now',
    description: 'Immediately finalize an active countdown.',
    inputSchema: {
      type: 'object',
      properties: {},
      additionalProperties: false,
    },
    _meta: {
      ui: {
        visibility: ['app'],
      },
    },
  },
  {
    name: 'app_clear_sessions',
    title: 'Clear Tracked Sessions',
    description: 'Clear stale tracked active sessions from state.',
    inputSchema: {
      type: 'object',
      properties: {},
      additionalProperties: false,
    },
    _meta: {
      ui: {
        visibility: ['app'],
      },
    },
  },
];

function buildToolResult(surface, snap, extraLine = '') {
  const text = extraLine ? `${extraLine}\n\n${summarizeSnapshot(snap)}` : summarizeSnapshot(snap);
  return {
    content: [{ type: 'text', text }],
    structuredContent: {
      surface,
      ...snap,
    },
  };
}

function handleToolCall(name, args = {}) {
  const dataDir = getDataDir();

  switch (name) {
    case 'open_panel': {
      const snap = getSnapshot(dataDir);
      return buildToolResult('panel', snap);
    }
    case 'show_status_card': {
      const snap = getSnapshot(dataDir);
      return buildToolResult('inline', snap);
    }
    case 'arm_guard': {
      const patch = { armed: true };
      if (args?.mode) patch.mode = args.mode;
      if (args?.action) patch.action = args.action;
      if (args?.graceSeconds !== undefined) patch.graceSeconds = Number(args.graceSeconds);
      updateConfig(dataDir, patch);
      const snap = getSnapshot(dataDir);
      return buildToolResult(
        'inline',
        snap,
        `Armed Auto Shutdown (${snap.config.mode}): ${snap.config.action} after ${snap.config.graceSeconds}s grace period.`
      );
    }
    case 'disarm_guard': {
      updateConfig(dataDir, { armed: false });
      cancelCountdown(dataDir, 'Disarmed via MCP tool');
      const snap = getSnapshot(dataDir);
      return buildToolResult('inline', snap, 'Auto Shutdown guard disarmed.');
    }
    case 'cancel_countdown': {
      cancelCountdown(dataDir, 'Cancelled via MCP tool');
      const snap = getSnapshot(dataDir);
      return buildToolResult('inline', snap, 'Countdown cancelled.');
    }
    case 'app_get_state': {
      const snap = getSnapshot(dataDir);
      return {
        content: [{ type: 'text', text: summarizeSnapshot(snap) }],
        structuredContent: snap,
      };
    }
    case 'app_update_config': {
      const patch = {};
      for (const key of ['armed', 'mode', 'action', 'graceSeconds', 'ignoreUserCancel', 'ignoreErrors', 'language']) {
        if (args && Object.prototype.hasOwnProperty.call(args, key) && args[key] !== undefined) {
          patch[key] = args[key];
        }
      }
      updateConfig(dataDir, patch);
      const snap = getSnapshot(dataDir);
      return {
        content: [{ type: 'text', text: 'Updated settings.' }],
        structuredContent: snap,
      };
    }
    case 'app_cancel_countdown': {
      cancelCountdown(dataDir, 'Cancelled from Auto Shutdown UI');
      const snap = getSnapshot(dataDir);
      return {
        content: [{ type: 'text', text: 'Countdown cancelled.' }],
        structuredContent: snap,
      };
    }
    case 'app_start_preview': {
      const seconds = Number(args?.seconds || 15);
      const res = startPreviewCountdown(dataDir, seconds);
      spawnCountdownWorker({ dataDir, startedAt: res.startedAt });
      const snap = getSnapshot(dataDir);
      return {
        content: [{ type: 'text', text: `Started ${seconds}s dry-run preview.` }],
        structuredContent: snap,
      };
    }
    case 'app_execute_now': {
      finalizeCountdownExecution(dataDir, { force: true });
      const snap = getSnapshot(dataDir);
      return {
        content: [{ type: 'text', text: 'Executed pending action.' }],
        structuredContent: snap,
      };
    }
    case 'app_clear_sessions': {
      clearActiveSessions(dataDir);
      const snap = getSnapshot(dataDir);
      return {
        content: [{ type: 'text', text: 'Cleared tracked sessions.' }],
        structuredContent: snap,
      };
    }
    default:
      return {
        isError: true,
        content: [{ type: 'text', text: `Unknown tool: ${name}` }],
      };
  }
}

function sendMessage(msg) {
  process.stdout.write(JSON.stringify(msg) + '\n');
}

function sendError(id, code, message) {
  sendMessage({
    jsonrpc: '2.0',
    id,
    error: { code, message },
  });
}

function handleRequest(req) {
  if (!req || typeof req !== 'object') return;
  const { id, method, params } = req;

  // Notifications have no id and require no response.
  if (id === undefined || id === null) {
    return;
  }

  try {
    if (method === 'initialize') {
      const clientVersion = typeof params?.protocolVersion === 'string' ? params.protocolVersion : '2025-06-18';
      sendMessage({
        jsonrpc: '2.0',
        id,
        result: {
          protocolVersion: clientVersion,
          capabilities: {
            tools: {},
            resources: {},
          },
          serverInfo: {
            name: 'auto-shutdown',
            version: '1.1.0',
          },
        },
      });
      return;
    }

    if (method === 'ping') {
      sendMessage({ jsonrpc: '2.0', id, result: {} });
      return;
    }

    if (method === 'tools/list') {
      sendMessage({ jsonrpc: '2.0', id, result: { tools: TOOLS } });
      return;
    }

    if (method === 'tools/call') {
      const result = handleToolCall(params?.name, params?.arguments || {});
      sendMessage({ jsonrpc: '2.0', id, result });
      return;
    }

    if (method === 'resources/list') {
      sendMessage({
        jsonrpc: '2.0',
        id,
        result: {
          resources: [
            {
              uri: APP_URI,
              name: 'Auto Shutdown',
              description: 'Native Antigravity Auto Shutdown control interface',
              mimeType: APP_MIME,
              _meta: {
                ui: {
                  prefersBorder: false,
                },
              },
            },
          ],
        },
      });
      return;
    }

    if (method === 'resources/read') {
      const uri = params?.uri;
      if (uri !== APP_URI) {
        sendError(id, -32602, `Unknown resource URI: ${uri}`);
        return;
      }
      const html = fs.readFileSync(getHtmlPath(), 'utf8');
      sendMessage({
        jsonrpc: '2.0',
        id,
        result: {
          contents: [
            {
              uri: APP_URI,
              mimeType: APP_MIME,
              text: html,
              _meta: {
                ui: {
                  prefersBorder: false,
                },
              },
            },
          ],
        },
      });
      return;
    }

    sendError(id, -32601, `Method not found: ${method}`);
  } catch (err) {
    sendError(id, -32603, err?.message || 'Internal server error');
  }
}

// Guard stdio against host shutdown EPIPE
process.stdout.on('error', (err) => {
  if (err?.code === 'EPIPE') process.exit(0);
});

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

rl.on('line', (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  try {
    const parsed = JSON.parse(trimmed);
    handleRequest(parsed);
  } catch {
    // Ignore malformed lines cleanly
  }
});

rl.on('close', () => {
  process.exit(0);
});

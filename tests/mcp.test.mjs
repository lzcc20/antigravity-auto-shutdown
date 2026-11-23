import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import readline from 'node:readline';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SERVER_PATH = path.join(ROOT, 'scripts', 'mcp-server.mjs');

function startMcpClient(dataDir) {
  const child = spawn(process.execPath, [SERVER_PATH], {
    env: { ...process.env, AUTO_SHUTDOWN_DATA_DIR: dataDir },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  const rl = readline.createInterface({ input: child.stdout });
  const pending = new Map();
  let nextId = 1;

  rl.on('line', (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    const msg = JSON.parse(trimmed);
    const resolver = pending.get(msg.id);
    if (resolver) {
      pending.delete(msg.id);
      resolver(msg);
    }
  });

  function request(method, params = {}) {
    const id = nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`Timeout waiting for ${method}`));
      }, 5000);
      pending.set(id, (msg) => {
        clearTimeout(timer);
        resolve(msg);
      });
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
    });
  }

  function close() {
    rl.close();
    child.stdin.end();
    child.kill();
  }

  return { request, close };
}

test('MCP App server: initialize, resources/read, tools/list, and live tool calls', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'agy-as-mcp-test-'));
  const client = startMcpClient(dir);
  try {
    const init = await client.request('initialize', {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'test', version: '1.0.0' },
    });
    assert.equal(init.result.protocolVersion, '2025-06-18');
    assert.ok(init.result.capabilities.tools);
    assert.ok(init.result.capabilities.resources);

    const resList = await client.request('resources/list');
    assert.equal(resList.result.resources.length, 1);
    assert.equal(resList.result.resources[0].uri, 'ui://auto-shutdown/app.html');
    assert.equal(resList.result.resources[0].mimeType, 'text/html;profile=mcp-app');

    const resRead = await client.request('resources/read', { uri: 'ui://auto-shutdown/app.html' });
    const html = resRead.result.contents[0].text;
    assert.equal(resRead.result.contents[0].mimeType, 'text/html;profile=mcp-app');
    assert.ok(html.includes('<!doctype html>'));
    assert.ok(html.includes('__MCP_APPS__'));
    assert.ok(html.length < 10 * 1024 * 1024);

    const toolsList = await client.request('tools/list');
    const openPanel = toolsList.result.tools.find((t) => t.name === 'open_panel');
    assert.ok(openPanel);
    assert.equal(openPanel._meta.ui.resourceUri, 'ui://auto-shutdown/app.html');
    assert.deepEqual(
      openPanel._meta['com.google.antigravity/ui'].entrypoints.map((e) => e.type),
      ['aux_pane', 'global']
    );

    const appOnly = toolsList.result.tools.find((t) => t.name === 'app_get_state');
    assert.deepEqual(appOnly._meta.ui.visibility, ['app']);

    // Update settings via app-only tool and verify persistence
    const updated = await client.request('tools/call', {
      name: 'app_update_config',
      arguments: { armed: true, mode: 'once', action: 'hibernate', graceSeconds: 60 },
    });
    assert.equal(updated.result.structuredContent.config.armed, true);
    assert.equal(updated.result.structuredContent.config.action, 'hibernate');
    assert.equal(updated.result.structuredContent.config.graceSeconds, 60);

    // Start and cancel dry-run preview via app-only tools
    const preview = await client.request('tools/call', {
      name: 'app_start_preview',
      arguments: { seconds: 15 },
    });
    assert.equal(preview.result.structuredContent.state.countdown.active, true);
    assert.equal(preview.result.structuredContent.state.countdown.preview, true);

    const cancelled = await client.request('tools/call', {
      name: 'app_cancel_countdown',
      arguments: {},
    });
    assert.equal(cancelled.result.structuredContent.state.countdown.active, false);

    // open_panel works with empty `{}` (required for Antigravity entrypoint launches)
    const panel = await client.request('tools/call', { name: 'open_panel', arguments: {} });
    assert.equal(panel.result.structuredContent.surface, 'panel');
    assert.ok(panel.result.content[0].text.includes('Auto Shutdown Guard'));
  } finally {
    client.close();
  }
});

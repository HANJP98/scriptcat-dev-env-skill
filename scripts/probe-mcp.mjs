// End-to-end probe: stdio JSON-RPC handshake with chrome-devtools-mcp + Edge CDP.
// Portable: reads the real service definition from ~/.workbuddy/mcp.json when present,
// so it validates the exact configuration the host will use. Falls back to the
// conventional layout otherwise. No machine-specific paths are baked in.
//
// Usage: node "%USERPROFILE%\EdgeAgent\probe-mcp.mjs"
import { spawn } from 'node:child_process';
import readline from 'node:readline';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const HOME = process.env.USERPROFILE || os.homedir();
const CFG = path.join(HOME, '.workbuddy', 'mcp.json');
const DEFAULT_ARGS = [
  path.join(HOME, 'EdgeAgent', 'mcp', 'node_modules', 'chrome-devtools-mcp', 'build', 'src', 'bin', 'chrome-devtools-mcp.js'),
  '--browserUrl=http://127.0.0.1:9222',
  '--no-page-id-routing',
  '--no-usage-statistics',
  '--no-performance-crux',
  '--categoryExtensions',
  '--workspace=' + path.join(HOME, 'EdgeAgent', 'out'),
];

let command = process.execPath;
let args = [];
let source = 'defaults (conventional layout)';

try {
  if (fs.existsSync(CFG)) {
    const cfg = JSON.parse(fs.readFileSync(CFG, 'utf8'));
    const svc = cfg.mcpServers && cfg.mcpServers['chrome-devtools'];
    if (svc && svc.command && Array.isArray(svc.args) && svc.args.length) {
      command = svc.command;
      args = svc.args.slice();
      source = 'mcp.json';
    }
  }
} catch (e) {
  console.log('[0] config      : unreadable (' + e.message + '), using defaults');
}
if (!args.length) args = DEFAULT_ARGS;
console.log('[0] config      : ' + source);
console.log('    command     : ' + command);

const child = spawn(command, args, {
  stdio: ['pipe', 'pipe', 'pipe'],
  env: { ...process.env, NO_PROXY: '127.0.0.1,localhost' },
});
child.on('error', e => console.error('[mcp:spawn] ' + e.message));
child.stderr.on('data', d => process.stderr.write('[mcp:err] ' + d.toString()));

let seq = 0;
const pending = new Map();
readline.createInterface({ input: child.stdout }).on('line', line => {
  let msg;
  try { msg = JSON.parse(line); } catch { return; }
  if (msg.id != null && pending.has(msg.id)) {
    pending.get(msg.id)(msg);
    pending.delete(msg.id);
  }
});

function request(method, params = {}, ms = 12000) {
  const id = ++seq;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { pending.delete(id); reject(new Error('timeout: ' + method)); }, ms);
    pending.set(id, m => { clearTimeout(timer); resolve(m); });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}
const text = m => JSON.stringify(m?.error ?? m?.result?.content ?? m?.result ?? m).slice(0, 900);
let failed = false;

try {
  const init = await request('initialize', {
    protocolVersion: '2025-06-18',
    capabilities: {},
    clientInfo: { name: 'edge-agent-probe', version: '1.0.0' },
  });
  if (!init.result) throw new Error('initialize failed: ' + text(init));
  console.log('[1] initialize : ok, server=' + init.result.serverInfo?.name + '@' + init.result.serverInfo?.version);
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} }) + '\n');

  const tools = await request('tools/list');
  const list = tools.result?.tools ?? [];
  const ext = list.filter(t => /extension/i.test(t.name)).map(t => t.name);
  console.log('[2] tools/list  : ok, ' + list.length + ' tools | extension tools: ' + (ext.join(', ') || '(none)'));
  if (!list.some(t => t.name === 'list_pages') || ext.length === 0) failed = true;

  const pages = await request('tools/call', { name: 'list_pages', arguments: {} });
  console.log('[3] list_pages  : ' + (pages.error ? 'ERROR ' + text(pages) : text(pages)));
  if (pages.error) failed = true;

  try {
    const exts = await request('tools/call', { name: 'list_extensions', arguments: {} }, 8000);
    console.log('[4] extensions  : ' + (exts.error ? 'ERROR ' + text(exts) : text(exts)));
  } catch (e) {
    console.log('[4] extensions  : skipped (' + e.message + ')');
  }
} catch (e) {
  console.error('PROBE FAILED:', e.message);
  failed = true;
} finally {
  child.stdin.end();
  child.kill();
  console.log(failed ? 'RESULT: FAIL' : 'RESULT: PASS');
  setTimeout(() => process.exit(failed ? 1 : 0), 300);
}

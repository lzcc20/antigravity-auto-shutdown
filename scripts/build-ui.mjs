import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');

function resolveSdkBundlePath() {
  const candidates = [
    process.env.MCP_EXT_APPS_BUNDLE,
    path.join(ROOT, 'node_modules', '@modelcontextprotocol', 'ext-apps', 'dist', 'src', 'app-with-deps.js'),
    path.join(process.env.TEMP || '/tmp', 'agy-as-uibuild', 'node_modules', '@modelcontextprotocol', 'ext-apps', 'dist', 'src', 'app-with-deps.js'),
  ].filter(Boolean);

  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  throw new Error(
    'Could not find @modelcontextprotocol/ext-apps/dist/src/app-with-deps.js. Install @modelcontextprotocol/ext-apps or set MCP_EXT_APPS_BUNDLE.'
  );
}

function inlineBundle(sdkSource) {
  // Replace trailing ESM `export{...};` with a local `__MCP_APPS__` object so the entire app lives in one CSP-safe inline module script.
  const match = sdkSource.match(/export\s*\{([^}]+)\}\s*;?\s*$/);
  if (!match) {
    throw new Error('Unexpected export format in @modelcontextprotocol/ext-apps bundle');
  }
  const mappings = match[1]
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .map((entry) => {
      const m = entry.match(/^([^\s]+)\s+as\s+([^\s]+)$/);
      return m ? `${m[2]}:${m[1]}` : `${entry}:${entry}`;
    });

  const body = sdkSource.slice(0, match.index);
  // Prevent accidental `</script>` sequence inside bundled strings from breaking the HTML script tag.
  const safeBody = body.replaceAll('</script>', '<\\/script>');
  return `${safeBody}\nconst __MCP_APPS__ = {${mappings.join(',')}};`;
}

function main() {
  const sdkPath = resolveSdkBundlePath();
  const sdkSource = fs.readFileSync(sdkPath, 'utf8');
  const templatePath = path.join(ROOT, 'web', 'app.html');
  const outDir = path.join(ROOT, 'ui');
  const outPath = path.join(outDir, 'app.html');

  const template = fs.readFileSync(templatePath, 'utf8');
  const marker = '/* __MCP_EXT_APPS_BUNDLE__ */';
  if (!template.includes(marker)) {
    throw new Error(`Missing marker ${marker} in ${templatePath}`);
  }

  const inlined = inlineBundle(sdkSource);
  const built = template.replace(marker, () => inlined);

  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(outPath, built, 'utf8');
  const kb = (Buffer.byteLength(built, 'utf8') / 1024).toFixed(1);
  console.log(`Built ${outPath} (${kb} KB) from ${sdkPath}`);
}

main();

/**
 * Bundles the ElevenLabs browser SDK into public/vendor/elevenlabs.js so the
 * page is self-contained (no runtime CDN) and works in Safari on iPhone/Mac.
 *
 * Runs on `npm run build` and automatically on `npm install` (postinstall).
 * If @elevenlabs/client isn't installed yet, it exits cleanly with a note.
 */
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');
const entry = path.join(root, 'src', 'sdk-entry.js');
const outfile = path.join(root, 'public', 'vendor', 'elevenlabs.js');

async function main() {
  // Confirm the dependency exists before trying to bundle it.
  const pkg = path.join(root, 'node_modules', '@elevenlabs', 'client', 'package.json');
  if (!fs.existsSync(pkg)) {
    console.warn('[build-client] @elevenlabs/client not installed yet — skipping bundle.');
    console.warn('[build-client] run `npm install` then `npm run build`.');
    return;
  }
  fs.mkdirSync(path.dirname(outfile), { recursive: true });
  await build({
    entryPoints: [entry],
    bundle: true,
    format: 'iife',
    globalName: 'ElevenLabsSDK',
    target: ['es2020', 'safari14'],
    outfile,
    minify: true,
    sourcemap: false,
    logLevel: 'info',
  });
  console.log('[build-client] wrote', path.relative(root, outfile));
}

main().catch((e) => {
  console.error('[build-client] failed:', e.message);
  process.exit(1);
});

/**
 * GodMode Call — backend.
 *
 * Serves the FaceTime-style frontend and a small API. ALL secret keys
 * (ElevenLabs, Anthropic/OpenAI) live here and never reach the browser. The
 * browser only ever receives a short-lived ElevenLabs conversation token and
 * non-secret config.
 *
 * Run:  npm start   (http://localhost:8787)
 */
import express from 'express';
import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

import { mintConversationToken, listVoices } from './src/elevenlabs.js';
import { analyzeImage } from './src/vision.js';
import { priceCheck } from './src/search.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load .env if present (no dependency; Node 20.6+/22 has loadEnvFile).
try {
  process.loadEnvFile(path.join(__dirname, '.env'));
} catch {
  /* no .env file — rely on real environment variables */
}

const PORT = Number(process.env.PORT || 8787);
const app = express();

app.use(express.json({ limit: process.env.MAX_UPLOAD || '8mb' }));

// --- Non-secret config for the client -------------------------------------
app.get('/api/config', (req, res) => {
  res.json({
    hasAgent: Boolean(process.env.ELEVENLABS_AGENT_ID),
    agentId: process.env.ELEVENLABS_AGENT_ID || null,
    hasElevenLabsKey: Boolean(process.env.ELEVENLABS_API_KEY),
    visionProvider: (process.env.VISION_PROVIDER || 'anthropic').toLowerCase(),
    visionModel:
      process.env.VISION_MODEL ||
      ((process.env.VISION_PROVIDER || 'anthropic').toLowerCase() === 'openai'
        ? 'gpt-4o'
        : 'claude-sonnet-5-5'),
    visionConfigured: isVisionConfigured(),
    priceCheckEnabled: String(process.env.PRICE_CHECK_ENABLED).toLowerCase() === 'true',
    defaultVoiceId: process.env.ELEVENLABS_VOICE_ID || null,
    // Scene-awareness (periodic frames) is OFF unless the user turns it on.
    sceneAwarenessIntervalMs: Number(process.env.SCENE_AWARENESS_INTERVAL_MS || 20000),
  });
});

// --- ElevenLabs conversation token (WebRTC) --------------------------------
app.get('/api/elevenlabs/token', async (req, res) => {
  try {
    const agentId = req.query.agentId || process.env.ELEVENLABS_AGENT_ID;
    const { token } = await mintConversationToken(agentId);
    res.json({ token });
  } catch (err) {
    sendError(res, err);
  }
});

// --- ElevenLabs voices (for the config screen) -----------------------------
app.get('/api/voices', async (req, res) => {
  try {
    res.json({ voices: await listVoices() });
  } catch (err) {
    sendError(res, err);
  }
});

// --- Vision: analyze a sampled frame ---------------------------------------
app.post('/api/vision', async (req, res) => {
  try {
    const { image, mediaType, question, context } = req.body || {};
    const imageBase64 = stripDataUri(image);
    const result = await analyzeImage({ imageBase64, mediaType, question, context });
    res.json(result);
  } catch (err) {
    sendError(res, err);
  }
});

// --- Price / current-value lookup (web search) -----------------------------
app.post('/api/price-check', async (req, res) => {
  try {
    const { query } = req.body || {};
    res.json(await priceCheck({ query }));
  } catch (err) {
    sendError(res, err);
  }
});

app.get('/healthz', (req, res) => res.json({ ok: true }));

// --- Static frontend -------------------------------------------------------
app.use(express.static(path.join(__dirname, 'public'), { extensions: ['html'] }));

// --- helpers ---------------------------------------------------------------
function isVisionConfigured() {
  const provider = (process.env.VISION_PROVIDER || 'anthropic').toLowerCase();
  return provider === 'openai' ? Boolean(process.env.OPENAI_API_KEY) : Boolean(process.env.ANTHROPIC_API_KEY);
}

function stripDataUri(image) {
  if (typeof image !== 'string') return image;
  const comma = image.indexOf(',');
  return image.startsWith('data:') && comma !== -1 ? image.slice(comma + 1) : image;
}

function sendError(res, err) {
  const status = err.status || 500;
  if (status >= 500) console.error('[call] error:', err.message);
  res.status(status).json({ error: { message: err.message, code: err.code || 'ERROR' } });
}

// --- start (http, or https if cert provided) -------------------------------
export function createServer() {
  const certPath = process.env.SSL_CERT;
  const keyPath = process.env.SSL_KEY;
  if (certPath && keyPath && fs.existsSync(certPath) && fs.existsSync(keyPath)) {
    return {
      server: https.createServer(
        { cert: fs.readFileSync(certPath), key: fs.readFileSync(keyPath) },
        app,
      ),
      scheme: 'https',
    };
  }
  return { server: http.createServer(app), scheme: 'http' };
}

export { app };

// Only listen when run directly (not when imported by tests).
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { server, scheme } = createServer();
  server.listen(PORT, '0.0.0.0', () => {
    console.log('');
    console.log('  📞 GodMode Call is running:');
    console.log('');
    console.log(`     This computer:  ${scheme}://localhost:${PORT}`);
    for (const ifaces of Object.values(os.networkInterfaces())) {
      for (const iface of ifaces || []) {
        if (iface.family === 'IPv4' && !iface.internal) {
          console.log(`     On your Wi-Fi:  ${scheme}://${iface.address}:${PORT}`);
        }
      }
    }
    if (scheme === 'http') {
      console.log('');
      console.log('  ⚠  Camera & mic need HTTPS on real devices (iPhone). localhost is exempt.');
      console.log('     For phone testing set SSL_CERT/SSL_KEY, or use a tunnel (see README).');
    }
    console.log('');
  });
}

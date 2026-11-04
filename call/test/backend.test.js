/**
 * Backend unit + integration tests (node --test, no extra deps).
 * Run: npm test   (from call/)
 *
 * Network is mocked by overriding globalThis.fetch, so these run offline and
 * never spend real API credits.
 */
import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

import { mintConversationToken, listVoices } from '../src/elevenlabs.js';
import { analyzeImage } from '../src/vision.js';
import { priceCheck } from '../src/search.js';
import { app } from '../server.js';

// --- fetch mock harness -----------------------------------------------------
const realFetch = globalThis.fetch;
let calls = [];
function mockFetch(handler) {
  calls = [];
  globalThis.fetch = async (url, opts = {}) => {
    calls.push({ url: String(url), opts });
    const r = handler(String(url), opts) || {};
    const status = r.status ?? 200;
    const bodyText = typeof r.body === 'string' ? r.body : JSON.stringify(r.body ?? {});
    return {
      ok: status >= 200 && status < 300,
      status,
      async text() { return bodyText; },
      async json() { return JSON.parse(bodyText); },
    };
  };
}
afterEach(() => { globalThis.fetch = realFetch; });

function clearKeys() {
  delete process.env.ELEVENLABS_API_KEY;
  delete process.env.ELEVENLABS_AGENT_ID;
  delete process.env.ANTHROPIC_API_KEY;
  delete process.env.OPENAI_API_KEY;
  delete process.env.VISION_PROVIDER;
  delete process.env.VISION_MODEL;
  delete process.env.PRICE_CHECK_ENABLED;
}
beforeEach(clearKeys);

// =========================== elevenlabs.js =================================
test('mintConversationToken fails cleanly with no API key', async () => {
  await assert.rejects(() => mintConversationToken('agent_x'), (e) => e.code === 'NO_ELEVENLABS_KEY' && e.status === 503);
});

test('mintConversationToken requires an agent id', async () => {
  process.env.ELEVENLABS_API_KEY = 'sk_test';
  await assert.rejects(() => mintConversationToken(''), (e) => e.code === 'NO_AGENT_ID');
});

test('mintConversationToken sends xi-api-key and parses token', async () => {
  process.env.ELEVENLABS_API_KEY = 'sk_secret_value';
  mockFetch((url, opts) => {
    assert.match(url, /\/v1\/convai\/conversation\/token\?agent_id=agent_abc/);
    assert.equal(opts.headers['xi-api-key'], 'sk_secret_value');
    return { body: { token: 'tok_123' } };
  });
  const out = await mintConversationToken('agent_abc');
  assert.equal(out.token, 'tok_123');
});

test('mintConversationToken accepts alternate token field names', async () => {
  process.env.ELEVENLABS_API_KEY = 'sk_test';
  mockFetch(() => ({ body: { conversation_token: 'tok_alt' } }));
  assert.equal((await mintConversationToken('a')).token, 'tok_alt');
});

test('mintConversationToken surfaces 401 as auth error', async () => {
  process.env.ELEVENLABS_API_KEY = 'bad';
  mockFetch(() => ({ status: 401, body: { detail: 'unauthorized' } }));
  await assert.rejects(() => mintConversationToken('a'), (e) => e.status === 401);
});

test('listVoices maps the API shape', async () => {
  process.env.ELEVENLABS_API_KEY = 'sk_test';
  mockFetch(() => ({ body: { voices: [{ voice_id: 'v1', name: 'Rachel', category: 'premade', preview_url: 'u' }] } }));
  const voices = await listVoices();
  assert.deepEqual(voices, [{ voiceId: 'v1', name: 'Rachel', category: 'premade', previewUrl: 'u' }]);
});

// =============================== vision.js =================================
test('analyzeImage throws without a vision key', async () => {
  await assert.rejects(() => analyzeImage({ imageBase64: 'abc', question: 'hi' }), (e) => e.code === 'NO_VISION_KEY');
});

test('analyzeImage (anthropic) sends an image block and returns text', async () => {
  process.env.ANTHROPIC_API_KEY = 'sk-ant-secret';
  process.env.VISION_MODEL = 'claude-sonnet-5-5';
  mockFetch((url, opts) => {
    assert.equal(url, 'https://api.anthropic.com/v1/messages');
    assert.equal(opts.headers['x-api-key'], 'sk-ant-secret');
    const body = JSON.parse(opts.body);
    assert.equal(body.model, 'claude-sonnet-5-5');
    const img = body.messages[0].content.find((b) => b.type === 'image');
    assert.ok(img, 'has image block');
    assert.equal(img.source.type, 'base64');
    assert.equal(img.source.data, 'BASE64DATA');
    assert.ok(body.system.includes('never invent') || body.system.toLowerCase().includes('honest') || body.system.includes('cannot see'));
    return { body: { content: [{ type: 'text', text: 'A red trading card.' }] } };
  });
  const out = await analyzeImage({ imageBase64: 'BASE64DATA', question: 'what is this?' });
  assert.equal(out.text, 'A red trading card.');
  assert.equal(out.provider, 'anthropic');
});

test('analyzeImage (openai) uses chat/completions with data URI', async () => {
  process.env.VISION_PROVIDER = 'openai';
  process.env.OPENAI_API_KEY = 'sk-openai';
  mockFetch((url, opts) => {
    assert.equal(url, 'https://api.openai.com/v1/chat/completions');
    const body = JSON.parse(opts.body);
    const img = body.messages[1].content.find((b) => b.type === 'image_url');
    assert.match(img.image_url.url, /^data:image\/jpeg;base64,ABC$/);
    return { body: { choices: [{ message: { content: 'A cat.' } }] } };
  });
  const out = await analyzeImage({ imageBase64: 'ABC', question: 'what?' });
  assert.equal(out.text, 'A cat.');
  assert.equal(out.provider, 'openai');
});

test('analyzeImage rejects missing image', async () => {
  process.env.ANTHROPIC_API_KEY = 'x';
  await assert.rejects(() => analyzeImage({ question: 'hi' }), (e) => e.status === 400);
});

// =============================== search.js =================================
test('priceCheck returns a clear "disabled" message when not enabled', async () => {
  const out = await priceCheck({ query: 'Charizard' });
  assert.equal(out.searched, false);
  assert.match(out.text, /isn't enabled|not enabled/i);
});

test('priceCheck requires a key when enabled', async () => {
  process.env.PRICE_CHECK_ENABLED = 'true';
  await assert.rejects(() => priceCheck({ query: 'x' }), (e) => e.code === 'NO_SEARCH_KEY');
});

test('priceCheck enables the web_search tool and returns text', async () => {
  process.env.PRICE_CHECK_ENABLED = 'true';
  process.env.ANTHROPIC_API_KEY = 'sk-ant';
  mockFetch((url, opts) => {
    const body = JSON.parse(opts.body);
    assert.ok(Array.isArray(body.tools));
    assert.equal(body.tools[0].name, 'web_search');
    assert.match(body.tools[0].type, /web_search/);
    return { body: { content: [{ type: 'text', text: 'Recent sold listings: $40-60.' }] } };
  });
  const out = await priceCheck({ query: 'Charizard base set' });
  assert.equal(out.searched, true);
  assert.match(out.text, /sold/i);
});

// =========================== server integration ============================
function listen() {
  return new Promise((resolve) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}
async function get(server, path) {
  const { port } = server.address();
  const res = await realFetch(`http://127.0.0.1:${port}${path}`);
  return { status: res.status, body: await res.text() };
}
async function post(server, path, obj) {
  const { port } = server.address();
  const res = await realFetch(`http://127.0.0.1:${port}${path}`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(obj),
  });
  return { status: res.status, body: await res.text() };
}

test('INVARIANT: /api/config never leaks secret keys to the client', async () => {
  process.env.ELEVENLABS_API_KEY = 'sk_SUPER_SECRET_EL';
  process.env.ELEVENLABS_AGENT_ID = 'agent_pub';
  process.env.ANTHROPIC_API_KEY = 'sk-ant-SUPER_SECRET';
  const server = await listen();
  try {
    const { status, body } = await get(server, '/api/config');
    assert.equal(status, 200);
    assert.ok(!body.includes('sk_SUPER_SECRET_EL'), 'ElevenLabs key must not appear');
    assert.ok(!body.includes('sk-ant-SUPER_SECRET'), 'Anthropic key must not appear');
    const cfg = JSON.parse(body);
    assert.equal(cfg.hasElevenLabsKey, true); // only a boolean, not the value
    assert.equal(cfg.agentId, 'agent_pub');   // agent id is not a secret
  } finally { server.close(); }
});

test('server /api/vision strips the data: URI prefix before sending base64', async () => {
  process.env.ANTHROPIC_API_KEY = 'sk-ant';
  let seen = null;
  mockFetch((url, opts) => {
    seen = JSON.parse(opts.body).messages[0].content.find((b) => b.type === 'image').source.data;
    return { body: { content: [{ type: 'text', text: 'ok' }] } };
  });
  const server = await listen();
  try {
    const { status } = await post(server, '/api/vision', { image: 'data:image/jpeg;base64,ZZZ123', question: 'hi' });
    assert.equal(status, 200);
    assert.equal(seen, 'ZZZ123', 'base64 should have the data: prefix removed');
  } finally { server.close(); }
});

test('server returns structured error (not a crash) when vision key missing', async () => {
  const server = await listen();
  try {
    const { status, body } = await post(server, '/api/vision', { image: 'x', question: 'hi' });
    assert.equal(status, 503);
    assert.equal(JSON.parse(body).error.code, 'NO_VISION_KEY');
  } finally { server.close(); }
});

test('healthz works', async () => {
  const server = await listen();
  try {
    const { status, body } = await get(server, '/healthz');
    assert.equal(status, 200);
    assert.equal(JSON.parse(body).ok, true);
  } finally { server.close(); }
});

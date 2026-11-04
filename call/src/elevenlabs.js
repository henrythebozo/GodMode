/**
 * ElevenLabs Agents helpers (server-side only).
 *
 * The browser never sees ELEVENLABS_API_KEY. It calls our /api routes, which
 * use the key to (a) mint a short-lived WebRTC conversation token and (b) list
 * the account's voices so the user can pick one.
 *
 * Token endpoint (WebRTC):  GET /v1/convai/conversation/token?agent_id=...
 * Docs: https://elevenlabs.io/docs/eleven-agents/libraries/java-script
 */

const BASE = 'https://api.elevenlabs.io';

function requireKey() {
  const key = process.env.ELEVENLABS_API_KEY;
  if (!key) {
    const err = new Error(
      'ELEVENLABS_API_KEY is not set on the server. Copy .env.example to .env and add your key.',
    );
    err.status = 503;
    err.code = 'NO_ELEVENLABS_KEY';
    throw err;
  }
  return key;
}

/**
 * Mint a conversation token for a WebRTC session with a (possibly private)
 * agent. Public agents don't strictly need this, but minting one anyway keeps
 * the agent id off the public network path and works for private agents too.
 *
 * @returns {Promise<{token: string}>}
 */
export async function mintConversationToken(agentId) {
  const key = requireKey();
  if (!agentId) {
    const err = new Error('No agentId provided and ELEVENLABS_AGENT_ID is unset.');
    err.status = 400;
    err.code = 'NO_AGENT_ID';
    throw err;
  }

  const url = `${BASE}/v1/convai/conversation/token?agent_id=${encodeURIComponent(agentId)}`;
  const res = await fetch(url, {
    method: 'GET',
    headers: { 'xi-api-key': key },
  });

  const text = await res.text();
  if (!res.ok) {
    const err = new Error(
      `ElevenLabs token request failed (${res.status}). ${truncate(text, 300)}`,
    );
    err.status = res.status === 401 ? 401 : 502;
    err.code = 'ELEVENLABS_TOKEN_FAILED';
    throw err;
  }

  let data;
  try {
    data = JSON.parse(text);
  } catch {
    const err = new Error('ElevenLabs returned a non-JSON token response.');
    err.status = 502;
    throw err;
  }

  // Be defensive about the field name across SDK/API versions.
  const token = data.token || data.conversation_token || data.conversationToken;
  if (!token) {
    const err = new Error('ElevenLabs token response did not contain a token.');
    err.status = 502;
    throw err;
  }
  return { token };
}

/**
 * List the account's voices so the config screen can offer real choices.
 * @returns {Promise<Array<{voiceId: string, name: string, category?: string, previewUrl?: string}>>}
 */
export async function listVoices() {
  const key = requireKey();
  const res = await fetch(`${BASE}/v1/voices`, {
    headers: { 'xi-api-key': key },
  });
  const text = await res.text();
  if (!res.ok) {
    const err = new Error(`ElevenLabs voices request failed (${res.status}). ${truncate(text, 200)}`);
    err.status = res.status === 401 ? 401 : 502;
    throw err;
  }
  const data = JSON.parse(text);
  const voices = Array.isArray(data.voices) ? data.voices : [];
  return voices.map((v) => ({
    voiceId: v.voice_id,
    name: v.name,
    category: v.category,
    previewUrl: v.preview_url,
  }));
}

function truncate(s, n) {
  if (typeof s !== 'string') return '';
  return s.length > n ? `${s.slice(0, n)}…` : s;
}

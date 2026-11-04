/**
 * Vision provider abstraction (server-side only).
 *
 * The browser sends a compressed JPEG snapshot + a question. We forward it to a
 * vision-capable model and return a short, spoken-friendly description. The
 * model is instructed to be honest: if the image is blurry, dark, or the thing
 * isn't clearly visible, it says so and asks the user to move closer — it must
 * NOT invent details it can't actually see.
 *
 * Providers: 'anthropic' (default) and 'openai'. Selected by VISION_PROVIDER.
 */

const VISION_SYSTEM_PROMPT = `You are the "eyes" of a voice assistant on a live video call. You are given a single still frame captured from the user's camera the moment they asked a visual question, plus their question.

Rules:
- Describe only what is actually visible in THIS frame. Never invent or assume details you cannot see.
- Your answer is read aloud, so keep it to 1-3 natural spoken sentences. No markdown, no lists unless essential.
- If the image is too blurry, dark, far away, cropped, or otherwise unclear to answer confidently, say that plainly and tell the user exactly what would help (e.g. "move a bit closer", "hold it steadier", "turn it toward the light", "show the front of the card").
- If you can identify an object but not fine details (e.g. a trading card's exact edition, grade, or serial), identify what you can and name what's still unreadable, rather than guessing.
- Be specific and useful. Lead with the direct answer to their question.`;

/**
 * @param {object} args
 * @param {string} args.imageBase64 - base64 JPEG (no data: prefix)
 * @param {string} [args.mediaType] - e.g. image/jpeg
 * @param {string} args.question - the user's spoken question
 * @param {string} [args.context] - optional conversation context
 * @returns {Promise<{text: string, provider: string, model: string}>}
 */
export async function analyzeImage({ imageBase64, mediaType = 'image/jpeg', question, context }) {
  const provider = (process.env.VISION_PROVIDER || 'anthropic').toLowerCase();
  if (!imageBase64) {
    const err = new Error('No image provided to vision service.');
    err.status = 400;
    throw err;
  }
  const userText = buildUserText(question, context);
  if (provider === 'openai') return analyzeWithOpenAI({ imageBase64, mediaType, userText });
  return analyzeWithAnthropic({ imageBase64, mediaType, userText });
}

function buildUserText(question, context) {
  const q = (question && question.trim()) || 'What am I looking at?';
  let t = `The user asked: "${q}"`;
  if (context && context.trim()) t += `\n\nRecent conversation context (for reference only): ${context.trim()}`;
  return t;
}

async function analyzeWithAnthropic({ imageBase64, mediaType, userText }) {
  const key = process.env.ANTHROPIC_API_KEY;
  if (!key) {
    const err = new Error('ANTHROPIC_API_KEY is not set on the server.');
    err.status = 503;
    err.code = 'NO_VISION_KEY';
    throw err;
  }
  const model = process.env.VISION_MODEL || 'claude-sonnet-5-5';
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model,
      max_tokens: 400,
      system: VISION_SYSTEM_PROMPT,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageBase64 } },
            { type: 'text', text: userText },
          ],
        },
      ],
    }),
  });
  const text = await res.text();
  if (!res.ok) throw apiError('Anthropic vision', res.status, text);
  const data = JSON.parse(text);
  const out = (data.content || [])
    .filter((b) => b.type === 'text')
    .map((b) => b.text)
    .join(' ')
    .trim();
  return { text: out || "I couldn't read that clearly — try again?", provider: 'anthropic', model };
}

async function analyzeWithOpenAI({ imageBase64, mediaType, userText }) {
  const key = process.env.OPENAI_API_KEY;
  if (!key) {
    const err = new Error('OPENAI_API_KEY is not set on the server.');
    err.status = 503;
    err.code = 'NO_VISION_KEY';
    throw err;
  }
  const model = process.env.VISION_MODEL || 'gpt-4o';
  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      model,
      max_tokens: 400,
      messages: [
        { role: 'system', content: VISION_SYSTEM_PROMPT },
        {
          role: 'user',
          content: [
            { type: 'text', text: userText },
            { type: 'image_url', image_url: { url: `data:${mediaType};base64,${imageBase64}` } },
          ],
        },
      ],
    }),
  });
  const text = await res.text();
  if (!res.ok) throw apiError('OpenAI vision', res.status, text);
  const data = JSON.parse(text);
  const out = data.choices?.[0]?.message?.content?.trim();
  return { text: out || "I couldn't read that clearly — try again?", provider: 'openai', model };
}

function apiError(label, status, body) {
  const err = new Error(`${label} request failed (${status}). ${truncate(body, 300)}`);
  err.status = status === 401 ? 401 : 502;
  err.code = 'VISION_FAILED';
  return err;
}

function truncate(s, n) {
  if (typeof s !== 'string') return '';
  return s.length > n ? `${s.slice(0, n)}…` : s;
}

export const _internals = { VISION_SYSTEM_PROMPT };

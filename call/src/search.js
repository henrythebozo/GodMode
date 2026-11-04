/**
 * Current-information lookup (server-side only), e.g. "how much is this worth?".
 *
 * Uses Claude's built-in web_search tool so we don't need a separate search
 * provider key. The model is told to distinguish SOLD/completed prices from
 * ASKING/listing prices, give a range with sources, and say clearly when it
 * cannot verify a value — never to invent one.
 *
 * Web search is a PAID Anthropic tool (billed per search in addition to
 * tokens). It is only invoked when the user explicitly asks for current info,
 * and is gated by PRICE_CHECK_ENABLED.
 */

const PRICE_SYSTEM_PROMPT = `You help a voice assistant answer "what is this worth / how much does this cost right now" questions using live web search.

Rules:
- Use web search to find CURRENT market information for the item described.
- Clearly distinguish SOLD / completed-sale prices (what items actually sold for) from ASKING / listing prices (what sellers are hoping to get). Prefer recent sold prices as the real value signal when available.
- Give a realistic range, not a single invented number. Mention condition/grade caveats if relevant (e.g. trading cards vary hugely by condition).
- Name where the figures come from (e.g. "recent eBay sold listings", a named marketplace).
- If you cannot find reliable current data, or the item is under-identified, SAY SO plainly and do not guess a value. It is correct to say "I can't verify a value for that."
- Your answer is read aloud: keep it to 2-4 natural spoken sentences, no markdown.`;

/**
 * @param {object} args
 * @param {string} args.query - what to price (ideally an identified item)
 * @returns {Promise<{text: string, searched: boolean, model: string}>}
 */
export async function priceCheck({ query }) {
  if (String(process.env.PRICE_CHECK_ENABLED).toLowerCase() !== 'true') {
    return {
      text:
        "Live price lookup isn't enabled on this server, so I can't verify a current value. " +
        'You can enable PRICE_CHECK_ENABLED in the server config to turn on web search.',
      searched: false,
      model: 'disabled',
    };
  }
  const key = process.env.ANTHROPIC_API_KEY;
  if (!key) {
    const err = new Error('ANTHROPIC_API_KEY is not set on the server.');
    err.status = 503;
    err.code = 'NO_SEARCH_KEY';
    throw err;
  }
  if (!query || !query.trim()) {
    const err = new Error('No query provided for price check.');
    err.status = 400;
    throw err;
  }

  const model = process.env.SEARCH_MODEL || 'claude-sonnet-5-5';
  const toolType = process.env.SEARCH_TOOL_TYPE || 'web_search_20250305';
  const maxUses = Number(process.env.SEARCH_MAX_USES || 5);

  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model,
      max_tokens: 700,
      system: PRICE_SYSTEM_PROMPT,
      tools: [{ type: toolType, name: 'web_search', max_uses: maxUses }],
      messages: [{ role: 'user', content: `Find the current value / price for: ${query.trim()}` }],
    }),
  });
  const text = await res.text();
  if (!res.ok) {
    const err = new Error(`Price check failed (${res.status}). ${truncate(text, 300)}`);
    err.status = res.status === 401 ? 401 : 502;
    err.code = 'SEARCH_FAILED';
    throw err;
  }
  const data = JSON.parse(text);
  const out = (data.content || [])
    .filter((b) => b.type === 'text')
    .map((b) => b.text)
    .join(' ')
    .trim();
  return {
    text: out || "I searched but couldn't pin down a reliable current value for that.",
    searched: true,
    model,
  };
}

function truncate(s, n) {
  if (typeof s !== 'string') return '';
  return s.length > n ? `${s.slice(0, n)}…` : s;
}

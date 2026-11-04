/* ===========================================================================
   GodMode Call — frontend logic.

   Voice:  ElevenLabs Agents over WebRTC (@elevenlabs/client, bundled).
   Vision: sampled camera frames -> our /api/vision (separate vision model).
           The agent "sees" only when it calls the `analyze_camera` client
           tool (natural speech) or when you tap Look / enable scene awareness.
           We never stream video to the model and never record anything.
   =========================================================================== */

const { Conversation } = window.ElevenLabsSDK || {};

// ---- tiny DOM helpers ------------------------------------------------------
const $ = (id) => document.getElementById(id);
const show = (el, yes = true) => { if (el) el.hidden = !yes; };

const els = {
  lobby: $('lobby'),
  call: $('call'),
  callBtn: $('callBtn'),
  lobbySub: $('lobbySub'),
  lobbyConfig: $('lobbyConfig'),
  openSettingsBtn: $('openSettingsBtn'),

  localVideo: $('localVideo'),
  cameraOffPlaceholder: $('cameraOffPlaceholder'),
  statusPill: $('statusPill'),
  statusText: $('statusText'),
  seeingIndicator: $('seeingIndicator'),
  seeingText: $('seeingText'),
  sceneIndicator: $('sceneIndicator'),
  orb: $('orb'),
  assistantMode: $('assistantMode'),
  captions: $('captions'),
  captionsToggle: $('captionsToggle'),

  muteBtn: $('muteBtn'),
  cameraBtn: $('cameraBtn'),
  lookBtn: $('lookBtn'),
  switchCamBtn: $('switchCamBtn'),
  endBtn: $('endBtn'),

  overlay: $('overlay'),
  overlayIcon: $('overlayIcon'),
  overlayTitle: $('overlayTitle'),
  overlayBody: $('overlayBody'),
  overlayRetry: $('overlayRetry'),
  overlayClose: $('overlayClose'),

  settingsSheet: $('settingsSheet'),
  settingsClose: $('settingsClose'),
  settingsSave: $('settingsSave'),
  agentIdInput: $('agentIdInput'),
  voiceSelect: $('voiceSelect'),
  voiceHint: $('voiceHint'),
  sceneToggle: $('sceneToggle'),
  sceneSecs: $('sceneSecs'),
  visionInfo: $('visionInfo'),
  priceInfo: $('priceInfo'),

  captureCanvas: $('captureCanvas'),
};

// ---- state -----------------------------------------------------------------
const state = {
  config: null,
  conversation: null,
  cameraStream: null,
  cameraOn: true,
  micMuted: false,
  facingMode: 'environment', // start rear-facing: you point it at things
  inCall: false,
  intentionalEnd: false,
  reconnectAttempts: 0,
  sceneTimer: null,
  framesInFlight: 0,
  captionLines: [],
  captionsVisible: true,
  orbRaf: null,
  lastContext: [],
};

const prefs = loadPrefs();

// ---- boot ------------------------------------------------------------------
init();

async function init() {
  if (!Conversation) {
    showOverlay('Setup incomplete', "The voice SDK didn't load. Run `npm run build` in the call/ folder, then reload.", { retry: false });
  }
  wireUI();
  await loadConfig();
}

async function loadConfig() {
  try {
    const res = await fetch('/api/config');
    state.config = await res.json();
  } catch {
    state.config = {};
  }
  const c = state.config || {};

  // Reflect configured-ness in the lobby.
  const rows = [];
  rows.push(line(c.hasElevenLabsKey && c.hasAgent, 'Voice (ElevenLabs agent)', 'needs ELEVENLABS_API_KEY + ELEVENLABS_AGENT_ID'));
  rows.push(line(c.visionConfigured, `Vision (${c.visionProvider || 'anthropic'} · ${c.visionModel || '—'})`, 'needs a vision API key'));
  rows.push(line(c.priceCheckEnabled, 'Live price lookup', 'off (optional, paid)', true));
  els.lobbyConfig.innerHTML = rows.join('');
  show(els.lobbyConfig, true);

  const ready = c.hasElevenLabsKey && c.hasAgent;
  els.callBtn.disabled = !ready;
  if (!ready) els.lobbySub.textContent = 'Add your ElevenLabs key and agent on the server to start (see Settings / README).';

  // scene interval label
  if (els.sceneSecs) els.sceneSecs.textContent = Math.round((c.sceneAwarenessIntervalMs || 20000) / 1000);
  els.visionInfo.innerHTML = c.visionConfigured
    ? `<span class="ok">Ready</span> — ${c.visionProvider} · ${c.visionModel}`
    : `<span class="miss">Not configured</span> — set a vision key on the server`;
  els.priceInfo.innerHTML = c.priceCheckEnabled
    ? '<span class="ok">Enabled</span> — uses paid web search only when you ask for a current value'
    : '<span class="miss">Disabled</span> — set PRICE_CHECK_ENABLED=true to allow web lookups';

  // restore prefs
  els.agentIdInput.value = prefs.agentId || '';
  els.sceneToggle.checked = Boolean(prefs.scene);
}

function line(ok, label, missHint, neutral) {
  const cls = ok ? 'ok' : neutral ? '' : 'miss';
  const mark = ok ? '✓' : neutral ? '•' : '!';
  return `<div><b class="${cls}">${mark}</b> ${label}${ok ? '' : ` <span class="miss">— ${missHint}</span>`}</div>`;
}

// ---- UI wiring -------------------------------------------------------------
function wireUI() {
  els.callBtn.addEventListener('click', startCall);
  els.endBtn.addEventListener('click', () => endCall(true));
  els.muteBtn.addEventListener('click', toggleMute);
  els.cameraBtn.addEventListener('click', toggleCamera);
  els.switchCamBtn.addEventListener('click', switchCamera);
  els.lookBtn.addEventListener('click', manualLook);

  els.openSettingsBtn.addEventListener('click', openSettings);
  els.settingsClose.addEventListener('click', () => show(els.settingsSheet, false));
  els.settingsSave.addEventListener('click', saveSettings);

  els.captionsToggle.addEventListener('click', () => {
    state.captionsVisible = !state.captionsVisible;
    show(els.captions, state.captionsVisible && state.captionLines.length > 0);
  });

  els.overlayClose.addEventListener('click', () => show(els.overlay, false));

  // make sure we release camera/mic if the tab is closed
  window.addEventListener('pagehide', () => endCall(true));
}

// ---- settings --------------------------------------------------------------
async function openSettings() {
  show(els.settingsSheet, true);
  // lazy-load voices once
  if (els.voiceSelect.dataset.loaded) return;
  if (!state.config?.hasElevenLabsKey) { els.voiceHint.textContent = 'Add an ElevenLabs key on the server to list voices.'; return; }
  try {
    const res = await fetch('/api/voices');
    const data = await res.json();
    if (data.error) throw new Error(data.error.message);
    for (const v of data.voices || []) {
      const opt = document.createElement('option');
      opt.value = v.voiceId;
      opt.textContent = v.category ? `${v.name} (${v.category})` : v.name;
      els.voiceSelect.appendChild(opt);
    }
    els.voiceSelect.value = prefs.voiceId || state.config.defaultVoiceId || '';
    els.voiceSelect.dataset.loaded = '1';
    els.voiceHint.textContent = 'Overrides the agent voice for this call. Requires voice override enabled on the agent.';
  } catch (e) {
    const msg = String(e.message || e);
    const brief = /401|unauthor|invalid_api_key/i.test(msg)
      ? 'Could not load voices — the ElevenLabs key looks invalid (401). Check it on the server.'
      : `Could not load voices: ${msg.slice(0, 100)}`;
    els.voiceHint.textContent = brief;
  }
}

function saveSettings() {
  prefs.agentId = els.agentIdInput.value.trim();
  prefs.voiceId = els.voiceSelect.value || '';
  prefs.scene = els.sceneToggle.checked;
  savePrefs(prefs);
  show(els.settingsSheet, false);
}

// ---- camera ----------------------------------------------------------------
async function acquireCamera() {
  const constraints = { video: { facingMode: { ideal: state.facingMode }, width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false };
  const stream = await navigator.mediaDevices.getUserMedia(constraints);
  attachCamera(stream);
  return stream;
}

function attachCamera(stream) {
  stopCameraStream();
  state.cameraStream = stream;
  els.localVideo.srcObject = stream;
  els.localVideo.classList.toggle('env-cam', state.facingMode === 'environment');
  state.cameraOn = true;
  show(els.cameraOffPlaceholder, false);
  els.localVideo.style.opacity = '1';
  setCtrlOff(els.cameraBtn, false);
  els.cameraBtn.setAttribute('aria-pressed', 'true');
}

function stopCameraStream() {
  if (state.cameraStream) {
    state.cameraStream.getTracks().forEach((t) => t.stop());
    state.cameraStream = null;
  }
}

async function toggleCamera() {
  if (!state.inCall) return;
  if (state.cameraOn) {
    stopCameraStream();
    els.localVideo.srcObject = null;
    els.localVideo.style.opacity = '0';
    state.cameraOn = false;
    show(els.cameraOffPlaceholder, true);
    setCtrlOff(els.cameraBtn, true);
    els.cameraBtn.setAttribute('aria-pressed', 'false');
    // Camera off => stop any ongoing frame uploads immediately.
    stopSceneAwareness(true);
  } else {
    try {
      await acquireCamera();
      if (prefs.scene) startSceneAwareness();
    } catch (e) {
      showToastOverlayCameraDenied(e);
    }
  }
}

async function switchCamera() {
  if (!state.inCall || !state.cameraOn) return;
  state.facingMode = state.facingMode === 'environment' ? 'user' : 'environment';
  try {
    await acquireCamera();
  } catch (e) {
    // fall back to the other camera if the requested one doesn't exist
    state.facingMode = state.facingMode === 'environment' ? 'user' : 'environment';
    try { await acquireCamera(); } catch { showToastOverlayCameraDenied(e); }
  }
}

// ---- frame capture ---------------------------------------------------------
/** Draw the current video frame to a canvas and return a compressed JPEG data URL, or null. */
function captureFrame(maxDim = 768, quality = 0.6) {
  if (!state.cameraOn || !state.cameraStream) return null;
  const v = els.localVideo;
  const vw = v.videoWidth, vh = v.videoHeight;
  if (!vw || !vh) return null;
  const scale = Math.min(1, maxDim / Math.max(vw, vh));
  const w = Math.round(vw * scale), h = Math.round(vh * scale);
  const cv = els.captureCanvas;
  cv.width = w; cv.height = h;
  const ctx = cv.getContext('2d');
  // Note: we capture the true (unmirrored) frame so the model sees reality.
  ctx.drawImage(v, 0, 0, w, h);
  return cv.toDataURL('image/jpeg', quality);
}

// ---- vision + price (also exposed to the agent as client tools) -----------
async function runVision(question, { label = 'Looking…' } = {}) {
  if (!state.cameraOn) {
    return "Your camera is off, so I can't see anything right now. Turn the camera on and I'll take a look.";
  }
  const dataUrl = captureFrame();
  if (!dataUrl) return "I couldn't grab a camera frame just now — give it a second and ask again.";

  beginSeeing(label);
  try {
    const res = await fetch('/api/vision', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ image: dataUrl, mediaType: 'image/jpeg', question, context: recentContext() }),
    });
    const data = await res.json();
    if (data.error) {
      return friendlyServiceError(data.error, 'see');
    }
    addCaption('camera', data.text);
    return data.text;
  } catch (e) {
    return `I couldn't reach the vision service (${e.message}).`;
  } finally {
    endSeeing();
  }
}

async function runPriceCheck(item) {
  beginSeeing('Checking value…');
  try {
    const res = await fetch('/api/price-check', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ query: item }),
    });
    const data = await res.json();
    if (data.error) return friendlyServiceError(data.error, 'price');
    return data.text;
  } catch (e) {
    return `I couldn't reach the price-lookup service (${e.message}).`;
  } finally {
    endSeeing();
  }
}

function friendlyServiceError(error, kind) {
  if (error.code === 'NO_VISION_KEY' || error.code === 'NO_SEARCH_KEY')
    return `The ${kind === 'see' ? 'vision' : 'price'} service isn't set up on the server yet.`;
  return `I ran into a problem trying to ${kind === 'see' ? 'see that' : 'look that up'}: ${error.message}`;
}

// "Look" button: force a visual turn even if the agent has no camera tool.
async function manualLook() {
  if (!state.inCall) return;
  if (!state.cameraOn) { flashMode('Camera is off'); return; }
  els.lookBtn.classList.add('busy');
  try {
    const desc = await runVision('What am I looking at?', { label: 'Looking…' });
    if (state.conversation) {
      // give the agent the fresh visual context, then prompt it to speak
      try { state.conversation.sendContextualUpdate(`[Camera] What the user's camera sees right now: ${desc}`); } catch {}
      try { state.conversation.sendUserMessage('What am I looking at?'); } catch {}
    }
  } finally {
    els.lookBtn.classList.remove('busy');
  }
}

// ---- scene awareness (optional, low frequency) -----------------------------
function startSceneAwareness() {
  if (state.sceneTimer || !state.inCall || !state.cameraOn) return;
  const interval = Math.max(8000, state.config?.sceneAwarenessIntervalMs || 20000);
  show(els.sceneIndicator, true);
  const tick = async () => {
    if (!state.inCall || !state.cameraOn || !state.conversation) return;
    const desc = await runVision('Briefly describe the current scene for ongoing awareness.', { label: 'Scene…' });
    try { state.conversation.sendContextualUpdate(`[Scene] ${desc}`); } catch {}
  };
  state.sceneTimer = setInterval(tick, interval);
}

function stopSceneAwareness(hideIndicator) {
  if (state.sceneTimer) { clearInterval(state.sceneTimer); state.sceneTimer = null; }
  if (hideIndicator) show(els.sceneIndicator, false);
}

// ---- the call --------------------------------------------------------------
async function startCall() {
  if (state.inCall) return;
  state.intentionalEnd = false;
  state.reconnectAttempts = 0;
  switchView('call');
  setStatus('connecting', 'Connecting…');

  // 1) camera (video-only; the SDK captures the mic itself)
  try {
    await acquireCamera();
  } catch (e) {
    // Camera denied/unavailable: continue voice-only, but say so plainly.
    state.cameraOn = false;
    show(els.cameraOffPlaceholder, true);
    setCtrlOff(els.cameraBtn, true);
    els.localVideo.style.opacity = '0';
    flashMode('Camera unavailable — voice only');
  }

  // 2) voice session
  try {
    await connectConversation();
  } catch (e) {
    console.error(e);
    endMedia();
    showOverlay('Could not start the call', describeStartError(e), {
      retry: true,
      onRetry: () => { show(els.overlay, false); startCall(); },
    });
    switchView('lobby');
    return;
  }

  state.inCall = true;
  startOrbLoop();
  if (prefs.scene && state.cameraOn) startSceneAwareness();
}

async function connectConversation() {
  const agentId = (prefs.agentId || state.config?.agentId || '').trim();
  const tokenRes = await fetch(`/api/elevenlabs/token${agentId ? `?agentId=${encodeURIComponent(agentId)}` : ''}`);
  const tokenData = await tokenRes.json();
  if (tokenData.error) { const e = new Error(tokenData.error.message); e.code = tokenData.error.code; throw e; }

  const overrides = {};
  const voiceId = prefs.voiceId || '';
  if (voiceId) overrides.tts = { voiceId };

  const opts = {
    conversationToken: tokenData.token,
    connectionType: 'webrtc',
    ...(Object.keys(overrides).length ? { overrides } : {}),
    clientTools: {
      // The agent calls this when the user asks something visual.
      analyze_camera: async (params = {}) => runVision(params.query || params.question || 'What am I looking at?'),
      // The agent calls this for "how much is this worth / what does it cost now?"
      check_price: async (params = {}) => runPriceCheck(params.item || params.query || params.description || ''),
    },
    onConnect: () => { setStatus('connected', 'Connected'); state.reconnectAttempts = 0; },
    onDisconnect: () => handleDisconnect(),
    onError: (msg) => { console.error('[elevenlabs]', msg); },
    onModeChange: (m) => updateMode(m && (m.mode || m)),
    onStatusChange: (s) => { const v = s && (s.status || s); if (v === 'connecting') setStatus('connecting', 'Connecting…'); },
    onMessage: (m) => handleMessage(m),
  };

  state.conversation = await Conversation.startSession(opts);
  // apply current mute state (default unmuted)
  try { state.conversation.setMicMuted(state.micMuted); } catch {}
}

function handleDisconnect() {
  if (state.intentionalEnd) return;
  if (!state.inCall) return;
  // unexpected drop -> try to reconnect
  if (state.reconnectAttempts < 3) {
    state.reconnectAttempts += 1;
    setStatus('reconnecting', `Reconnecting… (${state.reconnectAttempts}/3)`);
    const delay = 1000 * state.reconnectAttempts;
    setTimeout(async () => {
      try {
        await connectConversation();
      } catch (e) {
        if (state.reconnectAttempts >= 3) failReconnect(e);
      }
    }, delay);
  } else {
    failReconnect(new Error('Connection lost'));
  }
}

function failReconnect(e) {
  endMedia();
  state.inCall = false;
  stopOrbLoop();
  showOverlay('Call dropped', `The connection was lost and couldn't be restored. ${e?.message || ''}`.trim(), {
    retry: true,
    onRetry: () => { show(els.overlay, false); switchView('lobby'); },
  });
  switchView('lobby');
}

async function endCall(intentional) {
  state.intentionalEnd = Boolean(intentional);
  stopSceneAwareness(true);
  stopOrbLoop();
  if (state.conversation) {
    try { await state.conversation.endSession(); } catch {}
    state.conversation = null;
  }
  endMedia();
  state.inCall = false;
  state.captionLines = [];
  els.captions.innerHTML = '';
  show(els.captions, false);
  switchView('lobby');
  setStatus('connecting', 'Connecting…');
}

function endMedia() {
  stopCameraStream();
  els.localVideo.srcObject = null;
}

// ---- messages / captions ---------------------------------------------------
function handleMessage(m) {
  if (!m) return;
  // shape varies; be defensive
  const source = m.source || m.role || (m.type && String(m.type));
  const text = m.message || m.text || m.content || '';
  if (!text) return;
  const who = /user|human/i.test(String(source)) ? 'user' : 'agent';
  addCaption(who, text);
  state.lastContext.push(`${who === 'user' ? 'User' : 'Assistant'}: ${text}`);
  if (state.lastContext.length > 6) state.lastContext.shift();
}

function recentContext() { return state.lastContext.slice(-4).join('\n'); }

function addCaption(who, text) {
  const label = who === 'user' ? 'You' : who === 'camera' ? 'Camera' : 'Assistant';
  state.captionLines.push({ who: who === 'camera' ? 'agent' : who, label, text });
  if (state.captionLines.length > 4) state.captionLines.shift();
  els.captions.innerHTML = state.captionLines
    .map((l) => `<div class="cap-line ${l.who}"><span class="who">${l.label}</span>${escapeHtml(l.text)}</div>`)
    .join('');
  if (state.captionsVisible) show(els.captions, true);
}

// ---- orb + mode ------------------------------------------------------------
function updateMode(mode) {
  const speaking = /speak/i.test(String(mode));
  els.orb.classList.toggle('speaking', speaking);
  els.assistantMode.textContent = speaking ? 'Speaking' : 'Listening';
}

function startOrbLoop() {
  stopOrbLoop();
  const loop = () => {
    let level = 0;
    const c = state.conversation;
    if (c) {
      try {
        const out = c.getOutputByteFrequencyData?.();
        const inp = c.getInputByteFrequencyData?.();
        level = Math.max(avg(out), avg(inp) * 0.6);
      } catch {}
    }
    els.orb.style.setProperty('--level', level.toFixed(3));
    state.orbRaf = requestAnimationFrame(loop);
  };
  state.orbRaf = requestAnimationFrame(loop);
}

function stopOrbLoop() {
  if (state.orbRaf) cancelAnimationFrame(state.orbRaf);
  state.orbRaf = null;
  els.orb.style.setProperty('--level', '0');
}

function avg(arr) {
  if (!arr || !arr.length) return 0;
  let s = 0;
  for (let i = 0; i < arr.length; i++) s += arr[i];
  return Math.min(1, s / arr.length / 140); // normalize 0..255 -> ~0..1
}

// ---- controls helpers ------------------------------------------------------
function toggleMute() {
  state.micMuted = !state.micMuted;
  try { state.conversation?.setMicMuted(state.micMuted); } catch {}
  setCtrlOff(els.muteBtn, state.micMuted);
  els.muteBtn.setAttribute('aria-pressed', String(!state.micMuted));
  flashMode(state.micMuted ? 'Mic muted' : 'Mic on');
}

function setCtrlOff(btn, off) { btn.classList.toggle('is-off', off); }

function beginSeeing(label) {
  state.framesInFlight += 1;
  els.seeingText.textContent = label;
  show(els.seeingIndicator, true);
}
function endSeeing() {
  state.framesInFlight = Math.max(0, state.framesInFlight - 1);
  if (state.framesInFlight === 0) show(els.seeingIndicator, false);
}

let flashTimer = null;
function flashMode(text) {
  els.assistantMode.textContent = text;
  clearTimeout(flashTimer);
  flashTimer = setTimeout(() => {
    els.assistantMode.textContent = els.orb.classList.contains('speaking') ? 'Speaking' : 'Listening';
  }, 1600);
}

// ---- status / views / overlay ----------------------------------------------
function setStatus(stateName, text) {
  els.statusPill.dataset.state = stateName;
  els.statusText.textContent = text;
}

function switchView(name) {
  els.lobby.classList.toggle('is-active', name === 'lobby');
  els.call.classList.toggle('is-active', name === 'call');
}

function showOverlay(title, body, { retry = false, onRetry } = {}) {
  els.overlayTitle.textContent = title;
  els.overlayBody.textContent = body;
  show(els.overlayRetry, retry);
  els.overlayRetry.onclick = onRetry || (() => show(els.overlay, false));
  show(els.overlay, true);
}

function showToastOverlayCameraDenied(e) {
  const denied = e && (e.name === 'NotAllowedError' || e.name === 'SecurityError');
  showOverlay(
    denied ? 'Camera permission needed' : 'Camera unavailable',
    denied
      ? 'Allow camera access in your browser to let the assistant see. On iPhone Safari: aA / site settings → Camera → Allow, then try again. You can keep talking without it.'
      : `Couldn't open the camera: ${e?.message || 'unknown error'}. You can keep talking without it.`,
    { retry: false },
  );
}

function describeStartError(e) {
  if (e.code === 'NO_ELEVENLABS_KEY') return 'The server has no ElevenLabs API key. Add ELEVENLABS_API_KEY to call/.env and restart.';
  if (e.code === 'NO_AGENT_ID') return 'No ElevenLabs agent configured. Set ELEVENLABS_AGENT_ID in call/.env (or enter an Agent ID in Settings).';
  if (e.code === 'ELEVENLABS_TOKEN_FAILED') return `ElevenLabs rejected the token request: ${e.message}`;
  if (/microphone|getusermedia|permission|NotAllowed/i.test(e.message)) return 'Microphone permission is required for a voice call. Allow mic access and try again.';
  return e.message || 'Unknown error starting the call.';
}

// ---- prefs / utils ---------------------------------------------------------
function loadPrefs() {
  try { return JSON.parse(localStorage.getItem('cc_prefs') || '{}'); } catch { return {}; }
}
function savePrefs(p) {
  try { localStorage.setItem('cc_prefs', JSON.stringify(p)); } catch {}
}
function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// expose a few internals for debugging in the console
window.__call = { state, captureFrame, runVision, runPriceCheck };

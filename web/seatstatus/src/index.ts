import {
  createSessionFromTokenBundle,
  clearSessionCookie,
  getSessionWithAutoRefresh,
  handleAuthCallback,
  handleAuthLogin,
  requireSessionWithAutoRefresh,
} from './auth';
import { getDetail, getLastDiff, getSnapshot, pollSeatStatus } from './poller';
import { SeatStatusDO } from './seat_status_do';
import type { Env, SessionPayload } from './types';

const LAST_ACCESS_TOKEN_KEY = 'auth:last_access_token';
const APP_ICON_URL = 'https://preconnect.app/icon.svg';

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

function html(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { 'content-type': 'text/html; charset=utf-8' },
  });
}

function redirect(location: string): Response {
  return new Response(null, { status: 302, headers: { Location: location } });
}

function devicePage(): string {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Health</title>
<link rel="icon" type="image/svg+xml" href="${APP_ICON_URL}" />
<style>
body{font-family:ui-sans-serif,system-ui;margin:0;background:#ffffff;color:#1d1f24}
.w{max-width:760px;margin:0 auto;padding:28px 20px}
.card{background:#ffffff;border:1px solid rgba(46,62,87,.14);border-radius:22px;padding:24px;box-shadow:0 14px 34px rgba(17,35,64,.10)}
h2{margin:0;font-size:28px;line-height:1.1}
.brand{display:flex;align-items:center;margin-bottom:6px}
.muted{color:#6b7280}
.ok{color:#1E6BE3}
.err{color:#D63B3B}
.codeWrap{border:1px solid rgba(46,62,87,.16);border-radius:14px;padding:14px 16px;margin-top:14px}
.codeRow{display:flex;align-items:center;justify-content:center}
button{border:1px solid rgba(30,107,227,.30);background:#ffffff;color:#1E6BE3;border-radius:14px;padding:10px 12px;cursor:pointer;font-weight:700}
button:disabled{opacity:.6;cursor:default}
.iconBtn{display:inline-flex;align-items:center;justify-content:center;gap:8px;padding:10px 14px}
.iconBtn svg{width:18px;height:18px;stroke:#1E6BE3}
.hidden{display:none}
.sub{font-size:inherit}
.centerCol{display:flex;flex-direction:column;align-items:center}
</style></head><body><div class="w"><div class="card">
<div>
  <div class="brand"><h2>Health</h2></div>
  <p class="muted sub">Copy the code, open PreConnect App, and tap Connect.
</p>
  <div class="codeWrap">
    <div class="codeRow">
      <button id="copy" class="iconBtn" title="Copy Code" aria-label="Copy Code">
        <svg id="copyIcon" viewBox="0 0 24 24" fill="none" stroke-width="2" aria-hidden="true">
          <rect x="9" y="9" width="11" height="11" rx="2"></rect>
          <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
        </svg>
        <svg id="copiedIcon" class="hidden" viewBox="0 0 24 24" fill="none" stroke-width="2" aria-hidden="true">
          <path d="M20 7L10 17l-6-6"></path>
        </svg>
        <span id="copyText">Copy Code</span>
      </button>
    </div>
  </div>
  <div class="centerCol">
    <p id="status" class="muted sub">Preparing Code...</p>
    <button id="regen">Generate New Code</button>
  </div>
</div>
</div></div></div>
<script>
let code = null; let poll = null;
const statusEl = document.getElementById('status');
const regenEl = document.getElementById('regen');
const copyEl = document.getElementById('copy');
const copyTextEl = document.getElementById('copyText');
const copyIconEl = document.getElementById('copyIcon');
const copiedIconEl = document.getElementById('copiedIcon');
async function start() {
  if (poll) clearInterval(poll);
  regenEl.disabled = true;
  statusEl.textContent = 'Refreshing code...';
  const r = await fetch('/auth/device/start',{method:'POST',credentials:'include'});
  const j = await r.json();
  code = j.code;
  statusEl.textContent = 'Waiting for app confirmation...';
  regenEl.disabled = false;
  poll = setInterval(check, 1500);
}
async function copyCode() {
  if (!code) return;
  try {
    await navigator.clipboard.writeText(code);
    copyTextEl.textContent = 'Copied';
    copyIconEl.classList.add('hidden');
    copiedIconEl.classList.remove('hidden');
    copyEl.disabled = true;
    setTimeout(() => {
      copyTextEl.textContent = 'Copy Code';
      copyIconEl.classList.remove('hidden');
      copiedIconEl.classList.add('hidden');
      copyEl.disabled = false;
    }, 10000);
  } catch {}
}
async function check() {
  if (!code) return;
  const r = await fetch('/auth/device/status?code='+encodeURIComponent(code),{credentials:'include'});
  const j = await r.json();
  if (j.status === 'done') {
    clearInterval(poll);
    statusEl.innerHTML = '<span class="ok">Done. Signing in...</span>';
    location.href = '/auth/device/consume?code=' + encodeURIComponent(code);
  } else if (j.status === 'expired') {
    clearInterval(poll);
    statusEl.innerHTML = '<span class="err">Code Expired. Generate New Code.</span>';
  }
}
regenEl.addEventListener('click', start);
copyEl.addEventListener('click', copyCode);
start();
</script></body></html>`;
}

function corsHeaders(origin: string | null): Headers {
  const headers = new Headers();
  if (origin) headers.set('Access-Control-Allow-Origin', origin);
  headers.set('Access-Control-Allow-Credentials', 'true');
  headers.set('Access-Control-Allow-Headers', 'content-type, authorization');
  headers.set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  return headers;
}

async function requireAuthSession(
  req: Request,
): Promise<{ session: SessionPayload; setCookie?: string } | Response> {
  try {
    const result = await requireSessionWithAutoRefresh(req);
    return result;
  } catch {
    return json({ error: 'unauthorized' }, 401);
  }
}

function withSessionCookie(
  response: Response,
  auth: { setCookie?: string } | SessionPayload,
): Response {
  const setCookie = 'setCookie' in auth ? auth.setCookie : undefined;
  if (setCookie) {
    try {
      response.headers.append('Set-Cookie', setCookie);
    } catch {
    }
  }
  return response;
}

function appPage(): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Health</title>
  <link rel="icon" type="image/svg+xml" href="${APP_ICON_URL}" />
  <style>
    body{font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,sans-serif;margin:0;background:#ffffff;color:#1f2937}
    .wrap{max-width:760px;margin:0 auto;padding:18px 14px 28px}
    .top{display:grid;grid-template-columns:auto 1fr;align-items:center;gap:10px}
    .brand{display:flex;align-items:center;gap:10px}
    .brand img{width:30px;height:30px;border-radius:8px}
    h1{margin:0;font-size:28px;line-height:1;font-weight:900}
    .actions{display:grid;grid-template-columns:repeat(2, auto);gap:8px;justify-content:end}
    button{border:1px solid rgba(46,62,87,.20);background:#fff;color:#1f2937;border-radius:12px;padding:9px 11px;font-size:14px;white-space:nowrap}
    button{font-weight:700;color:#1E6BE3;cursor:pointer}
    button:disabled{opacity:.7;cursor:default}
    .grid{margin-top:10px;display:grid;gap:8px;grid-template-columns:1fr 1fr}
    .card{border:1px solid rgba(46,62,87,.16);border-radius:14px;background:#fff;padding:12px}
    .wide{grid-column:1 / -1}
    .label{font-size:12px;color:#64748b;font-weight:700;text-transform:uppercase;letter-spacing:.4px}
    .value{margin-top:4px;font-size:24px;font-weight:900}
    .ok{color:#1E6BE3}.err{color:#D63B3B}
    @media (max-width:760px){
      h1{font-size:22px}
      .top{grid-template-columns:auto 1fr}
      .actions{grid-template-columns:repeat(2, minmax(0, 1fr));gap:6px}
      button{font-size:12px;padding:8px 6px}
      .grid{grid-template-columns:repeat(2, minmax(0, 1fr))}
      .ws-health-title{display:none}
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="top">
      <div class="brand">
        <img src="${APP_ICON_URL}" alt="PreConnect"/>
        <h1 class="ws-health-title">Health</h1>
      </div>
      <div class="actions">
        <button id="refresh">Refresh</button>
        <button id="logout">Logout</button>
      </div>
    </div>
    <div class="grid">
      <div class="card"><div class="label">API</div><div id="health" class="value">-</div></div>
      <div class="card ws-card"><div class="label">WebSocket</div><div id="ws" class="value">-</div></div>
      <div class="card"><div class="label">Total Sections</div><div id="total" class="value">-</div></div>
      <div class="card"><div class="label">Pos Sections</div><div id="positive" class="value">-</div></div>
      <div class="card"><div class="label">Zero Sections</div><div id="zero" class="value">-</div></div>
      <div class="card"><div class="label">Neg Sections</div><div id="negative" class="value">-</div></div>
      <div class="card"><div class="label">Avg Seats</div><div id="avg" class="value">-</div></div>
      <div class="card"><div class="label">Min Seats</div><div id="min" class="value">-</div></div>
      <div class="card"><div class="label">Max Seats</div><div id="max" class="value">-</div></div>
      <div class="card"><div class="label">Last Diff</div><div id="diffCount" class="value">-</div></div>
      <div class="card"><div class="label">Last Fetch</div><div id="lastFetch" class="value" style="font-size:16px;font-weight:700">-</div></div>
      <div class="card"><div class="label">Last Change</div><div id="lastChange" class="value" style="font-size:16px;font-weight:700">-</div></div>
    </div>
  </div>
  <script>
    const healthEl = document.getElementById('health');
    const wsEl = document.getElementById('ws');
    const totalEl = document.getElementById('total');
    const positiveEl = document.getElementById('positive');
    const zeroEl = document.getElementById('zero');
    const negativeEl = document.getElementById('negative');
    const avgEl = document.getElementById('avg');
    const minEl = document.getElementById('min');
    const maxEl = document.getElementById('max');
    const diffCountEl = document.getElementById('diffCount');
    const lastFetchEl = document.getElementById('lastFetch');
    const lastChangeEl = document.getElementById('lastChange');
    const refreshEl = document.getElementById('refresh');
    const logoutEl = document.getElementById('logout');
    let ws;
    let reconnecting = false;
    const fmtTs = (ts) => {
      if (!ts) return 'never';
      const d = new Date(ts);
      const datePart = d.toLocaleDateString(undefined, {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
      });
      const timePart = d.toLocaleTimeString(undefined, {
        hour: 'numeric',
        minute: '2-digit',
        second: '2-digit',
      });
      return datePart + ', ' + timePart;
    };

    function renderStats(map, diff, lastFetchMs, lastChangeMs) {
      const safeMap = map || {};
      const safeDiff = diff || {};
      const values = Object.values(safeMap).map((v) => Number(v)).filter((v) => Number.isFinite(v));
      const positives = values.filter((v) => v > 0).length;
      const zeros = values.filter((v) => v === 0).length;
      const negatives = values.filter((v) => v < 0).length;
      const min = values.length ? Math.min(...values) : 0;
      const max = values.length ? Math.max(...values) : 0;
      const avg = values.length ? (values.reduce((a, b) => a + b, 0) / values.length).toFixed(2) : '0.00';
      totalEl.textContent = String(Object.keys(safeMap).length);
      positiveEl.textContent = String(positives);
      zeroEl.textContent = String(zeros);
      negativeEl.textContent = String(negatives);
      minEl.textContent = String(min);
      maxEl.textContent = String(max);
      avgEl.textContent = String(avg);
      diffCountEl.textContent = String(Object.keys(safeDiff).length);
      lastFetchEl.textContent = fmtTs(lastFetchMs);
      lastChangeEl.textContent = fmtTs(lastChangeMs);
    }

    async function loadStats() {
      const [res, diffRes] = await Promise.all([
        fetch('/api/seats/snapshot', { credentials:'include' }),
        fetch('/api/seats/diff', { credentials:'include' }),
      ]);
      if (res.status === 401 || diffRes.status === 401) { location.href = '/auth/device'; return; }
      const data = await res.json();
      const diffPayload = diffRes.ok ? await diffRes.json() : { diff: {} };
      renderStats(data?.map || {}, diffPayload?.diff || {}, data.lastFetchMs, data.lastChangeMs);
    }

    function connectWs(manual = false) {
      if (manual && reconnecting) return;
      if (manual) {
        reconnecting = true;
        refreshEl.disabled = true;
        refreshEl.textContent = 'Refreshing...';
      }
      if (ws) { try { ws.close(); } catch {} }
      const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
      ws = new WebSocket(scheme + '://' + location.host + '/ws');
      ws.onopen = async () => {
        wsEl.textContent = 'Connected';
        wsEl.className = 'value ok';
        healthEl.textContent = 'OK';
        healthEl.className = 'value ok';
        if (manual) {
          try {
            await fetch('/api/seats/refresh', { method:'POST', credentials:'include' });
          } catch {}
        }
        await loadStats();
        if (manual) {
          reconnecting = false;
          refreshEl.disabled = false;
          refreshEl.textContent = 'Refresh';
        }
      };
      ws.onclose = () => {
        wsEl.textContent = 'Disconnected';
        wsEl.className = 'value err';
        healthEl.textContent = 'ERR';
        healthEl.className = 'value err';
        if (manual) {
          reconnecting = false;
          refreshEl.disabled = false;
          refreshEl.textContent = 'Refresh';
        }
        setTimeout(() => connectWs(false), 2000);
      };
      ws.onerror = () => {
        wsEl.textContent = 'Error';
        wsEl.className = 'value err';
        healthEl.textContent = 'ERR';
        healthEl.className = 'value err';
        if (manual) {
          reconnecting = false;
          refreshEl.disabled = false;
          refreshEl.textContent = 'Refresh';
        }
      };
      ws.onmessage = async (ev) => {
        try {
          const msg = JSON.parse(ev.data);
          if (msg?.type === 'seat_status') {
            renderStats(msg.seatStatus || {}, msg.changedSections || {}, msg.ts, msg.ts);
            return;
          }
          if (msg?.type === 'seat_diff') await loadStats();
        } catch {}
      };
    }

    refreshEl.addEventListener('click', () => connectWs(true));
    logoutEl.addEventListener('click', async () => { await fetch('/auth/logout', { method:'POST', credentials:'include' }); location.href='/auth/device'; });
    connectWs(false);
  </script>
</body>
</html>`;
}

async function cacheAccessToken(env: Env, session: SessionPayload): Promise<void> {
  const token = session.accessToken?.trim();
  if (!token) return;
  const now = Math.floor(Date.now() / 1000);
  const ttl = Math.max(60, session.exp - now);
  try {
    await env.SEAT_STATUS.put(LAST_ACCESS_TOKEN_KEY, token, { expirationTtl: ttl });
  } catch (err) {
    console.error('Failed to cache access token:', err);
  }
}

async function readCachedAccessToken(env: Env): Promise<string | null> {
  const token = await env.SEAT_STATUS.get(LAST_ACCESS_TOKEN_KEY);
  return token?.trim() || null;
}

async function handleApi(
  req: Request,
  env: Env,
  auth: { session: SessionPayload; setCookie?: string },
): Promise<Response> {
  const url = new URL(req.url);
  const { session } = auth;

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(req.headers.get('Origin')) });
  }
  await cacheAccessToken(env, session);

  if (url.pathname === '/api/seats/snapshot' && req.method === 'GET') {
    const snap = await getSnapshot(env);
    return withSessionCookie(json(snap), auth);
  }

  if (url.pathname.startsWith('/api/seats/detail/') && req.method === 'GET') {
    const sectionId = url.pathname.replace('/api/seats/detail/', '').trim();
    if (!sectionId) return withSessionCookie(json({ error: 'missing section id' }, 400), auth);
    const detail = await getDetail(env, sectionId);
    if (!detail) return withSessionCookie(json({ error: 'not found' }, 404), auth);
    return withSessionCookie(json(detail), auth);
  }

  if (url.pathname === '/api/seats/diff' && req.method === 'GET') {
    const diff = await getLastDiff(env);
    return withSessionCookie(json({ diff }), auth);
  }

  if (url.pathname === '/api/seats/refresh' && req.method === 'POST') {
    const token = session.accessToken?.trim();
    if (!token) return withSessionCookie(json({ error: 'session token missing, login again' }, 401), auth);
    const result = await pollSeatStatus(env, {
      reason: 'manual-refresh',
      broadcast: true,
      accessToken: token,
    });
    return withSessionCookie(json(result), auth);
  }

  if (url.pathname === '/api/seats/search' && req.method === 'GET') {
    const q = (url.searchParams.get('q') ?? '').trim().toLowerCase();
    const snap = await getSnapshot(env);
    if (!q) return withSessionCookie(json({ results: [], total: 0 }), auth);

    const results = Object.entries(snap.map)
      .filter(([sectionId]) => sectionId.includes(q))
      .slice(0, 200)
      .map(([sectionId, consumedSeat]) => ({ sectionId, consumedSeat }));

    return withSessionCookie(json({ results, total: results.length }), auth);
  }

  return withSessionCookie(json({ error: 'not found' }, 404), auth);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS' && url.pathname.startsWith('/api/')) {
      return new Response(null, { status: 204, headers: corsHeaders(request.headers.get('Origin')) });
    }

    if (url.pathname === '/health') {
      return json({ ok: true, service: 'seatstatus' });
    }

    if (url.pathname === '/' && request.method === 'GET' && url.searchParams.has('code')) {
      return handleAuthCallback(request, env);
    }

    if (url.pathname === '/auth/device' && request.method === 'GET') {
      return html(devicePage());
    }

    if (url.pathname === '/auth/device/start' && request.method === 'POST') {
      const id = env.SEAT_STATUS_DO.idFromName('global');
      const stub = env.SEAT_STATUS_DO.get(id);
      return stub.fetch('https://internal/device/start', { method: 'POST' });
    }

    if (url.pathname === '/auth/device/status' && request.method === 'GET') {
      const code = (url.searchParams.get('code') ?? '').trim().toUpperCase();
      const id = env.SEAT_STATUS_DO.idFromName('global');
      const stub = env.SEAT_STATUS_DO.get(id);
      return stub.fetch(`https://internal/device/status?code=${encodeURIComponent(code)}`);
    }

    if (url.pathname === '/auth/device/complete' && request.method === 'POST') {
      const id = env.SEAT_STATUS_DO.idFromName('global');
      const stub = env.SEAT_STATUS_DO.get(id);
      return stub.fetch('https://internal/device/complete', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: await request.text(),
      });
    }

    if (url.pathname === '/auth/device/consume' && request.method === 'GET') {
      const code = (url.searchParams.get('code') ?? '').trim().toUpperCase();
      if (!code) return redirect('/auth/device');
      const id = env.SEAT_STATUS_DO.idFromName('global');
      const stub = env.SEAT_STATUS_DO.get(id);
      const consumeRes = await stub.fetch(
        `https://internal/device/consume?code=${encodeURIComponent(code)}`,
      );
      if (!consumeRes.ok) {
        return redirect('/auth/device');
      }
      const body = (await consumeRes.json()) as {
        accessToken?: string;
        refreshToken?: string;
        idToken?: string;
        expiresIn?: number;
      };
      if (!body.accessToken || !body.refreshToken) return redirect('/auth/device');
      const sessionPack = await createSessionFromTokenBundle({
        accessToken: body.accessToken,
        refreshToken: body.refreshToken,
        idToken: body.idToken,
        expiresIn: body.expiresIn,
      });
      await cacheAccessToken(env, sessionPack.session);
      const res = redirect('/');
      res.headers.append('Set-Cookie', sessionPack.setCookie);
      return res;
    }

    if (url.pathname === '/auth/login' && request.method === 'GET') {
      return handleAuthLogin(request, env);
    }

    if (url.pathname === '/auth/callback' && request.method === 'GET') {
      return handleAuthCallback(request, env);
    }

    if (url.pathname === '/auth/me' && request.method === 'GET') {
      const auth = await getSessionWithAutoRefresh(request);
      if (!auth.session) return json({ authenticated: false });
      await cacheAccessToken(env, auth.session);
      return withSessionCookie(
        json({ authenticated: true, user: { sub: auth.session.sub, exp: auth.session.exp } }),
        auth,
      );
    }

    if (url.pathname === '/auth/logout' && request.method === 'POST') {
      const res = json({ ok: true });
      res.headers.append('Set-Cookie', clearSessionCookie());
      return res;
    }

    if (url.pathname === '/' && request.method === 'GET') {
      const auth = await getSessionWithAutoRefresh(request);
      if (!auth.session) return redirect('/auth/device');
      await cacheAccessToken(env, auth.session);
      return withSessionCookie(html(appPage()), auth);
    }

    if (url.pathname === '/ws') {
      const sessionOrError = await requireAuthSession(request);
      if (sessionOrError instanceof Response) return sessionOrError;
      const token = sessionOrError.session.accessToken?.trim();
      if (!token) return json({ error: 'session token missing, login again' }, 401);
      await cacheAccessToken(env, sessionOrError.session);
      const id = env.SEAT_STATUS_DO.idFromName('global');
      const stub = env.SEAT_STATUS_DO.get(id);
      const headers = new Headers(request.headers);
      headers.set('x-seat-access-token', token);
      const wsRequest = new Request('https://internal/ws', {
        method: request.method,
        headers,
      });
      const wsRes = await stub.fetch(wsRequest);
      return withSessionCookie(wsRes, sessionOrError);
    }

    if (url.pathname.startsWith('/api/')) {
      const sessionOrError = await requireAuthSession(request);
      if (sessionOrError instanceof Response) return sessionOrError;
      return handleApi(request, env, sessionOrError);
    }

    return new Response('seatstatus worker', { status: 200 });
  },

  async scheduled(_event: ScheduledEvent, env: Env): Promise<void> {
    const id = env.SEAT_STATUS_DO.idFromName('global');
    const stub = env.SEAT_STATUS_DO.get(id);
    const token = await readCachedAccessToken(env);

    if (token) {
      await pollSeatStatus(env, { reason: 'cron', broadcast: true, accessToken: token });
    }
    await stub.fetch('https://internal/stats').catch(() => undefined);
  },
};

export { SeatStatusDO };

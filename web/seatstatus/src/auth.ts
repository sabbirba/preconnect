import type { Env, SessionPayload } from './types';

const SESSION_COOKIE = 'seatstatus_session';
const OAUTH_STATE_COOKIE = 'seatstatus_oauth_state';
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30;
const REFRESH_EARLY_SECONDS = 60;
const APP_BASE_URL = 'https://seatstatus.preconnect.app';
const OAUTH_CLIENT_ID = 'slm';
const OAUTH_AUTHORIZE_URL = 'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/auth';
const OAUTH_TOKEN_URL = 'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/token';
const OAUTH_REDIRECT_URL = `${APP_BASE_URL}/`;
const OAUTH_CLIENT_SECRET = '';
const SESSION_SECRET = '7918660cec9f7f25858372a83d3853a3e6efacf350dc0a6bc167ffa253ea7c7f';

function toB64Url(bytes: Uint8Array): string {
  const str = btoa(String.fromCharCode(...bytes));
  return str.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function fromB64Url(input: string): Uint8Array {
  const b64 = input.replace(/-/g, '+').replace(/_/g, '/');
  const padded = b64 + '='.repeat((4 - (b64.length % 4 || 4)) % 4);
  const str = atob(padded);
  const out = new Uint8Array(str.length);
  for (let i = 0; i < str.length; i += 1) out[i] = str.charCodeAt(i);
  return out;
}

async function hmacSign(input: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(input));
  return toB64Url(new Uint8Array(sig));
}

async function hmacVerify(input: string, signature: string, secret: string): Promise<boolean> {
  const expected = await hmacSign(input, secret);
  const a = fromB64Url(expected);
  const b = fromB64Url(signature);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

export function parseCookies(req: Request): Record<string, string> {
  const raw = req.headers.get('cookie');
  if (!raw) return {};
  return raw
    .split(';')
    .map((c) => c.trim())
    .filter(Boolean)
    .reduce<Record<string, string>>((acc, pair) => {
      const idx = pair.indexOf('=');
      if (idx <= 0) return acc;
      const k = pair.slice(0, idx);
      const v = pair.slice(idx + 1);
      acc[k] = decodeURIComponent(v);
      return acc;
    }, {});
}

function cookieBase(name: string, value: string, maxAge: number): string {
  return `${name}=${encodeURIComponent(value)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${maxAge}`;
}

function sessionCookie(value: string): string {
  return cookieBase(SESSION_COOKIE, value, SESSION_TTL_SECONDS);
}

export function clearSessionCookie(): string {
  return cookieBase(SESSION_COOKIE, '', 0);
}

function clearOauthStateCookie(): string {
  return cookieBase(OAUTH_STATE_COOKIE, '', 0);
}

function redirectWithCookies(location: string, cookies: string[]): Response {
  const headers = new Headers();
  headers.set('Location', location);
  for (const cookie of cookies) headers.append('Set-Cookie', cookie);
  return new Response(null, { status: 302, headers });
}

async function createSessionToken(payload: SessionPayload, secret: string): Promise<string> {
  const payloadPart = toB64Url(new TextEncoder().encode(JSON.stringify(payload)));
  const sig = await hmacSign(payloadPart, secret);
  return `${payloadPart}.${sig}`;
}

async function readSessionToken(token: string, secret: string): Promise<SessionPayload | null> {
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const [payloadPart, sigPart] = parts;
  if (!payloadPart || !sigPart) return null;

  const valid = await hmacVerify(payloadPart, sigPart, secret);
  if (!valid) return null;

  const payloadRaw = new TextDecoder().decode(fromB64Url(payloadPart));
  return JSON.parse(payloadRaw) as SessionPayload;
}

function randomState(): string {
  const arr = crypto.getRandomValues(new Uint8Array(24));
  return toB64Url(arr);
}

function decodeJwtPayload(token?: string): Record<string, unknown> {
  if (!token) return {};
  const parts = token.split('.');
  if (parts.length < 2) return {};
  try {
    return JSON.parse(new TextDecoder().decode(fromB64Url(parts[1] as string))) as Record<string, unknown>;
  } catch {
    return {};
  }
}

export type TokenBundle = {
  accessToken: string;
  refreshToken: string;
  idToken?: string;
  expiresIn?: number;
};

export async function createSessionFromTokenBundle(
  bundle: TokenBundle,
): Promise<{ session: SessionPayload; setCookie: string }> {
  const accessToken = bundle.accessToken.trim();
  const refreshToken = bundle.refreshToken.trim();
  if (!accessToken || !refreshToken) throw new Error('MISSING_TOKENS');

  const jwtPayload = decodeJwtPayload(bundle.idToken ?? accessToken);
  const now = Math.floor(Date.now() / 1000);
  const exp = now + Math.min(Math.max(bundle.expiresIn ?? 3600, 300), SESSION_TTL_SECONDS);
  const session: SessionPayload = {
    sub: (jwtPayload.sub as string | undefined) ?? 'sso-user',
    iat: now,
    exp,
    accessToken,
    refreshToken,
  };
  const token = await createSessionToken(session, SESSION_SECRET);
  return { session, setCookie: sessionCookie(token) };
}

export async function handleAuthLogin(_req: Request, _env: Env): Promise<Response> {
  const state = randomState();
  const authorizeUrl = new URL(OAUTH_AUTHORIZE_URL);
  authorizeUrl.searchParams.set('response_type', 'code');
  authorizeUrl.searchParams.set('client_id', OAUTH_CLIENT_ID);
  authorizeUrl.searchParams.set('redirect_uri', OAUTH_REDIRECT_URL);
  authorizeUrl.searchParams.set('scope', 'openid profile email offline_access');
  authorizeUrl.searchParams.set('state', state);

  return redirectWithCookies(authorizeUrl.toString(), [cookieBase(OAUTH_STATE_COOKIE, state, 600)]);
}

export async function handleAuthCallback(req: Request, _env: Env): Promise<Response> {
  const url = new URL(req.url);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  if (!code || !state) return new Response('Missing code/state', { status: 400 });

  const cookies = parseCookies(req);
  const expectedState = cookies[OAUTH_STATE_COOKIE];
  if (!expectedState || expectedState !== state) {
    return new Response('Invalid OAuth state', { status: 401 });
  }

  const tokenRes = await fetch(OAUTH_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      client_id: OAUTH_CLIENT_ID,
      redirect_uri: OAUTH_REDIRECT_URL,
      ...(OAUTH_CLIENT_SECRET.trim() ? { client_secret: OAUTH_CLIENT_SECRET.trim() } : {}),
    }),
  });

  if (!tokenRes.ok) {
    const msg = await tokenRes.text();
    return new Response(`Token exchange failed: ${msg}`, { status: 502 });
  }

  const tokenJson = (await tokenRes.json()) as {
    access_token?: string;
    refresh_token?: string;
    id_token?: string;
    expires_in?: number;
  };

  const accessToken = tokenJson.access_token?.trim();
  const refreshToken = tokenJson.refresh_token?.trim();
  if (!accessToken || !refreshToken) {
    return new Response('Token response missing access/refresh token', { status: 502 });
  }

  const jwtPayload = decodeJwtPayload(tokenJson.id_token);
  const sub = (jwtPayload.sub as string | undefined) ?? 'sso-user';

  const now = Math.floor(Date.now() / 1000);
  const exp = now + Math.min(Math.max(tokenJson.expires_in ?? 3600, 300), SESSION_TTL_SECONDS);
  const session = await createSessionToken(
    {
      sub,
      iat: now,
      exp,
      accessToken,
      refreshToken,
    },
    SESSION_SECRET,
  );

  const redirectTo = `${APP_BASE_URL}/`;
  return redirectWithCookies(redirectTo, [sessionCookie(session), clearOauthStateCookie()]);
}

async function refreshSession(
  session: SessionPayload,
): Promise<{ session: SessionPayload; setCookie: string } | null> {
  const refreshToken = session.refreshToken?.trim();
  if (!refreshToken) return null;

  const tokenRes = await fetch(OAUTH_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
      client_id: OAUTH_CLIENT_ID,
      ...(OAUTH_CLIENT_SECRET.trim() ? { client_secret: OAUTH_CLIENT_SECRET.trim() } : {}),
    }),
  });

  if (!tokenRes.ok) return null;

  const tokenJson = (await tokenRes.json()) as {
    access_token?: string;
    refresh_token?: string;
    id_token?: string;
    expires_in?: number;
  };

  const accessToken = tokenJson.access_token?.trim();
  if (!accessToken) return null;

  const jwtPayload = decodeJwtPayload(tokenJson.id_token);
  const now = Math.floor(Date.now() / 1000);
  const exp = now + Math.min(Math.max(tokenJson.expires_in ?? 3600, 300), SESSION_TTL_SECONDS);
  const nextSession: SessionPayload = {
    sub: (jwtPayload.sub as string | undefined) ?? session.sub ?? 'sso-user',
    iat: now,
    exp,
    accessToken,
    refreshToken: tokenJson.refresh_token?.trim() || refreshToken,
  };

  const sessionToken = await createSessionToken(nextSession, SESSION_SECRET);
  return { session: nextSession, setCookie: sessionCookie(sessionToken) };
}

export async function getSessionWithAutoRefresh(
  req: Request,
): Promise<{ session: SessionPayload | null; setCookie?: string }> {
  const cookies = parseCookies(req);
  const raw = cookies[SESSION_COOKIE];
  if (!raw) return { session: null };

  const session = await readSessionToken(raw, SESSION_SECRET);
  if (!session || !session.exp) return { session: null };

  const now = Math.floor(Date.now() / 1000);
  if (session.exp > now + REFRESH_EARLY_SECONDS && session.accessToken?.trim()) {
    return { session };
  }

  const refreshed = await refreshSession(session);
  if (!refreshed) return { session: null };
  return refreshed;
}

export async function requireSessionWithAutoRefresh(
  req: Request,
): Promise<{ session: SessionPayload; setCookie?: string }> {
  const result = await getSessionWithAutoRefresh(req);
  if (!result.session) throw new Error('UNAUTHORIZED');
  return { session: result.session, setCookie: result.setCookie };
}

import type { Env, JsonObject, SeatMap } from './types';

const UPSTREAM_SEAT_MAP_URL =
  'https://connect.bracu.ac.bd/api/adv/v1/advising/sections/seat-status';
const UPSTREAM_SECTION_DETAILS_TEMPLATE =
  'https://connect.bracu.ac.bd/api/adv/v1/advising/sections/{id}/details';
const UPSTREAM_REALM = 'bracu';
const UPSTREAM_TOKEN_ENDPOINT =
  'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/token';
const UPSTREAM_CLIENT_ID = 'slm';

const MAP_MAX_AGE_SECONDS = 2;
const MAP_STALE_SECONDS = 8;
const DETAIL_MAX_AGE_SECONDS = 60;
const DETAIL_STALE_SECONDS = 300;
const CACHE_NAME = 'seatstatus';

let tokenCache: { refresh: string; access: string; expMs: number } | null = null;

function json(status: number, body: unknown, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...headers,
    },
  });
}

function parseSectionId(path: string): number | null {
  const match = path.match(/^\/api\/sections\/(\d+)\/details$/);
  if (!match) return null;
  const id = Number.parseInt(match[1], 10);
  return Number.isFinite(id) ? id : null;
}

function isJsonObject(value: unknown): value is JsonObject {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function parseBearer(request: Request): string {
  const auth = (request.headers.get('authorization') ?? '').trim();
  if (!auth.toLowerCase().startsWith('bearer ')) return '';
  return auth.substring(7).trim();
}

function parseJwtExpMs(token: string): number {
  try {
    const parts = token.split('.');
    if (parts.length < 2) return 0;
    const raw = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = raw + '='.repeat((4 - (raw.length % 4)) % 4);
    const payload = JSON.parse(atob(padded)) as Record<string, unknown>;
    const exp = Number.parseInt(`${payload.exp ?? ''}`, 10);
    if (!Number.isFinite(exp) || exp <= 0) return 0;
    return exp * 1000;
  } catch {
    return 0;
  }
}

async function refreshAccessToken(refreshToken: string): Promise<string> {
  try {
    const response = await fetch(UPSTREAM_TOKEN_ENDPOINT, {
      method: 'POST',
      headers: {
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: refreshToken,
        client_id: UPSTREAM_CLIENT_ID,
      }),
    });
    if (!response.ok) return '';

    const payload = (await response.json()) as JsonObject;
    const access = `${payload.access_token ?? ''}`.trim();
    if (access.length === 0) return '';

    const expiresIn = Number.parseInt(`${payload.expires_in ?? ''}`, 10);
    const expFromJwt = parseJwtExpMs(access);
    const expFromApi = Number.isFinite(expiresIn)
      ? Date.now() + Math.max(30, expiresIn - 60) * 1000
      : 0;
    const expMs = Math.max(expFromJwt, expFromApi);

    tokenCache = {
      refresh: refreshToken,
      access,
      expMs,
    };

    return access;
  } catch {
    return '';
  }
}

async function resolveBearer(request: Request, env: Env): Promise<string> {
  const inlineBearer = parseBearer(request);
  if (inlineBearer.length > 0) return inlineBearer;

  const refresh = (env.REFRESH_TOKEN ?? '').trim();
  if (refresh.length === 0) return '';

  if (tokenCache && tokenCache.refresh === refresh && tokenCache.expMs > Date.now() + 60000) {
    return tokenCache.access;
  }

  return refreshAccessToken(refresh);
}

function upstreamHeaders(bearer: string, ifNoneMatch = ''): Headers {
  const headers = new Headers({
    'x-realm': UPSTREAM_REALM,
    accept: 'application/json',
  });
  if (bearer.length > 0) {
    headers.set('authorization', `Bearer ${bearer}`);
  }
  const tag = ifNoneMatch.trim();
  if (tag.length > 0) {
    headers.set('if-none-match', tag);
  }
  return headers;
}

function cacheRequest(key: string): Request {
  return new Request(`https://seatstatus-cache.local${key}`);
}

function cacheAgeSeconds(cached: Response): number {
  const storedAt = Number.parseInt(cached.headers.get('x-seatstatus-stored-at') ?? '0', 10);
  if (!Number.isFinite(storedAt) || storedAt <= 0) return Number.MAX_SAFE_INTEGER;
  return Math.floor((Date.now() - storedAt) / 1000);
}

async function parseObjectJson(response: Response): Promise<JsonObject | null> {
  const parsed = (await response.json()) as unknown;
  if (!isJsonObject(parsed)) return null;
  return parsed;
}

function cloneHeaders(base: Headers): Headers {
  const headers = new Headers(base);
  headers.set('content-type', 'application/json; charset=utf-8');
  return headers;
}

async function putCache(
  key: string,
  payload: unknown,
  etag: string,
  maxAgeSeconds: number,
  staleSeconds: number,
): Promise<Response> {
  const cache = await caches.open(CACHE_NAME);
  const headers = new Headers({
    'content-type': 'application/json; charset=utf-8',
    'cache-control': `public, max-age=${maxAgeSeconds}, stale-while-revalidate=${staleSeconds}`,
    'x-seatstatus-stored-at': `${Date.now()}`,
    'x-seatstatus-cache': 'miss',
  });
  if (etag.trim().length > 0) headers.set('etag', etag.trim());

  const response = new Response(JSON.stringify(payload), { status: 200, headers });
  await cache.put(cacheRequest(key), response.clone());
  return response;
}

async function serveCached(
  key: string,
  incomingEtag: string,
  cacheState: 'hit' | 'stale' | 'stale-if-error',
): Promise<Response | null> {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(cacheRequest(key));
  if (!cached) return null;

  const responseHeaders = cloneHeaders(cached.headers);
  responseHeaders.set('x-seatstatus-cache', cacheState);
  const currentEtag = (responseHeaders.get('etag') ?? '').trim();
  if (currentEtag.length > 0 && incomingEtag.trim() === currentEtag) {
    return new Response(null, { status: 304, headers: responseHeaders });
  }
  return new Response(await cached.text(), {
    status: cached.status,
    headers: responseHeaders,
  });
}

async function fetchSeatMap(request: Request, env: Env): Promise<Response> {
  const key = '/cache/api';
  const incomingEtag = (request.headers.get('if-none-match') ?? '').trim();
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(cacheRequest(key));

  if (cached && cacheAgeSeconds(cached) <= MAP_MAX_AGE_SECONDS) {
    const fast = await serveCached(key, incomingEtag, 'hit');
    if (fast) return fast;
  }

  const bearer = await resolveBearer(request, env);
  if (bearer.length === 0) {
    const stale = await serveCached(key, incomingEtag, 'stale-if-error');
    if (stale) return stale;
    return json(503, { error: 'missing_upstream_auth' }, { 'cache-control': 'no-store' });
  }

  const upstreamEtag = (cached?.headers.get('etag') ?? '').trim();
  const upstream = await fetch(UPSTREAM_SEAT_MAP_URL, {
    headers: upstreamHeaders(bearer, upstreamEtag),
  });

  if (upstream.status === 304) {
    const cachedBody = await serveCached(key, incomingEtag, 'stale');
    if (cachedBody) return cachedBody;
  }

  if (!upstream.ok) {
    const stale = await serveCached(key, incomingEtag, 'stale-if-error');
    if (stale) return stale;
    return json(502, { error: 'upstream_failed', status: upstream.status }, { 'cache-control': 'no-store' });
  }

  const data = await parseObjectJson(upstream);
  if (data == null) {
    return json(502, { error: 'invalid_upstream_payload' }, { 'cache-control': 'no-store' });
  }

  const nextMap: SeatMap = {};
  for (const [k, v] of Object.entries(data)) {
    const parsed = Number.parseInt(String(v), 10);
    if (Number.isFinite(parsed)) {
      nextMap[k] = parsed;
    }
  }

  return putCache(
    key,
    nextMap,
    upstream.headers.get('etag') ?? '',
    MAP_MAX_AGE_SECONDS,
    MAP_STALE_SECONDS,
  );
}

async function fetchSectionDetails(
  request: Request,
  sectionId: number,
  env: Env,
): Promise<Response> {
  const key = `/cache/detail/${sectionId}`;
  const incomingEtag = (request.headers.get('if-none-match') ?? '').trim();
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(cacheRequest(key));

  if (cached && cacheAgeSeconds(cached) <= DETAIL_MAX_AGE_SECONDS) {
    const fast = await serveCached(key, incomingEtag, 'hit');
    if (fast) return fast;
  }

  const bearer = await resolveBearer(request, env);
  if (bearer.length === 0) {
    const stale = await serveCached(key, incomingEtag, 'stale-if-error');
    if (stale) return stale;
    return json(503, { error: 'missing_upstream_auth' }, { 'cache-control': 'no-store' });
  }

  const upstreamEtag = (cached?.headers.get('etag') ?? '').trim();
  const url = UPSTREAM_SECTION_DETAILS_TEMPLATE.replace('{id}', String(sectionId));
  const upstream = await fetch(url, {
    headers: upstreamHeaders(bearer, upstreamEtag),
  });

  if (upstream.status === 304) {
    const cachedBody = await serveCached(key, incomingEtag, 'stale');
    if (cachedBody) return cachedBody;
  }

  if (!upstream.ok) {
    const stale = await serveCached(key, incomingEtag, 'stale-if-error');
    if (stale) return stale;
    return json(502, { error: 'upstream_failed', status: upstream.status }, { 'cache-control': 'no-store' });
  }

  const payload = await parseObjectJson(upstream);
  if (payload == null) {
    return json(502, { error: 'invalid_upstream_payload' }, { 'cache-control': 'no-store' });
  }

  return putCache(
    key,
    payload,
    upstream.headers.get('etag') ?? '',
    DETAIL_MAX_AGE_SECONDS,
    DETAIL_STALE_SECONDS,
  );
}

async function healthSummary(request: Request, env: Env): Promise<Response> {
  const cache = await caches.open(CACHE_NAME);
  const mapCached = await cache.match(cacheRequest('/cache/api'));
  return json(200, {
    status: 'ok',
    cache: {
      map: mapCached
        ? {
            ageSeconds: cacheAgeSeconds(mapCached),
            etag: mapCached.headers.get('etag') ?? null,
          }
        : null,
    },
    auth: {
      hasAuthorizationHeader: parseBearer(request).length > 0,
      hasConfiguredRefresh: (env.REFRESH_TOKEN ?? '').trim().length > 0,
    },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      const path = url.pathname;

      if (path === '/') return healthSummary(request, env);
      if (path === '/api') return fetchSeatMap(request, env);

      if (path.startsWith('/api/sections/') && path.endsWith('/details')) {
        const sectionId = parseSectionId(path);
        if (sectionId == null) return json(400, { error: 'invalid_section_id' });
        return fetchSectionDetails(request, sectionId, env);
      }

      if (path === '/internal/sync/map') {
        await fetchSeatMap(request, env);
        return json(202, { status: 'accepted' });
      }

      if (path === '/internal/sync/details') {
        const fromQuery = Number.parseInt(url.searchParams.get('sectionId') ?? '', 10);
        if (!Number.isFinite(fromQuery)) {
          return json(400, { error: 'sectionId_query_required' });
        }
        await fetchSectionDetails(request, fromQuery, env);
        return json(202, { status: 'accepted' });
      }

      if (path === '/ws') {
        return json(410, { error: 'websocket_removed' }, { 'cache-control': 'no-store' });
      }

      return json(404, { error: 'not_found' });
    } catch (error) {
      return json(
        500,
        {
          error: 'worker_exception',
          message: error instanceof Error ? error.message : 'unknown',
        },
        { 'cache-control': 'no-store' },
      );
    }
  },

  async scheduled(_event: unknown, env: Env): Promise<void> {
    const request = new Request('https://seatstatus.preconnect.app/internal/sync/map', {
      method: 'GET',
    });
    await fetchSeatMap(request, env);
  },
};

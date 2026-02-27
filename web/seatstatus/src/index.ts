import type { Env, JsonObject, SeatMap } from './types';

const UPSTREAM_SEAT_MAP_URL =
  'https://connect.bracu.ac.bd/api/adv/v1/advising/sections/seat-status';
const UPSTREAM_SECTION_DETAILS_TEMPLATE =
  'https://connect.bracu.ac.bd/api/adv/v1/advising/sections/{id}/details';
const UPSTREAM_TOKEN_ENDPOINT =
  'https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/token';
const UPSTREAM_REALM = 'bracu';
const UPSTREAM_CLIENT_ID = 'slm';

const CACHE_MAP_KEY = '/map.json';
const CACHE_DETAIL_PREFIX = '/detail/';
const CACHE_DETAILS_ALL_KEY = '/details-all.json';
const CACHE_CURSOR_KEY = '/details-sync-cursor.json';

interface CachedRecord {
  etag: string;
  storedAt: number;
  payload: JsonObject;
}

let tokenCache: { refresh: string; access: string; expMs: number } | null = null;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function json(status: number, body: unknown, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...headers,
    },
  });
}

function cacheRequest(path: string): Request {
  return new Request(`https://seatstatus-cache.local${path}`);
}

function isJsonObject(value: unknown): value is JsonObject {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function parseJwtExpMs(token: string): number {
  try {
    const part = token.split('.')[1];
    if (!part) return 0;
    const raw = part.replace(/-/g, '+').replace(/_/g, '/');
    const padded = raw + '='.repeat((4 - (raw.length % 4)) % 4);
    const payload = JSON.parse(atob(padded)) as Record<string, unknown>;
    const exp = Number.parseInt(`${payload.exp ?? ''}`, 10);
    return Number.isFinite(exp) && exp > 0 ? exp * 1000 : 0;
  } catch {
    return 0;
  }
}

function upstreamHeaders(bearer: string, ifNoneMatch = ''): Headers {
  const headers = new Headers({
    'x-realm': UPSTREAM_REALM,
    accept: 'application/json',
  });
  if (bearer) headers.set('authorization', `Bearer ${bearer}`);
  if (ifNoneMatch.trim()) headers.set('if-none-match', ifNoneMatch.trim());
  return headers;
}

function buildMapDiff(previous: SeatMap, next: SeatMap): SeatMap {
  const changed: SeatMap = {};
  for (const [key, value] of Object.entries(next)) {
    if (previous[key] !== value) changed[key] = value;
  }
  return changed;
}

async function readCacheRecord(path: string): Promise<CachedRecord | null> {
  const cache = await caches.open('seatstatus');
  const hit = await cache.match(cacheRequest(path));
  if (!hit) return null;
  try {
    const raw = (await hit.json()) as unknown;
    if (!isJsonObject(raw)) return null;
    if (!isJsonObject(raw.payload)) return null;
    const etag = `${raw.etag ?? ''}`.trim();
    const storedAt = Number.parseInt(`${raw.storedAt ?? ''}`, 10);
    if (!Number.isFinite(storedAt) || storedAt <= 0) return null;
    return { etag, storedAt, payload: raw.payload };
  } catch {
    return null;
  }
}

async function writeCacheRecord(
  path: string,
  payload: JsonObject,
  etag = '',
  storedAt = Date.now(),
): Promise<CachedRecord> {
  const record: CachedRecord = { etag: etag.trim(), storedAt, payload };
  const cache = await caches.open('seatstatus');
  await cache.put(
    cacheRequest(path),
    new Response(JSON.stringify(record), {
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'public, max-age=3600',
      },
    }),
  );
  return record;
}

async function refreshAccessToken(refreshToken: string): Promise<string> {
  try {
    const response = await fetch(UPSTREAM_TOKEN_ENDPOINT, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: refreshToken,
        client_id: UPSTREAM_CLIENT_ID,
      }),
    });
    if (!response.ok) return '';

    const payload = (await response.json()) as JsonObject;
    const access = `${payload.access_token ?? ''}`.trim();
    if (!access) return '';

    const expiresIn = Number.parseInt(`${payload.expires_in ?? ''}`, 10);
    const fromJwt = parseJwtExpMs(access);
    const fromApi = Number.isFinite(expiresIn)
      ? Date.now() + Math.max(30, expiresIn - 60) * 1000
      : 0;

    tokenCache = { refresh: refreshToken, access, expMs: Math.max(fromJwt, fromApi) };
    return access;
  } catch {
    return '';
  }
}

async function resolveBearer(env: Env): Promise<string> {
  const access = (env.WORKER_ACCESS_TOKEN ?? '').trim();
  if (access) {
    const exp = parseJwtExpMs(access);
    if (exp <= 0 || exp > Date.now() + 60000) return access;
  }

  const refresh = (env.WORKER_REFRESH_TOKEN ?? '').trim();
  if (!refresh) return '';

  if (tokenCache && tokenCache.refresh === refresh && tokenCache.expMs > Date.now() + 60000) {
    return tokenCache.access;
  }

  return refreshAccessToken(refresh);
}

async function mergeDetailsPatch(patch: Record<string, JsonObject>): Promise<void> {
  if (Object.keys(patch).length === 0) return;
  const existing = await readCacheRecord(CACHE_DETAILS_ALL_KEY);
  const next: JsonObject = existing?.payload ?? {};
  for (const [key, value] of Object.entries(patch)) {
    next[key] = value;
  }
  await writeCacheRecord(CACHE_DETAILS_ALL_KEY, next, existing?.etag ?? '');
}

async function fetchSeatMap(env: Env): Promise<CachedRecord | null> {
  const existing = await readCacheRecord(CACHE_MAP_KEY);
  const bearer = await resolveBearer(env);
  if (!bearer) return existing;

  const upstream = await fetch(UPSTREAM_SEAT_MAP_URL, {
    headers: upstreamHeaders(bearer, existing?.etag ?? ''),
  });

  if (upstream.status === 304 && existing) return existing;
  if (!upstream.ok) return existing;

  try {
    const parsed = (await upstream.json()) as unknown;
    if (!isJsonObject(parsed)) return existing;

    return writeCacheRecord(
      CACHE_MAP_KEY,
      parsed,
      (upstream.headers.get('etag') ?? '').trim(),
    );
  } catch {
    return existing;
  }
}

async function fetchSectionDetails(sectionId: number, env: Env): Promise<CachedRecord | null> {
  const path = `${CACHE_DETAIL_PREFIX}${sectionId}.json`;
  const existing = await readCacheRecord(path);
  const bearer = await resolveBearer(env);
  if (!bearer) return existing;

  const upstream = await fetch(UPSTREAM_SECTION_DETAILS_TEMPLATE.replace('{id}', `${sectionId}`), {
    headers: upstreamHeaders(bearer, existing?.etag ?? ''),
  });

  if (upstream.status === 304 && existing) return existing;
  if (!upstream.ok) return existing;

  try {
    const parsed = (await upstream.json()) as unknown;
    if (!isJsonObject(parsed)) return existing;
    const saved = await writeCacheRecord(path, parsed, (upstream.headers.get('etag') ?? '').trim());
    return saved;
  } catch {
    return existing;
  }
}

async function syncDetailsForIds(
  env: Env,
  sectionIds: number[],
  concurrency = 24,
): Promise<Record<string, JsonObject>> {
  const patch: Record<string, JsonObject> = {};
  let cursor = 0;
  while (cursor < sectionIds.length) {
    const batch = sectionIds.slice(cursor, cursor + concurrency);
    const fetched = await Promise.all(batch.map((id) => fetchSectionDetails(id, env)));
    for (let i = 0; i < batch.length; i += 1) {
      const record = fetched[i];
      if (record?.payload && isJsonObject(record.payload)) {
        patch[String(batch[i])] = record.payload;
      }
    }
    cursor += concurrency;
  }
  await mergeDetailsPatch(patch);
  return patch;
}

function pickChunk(ids: number[], cursor: number, chunkSize: number): { chunk: number[]; next: number } {
  if (ids.length === 0) return { chunk: [], next: 0 };
  let index = cursor % ids.length;
  if (index < 0) index = 0;
  const chunk: number[] = [];
  for (let i = 0; i < Math.min(chunkSize, ids.length); i += 1) {
    chunk.push(ids[index]);
    index = (index + 1) % ids.length;
  }
  return { chunk, next: index };
}

async function handleSeatMapSocket(socket: any, env: Env): Promise<void> {
  socket.accept();

  let open = true;
  let previousMap: SeatMap | null = null;
  let detailsCursor = 0;

  socket.addEventListener('close', () => {
    open = false;
  });
  socket.addEventListener('error', () => {
    open = false;
  });

  while (open) {
    try {
      const mapRecord = (await fetchSeatMap(env)) ?? (await readCacheRecord(CACHE_MAP_KEY));
      if (!mapRecord) {
        await sleep(5000);
        continue;
      }

      const currentMap = mapRecord.payload;
      if (previousMap == null) {
        const detailsAll = (await readCacheRecord(CACHE_DETAILS_ALL_KEY))?.payload ?? {};
        socket.send(
          JSON.stringify({
            type: 'status',
            state: 'connected',
            mode: 'websocket',
            frame: 'seat_map_full',
            count: Object.keys(currentMap).length,
          }),
        );
        socket.send(JSON.stringify(currentMap));
        if (Object.keys(detailsAll).length > 0) {
          socket.send(
            JSON.stringify({
              type: 'status',
              state: 'connected',
              mode: 'websocket',
              frame: 'details_full',
              count: Object.keys(detailsAll).length,
            }),
          );
          socket.send(JSON.stringify(detailsAll));
        }
        previousMap = currentMap;
      } else {
        const mapDiff = buildMapDiff(previousMap, currentMap);
        const changedIds = Object.keys(mapDiff)
          .map((id) => Number.parseInt(id, 10))
          .filter((v) => Number.isFinite(v));
        if (changedIds.length > 0) {
          const detailsPatch = await syncDetailsForIds(env, changedIds, 24);
          socket.send(
            JSON.stringify({
              type: 'status',
              state: 'connected',
              mode: 'websocket',
              frame: 'seat_map_diff',
              count: Object.keys(mapDiff).length,
            }),
          );
          socket.send(JSON.stringify(mapDiff));
          if (Object.keys(detailsPatch).length > 0) {
            socket.send(
              JSON.stringify({
                type: 'status',
                state: 'connected',
                mode: 'websocket',
                frame: 'details_patch',
                count: Object.keys(detailsPatch).length,
              }),
            );
            socket.send(JSON.stringify(detailsPatch));
          }
          previousMap = currentMap;
        }
      }

      const detailsAll = (await readCacheRecord(CACHE_DETAILS_ALL_KEY))?.payload ?? {};
      const missingIds = Object.keys(currentMap)
        .filter((id) => detailsAll[id] == null)
        .map((id) => Number.parseInt(id, 10))
        .filter((v) => Number.isFinite(v));
      if (missingIds.length > 0) {
        const picked = pickChunk(missingIds, detailsCursor, 8);
        detailsCursor = picked.next;
        const detailsPatch = await syncDetailsForIds(env, picked.chunk, 4);
        if (Object.keys(detailsPatch).length > 0) {
          socket.send(
            JSON.stringify({
              type: 'status',
              state: 'connected',
              mode: 'websocket',
              frame: 'details_patch',
              count: Object.keys(detailsPatch).length,
            }),
          );
          socket.send(JSON.stringify(detailsPatch));
        }
      }

      await sleep(5000);
    } catch (error) {
      try {
        socket.send(
          JSON.stringify({
            type: 'status',
            state: 'error',
            mode: 'websocket',
            message: error instanceof Error ? error.message : 'unknown_error',
          }),
        );
      } catch {}
      open = false;
    }
  }
}

async function syncDetailsChunk(env: Env, limit = 40): Promise<void> {
  const mapRecord = (await fetchSeatMap(env)) ?? (await readCacheRecord(CACHE_MAP_KEY));
  if (!mapRecord) return;

  const ids = Object.keys(mapRecord.payload)
    .map((v) => Number.parseInt(v, 10))
    .filter((v) => Number.isFinite(v))
    .sort((a, b) => a - b);
  if (ids.length === 0) return;

  const cursorRecord = await readCacheRecord(CACHE_CURSOR_KEY);
  const start = Number.parseInt(`${cursorRecord?.payload.index ?? 0}`, 10);
  let index = Number.isFinite(start) && start >= 0 ? start % ids.length : 0;

  const count = Math.max(1, Math.min(limit, ids.length));
  const chunk: number[] = [];
  for (let i = 0; i < count; i += 1) {
    chunk.push(ids[index]);
    index = (index + 1) % ids.length;
  }

  await syncDetailsForIds(env, chunk, 20);
  await writeCacheRecord(CACHE_CURSOR_KEY, { index }, '');
}

export default {
  async fetch(request: Request, env: Env, ctx: any): Promise<Response> {
    try {
      const url = new URL(request.url);
      const path = url.pathname;

      if (path === '/') {
        if (request.headers.get('upgrade')?.toLowerCase() !== 'websocket') {
          return json(426, { error: 'websocket_upgrade_required' });
        }
        const pair = new (globalThis as any).WebSocketPair();
        const client = pair[0];
        const server = pair[1];
        ctx.waitUntil(handleSeatMapSocket(server, env));
        return new Response(null, { status: 101, webSocket: client } as any);
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
    await fetchSeatMap(env);
    await syncDetailsChunk(env, 40);
  },
};

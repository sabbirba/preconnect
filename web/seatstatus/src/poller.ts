import type { Env, PollResult, SeatMap } from './types';

const KEY_MAP = 'seat:map';
const KEY_MAP_ETAG = 'seat:map:etag';
const KEY_LAST_FETCH = 'seat:last_fetch_ms';
const KEY_LAST_CHANGE = 'seat:last_change_ms';
const KEY_LAST_DIFF = 'seat:last_diff';
const DETAIL_PREFIX = 'seat:detail:';
const DETAIL_ETAG_PREFIX = 'seat:detail:etag:';
const CONNECT_ADVISING_SECTIONS_BASE = 'https://connect.bracu.ac.bd/api/adv/v1/advising/sections';
const SEAT_STATUS_MAP_URL = `${CONNECT_ADVISING_SECTIONS_BASE}/seat-status`;

type SeatChange = {
  previous: number | null;
  current: number | null;
  delta: number | null;
};

type SeatChanges = Record<string, SeatChange>;

async function kvGetJson<T>(kv: KVNamespace, key: string): Promise<T | null> {
  const raw = await kv.get(key);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

async function kvPutJson(kv: KVNamespace, key: string, value: unknown): Promise<void> {
  await kv.put(key, JSON.stringify(value));
}

function asNumber(input: string | undefined, fallback: number): number {
  if (!input) return fallback;
  const n = Number(input);
  return Number.isFinite(n) ? n : fallback;
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

async function fetchMap(
  env: Env,
  accessToken: string,
): Promise<{ map: SeatMap; notModified: boolean; mapChanges: SeatChanges }> {
  const oldMap = (await kvGetJson<SeatMap>(env.SEAT_STATUS, KEY_MAP)) ?? {};
  const etag = await env.SEAT_STATUS.get(KEY_MAP_ETAG);

  const headers = new Headers();
  if (etag) headers.set('If-None-Match', etag);
  headers.set('Accept', 'application/json');
  headers.set('Authorization', `Bearer ${accessToken}`);

  const res = await fetch(SEAT_STATUS_MAP_URL, { headers });

  if (res.status === 304) {
    return { map: oldMap, notModified: true, mapChanges: {} };
  }

  if (!res.ok) {
    throw new Error(`Seat map fetch failed: ${res.status}`);
  }

  const payload = (await res.json()) as SeatMap;
  const mode = (env.SEAT_MAP_MODE || 'snapshot').toLowerCase();

  let nextMap: SeatMap;
  let changedIds: string[];

  if (mode === 'delta') {
    nextMap = { ...oldMap, ...payload };
    changedIds = Object.keys(payload);
  } else {
    nextMap = payload;
    const keys = new Set([...Object.keys(oldMap), ...Object.keys(nextMap)]);
    changedIds = [];
    for (const key of keys) {
      if (oldMap[key] !== nextMap[key]) changedIds.push(key);
    }
  }

  const mapChanges: SeatChanges = {};
  for (const sectionId of changedIds) {
    const previous = oldMap[sectionId] ?? null;
    const current = nextMap[sectionId] ?? null;
    const delta =
      typeof previous === 'number' && typeof current === 'number' ? current - previous : null;
    mapChanges[sectionId] = { previous, current, delta };
  }

  const nextEtag = res.headers.get('ETag');
  await kvPutJson(env.SEAT_STATUS, KEY_MAP, nextMap);
  if (nextEtag) await env.SEAT_STATUS.put(KEY_MAP_ETAG, nextEtag);

  return { map: nextMap, notModified: false, mapChanges };
}

async function fetchDetailIfChanged(env: Env, sectionId: string, accessToken: string): Promise<boolean> {
  const etagKey = `${DETAIL_ETAG_PREFIX}${sectionId}`;
  const dataKey = `${DETAIL_PREFIX}${sectionId}`;

  const etag = await env.SEAT_STATUS.get(etagKey);
  const headers = new Headers({ Accept: 'application/json' });
  if (etag) headers.set('If-None-Match', etag);
  headers.set('Authorization', `Bearer ${accessToken}`);

  const res = await fetch(`${CONNECT_ADVISING_SECTIONS_BASE}/${sectionId}/details`, { headers });

  if (res.status === 304) return false;
  if (!res.ok) return false;

  const bodyText = await res.text();
  const oldText = await env.SEAT_STATUS.get(dataKey);
  if (oldText === bodyText) return false;

  await env.SEAT_STATUS.put(dataKey, bodyText);
  const nextEtag = res.headers.get('ETag');
  if (nextEtag) await env.SEAT_STATUS.put(etagKey, nextEtag);
  return true;
}

export async function pollSeatStatus(
  env: Env,
  opts?: { reason?: string; broadcast?: boolean; accessToken?: string },
): Promise<PollResult> {
  const accessToken = opts?.accessToken?.trim();
  if (!accessToken) {
    throw new Error('Missing access token for seat status polling');
  }
  const fetchedAt = Date.now();
  const mapResult = await fetchMap(env, accessToken);
  const changedIds = Object.keys(mapResult.mapChanges);

  const maxDetailIds = asNumber(env.DETAIL_FETCH_LIMIT, 250);
  const concurrency = Math.max(1, asNumber(env.DETAIL_FETCH_CONCURRENCY, 10));
  const candidateIds = changedIds.slice(0, maxDetailIds);

  let detailChangedCount = 0;
  for (const part of chunk(candidateIds, concurrency)) {
    const updates = await Promise.all(part.map((id) => fetchDetailIfChanged(env, id, accessToken)));
    detailChangedCount += updates.filter(Boolean).length;
  }

  const changedCount = changedIds.length;

  await env.SEAT_STATUS.put(KEY_LAST_FETCH, String(fetchedAt));
  if (changedCount > 0 || detailChangedCount > 0) {
    await env.SEAT_STATUS.put(KEY_LAST_CHANGE, String(fetchedAt));
    await kvPutJson(env.SEAT_STATUS, KEY_LAST_DIFF, mapResult.mapChanges);
  }

  if ((opts?.broadcast ?? true) && (changedCount > 0 || detailChangedCount > 0)) {
    const id = env.SEAT_STATUS_DO.idFromName('global');
    const stub = env.SEAT_STATUS_DO.get(id);
    await stub.fetch('https://internal/broadcast', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        type: 'seat_status',
        ts: fetchedAt,
        seatStatus: mapResult.map,
        changedSections: mapResult.mapChanges,
      }),
    });
  }

  return {
    changedIds,
    changedCount,
    mapCount: Object.keys(mapResult.map).length,
    fetchedAt,
    mapChanged: changedCount > 0,
    detailChangedCount,
    notModified: mapResult.notModified,
  };
}

export async function getSnapshot(env: Env): Promise<{
  map: SeatMap;
  lastFetchMs: number;
  lastChangeMs: number;
}> {
  const map = (await kvGetJson<SeatMap>(env.SEAT_STATUS, KEY_MAP)) ?? {};
  const lastFetchMs = Number((await env.SEAT_STATUS.get(KEY_LAST_FETCH)) ?? 0);
  const lastChangeMs = Number((await env.SEAT_STATUS.get(KEY_LAST_CHANGE)) ?? 0);
  return { map, lastFetchMs, lastChangeMs };
}

export async function getDetail(env: Env, sectionId: string): Promise<unknown | null> {
  return kvGetJson<unknown>(env.SEAT_STATUS, `${DETAIL_PREFIX}${sectionId}`);
}

export async function getLastDiff(env: Env): Promise<unknown | null> {
  return kvGetJson(env.SEAT_STATUS, KEY_LAST_DIFF);
}

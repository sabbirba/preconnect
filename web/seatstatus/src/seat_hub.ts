import type { Env, SeatMap, SeatMapEvent } from './types';
import { DurableObject } from 'cloudflare:workers';

const MAP_KEY = 'seat:map';
const MAP_ETAG_KEY = 'seat:map:etag';
const MAP_VERSION_KEY = 'seat:map:version';
const MAP_UPDATED_AT_KEY = 'seat:map:updated_at';
const DETAILS_IDS_KEY = 'seat:details:ids';
const LAST_MAP_SYNC_AT_KEY = 'seat:last_map_sync_at';
const LAST_DETAILS_SYNC_AT_KEY = 'seat:last_details_sync_at';
const RUNTIME_BEARER_TOKEN_KEY = 'seat:runtime_bearer_token';

function parseIntEnv(value: string | undefined, fallback: number): number {
  const parsed = Number.parseInt((value ?? '').trim(), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function deepEqualMap(a: SeatMap, b: SeatMap): boolean {
  const aKeys = Object.keys(a);
  const bKeys = Object.keys(b);
  if (aKeys.length !== bKeys.length) return false;
  for (const key of aKeys) {
    if (a[key] !== b[key]) return false;
  }
  return true;
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

export class SeatHub extends DurableObject {
  private readonly env: Env;
  private sockets: Set<WebSocket> = new Set();
  private mapSyncInFlight = false;
  private detailsSyncInFlight = false;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.env = env;
    this.sockets = new Set(ctx.getWebSockets());
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    await this.captureRuntimeToken(request);

    if (path === '/') {
      const mapUpdatedAt = await this.ctx.storage.get<string>(MAP_UPDATED_AT_KEY);
      const detailsCount = await this.detailsCount();
      return json(200, {
        status: 'ok',
        mapUpdatedAt: mapUpdatedAt ?? null,
        detailsCount,
      });
    }

    if (path === '/ws/connect') {
      if (request.headers.get('upgrade')?.toLowerCase() !== 'websocket') {
        return json(426, { error: 'websocket_upgrade_required' });
      }
      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];
      this.ctx.acceptWebSocket(server);
      this.sockets.add(server);
      await this.ensureFresh();
      await this.pushCurrentMap(server);
      return new Response(null, { status: 101, webSocket: client });
    }

    if (path === '/api') {
      await this.ensureMapFresh();
      const map = (await this.ctx.storage.get<SeatMap>(MAP_KEY)) ?? {};
      const version = (await this.ctx.storage.get<number>(MAP_VERSION_KEY)) ?? 0;
      const etag = `W/\"map-${version}\"`;
      const incomingEtag = (request.headers.get('if-none-match') ?? '').trim();
      if (incomingEtag === etag) {
        return new Response(null, {
          status: 304,
          headers: {
            ETag: etag,
            'Cache-Control': 'public, max-age=2, stale-while-revalidate=8',
          },
        });
      }
      return json(200, map, {
        ETag: etag,
        'Cache-Control': 'public, max-age=2, stale-while-revalidate=8',
      });
    }

    if (path.startsWith('/api/sections/') && path.endsWith('/details')) {
      const sectionId = this.parseSectionId(path);
      if (sectionId == null) return json(400, { error: 'invalid_section_id' });
      await this.ensureDetail(sectionId);
      const detail = await this.ctx.storage.get<Record<string, unknown>>(this.detailsKey(sectionId));
      if (!detail) return json(404, { error: 'section_not_ready' });

      const version = (await this.ctx.storage.get<number>(this.detailsVersionKey(sectionId))) ?? 0;
      const etag = `W/\"detail-${sectionId}-${version}\"`;
      const incomingEtag = (request.headers.get('if-none-match') ?? '').trim();
      if (incomingEtag === etag) {
        return new Response(null, {
          status: 304,
          headers: {
            ETag: etag,
            'Cache-Control': 'public, max-age=60, stale-while-revalidate=300',
          },
        });
      }

      return json(200, detail, {
        ETag: etag,
        'Cache-Control': 'public, max-age=60, stale-while-revalidate=300',
      });
    }

    if (path === '/internal/sync/map') {
      await this.syncMap();
      return json(202, { status: 'accepted' });
    }

    if (path === '/internal/sync/details') {
      await this.syncDetails();
      return json(202, { status: 'accepted' });
    }

    if (path === '/internal/cron') {
      await this.ensureFresh();
      return json(202, { status: 'accepted' });
    }

    return json(404, { error: 'not_found' });
  }

  async webSocketClose(ws: WebSocket): Promise<void> {
    this.sockets.delete(ws);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    this.sockets.delete(ws);
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== 'string') return;
    if (message === 'ping') {
      try {
        ws.send('pong');
      } catch (_) {}
      return;
    }
    if (message === 'refresh') {
      await this.ensureFresh();
      await this.pushCurrentMap(ws);
    }
  }

  private async ensureFresh(): Promise<void> {
    await this.ensureMapFresh();
    await this.ensureDetailsFresh();
  }

  private async ensureMapFresh(): Promise<void> {
    const now = Date.now();
    const last = (await this.ctx.storage.get<number>(LAST_MAP_SYNC_AT_KEY)) ?? 0;
    const intervalMs = parseIntEnv(this.env.MAP_SYNC_INTERVAL_MS, 5000);
    if (now - last < intervalMs) return;
    await this.syncMap();
  }

  private async ensureDetailsFresh(): Promise<void> {
    const now = Date.now();
    const last = (await this.ctx.storage.get<number>(LAST_DETAILS_SYNC_AT_KEY)) ?? 0;
    const intervalMs = parseIntEnv(this.env.DETAILS_SYNC_INTERVAL_MS, 3600000);
    if (now - last < intervalMs) return;
    await this.syncDetails();
  }

  private async syncMap(): Promise<void> {
    if (this.mapSyncInFlight) return;
    this.mapSyncInFlight = true;
    try {
      const currentEtag = (await this.ctx.storage.get<string>(MAP_ETAG_KEY)) ?? '';
      const response = await fetch(this.env.UPSTREAM_SEAT_MAP_URL, {
        headers: await this.upstreamHeaders(currentEtag),
      });

      await this.ctx.storage.put(LAST_MAP_SYNC_AT_KEY, Date.now());

      if (response.status === 304) {
        return;
      }
      if (!response.ok) {
        return;
      }

      const data = await response.json<unknown>();
      if (data == null || typeof data !== 'object' || Array.isArray(data)) {
        return;
      }

      const nextMap: SeatMap = {};
      for (const [key, value] of Object.entries(data as Record<string, unknown>)) {
        const parsed = Number.parseInt(String(value), 10);
        if (Number.isFinite(parsed)) {
          nextMap[key] = parsed;
        }
      }

      const previousMap = (await this.ctx.storage.get<SeatMap>(MAP_KEY)) ?? {};
      const changed = !deepEqualMap(previousMap, nextMap);

      const puts: Promise<unknown>[] = [];
      const etag = response.headers.get('etag')?.trim() ?? '';
      puts.push(this.ctx.storage.put(MAP_ETAG_KEY, etag));
      puts.push(this.ctx.storage.put(MAP_KEY, nextMap));
      puts.push(this.ctx.storage.put(MAP_UPDATED_AT_KEY, new Date().toISOString()));
      puts.push(this.ctx.storage.put(DETAILS_IDS_KEY, Object.keys(nextMap)));

      let nextVersion = (await this.ctx.storage.get<number>(MAP_VERSION_KEY)) ?? 0;
      if (changed) {
        nextVersion += 1;
        puts.push(this.ctx.storage.put(MAP_VERSION_KEY, nextVersion));
      }

      await Promise.all(puts);

      if (changed) {
        const event: SeatMapEvent = {
          type: 'seat_map',
          version: nextVersion,
          seatMap: nextMap,
          updatedAt: new Date().toISOString(),
        };
        await this.broadcast(event);
      }
    } finally {
      this.mapSyncInFlight = false;
    }
  }

  private async syncDetails(): Promise<void> {
    if (this.detailsSyncInFlight) return;
    this.detailsSyncInFlight = true;
    try {
      await this.syncMap();
      const ids = await this.detailIds();
      const batchSize = parseIntEnv(this.env.DETAILS_BATCH_SIZE, 12);

      let index = 0;
      while (index < ids.length) {
        const batch = ids.slice(index, index + batchSize);
        await Promise.all(batch.map((id) => this.syncSingleDetail(id)));
        index += batchSize;
      }

      await this.ctx.storage.put(LAST_DETAILS_SYNC_AT_KEY, Date.now());
    } finally {
      this.detailsSyncInFlight = false;
    }
  }

  private async ensureDetail(sectionId: number): Promise<void> {
    const key = this.detailsKey(sectionId);
    const cached = await this.ctx.storage.get(key);
    if (cached != null) {
      const intervalMs = parseIntEnv(this.env.DETAILS_SYNC_INTERVAL_MS, 3600000);
      const ts = (await this.ctx.storage.get<number>(this.detailsUpdatedAtEpochKey(sectionId))) ?? 0;
      if (Date.now() - ts < intervalMs) return;
    }
    await this.syncSingleDetail(sectionId);
  }

  private async syncSingleDetail(sectionId: number): Promise<void> {
    const etagKey = this.detailsEtagKey(sectionId);
    const currentEtag = (await this.ctx.storage.get<string>(etagKey)) ?? '';

    const url = this.env.UPSTREAM_SECTION_DETAILS_TEMPLATE.replace('{id}', String(sectionId));
    const response = await fetch(url, {
      headers: await this.upstreamHeaders(currentEtag),
    });

    if (response.status === 304) {
      return;
    }
    if (!response.ok) {
      return;
    }

    const payload = await response.json<unknown>();
    if (payload == null || typeof payload !== 'object' || Array.isArray(payload)) {
      return;
    }

    const key = this.detailsKey(sectionId);
    const previous = await this.ctx.storage.get<Record<string, unknown>>(key);
    const next = payload as Record<string, unknown>;
    const changed = JSON.stringify(previous ?? {}) !== JSON.stringify(next);

    const puts: Promise<unknown>[] = [];
    puts.push(this.ctx.storage.put(key, next));
    puts.push(this.ctx.storage.put(this.detailsUpdatedAtIsoKey(sectionId), new Date().toISOString()));
    puts.push(this.ctx.storage.put(this.detailsUpdatedAtEpochKey(sectionId), Date.now()));
    puts.push(this.ctx.storage.put(etagKey, response.headers.get('etag')?.trim() ?? ''));

    if (changed) {
      const nextVersion = ((await this.ctx.storage.get<number>(this.detailsVersionKey(sectionId))) ?? 0) + 1;
      puts.push(this.ctx.storage.put(this.detailsVersionKey(sectionId), nextVersion));
    }

    await Promise.all(puts);

    const ids = await this.detailIds();
    if (!ids.includes(sectionId)) {
      ids.push(sectionId);
      ids.sort((a, b) => a - b);
      await this.ctx.storage.put(DETAILS_IDS_KEY, ids.map(String));
    }
  }

  private async pushCurrentMap(ws: WebSocket): Promise<void> {
    const map = (await this.ctx.storage.get<SeatMap>(MAP_KEY)) ?? {};
    const version = (await this.ctx.storage.get<number>(MAP_VERSION_KEY)) ?? 0;
    const payload: SeatMapEvent = {
      type: 'seat_map',
      version,
      seatMap: map,
      updatedAt: new Date().toISOString(),
    };
    try {
      ws.send(JSON.stringify(payload));
    } catch (_) {
      this.sockets.delete(ws);
      try {
        ws.close(1011, 'send_failed');
      } catch (_) {}
    }
  }

  private async broadcast(event: SeatMapEvent): Promise<void> {
    const message = JSON.stringify(event);
    for (const socket of this.sockets) {
      try {
        socket.send(message);
      } catch (_) {
        this.sockets.delete(socket);
        try {
          socket.close(1011, 'send_failed');
        } catch (_) {}
      }
    }
  }

  private async upstreamHeaders(ifNoneMatch: string): Promise<Headers> {
    const runtimeToken =
      (await this.ctx.storage.get<string>(RUNTIME_BEARER_TOKEN_KEY)) ?? '';
    const configuredToken = (this.env.UPSTREAM_BEARER_TOKEN ?? '').trim();
    const bearerToken =
      configuredToken.length > 0 ? configuredToken : runtimeToken.trim();

    const headers = new Headers({
      'X-REALM': this.env.UPSTREAM_REALM,
      Accept: 'application/json',
    });
    if (bearerToken.length > 0) {
      headers.set('Authorization', `Bearer ${bearerToken}`);
    }
    const tag = ifNoneMatch.trim();
    if (tag.length > 0) {
      headers.set('If-None-Match', tag);
    }
    return headers;
  }

  private async captureRuntimeToken(request: Request): Promise<void> {
    const auth = (request.headers.get('authorization') ?? '').trim();
    if (!auth.toLowerCase().startsWith('bearer ')) return;
    const token = auth.substring(7).trim();
    if (token.length < 16) return;
    await this.ctx.storage.put(RUNTIME_BEARER_TOKEN_KEY, token);
  }

  private parseSectionId(path: string): number | null {
    const match = path.match(/^\/api\/sections\/(\d+)\/details$/);
    if (!match) return null;
    const parsed = Number.parseInt(match[1], 10);
    return Number.isFinite(parsed) ? parsed : null;
  }

  private async detailsCount(): Promise<number> {
    const ids = await this.detailIds();
    return ids.length;
  }

  private async detailIds(): Promise<number[]> {
    const idsRaw = (await this.ctx.storage.get<string[]>(DETAILS_IDS_KEY)) ?? [];
    const ids = idsRaw
      .map((v) => Number.parseInt(v, 10))
      .filter((v) => Number.isFinite(v));
    ids.sort((a, b) => a - b);
    return ids;
  }

  private detailsKey(sectionId: number): string {
    return `seat:detail:${sectionId}`;
  }

  private detailsEtagKey(sectionId: number): string {
    return `seat:detail:${sectionId}:etag`;
  }

  private detailsVersionKey(sectionId: number): string {
    return `seat:detail:${sectionId}:version`;
  }

  private detailsUpdatedAtIsoKey(sectionId: number): string {
    return `seat:detail:${sectionId}:updated_at_iso`;
  }

  private detailsUpdatedAtEpochKey(sectionId: number): string {
    return `seat:detail:${sectionId}:updated_at_epoch`;
  }
}

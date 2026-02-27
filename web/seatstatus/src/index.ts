import { SeatHub } from './seat_hub';
import type { Env } from './types';

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}

function hubStub(env: Env): DurableObjectStub {
  const id = env.SEAT_HUB.idFromName('global');
  return env.SEAT_HUB.get(id);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === '/') {
      const stub = hubStub(env);
      return stub.fetch('https://seat-hub.local/');
    }

    if (path === '/api') {
      const stub = hubStub(env);
      return stub.fetch(new Request('https://seat-hub.local/api', request));
    }

    if (path.startsWith('/api/sections/') && path.endsWith('/details')) {
      const stub = hubStub(env);
      const forward = new Request(`https://seat-hub.local${path}`, request);
      return stub.fetch(forward);
    }

    if (path === '/ws') {
      if (request.headers.get('upgrade')?.toLowerCase() !== 'websocket') {
        return json(426, { error: 'websocket_upgrade_required' });
      }
      const stub = hubStub(env);
      return stub.fetch('https://seat-hub.local/ws/connect', request);
    }

    if (path === '/internal/sync/map' || path === '/internal/sync/details') {
      const sharedSecret = (env.SYNC_SHARED_SECRET ?? '').trim();
      if (sharedSecret.length > 0) {
        const incoming = (request.headers.get('x-sync-secret') ?? '').trim();
        if (incoming != sharedSecret) {
          return json(401, { error: 'unauthorized' });
        }
      }
      const stub = hubStub(env);
      return stub.fetch(new Request(`https://seat-hub.local${path}`, request));
    }

    return json(404, { error: 'not_found' });
  },

  async scheduled(_event: ScheduledEvent, env: Env): Promise<void> {
    const stub = hubStub(env);
    await stub.fetch('https://seat-hub.local/internal/cron');
  },
};

export { SeatHub };

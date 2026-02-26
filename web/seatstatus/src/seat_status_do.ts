import { pollSeatStatus } from './poller';
import type { Env } from './types';

function asNumber(input: string | undefined, fallback: number): number {
  if (!input) return fallback;
  const n = Number(input);
  return Number.isFinite(n) ? n : fallback;
}

export class SeatStatusDO {
  private readonly ctx: DurableObjectState;
  private readonly env: Env;
  private sockets = new Set<WebSocket>();

  constructor(ctx: DurableObjectState, env: Env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/device/start' && request.method === 'POST') {
      const code = this.randomCode();
      await this.ctx.storage.put(`device:${code}`, {
        status: 'pending',
        createdAt: Date.now(),
        expiresAt: Date.now() + 10 * 60 * 1000,
      });
      return new Response(JSON.stringify({ code, expiresIn: 600 }), {
        headers: { 'content-type': 'application/json' },
      });
    }

    if (url.pathname === '/device/status' && request.method === 'GET') {
      const code = (url.searchParams.get('code') ?? '').trim().toUpperCase();
      if (!code) return new Response(JSON.stringify({ status: 'missing' }), { status: 400 });
      const state = await this.ctx.storage.get<Record<string, unknown>>(`device:${code}`);
      if (!state) return new Response(JSON.stringify({ status: 'expired' }), { headers: { 'content-type': 'application/json' } });
      const expiresAt = Number(state.expiresAt ?? 0);
      if (expiresAt && expiresAt < Date.now()) {
        await this.ctx.storage.delete(`device:${code}`);
        return new Response(JSON.stringify({ status: 'expired' }), { headers: { 'content-type': 'application/json' } });
      }
      return new Response(JSON.stringify({ status: String(state.status ?? 'pending') }), {
        headers: { 'content-type': 'application/json' },
      });
    }

    if (url.pathname === '/device/complete' && request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as {
        code?: string;
        accessToken?: string;
        refreshToken?: string;
        idToken?: string;
        expiresIn?: number;
      };
      const code = (body.code ?? '').trim().toUpperCase();
      if (!code || !body.accessToken || !body.refreshToken) {
        return new Response(JSON.stringify({ ok: false, error: 'invalid payload' }), {
          status: 400,
          headers: { 'content-type': 'application/json' },
        });
      }
      const state = await this.ctx.storage.get<Record<string, unknown>>(`device:${code}`);
      if (!state || String(state.status ?? '') !== 'pending') {
        return new Response(JSON.stringify({ ok: false, error: 'invalid or expired code' }), {
          status: 404,
          headers: { 'content-type': 'application/json' },
        });
      }
      await this.ctx.storage.put(`device:${code}`, {
        status: 'done',
        createdAt: state.createdAt ?? Date.now(),
        expiresAt: Date.now() + 2 * 60 * 1000,
        accessToken: String(body.accessToken),
        refreshToken: String(body.refreshToken),
        idToken: body.idToken ? String(body.idToken) : undefined,
        expiresIn: body.expiresIn,
      });
      return new Response(JSON.stringify({ ok: true }), {
        headers: { 'content-type': 'application/json' },
      });
    }

    if (url.pathname === '/device/consume' && request.method === 'GET') {
      const code = (url.searchParams.get('code') ?? '').trim().toUpperCase();
      if (!code) return new Response(JSON.stringify({ ok: false, error: 'missing code' }), { status: 400 });
      const key = `device:${code}`;
      const state = await this.ctx.storage.get<Record<string, unknown>>(key);
      if (!state || String(state.status ?? '') !== 'done') {
        return new Response(JSON.stringify({ ok: false, error: 'not ready' }), {
          status: 404,
          headers: { 'content-type': 'application/json' },
        });
      }
      await this.ctx.storage.delete(key);
      return new Response(
        JSON.stringify({
          ok: true,
          accessToken: String(state.accessToken ?? ''),
          refreshToken: String(state.refreshToken ?? ''),
          idToken: state.idToken ? String(state.idToken) : undefined,
          expiresIn: state.expiresIn,
        }),
        { headers: { 'content-type': 'application/json' } },
      );
    }

    if (url.pathname === '/ws') {
      if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
        return new Response('Expected websocket', { status: 426 });
      }

      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];
      const accessToken = request.headers.get('x-seat-access-token');
      this.ctx.acceptWebSocket(server);
      this.sockets.add(server);

      server.serializeAttachment({ connectedAt: Date.now(), accessToken });

      if (this.sockets.size === 1) {
        const due = Date.now() + 1000;
        await this.ctx.storage.setAlarm(due);
      }

      return new Response(null, { status: 101, webSocket: client });
    }

    if (url.pathname === '/broadcast' && request.method === 'POST') {
      const payload = await request.text();
      this.broadcast(payload);
      return new Response(JSON.stringify({ ok: true, clients: this.sockets.size }), {
        headers: { 'content-type': 'application/json' },
      });
    }

    if (url.pathname === '/stats') {
      return new Response(JSON.stringify({ clients: this.sockets.size }), {
        headers: { 'content-type': 'application/json' },
      });
    }

    return new Response('Not found', { status: 404 });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== 'string') return;
    if (message === 'ping') {
      ws.send(JSON.stringify({ type: 'pong', ts: Date.now() }));
      return;
    }
  }

  async webSocketClose(ws: WebSocket): Promise<void> {
    this.sockets.delete(ws);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    this.sockets.delete(ws);
    try {
      ws.close(1011, 'socket error');
    } catch {
    }
  }

  async alarm(): Promise<void> {
    if (this.sockets.size === 0) return;
    const accessToken = this.getAnySocketAccessToken();
    if (!accessToken) return;

    try {
      await pollSeatStatus(this.env, { reason: 'active-ws', broadcast: true, accessToken });
    } catch (err) {
      console.error('alarm poll failed', err);
    }

    const intervalMs = Math.max(1000, asNumber(this.env.ACTIVE_POLL_SECONDS, 5) * 1000);
    await this.ctx.storage.setAlarm(Date.now() + intervalMs);
  }

  private broadcast(textPayload: string): void {
    for (const ws of this.sockets) {
      try {
        ws.send(textPayload);
      } catch {
        this.sockets.delete(ws);
        try {
          ws.close(1011, 'send failed');
        } catch {
        }
      }
    }
  }

  private getAnySocketAccessToken(): string | null {
    for (const ws of this.sockets) {
      try {
        const attachment = ws.deserializeAttachment() as { accessToken?: string } | null;
        if (attachment?.accessToken) return attachment.accessToken;
      } catch {
      }
    }
    return null;
  }

  private randomCode(): string {
    const bytes = crypto.getRandomValues(new Uint8Array(12));
    return Array.from(bytes, (b) => (b % 36).toString(36)).join('').toUpperCase();
  }
}

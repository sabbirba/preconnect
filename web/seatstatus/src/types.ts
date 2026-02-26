export interface Env {
  SEAT_STATUS_DO: DurableObjectNamespace;
  SEAT_STATUS: KVNamespace;

  SEAT_MAP_MODE: 'snapshot' | 'delta' | string;
  DETAIL_FETCH_CONCURRENCY: string;
  DETAIL_FETCH_LIMIT: string;
  ACTIVE_POLL_SECONDS: string;
  IDLE_POLL_SECONDS: string;
}

export type SeatMap = Record<string, number>;

export interface PollResult {
  changedIds: string[];
  changedCount: number;
  mapCount: number;
  fetchedAt: number;
  mapChanged: boolean;
  detailChangedCount: number;
  notModified: boolean;
}

export interface SessionPayload {
  sub: string;
  iat: number;
  exp: number;
  accessToken?: string;
  refreshToken?: string;
}

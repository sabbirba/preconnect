export interface Env {
  SEAT_HUB: DurableObjectNamespace;
  UPSTREAM_BEARER_TOKEN: string;
  SYNC_SHARED_SECRET?: string;
  UPSTREAM_SEAT_MAP_URL: string;
  UPSTREAM_SECTION_DETAILS_TEMPLATE: string;
  UPSTREAM_REALM: string;
  MAP_SYNC_INTERVAL_MS: string;
  DETAILS_SYNC_INTERVAL_MS: string;
  DETAILS_BATCH_SIZE: string;
}

export type SeatMap = Record<string, number>;

export interface SeatMapEvent {
  type: 'seat_map';
  version: number;
  seatMap: SeatMap;
  updatedAt: string;
}

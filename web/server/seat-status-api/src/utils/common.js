import { createHash, randomBytes } from 'node:crypto';

export function etagFor(data) {
  const raw = JSON.stringify(data ?? null);
  return `"${createHash('sha1').update(raw).digest('base64url')}"`;
}

export function snapshotPayload(data) {
  const serialized = JSON.stringify(data ?? null);
  return {
    value: data,
    serialized,
    etag: `"${createHash('sha1').update(serialized).digest('base64url')}"`,
  };
}

export function writeCacheHeaders(reply, seconds, etag) {
  reply.header(
    'Cache-Control',
    `public, max-age=0, s-maxage=${seconds}, stale-while-revalidate=${seconds * 2}`,
  );
  reply.header('ETag', etag);
  reply.header('Vary', 'Origin');
}

export function replyFromSnapshot(req, reply, seconds, snapshot) {
  writeCacheHeaders(reply, seconds, snapshot.etag);
  if (req.headers['if-none-match'] === snapshot.etag) {
    return reply.code(304).send();
  }
  reply.type('application/json; charset=utf-8');
  return reply.send(snapshot.serialized);
}

export function randomToken(length = 32) {
  return randomBytes(length).toString('base64url');
}

export function sanitizeEmail(input) {
  return `${input || ''}`.trim().toLowerCase();
}

export function sanitizeInitial(input) {
  const initial = `${input || ''}`.trim().toUpperCase();
  if (!initial) return '';
  if (['TBA', 'NULL', 'N/A', '--'].includes(initial)) return '';
  return initial;
}

export function isIsoDateString(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(`${value || ''}`.trim());
}

export function parseIsoDateUtc(value) {
  if (!isIsoDateString(value)) return null;
  const [year, month, day] = `${value}`.split('-').map((part) => Number(part));
  if (!year || !month || !day) return null;
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null;
  }
  return date;
}

export function formatIsoDateUtc(date) {
  const year = date.getUTCFullYear();
  const month = `${date.getUTCMonth() + 1}`.padStart(2, '0');
  const day = `${date.getUTCDate()}`.padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function currentUtcYear() {
  return new Date().getUTCFullYear();
}

export function formatDateForTimeZone(date, timeZone) {
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const parts = formatter.formatToParts(date);
  const day = parts.find((part) => part.type === 'day')?.value || '01';
  const month = parts.find((part) => part.type === 'month')?.value || '01';
  const year =
    parts.find((part) => part.type === 'year')?.value ||
    `${date.getUTCFullYear()}`;
  return `${day}-${month}-${year}`;
}

export function yearDateRange(year) {
  return { startDate: `${year}-01-01`, endDate: `${year}-12-31` };
}

export function normalizeTime(value) {
  const text = `${value || ''}`.trim();
  if (!text) return null;
  const match = text.match(/^(\d{1,2}):(\d{2})/);
  if (!match) return null;
  return `${match[1].padStart(2, '0')}:${match[2]}`;
}

export function addMinutesToTime(value, minutes) {
  const normalized = normalizeTime(value);
  if (!normalized) return null;
  const [hours, mins] = normalized.split(':').map((part) => Number(part));
  if (!Number.isFinite(hours) || !Number.isFinite(mins)) return null;
  const totalMinutes = (((hours * 60) + mins + minutes) % 1440 + 1440) % 1440;
  const nextHours = `${Math.floor(totalMinutes / 60)}`.padStart(2, '0');
  const nextMinutes = `${totalMinutes % 60}`.padStart(2, '0');
  return `${nextHours}:${nextMinutes}`;
}

export function weekDateRange(isoDate) {
  const base = parseIsoDateUtc(isoDate);
  if (!base) return null;
  const start = new Date(base.getTime());
  const weekdayOffset = (start.getUTCDay() + 6) % 7;
  start.setUTCDate(start.getUTCDate() - weekdayOffset);
  const end = new Date(start.getTime());
  end.setUTCDate(end.getUTCDate() + 6);
  return {
    startDate: formatIsoDateUtc(start),
    endDate: formatIsoDateUtc(end),
  };
}

export function isCalendarHolidayRecord(value) {
  return (
    value &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    typeof value.id === 'string' &&
    typeof value.label === 'string' &&
    typeof value.startDate === 'string' &&
    typeof value.endDate === 'string' &&
    !Array.isArray(value.scheduleInfos)
  );
}

export function extractCalendarHolidays(raw) {
  const output = [];

  function visit(node) {
    if (Array.isArray(node)) {
      for (const item of node) visit(item);
      return;
    }
    if (!node || typeof node !== 'object') return;
    if (isCalendarHolidayRecord(node)) {
      output.push(node);
      return;
    }
    for (const value of Object.values(node)) visit(value);
  }

  visit(raw);
  return output;
}

export function toSeatNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

export function seatPlural(value) {
  return Math.abs(Number(value) || 0) === 1 ? 'seat' : 'seats';
}
